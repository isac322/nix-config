#!/usr/bin/env python3
"""Initialize, inspect, validate, and serve a private review cockpit workspace."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from contextlib import suppress
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from server import ReportBuilder, handoff_prompt, normalize_decision_record

SKILL_ROOT = Path(__file__).resolve().parent.parent
GROUP_ID = re.compile(r"[a-z0-9][a-z0-9-]{1,63}")
REPO_NAME = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")
REFERENCE = re.compile(r"(?<![A-Za-z0-9_/])#(\d+)\b")
KNOWN_BOTS = {"dependabot", "dependabot[bot]", "github-actions[bot]", "renovate[bot]"}


def resolve_root(raw_root: Path | None) -> Path:
    if raw_root is not None:
        return raw_root.resolve()
    env_root = os.environ.get("REVIEW_COCKPIT_ROOT", "").strip()
    if env_root:
        return Path(env_root).resolve()
    raise ValueError("workspace root is required; pass --root or set REVIEW_COCKPIT_ROOT")


def load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def save_json(path: Path, value: Any, *, overwrite: bool = False) -> None:
    """Create data by default; only explicitly managed files may be replaced."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if overwrite or not path.exists():
        with path.open("w" if overwrite else "x", encoding="utf-8") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2)
            handle.write("\n")


def command_output(arguments: list[str], *, cwd: Path | None = None) -> str:
    result = subprocess.run(
        arguments,
        cwd=cwd,
        check=True,
        capture_output=True,
        text=True,
        timeout=60,
    )
    return result.stdout.strip()


def detect_repository() -> str:
    with suppress(OSError, subprocess.SubprocessError):
        remote = command_output(["git", "remote", "get-url", "origin"])
        match = re.search(r"github\.com[:/]([^/]+/[^/]+?)(?:\.git)?$", remote)
        if match:
            return match[1]
    return command_output(
        [
            "gh",
            "repo",
            "view",
            "--json",
            "nameWithOwner",
            "--jq",
            ".nameWithOwner",
        ]
    )


def github_snapshot(repo: str) -> dict[str, Any]:
    """Fetch every open page instead of silently truncating the backlog."""
    pages = json.loads(
        command_output(
            [
                "gh",
                "api",
                "--paginate",
                "--slurp",
                f"repos/{repo}/issues?state=open&per_page=100",
            ]
        )
    )
    items: list[dict[str, Any]] = []
    for page in pages:
        for item in page:
            kind = "pr" if "pull_request" in item else "issue"
            head = ""
            if kind == "pr":
                details = json.loads(
                    command_output(
                        [
                            "gh",
                            "api",
                            f"repos/{repo}/pulls/{item['number']}",
                        ]
                    )
                )
                head = details.get("head", {}).get("sha", "")
            items.append(
                {
                    "number": item["number"],
                    "type": kind,
                    "title": item["title"],
                    "body": item.get("body") or "",
                    "author": item["user"]["login"],
                    "url": item["html_url"],
                    "head": head,
                    "updated_at": item["updated_at"],
                }
            )
    repo_info = json.loads(command_output(["gh", "api", f"repos/{repo}"]))
    branch = repo_info["default_branch"]
    base_sha = command_output(["gh", "api", f"repos/{repo}/commits/{branch}", "--jq", ".sha"])
    release: dict[str, Any] | None = None
    try:
        value = json.loads(command_output(["gh", "api", f"repos/{repo}/releases/latest"]))
        release = {
            "tag": value["tag_name"],
            "publishedAt": value.get("published_at"),
            "url": value.get("html_url"),
        }
    except subprocess.CalledProcessError as error:
        if "404" not in (error.stderr or ""):
            raise
    return {"items": items, "base_branch": branch, "base_sha": base_sha, "latest_release": release}


def normalize_item(raw: dict[str, Any]) -> dict[str, Any]:
    metadata = raw.get("metadata", raw)
    if not isinstance(metadata, dict):
        raise ValueError("item metadata must be an object")
    kind = metadata.get("type", "pr" if raw.get("pull_request") else "issue")
    if kind not in {"issue", "pr"}:
        raise ValueError("item type must be issue or pr")
    number = metadata.get("number")
    if not isinstance(number, int) or isinstance(number, bool) or number < 1:
        raise ValueError("item number must be a positive integer")
    author = metadata.get("author", metadata.get("user", {}))
    if isinstance(author, dict):
        author = author.get("login", "")
    return {
        **metadata,
        "type": kind,
        "number": number,
        "author": author,
        "url": metadata.get("url", metadata.get("html_url", "")),
        "body": raw.get("body", metadata.get("body", "")) or "",
    }


