#!/usr/bin/env python3
"""Read-only, observe-only local review gate for GitHub pull requests."""
from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
from urllib.parse import urlparse

VERSION = "0.1.0"
REVIEWER = "haechibot[bot]"
DEFAULT_REPOS = ("isac322/cc-lb", "isac322/krema", "isac322/kwin-mcp", "isac322/pillar-csi")
DEFAULT_MODEL = "gpt-6.1-sol"
DEFAULT_EFFORT = "high"
PUSH_WAIT = 120.0
GATE_TIMEOUT = 1500.0
MAX_GATES = 2
ACTIVE_DEADLINE: float | None = None
DEDUP_FDS: dict[str, int] = {}
ALLOWED_GIT = frozenset({"rev-parse", "symbolic-ref", "config", "cat-file", "diff", "patch-id", "archive"})
MARKER_RE = re.compile(r"issue-agent(?::[^:\s>]+)+:review:([0-9a-fA-F]{7,64})")
DOC_RE = re.compile(r"^(?:docs/|.*\.md$|.*\.mdx$|.*\.txt$|LICENSE(?:\..*)?$)", re.IGNORECASE)


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def state_root() -> Path:
    base = os.environ.get("XDG_STATE_HOME")
    if not base:
        base = str(Path.home() / ".local" / "state")
    root = Path(base) / "pr-gate"
    root.mkdir(parents=True, exist_ok=True)
    root.chmod(0o700)
    (root / "runs").mkdir(exist_ok=True)
    (root / "runs").chmod(0o700)
    return root


def secure_mkdir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    path.chmod(0o700)


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        os.chmod(path, 0o600)
        json.dump(value, handle, sort_keys=True, separators=(",", ":"))
        handle.write("\n")


def append_observation(root: Path, observation: dict) -> None:
    path = root / "observations.jsonl"
    with open(path, "a", encoding="utf-8") as handle:
        os.chmod(path, 0o600)
        handle.write(json.dumps(observation, sort_keys=True, separators=(",", ":")) + "\n")


def default_observation(**changes: object) -> dict:
    row = {
        "ts": utc_now(), "trigger": None, "repo": None, "pr": None, "branch": None,
        "head_sha": None, "tree_sha": None, "last_reviewed_sha": None,
        "path": "skipped", "skip_reason": None, "status": "ok", "verdict": None,
        "threads_open": 0, "new_findings": 0, "escalations": 0, "wall_s": 0.0,
        "input_tokens": None, "cached_input_tokens": None, "output_tokens": None,
        "run_dir": None, "gate_version": None, "model": DEFAULT_MODEL, "effort": DEFAULT_EFFORT,
        "would_block": False, "would_escalate": False, "agent_kind": os.environ.get("PR_GATE_AGENT_KIND") or "unknown",
    }
    row.update(changes)
    return row


def remaining_deadline() -> float:
    if ACTIVE_DEADLINE is None:
        return GATE_TIMEOUT
    value = ACTIVE_DEADLINE - time.monotonic()
    if value <= 0:
        raise TimeoutError("gate deadline exceeded")
    return value


def git(root: Path, *args: str, input_data: bytes | None = None, check: bool = True) -> bytes:
    if not args or args[0] not in ALLOWED_GIT:
        raise ValueError(f"git subcommand not allowed: {args[0] if args else ''}")
    command = ["git", "-C", str(root), *args]
    try:
        result = subprocess.run(command, input=input_data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False, timeout=remaining_deadline())
    except subprocess.TimeoutExpired as error:
        raise TimeoutError("git deadline exceeded") from error
    if check and result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace").strip() or "git command failed")
    return result.stdout


def git_text(root: Path, *args: str, check: bool = True) -> str:
    return git(root, *args, check=check).decode("utf-8", errors="replace").strip()


def resolve_root(cwd: Path, git_dir_hint: str | None = None) -> Path:
    if git_dir_hint:
        command = ["git", "-C", str(cwd), "--git-dir", git_dir_hint, "rev-parse", "--show-toplevel"]
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        if result.returncode:
            raise RuntimeError(result.stderr.decode(errors="replace").strip() or "not a git repository")
        return Path(result.stdout.decode().strip()).resolve()
    return Path(git_text(cwd, "rev-parse", "--show-toplevel")).resolve()


