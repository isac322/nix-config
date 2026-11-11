"""Transport contracts at the gh subprocess boundary, without network traffic.

Primary references (accessed 2026-11-11):
* https://cli.github.com/manual/gh_api -- --paginate/--slurp page envelope.
* https://github.com/cli/cli/blob/trunk/pkg/cmd/api/api.go -- apiRun,
  processResponse, parseErrorResponse: error bodies remain on stdout, the
  message and HTTP status normally appear on stderr, and exit status is nonzero.
* https://docs.github.com/en/rest/using-the-rest-api/troubleshooting-the-rest-api
  -- rate-limit, private-resource 404, permissions, and 422 response contracts.
* https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api
  -- rate-limit errors require a delay of at least one minute without headers.

The fixtures model gh's process output, not an HTTP server or GitHub logic.
Malformed output is deliberate transport fault injection, not a claimed valid
GitHub response. No test requires credentials or makes a GitHub request.
"""

import contextlib
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import time
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).parents[1] / "src/github_pr_wait.py"
SPEC = importlib.util.spec_from_file_location("github_pr_wait_transport_contract", SOURCE)
w = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(w)
URL = "https://github.com/example/project/pull/7"
ROOT = "repos/example/project"
PULL = ROOT + "/pulls/7"
REVIEWS = PULL + "/reviews?per_page=100"
PR = {"head": {"sha": "head"}, "base": {"ref": "main", "sha": "base"},
      "merged": False, "merge_commit_sha": None, "state": "open"}
SECRET = "ghp_FAKE_TRANSPORT_REDACTION_SENTINEL"


class Clock:
    def __init__(self):
        self.value = 0.0
        self.sleeps = []

    def __call__(self):
        return self.value

    def sleep(self, seconds):
        self.sleeps.append(seconds)
        self.value += seconds


def reply(endpoint, value, *, code=0, stderr="", elapsed=0):
    return {"endpoint": endpoint, "stdout": json.dumps(value), "code": code,
            "stderr": stderr, "elapsed": elapsed}


def http_error(status, message, *, endpoint=PULL, elapsed=0):
    # gh emits the JSON body even when processResponse returns SilentError.
    body = {"message": message, "documentation_url": "https://docs.github.com/rest",
            "status": str(status)}
    if status == 422:
        body["errors"] = [{"resource": "PullRequest", "field": "head", "code": "invalid"}]
    return reply(endpoint, body, code=1,
                 stderr=f"gh: {message} (HTTP {status})\n", elapsed=elapsed)


class ScriptedGh:
    """Only replaces Popen; CLI parsing, adapter, observation, and loop are real."""

    def __init__(self, responses, clock=None):
        self.responses = list(responses)
        self.calls = []
        self.clock = clock

    def __call__(self, command, **kwargs):
        if not self.responses:
            raise AssertionError("Unexpected extra gh invocation: " + repr(command))
        response = self.responses.pop(0)
        endpoint = response["endpoint"]
        if command[:2] != ["gh", "api"] or endpoint not in command:
            raise AssertionError((endpoint, command))
        if command[command.index("--method") + 1] != "GET":
            raise AssertionError("Read-only contract violated")
        self.calls.append((command, self.clock() if self.clock else None))
        owner = self

        class Process:
            returncode = response["code"]

            def communicate(self, timeout=None):
                if owner.clock:
                    owner.clock.value += response["elapsed"]
                return response["stdout"], response["stderr"]

        return Process()


