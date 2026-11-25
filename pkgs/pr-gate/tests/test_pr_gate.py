import argparse
import contextlib
import datetime as dt
import io
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import warnings
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("pr_gate", Path(__file__).parents[1] / "src" / "pr_gate.py")
pr_gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pr_gate)


class GateHelpersTests(unittest.TestCase):
    def test_marker_uses_review_marker_not_commit_id(self):
        self.assertEqual(pr_gate.marker_sha("x <!-- issue-agent:delivery:review:ABCDEF123 -->"), "abcdef123")
        self.assertIsNone(pr_gate.marker_sha("commit_id=abcdef123"))
        self.assertEqual(pr_gate.newest_reviewed_sha([
            {"user": {"login": pr_gate.REVIEWER}, "body": "<!-- issue-agent:delivery:review:abc1234 -->", "submitted_at": "2026-01-01T00:00:00Z", "id": 1},
            {"user": {"login": pr_gate.REVIEWER}, "body": "<!-- issue-agent:63fd7c00-dffe-11f1-8027-9ff7e9ad9b2c:review:17c568dae157affd621f64df8c23ee25b89ccbf8 -->", "commit_id": "def5678", "submitted_at": "2026-01-02T00:00:00Z", "id": 2},
        ]), "17c568dae157affd621f64df8c23ee25b89ccbf8")

    def test_docs_only_and_empty_delta(self):
        self.assertTrue(pr_gate.docs_only(["README.md", "docs/guide.mdx", "LICENSE"]))
        self.assertFalse(pr_gate.docs_only(["README.md", "src/main.py"]))
        self.assertFalse(pr_gate.docs_only([]))

    def test_review_bound(self):
        open_pr = {"state": "OPEN", "isDraft": False}
        self.assertTrue(pr_gate.review_bound("example/repo", open_pr, [], ("example/repo",)))
        self.assertTrue(pr_gate.review_bound("other/repo", open_pr, [{"user": {"login": pr_gate.REVIEWER}}], ()))
        self.assertFalse(pr_gate.review_bound("example/repo", {**open_pr, "isDraft": True}, [], ("example/repo",)))
        self.assertFalse(pr_gate.review_bound("other/repo", open_pr, [], ()))

    def test_consecutive_partials_require_author_reply_and_trailing_replies(self):
        thread = {"comments": {"nodes": [
            {"author": {"login": pr_gate.REVIEWER}, "body": "finding"},
            {"author": {"login": "author"}, "body": "fixed"},
            {"author": {"login": pr_gate.REVIEWER}, "body": "Partially fixed: one case remains"},
            {"author": {"login": pr_gate.REVIEWER}, "body": "partially fixed: another case"},
        ]}}
        self.assertEqual(pr_gate.consecutive_partials(thread), 2)
        self.assertEqual(pr_gate.consecutive_partials({"comments": {"nodes": thread["comments"]["nodes"][:1]}}), 0)

    def test_observation_and_run_permissions_and_dedup(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            root.chmod(0o700)
            pr_gate.write_json(root / "result.json", {"ok": True})
            self.assertEqual((root.stat().st_mode & 0o777), 0o700)
            self.assertEqual((root.joinpath("result.json").stat().st_mode & 0o777), 0o600)
            run = root / "run"
            self.assertTrue(pr_gate.acquire_dedup(run, "version"))
            self.assertFalse(pr_gate.acquire_dedup(run, "version"))
            self.assertTrue(pr_gate.acquire_dedup(run, "other-version"))

    def test_busy_slot(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            slots = [pr_gate.acquire_slot(root), pr_gate.acquire_slot(root)]
            self.assertIsNotNone(slots[0])
            self.assertIsNotNone(slots[1])
            self.assertIsNone(pr_gate.acquire_slot(root))
            for slot in slots:
                os.close(slot[0])

    def test_token_usage_sum_and_unparseable_values_are_null(self):
        usage = pr_gate.parse_usage(json.dumps({"type": "turn.completed", "usage": {"input_tokens": 10, "cached_input_tokens": 4, "output_tokens": 3}}) + "\n" + json.dumps({"usage": {"input_tokens": 2, "output_tokens": 1}}))
        self.assertEqual(usage, {"input_tokens": 12, "cached_input_tokens": 4, "output_tokens": 4})
        self.assertEqual(pr_gate.parse_usage("not-json"), {"input_tokens": None, "cached_input_tokens": None, "output_tokens": None})

    def test_codex_timeout_kills_process_group(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            data = root / "data"
            data.mkdir()
            (data / "gate-prompt.md").write_text("hello {repo}")
            (data / "gate-schema.json").write_text("{}")
            fake = root / "codex"
            fake.write_text("#!/bin/sh\nsleep 30\n")
            fake.chmod(0o755)
            run = root / "run"
            run.mkdir()
            snap = root / "snapshot"
            snap.mkdir()
            old_deadline = pr_gate.ACTIVE_DEADLINE
            pr_gate.ACTIVE_DEADLINE = __import__("time").monotonic() + 0.05
            try:
                with patch.dict(os.environ, {"PATH": str(root), "PR_GATE_DATA_DIR": str(data)}):
                    status, _, _ = pr_gate.run_codex(run, snap, {"repo": "x", "pr": 1, "head_sha": "h", "last_reviewed_sha": "l", "packet": "p"})
                self.assertEqual(status, "timeout")
            finally:
                pr_gate.ACTIVE_DEADLINE = old_deadline

FAKE_TOOL = r'''
import json
import os
from pathlib import Path
import sys

name = Path(sys.argv[0]).name
args = sys.argv[1:]
root = Path(os.environ["FAKE_GATE_ROOT"])
entry = {"argv": args}
if name == "codex":
    snapshot = Path(args[args.index("--cd") + 1])
    entry["snapshot"] = {str(p.relative_to(snapshot)): p.read_text() for p in snapshot.rglob("*") if p.is_file()}
    entry["prompt"] = sys.stdin.read()
with (root / (name + ".jsonl")).open("a") as handle:
    handle.write(json.dumps(entry) + "\n")
if name == "git":
    os.execv(os.environ["REAL_GIT"], [os.environ["REAL_GIT"], *args])
fixture = json.loads((root / "fixture.json").read_text())
if name == "codex":
    if "--skip-git-repo-check" not in args and not (snapshot / ".git").exists():
        print("not inside a trusted git repository", file=sys.stderr)
        sys.exit(1)
    Path(args[args.index("--output-last-message") + 1]).write_text(json.dumps(fixture["result"]))
    print(json.dumps({"type": "turn.completed", "usage": {"input_tokens": 10, "cached_input_tokens": 4, "output_tokens": 3}}))
elif fixture.get("gh_mode") == "error":
    print("authentication failed", file=sys.stderr)
    sys.exit(1)
elif fixture.get("gh_mode") == "malformed":
    print("{invalid json")
elif args[:2] == ["pr", "view"]:
    if fixture.get("gh_mode") == "no_pr":
        print("no pull requests found for branch", file=sys.stderr)
        sys.exit(1)
    print(json.dumps(fixture["pr"]))
elif args[:2] == ["api", "graphql"]:
    print(json.dumps({"data": {"repository": {"pullRequest": {"reviewThreads": {"nodes": fixture["threads"]}}}}}))
elif any("/reviews?" in arg for arg in args):
    print(json.dumps(fixture["reviews"]))
elif any("/comments?" in arg for arg in args):
    print(json.dumps(fixture.get("comments", [])))
elif any("/compare/" in arg for arg in args):
    if "Accept: application/vnd.github.diff" in args:
        print(fixture.get("compare_patch", ""), end="")
    else:
        print(json.dumps({"files": [{"filename": "src.py"}]}))
else:
    raise SystemExit("unexpected gh command: " + repr(args))
'''


class GateWorkerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ.get("PR_GATE_TEST_SCRATCH"))
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.real_git = shutil.which("git")
        self.env = {
            **os.environ, "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_AUTHOR_NAME": "Gate Test", "GIT_AUTHOR_EMAIL": "gate@example.invalid",
            "GIT_COMMITTER_NAME": "Gate Test", "GIT_COMMITTER_EMAIL": "gate@example.invalid",
            "GIT_OPTIONAL_LOCKS": "0",
        }
        self.git("init", "-b", "main")
        self.git("config", "remote.origin.url", "git@github.com:isac322/cc-lb.git")
        self.base = self.commit("src.py", "initial\n")
        self.git("checkout", "-b", "fix")
        self.last = self.commit("src.py", "reviewed\n")
        self.head = self.commit("src.py", "fixed\n")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("gh", "codex", "git"):
            tool = self.bin / name
            tool.write_text(f"#!{sys.executable}\n" + FAKE_TOOL)
            tool.chmod(0o755)
        self.env.update({
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "REAL_GIT": self.real_git, "FAKE_GATE_ROOT": str(self.root),
            "XDG_STATE_HOME": str(self.root / "state"), "PR_GATE_REPOS": "isac322/cc-lb",
            "PR_GATE_DATA_DIR": str(Path(pr_gate.__file__).parent),
            "PR_GATE_DEADLINE": "10",
        })
        self.trigger_ts = "2026-11-17T12:00:00.000000Z"
        self.fixture = {
            "pr": {"number": 17, "state": "OPEN", "isDraft": False, "headRefOid": self.head,
                   "baseRefName": "main", "title": "Fix contract", "body": "Preserve behavior",
                   "closingIssuesReferences": []},
            "reviews": [self.review(self.last)], "threads": [],
            "result": {"verdict": "BLOCKING", "threads": [], "new_findings": [
                {"mechanism": "missed case", "evidence": "src.py:1", "severity": "P1"}
            ], "reason": "Counterexample"},
        }

    def git(self, *args):
        return subprocess.check_output([self.real_git, "-C", str(self.repo), *args],
                                       env=self.env, stderr=subprocess.PIPE).decode().strip()

    def commit(self, path, content):
        (self.repo / path).write_text(content)
        self.git("add", path)
        self.git("-c", "commit.gpgsign=false", "commit", "-m", "test change")
        return self.git("rev-parse", "HEAD")

    def review(self, sha, timestamp="2026-11-17T11:00:00Z", review_id=1):
        return {"id": review_id, "user": {"login": pr_gate.REVIEWER},
                "body": f"<!-- issue-agent:delivery:review:{sha} -->",
                "commit_id": self.base, "submitted_at": timestamp, "state": "CHANGES_REQUESTED"}

    def calls(self, name):
        log = self.root / (name + ".jsonl")
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    def worker(self):
        (self.root / "fixture.json").write_text(json.dumps(self.fixture))
        args = argparse.Namespace(cwd=str(self.repo), trigger="push", git_dir_hint=None,
                                  command="git push", trigger_ts=self.trigger_ts)
        old_deadline = pr_gate.ACTIVE_DEADLINE
        try:
            with patch.dict(os.environ, self.env, clear=True):
                pr_gate.observe_worker(args)
        finally:
            pr_gate.ACTIVE_DEADLINE = old_deadline
            for key, fd in list(pr_gate.DEDUP_FDS.items()):
                if key.startswith(str(self.root)):
                    os.close(fd)
                    del pr_gate.DEDUP_FDS[key]
        rows = self.root / "state" / "pr-gate" / "observations.jsonl"
        return json.loads(rows.read_text().splitlines()[-1])

    def repo_state(self):
        return {
            "files": {str(p.relative_to(self.repo)): p.read_bytes()
                      for p in self.repo.rglob("*") if p.is_file()},
            "refs": self.git("show-ref"), "worktrees": self.git("worktree", "list", "--porcelain"),
            "config": self.git("config", "--local", "--list"),
            "status": self.git("status", "--porcelain=v1", "--untracked-files=all"),
        }

    def test_model_snapshot_is_read_only_and_codex_runs_once(self):
        (self.repo / "src.py").write_text("staged edit\n")
        self.git("add", "src.py")
        (self.repo / "src.py").write_text("unstaged edit\n")
        (self.repo / "untracked.txt").write_text("private dirty data\n")
        before = self.repo_state()
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always", ResourceWarning)
            row = self.worker()
        self.assertEqual([warning for warning in caught if issubclass(warning.category, ResourceWarning)], [])
        self.assertEqual((row["path"], row["status"], row["verdict"]), ("model", "ok", "BLOCKING"))
        self.assertTrue(row["would_block"])
        calls = self.calls("codex")
        self.assertEqual(len(calls), 1)
        argv = calls[0]["argv"]
        self.assertEqual(argv[argv.index("--sandbox") + 1], "read-only")
        self.assertIn("--skip-git-repo-check", argv)
        self.assertIn("--ephemeral", argv)
        self.assertEqual(argv[argv.index("--output-schema") + 1], str(Path(pr_gate.__file__).parent / "gate-schema.json"))
        self.assertEqual(calls[0]["snapshot"], {"src.py": "fixed\n"})
        self.assertFalse((Path(row["run_dir"]) / "snapshot").exists())
        self.assertEqual(self.repo_state(), before)
        self.assertEqual(row["input_tokens"], 10)

    def test_draft_is_skipped(self):
        self.fixture["pr"]["isDraft"] = True
        row = self.worker()
        self.assertEqual((row["path"], row["skip_reason"]), ("skipped", "not_review_bound"))
        self.assertEqual(self.calls("codex"), [])

    def test_no_pr_is_skipped(self):
        self.fixture["gh_mode"] = "no_pr"
        row = self.worker()
        self.assertEqual((row["path"], row["status"]), ("skipped", "ok"))
        self.assertEqual(row["skip_reason"], "no_pr")
        self.assertEqual(self.calls("codex"), [])

    def test_unlisted_without_reviewer_is_skipped(self):
        self.env["PR_GATE_REPOS"] = "other/repo"
        self.fixture["reviews"] = []
        row = self.worker()
        self.assertEqual((row["path"], row["skip_reason"]), ("skipped", "not_review_bound"))
        self.assertEqual(self.calls("codex"), [])

    def test_empty_commit_is_inert(self):
        self.fixture["reviews"] = [self.review(self.head)]
        self.git("-c", "commit.gpgsign=false", "commit", "--allow-empty", "-m", "empty")
        self.fixture["pr"]["headRefOid"] = self.git("rev-parse", "HEAD")
        row = self.worker()
        self.assertEqual((row["path"], row["status"]), ("inert", "ok"))
        self.assertEqual(self.calls("codex"), [])

    def test_base_advance_with_identical_three_dot_diff_is_inert(self):
        self.fixture["reviews"] = [self.review(self.head)]
        self.git("checkout", "main")
        self.commit("base.py", "base advance\n")
        self.git("checkout", "fix")
        self.git("-c", "commit.gpgsign=false", "merge", "--no-edit", "main")
        self.fixture["pr"]["headRefOid"] = self.git("rev-parse", "HEAD")
        row = self.worker()
        self.assertEqual((row["path"], row["status"]), ("inert", "ok"))
        self.assertEqual(self.calls("codex"), [])

    def test_docs_delta_avoids_codex(self):
        self.fixture["reviews"] = [self.review(self.head)]
        self.fixture["pr"]["headRefOid"] = self.commit("README.md", "documentation\n")
        row = self.worker()
        self.assertEqual((row["path"], row["status"]), ("docs_only", "ok"))
        self.assertEqual(self.calls("codex"), [])

    def test_unobserved_push_has_separate_short_deadline(self):
        self.fixture["pr"]["headRefOid"] = self.base
        with patch.object(pr_gate, "PUSH_WAIT", 0.05):
            row = self.worker()
        self.assertEqual((row["status"], row["skip_reason"]), ("push_not_observed", "push_not_observed"))
        self.assertEqual(self.calls("codex"), [])

    def test_gh_failures_are_contained(self):
        for mode in ("error", "malformed"):
            with self.subTest(mode=mode):
                self.fixture["gh_mode"] = mode
                row = self.worker()
                self.assertEqual(row["status"], "error")
                self.assertIn("authentication failed" if mode == "error" else "malformed JSON", row["skip_reason"])
                self.assertEqual(self.calls("codex"), [])

    def test_after_trigger_reviews_and_thread_comments_are_blinded(self):
        self.fixture["reviews"].append(self.review(self.head, "2026-11-17T12:00:01Z", 2))
        self.fixture["threads"] = [
            {"id": "old", "isResolved": False, "comments": {"nodes": [
                {"author": {"login": pr_gate.REVIEWER}, "body": "old finding", "createdAt": "2026-11-17T11:00:00Z"},
                {"author": {"login": pr_gate.REVIEWER}, "body": "FUTURE_SECRET", "createdAt": "2026-11-17T12:00:01Z"},
            ]}},
            {"id": "future", "isResolved": False, "comments": {"nodes": [
                {"author": {"login": pr_gate.REVIEWER}, "body": "FUTURE_SECRET", "createdAt": "2026-11-17T12:00:01Z"},
            ]}},
        ]
        row = self.worker()
        self.assertEqual(row["status"], "ok")
        self.assertEqual(row["last_reviewed_sha"], self.last)
        packet = Path(row["run_dir"]) / "packet" / "threads.json"
        threads = json.loads(packet.read_text())
        self.assertEqual([thread["id"] for thread in threads], ["old"])
        self.assertNotIn("FUTURE_SECRET", packet.read_text())

    def test_dedup_keys_include_pr_number(self):
        first = self.worker()
        self.assertEqual(first["status"], "ok")
        second = self.worker()
        self.assertEqual(second["skip_reason"], "duplicate")
        self.assertEqual(len(self.calls("codex")), 1)
        self.fixture["pr"]["number"] = 18
        third = self.worker()
        self.assertEqual((third["path"], third["status"]), ("model", "ok"))
        self.assertNotEqual(first["run_dir"], third["run_dir"])
        self.assertEqual(len(self.calls("codex")), 2)

    def test_worker_git_commands_are_read_only(self):
        row = self.worker()
        self.assertEqual((row["path"], row["status"]), ("model", "ok"))
        calls = self.calls("git")
        self.assertTrue(calls)
        allowed = {"rev-parse", "symbolic-ref", "config", "cat-file", "diff", "patch-id", "archive"}
        for call in calls:
            argv = call["argv"]
            self.assertEqual(argv[:2], ["-C", str(self.repo)])
            self.assertIn(argv[2], allowed)
            if argv[2] == "config":
                self.assertEqual(argv[3:], ["--get", "remote.origin.url"])

    def test_remote_tracking_base_works_without_local_base(self):
        self.git("update-ref", "refs/remotes/origin/main", self.base)
        self.git("branch", "-D", "main")
        row = self.worker()
        self.assertEqual((row["path"], row["status"]), ("model", "ok"))

    def test_remote_tracking_base_preferred_to_stale_local_base(self):
        self.git("update-ref", "refs/remotes/origin/main", self.base)
        self.git("update-ref", "refs/heads/main", self.head)
        self.fixture["reviews"] = []
        row = self.worker()
        self.assertEqual((row["path"], row["status"]), ("model", "ok"))
        delta = (Path(row["run_dir"]) / "packet" / "delta.patch").read_text()
        self.assertIn("+fixed", delta)

    def test_missing_base_uses_compare_api_without_fast_paths(self):
        self.git("branch", "-D", "main")
        self.fixture["compare_patch"] = "diff --git a/src.py b/src.py\n+fixed\n"
        row = self.worker()
        self.assertEqual((row["path"], row["status"]), ("model", "ok"))
        self.assertEqual((Path(row["run_dir"]) / "packet" / "delta.patch").read_text(), self.fixture["compare_patch"])
        self.assertTrue(any("/compare/" in " ".join(c["argv"]) for c in self.calls("gh")))
        self.assertEqual((Path(row["run_dir"]) / "packet" / "pr-files.txt").read_text(), "src.py\n")

    def test_missing_reviewed_commit_uses_raw_compare_delta(self):
        self.fixture["reviews"] = [self.review("a" * 40)]
        self.fixture["compare_patch"] = "diff --git a/src.py b/src.py\n+fixed\n"
        row = self.worker()
        self.assertEqual((row["path"], row["status"]), ("model", "ok"))
        self.assertEqual((Path(row["run_dir"]) / "packet" / "delta.patch").read_text(), self.fixture["compare_patch"])

    def test_first_review_without_local_base_uses_compare_delta(self):
        self.git("branch", "-D", "main")
        self.fixture["reviews"] = []
        self.fixture["compare_patch"] = "diff --git a/src.py b/src.py\n+fixed\n"
        row = self.worker()
        self.assertEqual((row["path"], row["status"]), ("model", "ok"))
        self.assertEqual((Path(row["run_dir"]) / "packet" / "delta.patch").read_text(), self.fixture["compare_patch"])

    def test_report_matches_marker_and_distinguishes_grace_period(self):
        matched = self.worker()
        now = dt.datetime.now(dt.timezone.utc)
        pending = {**matched, "head_sha": "a" * 40, "ts": (now - dt.timedelta(minutes=30)).isoformat()}
        old = {**matched, "head_sha": "b" * 40, "ts": (now - dt.timedelta(hours=4)).isoformat()}
        self.fixture["reviews"] = [self.review(self.head)]
        self.fixture["comments"] = [
            {"pull_request_review_id": 1, "path": "src.py", "body": "Partially fixed: missed case"},
            {"pull_request_review_id": 999, "path": "other.py", "body": "unrelated"},
        ]
        (self.root / "fixture.json").write_text(json.dumps(self.fixture))
        output = self.root / "report.json"
        with patch.dict(os.environ, self.env, clear=True), contextlib.redirect_stdout(io.StringIO()):
            state = pr_gate.state_root()
            pr_gate.append_observation(state, pending)
            pr_gate.append_observation(state, old)
            result = pr_gate.report(argparse.Namespace(since="2026-01-01", json=str(output)))
        self.assertEqual(result, 0)
        report = json.loads(output.read_text())
        self.assertEqual([pair["status"] for pair in report["pairs"]], ["matched", "pending", "no_review"])
        self.assertEqual(report["summary"]["both"], 1)
        self.assertEqual(len(report["pairs"][0]["haechibot"]["partial_replies"]), 1)

    def test_observe_honors_valid_extension_trigger_timestamp(self):
        args = argparse.Namespace()
        with patch.dict(os.environ, {"PR_GATE_TRIGGER_TS": self.trigger_ts}), patch.object(pr_gate.os, "fork", return_value=123):
            self.assertEqual(pr_gate.observe(args), 0)
        self.assertEqual(args.trigger_ts, self.trigger_ts)

    def test_observe_normalizes_extension_timestamp_to_utc(self):
        args = argparse.Namespace()
        with patch.dict(os.environ, {"PR_GATE_TRIGGER_TS": "2026-11-17T21:00:00.123456+09:00"}), patch.object(pr_gate.os, "fork", return_value=123):
            self.assertEqual(pr_gate.observe(args), 0)
        self.assertEqual(args.trigger_ts, "2026-11-17T12:00:00.123456Z")

    def test_observe_replaces_invalid_extension_trigger_timestamp(self):
        args = argparse.Namespace()
        with patch.dict(os.environ, {"PR_GATE_TRIGGER_TS": "invalid"}), patch.object(pr_gate.os, "fork", return_value=123):
            self.assertEqual(pr_gate.observe(args), 0)
        dt.datetime.fromisoformat(args.trigger_ts.replace("Z", "+00:00"))


class TriggerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        env = patch.dict(os.environ, {"XDG_STATE_HOME": self.temp.name}, clear=False)
        env.start()
        self.addCleanup(env.stop)
        os.environ.pop("PR_GATE_DISABLE", None)
        observe = patch.object(pr_gate, "observe", return_value=0)
        self.observe = observe.start()
        self.addCleanup(observe.stop)

    def observed(self) -> list[argparse.Namespace]:
        return [call.args[0] for call in self.observe.call_args_list]

    def run_hook(self, harness: str, payload: object) -> str:
        stdout = io.StringIO()
        raw = payload if isinstance(payload, str) else json.dumps(payload)
        with patch.object(sys, "stdin", io.StringIO(raw)), contextlib.redirect_stdout(stdout):
            self.assertEqual(pr_gate.hook(argparse.Namespace(harness=harness)), 0)
        return stdout.getvalue()

    def test_trigger_grammar(self):
        cases = [
            ("git push", "push"),
            ("git -C ~/src/repo push origin main", "push"),
            ("cd 'repo with spaces' && git push", "push"),
            ("env FOO=1 git push", "push"),
            ("GIT_SSH_COMMAND='ssh -i key' command git push", "push"),
            ("git push --force-with-lease origin HEAD:branch", "push"),
            ("git push origin main refs/heads/a:refs/heads/b", "push"),
            ("git push origin main || true", "push"),
            ("git push --dry-run", None),
            ("git push -n origin main", None),
            ("git push --help", None),
            ("make test;git push -n", None),
            ("make test&&git push --dry-run", None),
            ("git push && ls -n", "push"),
            ("gh pr create --fill && git branch -d old", "pr-create"),
            ("git status\ngit push", "push"),
            ("gh pr create --title change", "pr-create"),
            ("gh pr create --draft", None),
            ("gh pr create -d", None),
            ("gh pr ready", "pr-ready"),
            ("gh pr ready --undo", None),
            ("git pushd", None),
            ("echo 'git push'", None),
            ("git status", None),
        ]
        for command, expected in cases:
            with self.subTest(command=command):
                parsed = pr_gate.parse_trigger(command)
                self.assertEqual(parsed[0] if parsed else None, expected)

    def test_trigger_directory_resolution(self):
        home = str(Path.home())
        self.assertEqual(pr_gate.parse_trigger("git -C ~/src/repo push"), ("push", "~/src/repo"))
        self.assertEqual(pr_gate.parse_trigger("cd 'repo with spaces' && git push"), ("push", "repo with spaces"))
        self.assertEqual(pr_gate.parse_trigger("git push; cd elsewhere"), ("push", None))
        self.assertEqual(pr_gate.resolve_workdir("~/src/repo", "/work"), f"{home}/src/repo")
        self.assertEqual(pr_gate.resolve_workdir("sub", "/work"), "/work/sub")
        self.assertEqual(pr_gate.resolve_workdir(None, "/work"), "/work")

    def test_claude_hook_dispatches_main_and_subagent_bash(self):
        payload = {"hook_event_name": "PostToolUse", "tool_name": "Bash", "tool_input": {"command": "git push origin main"}, "cwd": "/work/a"}
        self.assertEqual(self.run_hook("claude", payload), "")
        self.run_hook("claude", {**payload, "cwd": "/work/b", "agent_id": "a1", "agent_type": "browser"})
        observed = self.observed()
        self.assertEqual([(args.cwd, args.trigger) for args in observed], [("/work/a", "push"), ("/work/b", "push")])
        self.assertEqual(os.environ["PR_GATE_HARNESS"], "claude")
        self.assertEqual(os.environ["PR_GATE_AGENT_KIND"], "subagent")

    def test_codex_hook_dispatches_string_and_argv_commands(self):
        self.run_hook("codex", {"tool_name": "Bash", "tool_input": {"command": "gh pr create --fill"}, "cwd": "/work/a", "tool_response": "ok"})
        self.assertEqual(os.environ["PR_GATE_AGENT_KIND"], "main")
        self.run_hook("codex", {"tool_name": "Bash", "tool_input": {"command": ["bash", "-lc", "git push"]}, "cwd": "/work/b"})
        self.assertEqual([(args.cwd, args.trigger) for args in self.observed()], [("/work/a", "pr-create"), ("/work/b", "push")])
        self.assertEqual(os.environ["PR_GATE_HARNESS"], "codex")

    def test_agy_hook_uses_tool_cwd_skips_failures_and_always_answers(self):
        call = {"name": "run_command", "args": {"CommandLine": "git push", "Cwd": "/work/tool"}}
        self.assertEqual(json.loads(self.run_hook("agy", {"toolCall": call, "cwd": "/work/agent"})), {})
        self.assertEqual(json.loads(self.run_hook("agy", {"toolCall": {**call, "args": {"CommandLine": "gh pr ready"}}, "cwd": "/work/agent"})), {})
        self.assertEqual(json.loads(self.run_hook("agy", {"toolCall": call, "cwd": "/work/x", "error": "exit status 1"})), {})
        self.assertEqual(json.loads(self.run_hook("agy", {"toolCall": {**call, "args": {"CommandLine": "git push", "Cwd": "/work/ok"}}, "error": ""})), {})
        self.assertEqual([(args.cwd, args.trigger) for args in self.observed()], [("/work/tool", "push"), ("/work/agent", "pr-ready"), ("/work/ok", "push")])
        self.assertEqual(os.environ["PR_GATE_HARNESS"], "agy")

    def test_irrelevant_or_malformed_payloads_do_nothing(self):
        for harness, payload in [
            ("claude", {"tool_name": "Edit", "tool_input": {"command": "git push"}, "cwd": "/w"}),
            ("claude", {"tool_name": "Bash", "tool_input": {"command": "git status"}, "cwd": "/w"}),
            ("codex", {"tool_name": "Bash", "tool_input": {"command": "git push"}}),
            ("codex", "not json"),
            ("codex", ""),
            ("agy", {"toolCall": {"name": "view_file", "args": {"CommandLine": "git push"}}, "cwd": "/w"}),
            ("agy", "[1, 2"),
        ]:
            with self.subTest(harness=harness, payload=payload):
                output = self.run_hook(harness, payload)
                self.assertEqual(output.strip(), "{}" if harness == "agy" else "")
        self.assertEqual(self.observed(), [])

    def test_disable_switch_and_debounce(self):
        with patch.dict(os.environ, {"PR_GATE_DISABLE": "1"}):
            self.assertFalse(pr_gate.dispatch("omp", "git push", "/w", "main"))
        self.assertTrue(pr_gate.dispatch("omp", "git push", "/w", "main"))
        self.assertFalse(pr_gate.dispatch("claude", "git push origin main", "/w", "main"))
        self.assertTrue(pr_gate.dispatch("claude", "gh pr create", "/w", "main"))
        self.assertTrue(pr_gate.dispatch("claude", "git push", "/other", "main"))
        root = pr_gate.state_root()
        self.assertFalse(pr_gate.debounced(root, "k", now=100.0))
        self.assertTrue(pr_gate.debounced(root, "k", now=104.0))
        self.assertFalse(pr_gate.debounced(root, "k", now=110.0))
        self.assertEqual(len(self.observed()), 3)

    def test_dispatch_marks_observation_with_harness(self):
        pr_gate.dispatch("codex", "git push", "/w", "subagent")
        row = pr_gate.default_observation()
        self.assertEqual((row["harness"], row["agent_kind"]), ("codex", "subagent"))


if __name__ == "__main__":
    unittest.main()