def remote_repo(url: str) -> str:
    value = url.strip()
    if value.startswith("git@"):
        value = value.split(":", 1)[1]
    else:
        value = urlparse(value).path.lstrip("/")
    value = value.removesuffix(".git").strip("/")
    if value.count("/") != 1:
        raise ValueError("origin is not a GitHub owner/repository URL")
    return value


def gh_output(*args: str) -> bytes:
    try:
        result = subprocess.run(["gh", *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False, timeout=remaining_deadline())
    except subprocess.TimeoutExpired as error:
        raise TimeoutError("gh deadline exceeded") from error
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace").strip() or "gh command failed")
    return result.stdout


def gh_json(*args: str) -> object:
    try:
        return json.loads(gh_output(*args).decode("utf-8"))
    except json.JSONDecodeError as error:
        raise RuntimeError("gh returned malformed JSON") from error


def reviews_for(repo: str, pr: int, before: str | None = None) -> list[dict]:
    value = gh_json("api", "--paginate", f"repos/{repo}/pulls/{pr}/reviews?per_page=100")
    if not isinstance(value, list):
        raise RuntimeError("gh reviews JSON is not an array")
    if all(isinstance(item, dict) for item in value):
        rows = value
    else:
        rows = [item for page in value if isinstance(page, list) for item in page if isinstance(item, dict)]
        if not rows and value:
            raise RuntimeError("gh reviews JSON is malformed")
    if before:
        rows = [item for item in rows if str(item.get("submitted_at") or item.get("submittedAt") or "") < before]
    return rows


def marker_sha(body: str | None) -> str | None:
    if not isinstance(body, str):
        return None
    match = MARKER_RE.search(body)
    return match.group(1).lower() if match else None


def reviewer_login(review: dict) -> str:
    user = review.get("user") or review.get("author") or {}
    return str(user.get("login") or "")


def has_reviewer_review(reviews: list[dict]) -> bool:
    return any(reviewer_login(review) == REVIEWER for review in reviews)


def review_bound(repo: str, pr: dict, reviews: list[dict], configured: tuple[str, ...]) -> bool:
    return pr.get("state") == "OPEN" and not bool(pr.get("isDraft")) and (repo in configured or has_reviewer_review(reviews))


def newest_reviewed_sha(reviews: list[dict]) -> str | None:
    candidates = [review for review in reviews if reviewer_login(review) == REVIEWER and marker_sha(review.get("body"))]
    candidates.sort(key=lambda item: (item.get("submitted_at") or item.get("submittedAt") or "", item.get("id") or 0))
    return marker_sha(candidates[-1].get("body")) if candidates else None


def consecutive_partials(thread: dict, reviewer: str = REVIEWER) -> int:
    comments = ((thread.get("comments") or {}).get("nodes") if isinstance(thread.get("comments"), dict) else thread.get("comments")) or []
    count = 0
    saw_author = False
    for comment in reversed(comments):
        login = reviewer_login(comment)
        body = str(comment.get("body") or "")
        if login != reviewer:
            saw_author = True
            break
        if not (re.search(r"partially fixed", body, re.IGNORECASE) or body.lstrip().lower().startswith("partially fixed")):
            break
        count += 1
    return count if saw_author else 0


def docs_only(paths: list[str]) -> bool:
    return bool(paths) and all(DOC_RE.match(path) for path in paths)


def tree_sha(root: Path, sha: str) -> str:
    return git_text(root, "rev-parse", f"{sha}^{{tree}}")


def patch_id(root: Path, patch: bytes) -> str:
    if not patch.strip():
        return ""
    value = git(root, "patch-id", "--stable", input_data=patch).decode(errors="replace").split()
    return value[0] if value else ""


def unchanged_three_dot(root: Path, base: str, old: str, new: str) -> bool:
    try:
        old_patch = git(root, "diff", f"{base}...{old}")
        new_patch = git(root, "diff", f"{base}...{new}")
        return patch_id(root, old_patch) == patch_id(root, new_patch)
    except (RuntimeError, ValueError):
        return False


def linked_issue_contract(repo: str, pr: dict) -> str:
    issues = []
    for item in pr.get("closingIssuesReferences") or []:
        number = item.get("number") if isinstance(item, dict) else None
        if number is None:
            continue
        try:
            issue = gh_json("api", f"repos/{repo}/issues/{int(number)}")
            issues.append({"number": number, "title": item.get("title"), "body": issue.get("body", "") if isinstance(issue, dict) else ""})
        except (RuntimeError, ValueError, json.JSONDecodeError):
            issues.append({"number": number, "title": item.get("title"), "body": ""})
    return "# Pull request\n\n## Title\n" + str(pr.get("title") or "") + "\n\n## Body\n" + str(pr.get("body") or "") + "\n\n## Closing issues\n" + json.dumps(issues, ensure_ascii=False, indent=2) + "\n"


def fetch_threads(repo: str, pr: int, before: str | None = None) -> list[dict]:
    owner, name = repo.split("/", 1)
    query = """query($owner:String!, $name:String!, $number:Int!) { repository(owner:$owner,name:$name) { pullRequest(number:$number) { reviewThreads(first:100) { nodes { id isResolved comments(first:100) { nodes { databaseId author { login } body createdAt path line } } } } } } }"""
    value = gh_json("api", "graphql", "-f", f"query={query}", "-f", f"owner={owner}", "-f", f"name={name}", "-F", f"number={pr}")
    nodes = (((value.get("data") or {}).get("repository") or {}).get("pullRequest") or {}).get("reviewThreads", {}).get("nodes", []) if isinstance(value, dict) else []
    result = []
    for thread in nodes:
        comments = ((thread.get("comments") or {}).get("nodes") or []) if isinstance(thread, dict) else []
        if before:
            comments = [comment for comment in comments if str(comment.get("createdAt") or "") < before]
        if isinstance(thread, dict) and not thread.get("isResolved") and comments and reviewer_login(comments[0]) == REVIEWER:
            thread = dict(thread)
            thread["comments"] = {"nodes": comments}
            result.append(thread)
    return result


def write_packet(run: Path, repo: str, pr: int, pr_data: dict, root: Path, head: str, last: str | None, base: str | None, delta: bytes, threads: list[dict]) -> None:
    packet = run / "packet"
    secure_mkdir(packet)
    write_json(packet / "threads.json", threads)
    (packet / "contract.md").write_text(linked_issue_contract(repo, pr_data), encoding="utf-8")
    os.chmod(packet / "contract.md", 0o600)
    (packet / "delta.patch").write_bytes(delta)
    os.chmod(packet / "delta.patch", 0o600)
    if base is not None:
        files = git_text(root, "diff", "--name-only", f"{base}...{head}")
    else:
        base_name = str(pr_data.get("baseRefName") or "main")
        comparison = gh_json("api", f"repos/{repo}/compare/{base_name}...{head}")
        files = "\n".join(item["filename"] for item in comparison["files"])
    (packet / "pr-files.txt").write_text(files + ("\n" if files else ""), encoding="utf-8")
    os.chmod(packet / "pr-files.txt", 0o600)


def snapshot(root: Path, head: str, destination: Path) -> None:
    secure_mkdir(destination)
    source = subprocess.Popen(["git", "-C", str(root), "archive", head], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        assert source.stdout is not None
        tar = subprocess.Popen(["tar", "-x", "-C", str(destination)], stdin=source.stdout, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        source.stdout.close()
        _, tar_err = tar.communicate()
        source_err = source.stderr.read() if source.stderr else b""
        source.wait()
    except BaseException:
        with contextlib.suppress(ProcessLookupError):
            source.kill()
        source.wait()
        raise
    finally:
        if source.stdout is not None:
            source.stdout.close()
        if source.stderr is not None:
            source.stderr.close()
    if source.returncode or tar.returncode:
        raise RuntimeError((source_err + tar_err).decode(errors="replace").strip() or "git archive failed")


def parse_usage(events: str) -> dict[str, int | None]:
    totals: dict[str, int | None] = {"input_tokens": None, "cached_input_tokens": None, "output_tokens": None}
    for line in events.splitlines():
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        seen: set[int] = set()
        def walk(node: object) -> None:
            if isinstance(node, dict):
                keys = {key for key in totals if key in node and isinstance(node[key], (int, float))}
                if keys and id(node) not in seen:
                    seen.add(id(node))
                    for key in keys:
                        totals[key] = int(node[key]) + int(totals[key] or 0)
                for child in node.values():
                    walk(child)
            elif isinstance(node, list):
                for child in node:
                    walk(child)
        walk(value)
    return totals


def gate_paths() -> tuple[Path, Path]:
    data = os.environ.get("PR_GATE_DATA_DIR")
    if data:
        root = Path(data)
    else:
        root = Path(__file__).resolve().parent
    return root / "gate-prompt.md", root / "gate-schema.json"
def gate_version() -> str:
    prompt_file, schema_file = gate_paths()
    digest = hashlib.sha256()
    digest.update(VERSION.encode())
    for path in (prompt_file, schema_file, Path(__file__)):
        try:
            digest.update(path.read_bytes())
        except OSError:
            pass
    return digest.hexdigest()[:16]


def run_codex(run: Path, snapshot_dir: Path, prompt_data: dict[str, object]) -> tuple[str, dict[str, int | None], int | None]:
    prompt_file, schema_file = gate_paths()
    prompt = prompt_file.read_text(encoding="utf-8").format(**prompt_data)
    events_path = run / "events.jsonl"
    result_path = run / "result.json"
    stderr_path = run / "stderr.log"
    command = ["codex", "exec", "--model", os.environ.get("PR_GATE_MODEL", DEFAULT_MODEL), "-c", f"model_reasoning_effort={os.environ.get('PR_GATE_EFFORT', DEFAULT_EFFORT)}", "--sandbox", "read-only", "--skip-git-repo-check", "--ignore-rules", "--color", "never", "--json", "--ephemeral", "--cd", str(snapshot_dir), "--output-last-message", str(result_path), "--output-schema", str(schema_file), "-"]
    started = time.monotonic()
    with open(events_path, "w", encoding="utf-8") as events, open(stderr_path, "w", encoding="utf-8") as stderr:
        os.chmod(events_path, 0o600)
        os.chmod(stderr_path, 0o600)
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=events, stderr=stderr, text=True, start_new_session=True)
        try:
            process.communicate(prompt, timeout=remaining_deadline())
        except subprocess.TimeoutExpired:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
            return "timeout", parse_usage(events_path.read_text(encoding="utf-8", errors="replace")), int(time.monotonic() - started)
    usage = parse_usage(events_path.read_text(encoding="utf-8", errors="replace"))
    return ("ok" if process.returncode == 0 else "error"), usage, int(time.monotonic() - started)


def valid_result(path: Path) -> dict | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(value, dict) or value.get("verdict") not in ("GREEN", "BLOCKING") or not isinstance(value.get("threads"), list) or not isinstance(value.get("new_findings"), list) or not isinstance(value.get("reason"), str):
        return None
    for finding in value["new_findings"]:
        if not isinstance(finding, dict) or not all(isinstance(finding.get(key), str) for key in ("mechanism", "evidence")) or finding.get("severity") not in ("P0", "P1", "P2", "P3"):
            return None
    for thread in value["threads"]:
        if not isinstance(thread, dict) or not isinstance(thread.get("thread_id"), str) or not isinstance(thread.get("assumptions"), list) or not all(isinstance(item, str) for item in thread["assumptions"]) or not isinstance(thread.get("invariant"), str) or thread.get("status") not in ("closed", "open") or thread.get("decision") not in ("NONE", "KEEP_PATCHING", "ESCALATE_CONTRACT") or not isinstance(thread.get("counterexamples"), list):
            return None
    return value


def acquire_slot(root: Path) -> tuple[int, Path] | None:
    slots = root / "slots"
    secure_mkdir(slots)
    for index in range(MAX_GATES):
        path = slots / f"{index}.lock"
        handle = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return handle, path
        except BlockingIOError:
            os.close(handle)
    return None


def acquire_dedup(run: Path, version: str) -> bool:
    secure_mkdir(run)
    key = str(run / version)
    if Path(run / f"run.{version}.done").exists():
        return False
    fd = os.open(run / f"run.{version}.lock", os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        os.close(fd)
        return False
    DEDUP_FDS[key] = fd
    return True


def finish_dedup(run: Path, version: str) -> None:
    key = str(run / version)
    fd = DEDUP_FDS.pop(key, None)
    Path(run / f"run.{version}.done").touch(mode=0o600, exist_ok=True)
    if fd is not None:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def config_repos() -> tuple[str, ...]:
    value = os.environ.get("PR_GATE_REPOS")
    return tuple(item.strip() for item in value.split(",") if item.strip()) if value is not None else DEFAULT_REPOS


def observe_worker(args: argparse.Namespace) -> None:
    global ACTIVE_DEADLINE
    root_state = state_root()
    started = time.monotonic()
    ACTIVE_DEADLINE = started + float(os.environ.get("PR_GATE_DEADLINE", GATE_TIMEOUT))
    version = gate_version()
    base_row = default_observation(
        ts=getattr(args, "trigger_ts", utc_now()),
        trigger=args.trigger,
        gate_version=version,
        model=os.environ.get("PR_GATE_MODEL", DEFAULT_MODEL),
        effort=os.environ.get("PR_GATE_EFFORT", DEFAULT_EFFORT),
    )
    try:
        root = resolve_root(Path(args.cwd).resolve(), args.git_dir_hint)
    except Exception:
        base_row.update(skip_reason="not_git_repo", status="ok", wall_s=time.monotonic() - started)
        append_observation(root_state, base_row)
        return
    try:
        remote = remote_repo(git_text(root, "config", "--get", "remote.origin.url"))
        branch = git_text(root, "symbolic-ref", "--quiet", "--short", "HEAD", check=False) or git_text(root, "rev-parse", "--abbrev-ref", "HEAD")
        head = git_text(root, "rev-parse", "HEAD")
        tree = tree_sha(root, head)
        base_row.update(repo=remote, branch=branch, head_sha=head, tree_sha=tree)
        fields = "number,isDraft,state,headRefOid,baseRefName,body,title,closingIssuesReferences,url"
        try:
            pr_data = gh_json("pr", "view", branch, "--repo", remote, "--json", fields)
        except RuntimeError as error:
            if "no pull requests found" not in str(error).lower():
                raise
            pr_data = None
        if pr_data is None:
            base_row.update(skip_reason="no_pr", wall_s=time.monotonic() - started)
            append_observation(root_state, base_row)
            return
        if not isinstance(pr_data, dict) or not pr_data.get("number"):
            raise RuntimeError("malformed pull request JSON")
        pr_number = int(pr_data["number"])
        reviews = reviews_for(remote, pr_number, before=base_row["ts"])
        base_row["pr"] = pr_number
        if not review_bound(remote, pr_data, reviews, config_repos()):
            base_row.update(skip_reason="not_review_bound", wall_s=time.monotonic() - started)
            append_observation(root_state, base_row)
            return
        push_deadline = min(ACTIVE_DEADLINE, time.monotonic() + PUSH_WAIT)
        while str(pr_data.get("headRefOid") or "").lower() != head.lower() and time.monotonic() < push_deadline:
            time.sleep(min(1.0, max(0.0, push_deadline - time.monotonic())))
            if time.monotonic() >= push_deadline:
                break
            pr_data = gh_json("pr", "view", branch, "--repo", remote, "--json", fields)
        if str(pr_data.get("headRefOid") or "").lower() != head.lower():
            base_row.update(skip_reason="push_not_observed", status="push_not_observed", wall_s=time.monotonic() - started)
            append_observation(root_state, base_row)
            return
        last = newest_reviewed_sha(reviews)
        base_row["last_reviewed_sha"] = last
        run = root_state / "runs" / remote.replace("/", "__") / str(pr_number) / head
        base_row["run_dir"] = str(run)
        if not acquire_dedup(run, version):
            base_row.update(skip_reason="duplicate", wall_s=time.monotonic() - started)
            append_observation(root_state, base_row)
            return
        base_name = str(pr_data.get("baseRefName") or "main")
        base_ref = None
        for candidate in (f"refs/remotes/origin/{base_name}", f"refs/heads/{base_name}"):
            resolved = git_text(root, "rev-parse", "--verify", f"{candidate}^{{commit}}", check=False)
            if resolved:
                base_ref = resolved
                break
        missing_last = False
        if last:
            try:
                git(root, "cat-file", "-e", f"{last}^{{commit}}")
            except RuntimeError:
                missing_last = True
        threads: list[dict] = []
        if base_ref is None or missing_last:
            path = "model"
            compare_base = last or base_name
            delta = gh_output("api", "-H", "Accept: application/vnd.github.diff", f"repos/{remote}/compare/{compare_base}...{head}")
        elif not last:
            path = "model"
            delta = git(root, "diff", f"{base_ref}...{head}")
        else:
            old_tree = tree_sha(root, last)
            if old_tree == tree or unchanged_three_dot(root, base_ref, last, head):
                path = "inert"
            else:
                changed = git_text(root, "diff", "--name-only", f"{last}..{head}").splitlines()
                path = "docs_only" if docs_only(changed) else "model"
            delta = git(root, "diff", f"{last}..{head}")
        if path != "model":
            base_row.update(path=path, status="ok", wall_s=time.monotonic() - started)
            append_observation(root_state, base_row)
            finish_dedup(run, version)
            return
        if shutil_which("codex") is None:
            base_row.update(skip_reason="codex_missing", wall_s=time.monotonic() - started)
            append_observation(root_state, base_row)
            finish_dedup(run, version)
            return
        slot = acquire_slot(root_state)
        if slot is None:
            base_row.update(skip_reason="busy", wall_s=time.monotonic() - started)
            append_observation(root_state, base_row)
            finish_dedup(run, version)
            return
        slot_fd, _ = slot
        snapshot_dir: Path | None = None
        try:
            threads = fetch_threads(remote, pr_number, before=base_row["ts"])
            for thread in threads:
                thread["consecutive_partials"] = consecutive_partials(thread)
            write_packet(run, remote, pr_number, pr_data, root, head, last, base_ref, delta, threads)
            snapshot_dir = run / "snapshot"
            snapshot(root, head, snapshot_dir)
            status, usage, wall = run_codex(run, snapshot_dir, {"repo": remote, "pr": pr_number, "head_sha": head, "last_reviewed_sha": last or "(first review)", "packet": str(run / "packet")})
            result = valid_result(run / "result.json")
            would_escalate = any(isinstance(thread.get("decision"), str) and thread.get("decision") == "ESCALATE_CONTRACT" for thread in (result or {}).get("threads", []))
            base_row.update(path="model", status=status, verdict=result.get("verdict") if result and status == "ok" else None, threads_open=len(threads), new_findings=len(result.get("new_findings", [])) if result and status == "ok" else 0, escalations=sum(1 for t in threads if t.get("consecutive_partials", 0) >= 2), wall_s=wall, input_tokens=usage["input_tokens"], cached_input_tokens=usage["cached_input_tokens"], output_tokens=usage["output_tokens"], would_block=bool(status == "ok" and result and result.get("verdict") == "BLOCKING"), would_escalate=would_escalate)
            append_observation(root_state, base_row)
            finish_dedup(run, version)
        finally:
            if snapshot_dir is not None:
                with contextlib.suppress(OSError):
                    import shutil
                    shutil.rmtree(snapshot_dir)
            os.close(slot_fd)
    except TimeoutError as error:
        base_row.update(status="timeout", verdict=None, skip_reason=str(error)[:240], wall_s=time.monotonic() - started)
        append_observation(root_state, base_row)
    except Exception as error:
        base_row.update(status="error", verdict=None, skip_reason=str(error)[:240], wall_s=time.monotonic() - started)
        append_observation(root_state, base_row)


def shutil_which(name: str) -> str | None:
    for directory in os.environ.get("PATH", "").split(os.pathsep):
        candidate = Path(directory) / name
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def observe(args: argparse.Namespace) -> int:
    trigger_ts = os.environ.get("PR_GATE_TRIGGER_TS", "")
    try:
        triggered_at = dt.datetime.fromisoformat(trigger_ts.replace("Z", "+00:00"))
        if triggered_at.tzinfo is None:
            triggered_at = triggered_at.replace(tzinfo=dt.timezone.utc)
    except ValueError:
        triggered_at = dt.datetime.now(dt.timezone.utc)
    args.trigger_ts = triggered_at.astimezone(dt.timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")
    if os.fork() == 0:
        try:
            os.setsid()
            root = state_root()
            log = open(root / "pr-gate.log", "a", encoding="utf-8")
            os.chmod(log.fileno(), 0o600)
            os.dup2(log.fileno(), 1)
            os.dup2(log.fileno(), 2)
            log.close()
            observe_worker(args)
        finally:
            os._exit(0)
    return 0


def load_observations(root: Path, since: str | None = None) -> list[dict]:
    path = root / "observations.jsonl"
    if not path.exists():
        return []
    rows = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        if since and str(row.get("ts", ""))[:10] < since:
            continue
        if isinstance(row, dict):
            rows.append(row)
    return rows


def report(args: argparse.Namespace) -> int:
    rows = load_observations(state_root(), args.since)
    pairs = []
    now = dt.datetime.now(dt.timezone.utc)
    for row in rows:
        if row.get("path") != "model" or not row.get("repo") or not row.get("pr"):
            continue
        try:
            reviews = reviews_for(str(row["repo"]), int(row["pr"]))
            selected = next((review for review in reversed(reviews) if reviewer_login(review) == REVIEWER and marker_sha(review.get("body")) == str(row.get("head_sha", "")).lower()), None)
            try:
                observed_at = dt.datetime.fromisoformat(str(row.get("ts", "")).replace("Z", "+00:00"))
                age_hours = (now - observed_at).total_seconds() / 3600
            except (TypeError, ValueError):
                age_hours = 999.0
            pair_status = "matched" if selected else ("pending" if age_hours < 3 else "no_review")
            gate = valid_result(Path(str(row["run_dir"])) / "result.json") if row.get("run_dir") else None
            inline: list[dict] = []
            partial: list[dict] = []
            if selected:
                comments = gh_json("api", "--paginate", f"repos/{row['repo']}/pulls/{row['pr']}/comments?per_page=100")
                if not isinstance(comments, list):
                    raise RuntimeError("malformed review comments JSON")
                for item in comments:
                    if item.get("pull_request_review_id") != selected.get("id"):
                        continue
                    comment = {"path": item.get("path"), "body": item.get("body")}
                    inline.append(comment)
                    if re.search(r"partially fixed", str(item.get("body") or ""), re.IGNORECASE):
                        partial.append(comment)
            pairs.append({"status": pair_status, "observation": row, "gate_result": gate, "haechibot": {"state": selected.get("state") if selected else None, "body": selected.get("body") if selected else None, "inline_comments": inline, "partial_replies": partial}})
        except Exception as error:
            pairs.append({"status": "api_error", "observation": row, "gate_result": None, "haechibot": {"state": None, "body": None, "inline_comments": [], "partial_replies": [], "error": str(error)}})
    summary = {
        "observations_by_path": {}, "observations_by_status": {}, "denominator": 0, "gate_BLOCKING": 0,
        "haechibot_CHANGES_REQUESTED_same_head": 0, "both": 0,
        "decision_rule": "Denominator = path=model, status=ok observations whose head received a haechibot review; numerator is adjudicated manually from blinded pairs (no automatic mechanism matching); minimum n=20.",
    }
    for row in rows:
        summary["observations_by_path"][row.get("path")] = summary["observations_by_path"].get(row.get("path"), 0) + 1
        summary["observations_by_status"][row.get("status")] = summary["observations_by_status"].get(row.get("status"), 0) + 1
    for pair in pairs:
        observation = pair["observation"]
        eligible = pair.get("status") == "matched" and observation.get("status") == "ok"
        gate_blocking = eligible and (pair.get("gate_result") or {}).get("verdict") == "BLOCKING"
        remote_changes = eligible and pair["haechibot"].get("state") == "CHANGES_REQUESTED"
        summary["denominator"] += int(eligible)
        summary["gate_BLOCKING"] += int(gate_blocking)
        summary["haechibot_CHANGES_REQUESTED_same_head"] += int(remote_changes)
        summary["both"] += int(gate_blocking and remote_changes)
    output = {"pairs": pairs, "summary": summary}
    if args.json:
        write_json(Path(args.json), output)
    print("path/status                    count")
    for key, count in sorted(summary["observations_by_path"].items(), key=lambda item: str(item[0])):
        print(f"{key:<24} {count}")
    print(f"gate BLOCKING: {summary['gate_BLOCKING']}")
    print(f"haechibot CHANGES_REQUESTED (same head): {summary['haechibot_CHANGES_REQUESTED_same_head']}")
    print(f"both: {summary['both']}")
    print(summary["decision_rule"])
    if not args.json:
        print(json.dumps(output, ensure_ascii=False, indent=2))
    return 0


def status(_: argparse.Namespace) -> int:
    rows = load_observations(state_root())[-10:]
    print(json.dumps(rows, ensure_ascii=False, indent=2))
    return 0


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(prog="pr-gate")
    commands = root.add_subparsers(dest="command", required=True)
    observe_parser = commands.add_parser("observe")
    observe_parser.add_argument("--cwd", required=True)
    observe_parser.add_argument("--trigger", choices=("push", "pr-create", "pr-ready"), required=True)
    observe_parser.add_argument("--git-dir-hint")
    observe_parser.add_argument("--command", default="")
    observe_parser.set_defaults(handler=observe)
    report_parser = commands.add_parser("report")
    report_parser.add_argument("--since", required=True)
    report_parser.add_argument("--json")
    report_parser.set_defaults(handler=report)
    status_parser = commands.add_parser("status")
    status_parser.set_defaults(handler=status)
    return root


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    return int(args.handler(args))


if __name__ == "__main__":
    raise SystemExit(main())