def cluster_items(items: list[dict[str, Any]]) -> list[list[dict[str, Any]]]:
    """Use connected components so transitive issue/PR references stay together."""
    by_number = {item["number"]: item for item in items}
    neighbors: dict[int, set[int]] = {number: set() for number in by_number}
    for number, item in by_number.items():
        for reference in REFERENCE.findall(str(item.get("body", ""))):
            related = int(reference)
            if related in by_number:
                neighbors[number].add(related)
                neighbors[related].add(number)
    result: list[list[dict[str, Any]]] = []
    unseen = set(by_number)
    while unseen:
        pending = [min(unseen)]
        component: set[int] = set()
        while pending:
            number = pending.pop()
            if number in component:
                continue
            component.add(number)
            pending.extend(neighbors[number] - component)
        unseen.difference_update(component)
        result.append([by_number[number] for number in sorted(component)])
    return result


def sync_web(root: Path) -> None:
    web = root / "web"
    web.mkdir(parents=True, exist_ok=True)
    for filename in ("index.html", "styles.css", "app.js"):
        shutil.copyfile(SKILL_ROOT / "assets" / "web" / filename, web / filename)
    shutil.copyfile(SKILL_ROOT / "scripts" / "server.py", web / "server.py")
    for source, target in (
        ("evidence-and-handoff-schema.md", "EVIDENCE-SCHEMA.md"),
        ("qa-checklist.md", "QA-CHECKLIST.md"),
    ):
        shutil.copyfile(SKILL_ROOT / "references" / source, web / target)


def import_workspace(source: Path, root: Path) -> None:
    """Copy missing workspace data only, preserving existing evidence and owner decisions."""
    if root.is_relative_to(source) or source.is_relative_to(root):
        raise ValueError("source and destination workspaces must not contain one another")
    for filename in ("groups.json", "run-contract.json", "classification.json"):
        if not (source / filename).is_file():
            raise ValueError(f"source workspace is missing {filename}")
    groups = load_json(source / "groups.json")
    if not isinstance(groups, list):
        raise ValueError("source groups.json must be a list")
    relocated: list[dict[str, Any]] = []
    for group in groups:
        if not isinstance(group, dict):
            raise ValueError("source group must be an object")
        entry = dict(group)
        entry["input_paths"] = []
        for raw_path in group.get("input_paths", []):
            path = Path(str(raw_path))
            path = path if path.is_absolute() else source / path
            try:
                relative = path.resolve().relative_to(source)
            except ValueError as error:
                raise ValueError("source input path escapes its workspace") from error
            entry["input_paths"].append(relative.as_posix())
        if "directory" in entry:
            entry["directory"] = str(root / "groups" / str(entry["id"]))
        relocated.append(entry)
    root.mkdir(parents=True, exist_ok=True)
    for directory in ("inputs", "groups", "evidence"):
        origin = source / directory
        if not origin.is_dir():
            continue
        for path in origin.rglob("*"):
            if path.is_symlink():
                continue
            if path.is_file() and path.resolve().is_relative_to(source):
                target = root / path.relative_to(source)
                target.parent.mkdir(parents=True, exist_ok=True)
                if not target.exists():
                    shutil.copyfile(path, target)
    save_json(root / "groups.json", relocated)
    for filename in ("run-contract.json", "classification.json", "decisions.json"):
        origin = source / filename
        if origin.is_file() and not (root / filename).exists():
            shutil.copyfile(origin, root / filename)