class TransportContractTests(unittest.TestCase):
    def cli(self, responses, *extra, purpose="merged"):
        gh = ScriptedGh(responses)
        stdout, stderr = io.StringIO(), io.StringIO()
        previous = signal.getsignal(signal.SIGTERM)
        with patch.object(w.subprocess, "Popen", side_effect=gh), \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = w.main(["snapshot", URL, "--until", purpose, *extra])
        self.assertIs(signal.getsignal(signal.SIGTERM), previous)
        self.assertEqual(len(stdout.getvalue().splitlines()), 1)
        self.assertNotIn(SECRET, stdout.getvalue() + stderr.getvalue())
        self.assertEqual(stderr.getvalue(), "")
        self.assertFalse(gh.responses, "Not all scripted responses were consumed")
        return code, json.loads(stdout.getvalue()), gh

    def wait(self, responses, *, timeout=120, interval=1, clock=None):
        clock = clock or Clock()
        gh = ScriptedGh(responses, clock)
        args = w.parser().parse_args([
            "wait", URL, "--until", "merged", "--expected-head", "head",
            "--timeout", str(timeout), "--interval", str(interval)])
        with patch.object(w.subprocess, "Popen", side_effect=gh):
            result, code = w.run(args, clock=clock, sleep=clock.sleep)
        self.assertNotIn(SECRET, json.dumps(result))
        self.assertFalse(gh.responses, "Not all scripted responses were consumed")
        return code, result, gh, clock

    def test_permissions_and_invalid_credentials_are_terminal_and_redacted(self):
        for status, message in ((401, "Bad credentials"),
                                (403, "Resource not accessible by integration"),
                                (403, "Resource not accessible by personal access token")):
            with self.subTest(status=status, message=message):
                error = http_error(status, message + " " + SECRET)
                code, result, gh = self.cli([error])
                self.assertEqual((code, result["outcome"]), (1, "auth-error"))
                self.assertEqual(len(gh.calls), 1)

    def test_nonretryable_http_errors_do_not_look_like_absent_policy_or_success(self):
        for status, message in ((404, "Not Found"), (410, "Gone"),
                                (422, "Validation Failed")):
            with self.subTest(status=status):
                code, result, gh, clock = self.wait([http_error(status, message + " " + SECRET)])
                self.assertEqual((code, result["outcome"]), (1, "transport-error"))
                self.assertEqual(len(gh.calls), 1)
                self.assertEqual(clock.sleeps, [])

    def test_rate_limited_403_and_429_stop_without_permission_error_or_early_retry(self):
        for status in (403, 429):
            for message in ("API rate limit exceeded for 192.0.2.1.",
                            "You have exceeded a secondary rate limit. Please wait a few minutes before you try again."):
                with self.subTest(status=status, message=message):
                    code, result, gh, clock = self.wait([http_error(status, message)])
                    self.assertEqual((code, result["outcome"]), (1, "rate-limited"))
                    self.assertEqual(len(gh.calls), 1)
                    self.assertEqual(clock.sleeps, [])

    def test_server_and_network_errors_stop_after_three_consecutive_failures(self):
        for status in (500, 502, 503, 504, None):
            with self.subTest(status=status):
                if status is None:
                    failure = reply(PULL, None, code=1,
                                    stderr="error connecting to api.github.com: " + SECRET)
                else:
                    failure = http_error(status, "Server Error " + SECRET)
                code, result, gh, clock = self.wait([copy.deepcopy(failure) for _ in range(3)])
                self.assertEqual((code, result["outcome"]), (1, "transport-error"))
                self.assertEqual(result["evidence"]["consecutiveErrors"], 3)
                self.assertEqual(len(gh.calls), 3)
                self.assertEqual(len(clock.sleeps), 2)

    def test_completed_pending_observation_resets_consecutive_error_budget(self):
        code, result, gh, _ = self.wait([
            http_error(503, "Server Error"), http_error(502, "Bad Gateway"),
            reply(PULL, PR), reply(PULL, PR),
            http_error(503, "Server Error"), http_error(502, "Bad Gateway"),
            reply(PULL, {**PR, "merged": True, "state": "closed"})])
        self.assertEqual((code, result["outcome"]), (0, "success"))
        self.assertEqual(len(gh.calls), 7)

    def test_nonzero_gh_exit_never_uses_success_shaped_stdout(self):
        code, result, _ = self.cli([reply(PULL, {**PR, "merged": True}, code=1,
                                            stderr="gh: Server Error (HTTP 503) " + SECRET)])
        self.assertEqual((code, result["outcome"]), (1, "transport-error"))

    def test_malformed_and_truncated_json_emit_one_redacted_error(self):
        for raw in ("", '{"head":', '{}{}', "null", "[]", '"' + SECRET + '"'):
            with self.subTest(raw=raw):
                response = reply(PULL, {})
                response["stdout"] = raw
                code, result, _ = self.cli([response])
                self.assertEqual((code, result["outcome"]), (1, "transport-error"))

    def test_review_snapshot_consumes_all_slurped_pages_through_real_adapter(self):
        rows = [{"id": 1, "user": {"login": "bot"}}, {"id": 2, "user": {"login": "other"}}]
        code, result, gh = self.cli([
            reply(PULL, PR), reply(REVIEWS, [[rows[0]], [], [rows[1]]]), reply(PULL, PR)],
            "--reviewer", "bot", purpose="review-response")
        self.assertEqual(code, 0)
        self.assertEqual(result["reviewIds"], [1, 2])
        self.assertEqual(result["reviews"], rows)
        self.assertIn("--paginate", gh.calls[1][0])
        self.assertIn("--slurp", gh.calls[1][0])

    def test_partial_pagination_error_is_not_a_complete_snapshot(self):
        error = http_error(503, "Server Error " + SECRET, endpoint=REVIEWS)
        # gh closes the --slurp outer array even when a later page returns an error.
        error["stdout"] = json.dumps([[{"id": 1}], json.loads(error["stdout"])])
        code, result, _ = self.cli([reply(PULL, PR), error],
                                   "--reviewer", "bot", purpose="review-response")
        self.assertEqual((code, result["outcome"]), (1, "transport-error"))
        self.assertNotIn("reviewIds", result)

    def test_malformed_later_page_cannot_be_silently_dropped(self):
        for pages in ([[{"id": 1}], None], [[{"id": 1}], [None]],
                      [[{"id": 1}], {"message": "upstream error"}]):
            with self.subTest(pages=pages):
                code, result, _ = self.cli([reply(PULL, PR), reply(REVIEWS, pages)],
                                           "--reviewer", "bot", purpose="review-response")
                self.assertEqual((code, result["outcome"]), (1, "transport-error"))

    def test_later_check_run_page_can_prevent_false_success(self):
        required = [{"context": name, "app_id": 15368} for name in ("build", "test")]
        checks = [{"id": identifier, "name": name, "app": {"id": 15368},
                   "status": "completed", "conclusion": conclusion, "check_suite": {"id": 90}}
                  for identifier, name, conclusion in ((1, "build", "success"), (2, "test", "failure"))]
        code, result, gh = self.cli([
            reply(PULL, PR), reply(ROOT + "/branches/main", {"protected": True}),
            reply(ROOT + "/branches/main/protection", {"required_status_checks": {
                "checks": required, "contexts": ["build", "test"], "strict": False}}),
            reply(ROOT + "/rules/branches/main?per_page=100", [[]]),
            reply(ROOT + "/commits/head/check-runs?per_page=100&filter=all",
                  [{"total_count": 2, "check_runs": [checks[0]]},
                   {"total_count": 2, "check_runs": [checks[1]]}]),
            reply(ROOT + "/commits/head/statuses?per_page=100", [[]]),
            reply(ROOT + "/actions/runs?check_suite_id=90&per_page=100",
                  [{"total_count": 1, "workflow_runs": [
                      {"id": 90, "check_suite_id": 90, "event": "pull_request"}]}]),
            reply(PULL, PR)],
            purpose="required-checks")
        self.assertEqual((code, result["outcome"]), (0, "checks-failed"))
        self.assertEqual(result["evidence"]["failed"][0]["context"], "test")
        self.assertEqual(len(result["evidence"]["observation"]["checks"]), 2)
        self.assertIn("--slurp", gh.calls[4][0])

    def test_last_complete_observation_survives_later_transport_errors(self):
        code, result, _, _ = self.wait([
            reply(PULL, PR), reply(PULL, PR),
            http_error(503, "Server Error"), http_error(503, "Server Error"),
            http_error(503, "Server Error")])
        self.assertEqual((code, result["outcome"]), (1, "transport-error"))
        self.assertEqual(result["evidence"]["lastObservation"]["head"], "head")
        self.assertEqual(result["evidence"]["lastObservation"]["outcome"], "pending")
        self.assertEqual(result["evidence"]["missing"], ["merged"])

    def test_deadline_includes_api_execution_and_rejects_late_success(self):
        code, result, gh, clock = self.wait([
            reply(PULL, {**PR, "merged": True}, elapsed=2)], timeout=2)
        self.assertEqual((code, result["outcome"]), (1, "timeout"))
        self.assertEqual(len(gh.calls), 1)
        self.assertEqual(clock.sleeps, [])

    def test_total_deadline_clamps_sleep_and_prevents_another_api_call(self):
        code, result, gh, clock = self.wait([
            reply(PULL, PR, elapsed=0.25), reply(PULL, PR, elapsed=0.25)],
            timeout=1, interval=10)
        self.assertEqual((code, result["outcome"]), (1, "timeout"))
        self.assertEqual(clock.sleeps, [0.5])
        self.assertEqual(len(gh.calls), 2)
        self.assertEqual(result["evidence"]["lastObservation"]["head"], "head")

    def test_missing_gh_executable_fails_once_without_exposing_os_error(self):
        args = w.parser().parse_args(["wait", URL, "--until", "merged",
                                      "--expected-head", "head", "--timeout", "10"])
        clock = Clock()
        with patch.object(w.subprocess, "Popen", side_effect=FileNotFoundError(SECRET)) as spawn:
            result, code = w.run(args, clock=clock, sleep=clock.sleep)
        self.assertEqual((code, result["outcome"]), (1, "transport-error"))
        self.assertEqual(spawn.call_count, 1)
        self.assertNotIn(SECRET, json.dumps(result))
        self.assertEqual(clock.sleeps, [])

    def test_cancellation_during_sleep_keeps_last_observation(self):
        for interruption in (w.Cancelled, KeyboardInterrupt):
            with self.subTest(interruption=interruption.__name__):
                gh = ScriptedGh([reply(PULL, PR), reply(PULL, PR)])
                args = w.parser().parse_args(["wait", URL, "--until", "merged",
                                              "--expected-head", "head", "--timeout", "10"])
                clock = Clock()

                def interrupted_sleep(_seconds):
                    raise interruption()

                with patch.object(w.subprocess, "Popen", side_effect=gh):
                    result, code = w.run(args, clock=clock, sleep=interrupted_sleep)
                self.assertEqual((code, result["outcome"]), (130, "cancelled"))
                self.assertEqual(result["evidence"]["lastObservation"]["head"], "head")
                self.assertEqual(result["evidence"]["missing"], ["merged"])

    def test_final_pr_read_failure_never_returns_a_provisional_review_snapshot(self):
        code, result, _ = self.cli([
            reply(PULL, PR), reply(REVIEWS, [[{"id": 17, "user": {"login": "bot"}}]]),
            http_error(503, "Server Error", endpoint=PULL)],
            "--reviewer", "bot", purpose="review-response")
        self.assertEqual((code, result["outcome"]), (1, "transport-error"))
        self.assertNotEqual(result.get("outcome"), "success")

    @unittest.skipUnless(hasattr(os, "fork"), "requires POSIX process groups")
    def test_hung_descendant_holding_stdout_is_killed_by_total_deadline(self):
        # The gh-shaped child exits, but its descendant keeps PIPE handles open.
        # Exercise real communicate timeout/group teardown, not a Popen mock.
        original_popen = subprocess.Popen
        read_fd, write_fd = os.pipe()
        children = []
        child_script = (
            "import os,time; pid=os.fork(); "
            f"os.write({write_fd}, (str(os.getpid())+'\\n').encode()) if pid == 0 else None; "
            "time.sleep(30) if pid == 0 else None"
        )

        def spawn(_command, **kwargs):
            child = original_popen([sys.executable, "-c", child_script],
                                   pass_fds=(write_fd,), **kwargs)
            children.append(child)
            return child

        started = time.monotonic()
        try:
            with patch.object(w.subprocess, "Popen", side_effect=spawn):
                api = w.GitHub(time.monotonic() + 0.5, 30)
                with self.assertRaises(w.Failure) as caught:
                    api.get(PULL)
            self.assertEqual(caught.exception.outcome, "timeout")
            self.assertLess(time.monotonic() - started, 5)
            self.assertIsNotNone(children[0].returncode)
            self.assertTrue(select.select([read_fd], [], [], 1)[0], "descendant did not announce its pid")
            raw_pid = os.read(read_fd, 100).strip()
            self.assertTrue(raw_pid, "descendant did not start before the deadline")
            self.assertGreater(int(raw_pid), 0)
            # A killed orphan may remain a zombie until init reaps it. Pipe EOF
            # proves no live descendant still holds the output descriptors.
            self.assertEqual(children[0].communicate(timeout=1), ("", ""))
        finally:
            os.close(read_fd)
            os.close(write_fd)
            for child in children:
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                child.communicate(timeout=2)


if __name__ == "__main__":
    unittest.main()