def initialize(args: argparse.Namespace) -> dict[str, Any]:
    root: Path = args.root.resolve()
    existing: Path | None = args.from_workspace.resolve() if args.from_workspace else None
    if existing is not None:
        if not existing.is_dir():
            raise ValueError("source workspace is not a directory")
        if root != existing:
            import_workspace(existing, root)
        for filename in ("groups.json", "run-contract.json", "classification.json"):
            if not (root / filename).is_file():
                raise ValueError(f"existing workspace is missing {filename}")
    else:
        for filename in ("groups.json", "run-contract.json", "classification.json"):
            if (root / filename).exists():
                raise ValueError(
                    "workspace already initialized; use --from-workspace to refresh assets"
                )
        snapshot: Any = load_json(args.items_json) if args.items_json else None
        if isinstance(snapshot, list):
            snapshot = {"items": snapshot}
        if snapshot is not None and not isinstance(snapshot, dict):
            raise ValueError("items JSON must be a list or an object containing items")
        repo = args.repo or (snapshot or {}).get("repo") or detect_repository()
        if not REPO_NAME.fullmatch(repo):
            raise ValueError("repository must be owner/repo")
        if snapshot is None:
            snapshot = github_snapshot(repo)
        raw_items = snapshot.get("items", [])
        if not isinstance(raw_items, list) or any(not isinstance(item, dict) for item in raw_items):
            raise ValueError("items must be a list of objects")
        all_items = [normalize_item(item) for item in raw_items]
        if len({item["number"] for item in all_items}) != len(all_items):
            raise ValueError("item numbers must be unique")
        repo_owner = repo.split("/")[0].lower()
        include_owner = bool(getattr(args, "include_owner", False))
        include_bots = bool(getattr(args, "include_bots", False))
        excluded_counts = {"own_issues": 0, "own_prs": 0, "bot_issues": 0, "bot_prs": 0}
        excluded_authors: set[str] = set(snapshot.get("excluded_authors", []))
        items: list[dict[str, Any]] = []
        for item in all_items:
            author = str(item.get("author", "")).strip()
            author_lower = author.lower()
            is_bot = bool(author) and (author_lower.endswith("[bot]") or author_lower in KNOWN_BOTS)
            is_owner = bool(author) and author_lower == repo_owner
            if is_bot and not include_bots:
                excluded_authors.add(author)
                excluded_counts["bot_prs" if item["type"] == "pr" else "bot_issues"] += 1
                continue
            if is_owner and not include_owner:
                excluded_authors.add(author)
                excluded_counts["own_prs" if item["type"] == "pr" else "own_issues"] += 1
                continue
            items.append(item)
        groups: list[dict[str, Any]] = []
        for component in cluster_items(items):
            first = component[0]
            group_id = f"group-{first['number']}"
            input_paths: list[str] = []
            item_ids: list[str] = []
            for item in component:
                item_id = f"{item['type']}:{item['number']}"
                relative = f"inputs/{item['type']}-{item['number']}.json"
                save_json(root / relative, {"metadata": item, "body": item["body"]})
                input_paths.append(relative)
                item_ids.append(item_id)
            status = first.get("status", {})
            if not isinstance(status, dict):
                raise ValueError("item status must be an object")
            groups.append(
                {
                    "id": group_id,
                    "title": first.get("title", group_id),
                    "area": str(first.get("area", "general")).strip() or "general",
                    "owner": "",
                    "phase": first.get("phase", "research"),
                    "items": item_ids,
                    "input_paths": input_paths,
                }
            )
            save_json(
                root / "groups" / group_id / "status.json",
                {
                    "state": "needs_information",
                    "summary": "Investigation has not started.",
                    "next_action": (
                        "Investigate the original report and prepare an evidence-backed QA plan."
                    ),
                    "blockers": [],
                    "decisions": [],
                    **status,
                },
            )
        save_json(root / "groups.json", groups)
        save_json(
            root / "run-contract.json",
            {
                "repo": repo,
                "login": repo.split("/")[0],
                "base_branch": snapshot.get("base_branch", "main"),
                "base_sha": snapshot.get("base_sha", ""),
                "latest_release": snapshot.get("latest_release"),
                "created_at": datetime.now(UTC).isoformat(),
                "boundary": (
                    "Decisions are records only; execution and merge "
                    "require separate authorization."
                ),
                "excluded_authors": sorted(
                    excluded_authors or {repo.split("/")[0], "dependabot[bot]"}
                ),
                "excluded": snapshot.get("excluded", excluded_counts),
            },
        )
        save_json(
            root / "classification.json",
            {
                "version": 1,
                "frozen": bool(snapshot.get("classification_frozen", len(items) >= 20)),
                "verdicts": {
                    f"{item['type']}:{item['number']}": {"state": "unclassified"} for item in items
                },
            },
        )
    (root / "evidence").mkdir(parents=True, exist_ok=True)
    (root / "groups").mkdir(parents=True, exist_ok=True)
    save_json(root / "decisions.json", {"version": 1, "decisions": {}})
    sync_web(root)
    return {"ok": True, "root": str(root), "summary": builder(root).build()["summary"]}


def builder(root: Path) -> ReportBuilder:
    return ReportBuilder(root, root / "evidence", root / "decisions.json")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def validate(root: Path) -> dict[str, Any]:
    groups = load_json(root / "groups.json")
    contract = load_json(root / "run-contract.json")
    decisions = load_json(root / "decisions.json")
    classification = load_json(root / "classification.json")
    require(isinstance(contract, dict), "run-contract.json must be an object")
    require(
        isinstance(contract.get("repo"), str) and bool(REPO_NAME.fullmatch(contract["repo"])),
        "contract repo must be owner/repo",
    )
    for key in ("base_sha", "base_branch"):
        require(key not in contract or isinstance(contract[key], str), f"{key} must be text")
    latest_release = contract.get("latest_release")
    require(
        latest_release is None or isinstance(latest_release, dict),
        "latest_release must be an object or null",
    )
    if isinstance(latest_release, dict):
        require(isinstance(latest_release.get("tag"), str), "latest_release.tag must be text")
        for key in ("publishedAt", "url"):
            require(
                latest_release.get(key) is None or isinstance(latest_release[key], str),
                f"latest_release.{key} must be text or null",
            )
    require(isinstance(classification, dict), "classification.json must be an object")
    require(isinstance(groups, list), "groups.json must be a list")
    ids: set[str] = set()
    for group in groups:
        require(isinstance(group, dict), "each group must be an object")
        group_id = group.get("id")
        require(
            isinstance(group_id, str) and bool(GROUP_ID.fullmatch(group_id)), "invalid group id"
        )
        require(group_id not in ids, "duplicate group id")
        ids.add(group_id)
        require(isinstance(group.get("title"), str), f"{group_id}: title must be text")
        require(isinstance(group.get("area"), str), f"{group_id}: area must be text")
        require(
            isinstance(group.get("items"), list)
            and all(isinstance(item, str) for item in group["items"]),
            f"{group_id}: items must be strings",
        )
        status = load_json(root / "groups" / group_id / "status.json")
        require(isinstance(status, dict), f"{group_id}: status must be an object")
        require(isinstance(status.get("state"), str), f"{group_id}: status state must be text")
        require(
            isinstance(status.get("blockers", []), list), f"{group_id}: blockers must be a list"
        )
        questions = status.get("decisions", [])
        require(isinstance(questions, list), f"{group_id}: decisions must be a list")
        question_ids: set[str] = set()
        for question in questions:
            require(isinstance(question, dict), f"{group_id}: question must be an object")
            question_id = question.get("id", question.get("decisionId"))
            if question_id is not None:
                require(
                    isinstance(question_id, str) and question_id not in question_ids,
                    f"{group_id}: invalid or duplicate question id",
                )
                question_ids.add(question_id)
            require(isinstance(question.get("options", []), list), "options must be a list")
            require(
                any(
                    isinstance(question.get(key), str) and question[key].strip()
                    for key in ("question", "title")
                ),
                f"{group_id}: question text is missing",
            )
            option_ids: set[str] = set()
            for option in question.get("options", []):
                require(isinstance(option, (dict, str)), "option must be an object or text")
                if not isinstance(option, dict):
                    continue
                require(
                    any(
                        isinstance(option.get(key), str) and option[key].strip()
                        for key in ("label", "title", "text", "name")
                    ),
                    "option label is missing",
                )
                option_id = option.get("id", option.get("optionId", option.get("option_id")))
                if option_id is not None:
                    require(
                        isinstance(option_id, str) and option_id not in option_ids,
                        "invalid or duplicate option id",
                    )
                    option_ids.add(option_id)
    require(
        isinstance(decisions, dict) and isinstance(decisions.get("decisions"), dict),
        "decisions.json must contain a decisions object",
    )
    for group_id, record in decisions["decisions"].items():
        require(group_id in ids and isinstance(record, dict), "invalid stored decision group")
        require(
            record.get("action") in {"approve", "defer", "request_changes", "add_info"},
            f"{group_id}: invalid decision action",
        )
        require(
            record.get("mergeAuthorization", False) is False,
            f"{group_id}: mergeAuthorization must be false",
        )
        require(
            "answers" not in record or isinstance(record["answers"], dict),
            f"{group_id}: answers must be an object",
        )
        for question_id, answer in normalize_decision_record(record)["answers"].items():
            require(isinstance(question_id, str) and isinstance(answer, dict), "invalid answer")
            require(isinstance(answer.get("optionId"), str), "answer optionId must be text")
            require(
                answer.get("action") in {"approve", "defer", "request_changes", "add_info"},
                "invalid answer action",
            )
    report = builder(root).build()
    handoff = builder(root).build_handoff()
    require(len(report["groups"]) == len(groups), "report discarded a group")
    require(
        report["summary"]["active"] + report["summary"]["completed"] == len(groups),
        "active/completed count mismatch",
    )
    require(
        report["summary"]["working"] + report["summary"]["idle"] == len(groups),
        "working/idle count mismatch",
    )
    require(
        handoff["counts"]["undecidedCount"] == report["summary"]["needsDecision"],
        "handoff undecided count mismatch",
    )
    for group in report["groups"]:
        require(
            all(isinstance(group[key], bool) for key in ("ready", "completed", "needsDecision")),
            "report flags must be boolean",
        )
        require(
            isinstance(group.get("agentActivity"), dict)
            and isinstance(group["agentActivity"].get("active"), bool)
            and isinstance(group["agentActivity"].get("harnesses"), list),
            "report agentActivity must be a valid activity object",
        )
        require(isinstance(group["areaLabel"], str), "report areaLabel must be text")
        require(isinstance(group["questions"], list), "report questions must be a list")
        require(
            all(isinstance(group[key], dict) for key in ("qa", "review", "status")),
            "assessment fields must be objects",
        )
        require(isinstance(group["items"], list), "report items must be a list")
        require(
            all(
                isinstance(item, dict) and isinstance(item.get("id"), str)
                for item in group["items"]
            ),
            "report items must have text ids",
        )
    require(
        len(report["areaCatalog"]) == len({group["area"] for group in report["groups"]}),
        "area catalog does not cover every distinct area",
    )
    require(
        handoff["counts"]["decidedCount"] == len(handoff["queue"]), "handoff decided count mismatch"
    )
    require(
        all(isinstance(item.get("agentInstruction"), str) for item in handoff["queue"]),
        "handoff instructions must be text",
    )
    require(isinstance(handoff["resumePrompt"], str), "resumePrompt must be text")
    require(
        all(isinstance(item["answers"], list) for item in handoff["queue"]),
        "handoff answers must be a list",
    )
    return {
        "ok": True,
        "repository": report["repository"],
        "summary": report["summary"],
        "handoffCounts": handoff["counts"],
    }


def filter_active(handoff: dict[str, Any]) -> dict[str, Any]:
    result = dict(handoff)
    result["queue"] = [item for item in handoff["queue"] if not item["completed"]]
    counts = dict(handoff["counts"])
    counts["decidedCount"] = len(result["queue"])
    for key, action in (
        ("approvedCount", "approve"),
        ("deferredCount", "defer"),
        ("changesRequestedCount", "request_changes"),
        ("infoRequestedCount", "add_info"),
    ):
        counts[key] = sum(item["action"] == action for item in result["queue"])
    result["counts"] = counts
    result["resumePrompt"] = handoff_prompt(result)
    return result


def update_activity(args: argparse.Namespace) -> dict[str, Any]:
    root = resolve_root(args.root)
    groups = load_json(root / "groups.json")
    ids = {group.get("id") for group in groups if isinstance(group, dict)}
    require(args.group in ids, f"unknown group: {args.group}")
    active = args.state == "working"
    payload: dict[str, Any] = {
        "active": active,
        "state": args.state,
        "updatedAt": datetime.now(UTC).isoformat(),
    }
    if args.harness:
        payload["harness"] = args.harness
    if args.pid is not None:
        payload["pid"] = args.pid
    path = root / "groups" / args.group / "activity.json"
    save_json(path, payload, overwrite=True)
    return {"ok": True, "group": args.group, "activity": payload}


def wait_for_submission(args: argparse.Namespace) -> dict[str, Any]:
    root = resolve_root(args.root)
    deadline = time.monotonic() + args.timeout if args.timeout > 0 else None
    while True:
        handoff = builder(root).build_handoff()
        if args.only_active:
            handoff = filter_active(handoff)
        submission = handoff.get("submission", {})
        if isinstance(submission, dict) and submission.get("submitted") is True:
            return handoff
        if deadline is not None and time.monotonic() >= deadline:
            raise ValueError("timed out waiting for feedback submission")
        time.sleep(0.35)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    init = commands.add_parser("init", help="create a workspace or refresh existing web assets")
    init.add_argument("--root", required=True, type=Path)
    init.add_argument("--from-workspace", type=Path)
    init.add_argument("--repo")
    init.add_argument("--items-json", type=Path)
    init.add_argument("--include-owner", action="store_true")
    init.add_argument("--include-bots", action="store_true")
    check = commands.add_parser("validate")
    check.add_argument("--root", type=Path, default=None)
    status = commands.add_parser("status")
    status.add_argument("--root", type=Path, default=None)
    status.add_argument("--format", choices=("json", "table"), default="table")
    handoff = commands.add_parser("handoff")
    handoff.add_argument("--root", type=Path, default=None)
    handoff.add_argument("--format", choices=("json", "prompt", "markdown"), default="json")
    handoff.add_argument("--only-active", action="store_true")
    wait_cmd = commands.add_parser("wait", help="wait until the owner clicks Submit in the cockpit")
    wait_cmd.add_argument("--root", type=Path, default=None)
    wait_cmd.add_argument("--format", choices=("json", "prompt", "markdown"), default="prompt")
    wait_cmd.add_argument("--only-active", action="store_true")
    wait_cmd.add_argument("--timeout", type=float, default=0.0)
    activity = commands.add_parser("activity", help="record or clear harness activity for a group")
    activity.add_argument("--root", type=Path, default=None)
    activity.add_argument("--group", required=True)
    activity.add_argument("--state", choices=("working", "idle"), required=True)
    activity.add_argument("--harness", default=None)
    activity.add_argument("--pid", type=int, default=None)
    serve = commands.add_parser("serve")
    serve.add_argument("--root", required=True, type=Path)
    serve.add_argument("--bind", default="127.0.0.1")
    serve.add_argument("--port", default=8787, type=int)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    try:
        if args.command == "serve":
            raise SystemExit(
                subprocess.call(
                    [
                        sys.executable,
                        str(Path(__file__).with_name("server.py")),
                        "--root",
                        str(args.root),
                        "--bind",
                        args.bind,
                        "--port",
                        str(args.port),
                    ]
                )
            )
        if args.command == "init":
            value = initialize(args)
        elif args.command == "activity":
            value = update_activity(args)
        elif args.command == "validate":
            root = resolve_root(args.root)
            value = validate(root)
        elif args.command in {"handoff", "wait"}:
            if args.command == "wait":
                value = wait_for_submission(args)
            else:
                root = resolve_root(args.root)
                value = builder(root).build_handoff()
                if args.only_active:
                    value = filter_active(value)
            if args.format != "json":
                print(value["resumePrompt"], end="")
                return
        else:
            root = resolve_root(args.root)
            report = builder(root).build()
            value = {
                "repository": report["repository"],
                "summary": report["summary"],
                "undecided": builder(root).build_handoff()["undecided"],
            }
            if args.format == "table":
                summary = report["summary"]
                print(f"Repository: {report['repository']}")
                print(
                    f"Total: {summary['total']}  Active: {summary['active']}  "
                    f"Working: {summary['working']}  Completed: {summary['completed']}  "
                    f"Undecided: {summary['needsDecision']}"
                )
                print("GROUP\tSTATE\tHARNESS\tTITLE")
                for group in report["groups"]:
                    state = "completed" if group["completed"] else group["status"]["state"]
                    harness_info = group["agentActivity"]["label"]
                    print(f"{group['id']}\t{state}\t{harness_info}\t{group['title']}")
                return
        print(json.dumps(value, ensure_ascii=False, indent=2))
    except (OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError) as error:
        print(json.dumps({"ok": False, "error": str(error)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
