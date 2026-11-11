import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
import select
import unittest
from unittest.mock import Mock, patch

SPEC = importlib.util.spec_from_file_location("github_pr_wait", Path(__file__).parents[1] / "src/github_pr_wait.py")
w = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(w)
URL = "https://github.com/example/project/pull/7"
ROOT = "repos/example/project"
PULL = ROOT + "/pulls/7"
PR = {"head": {"sha": "head"}, "base": {"ref": "main", "sha": "base"},
      "merged": False, "merge_commit_sha": "test-merge", "state": "open", "mergeable": None,
      "mergeable_state": "blocked"}
REQUESTED = "2026-11-11T10:00:01Z"


def arguments(purpose="merged", command="wait", *extra):
    argv = [command, URL, "--until", purpose]
    if command == "wait":
        argv += ["--expected-head", "head", "--timeout", "10", "--interval", "1"]
    if purpose == "review-response":
        argv += ["--reviewer", "bot"]
        if command == "wait":
            argv += ["--baseline", "baseline.json", "--requested-after", REQUESTED]
    return w.parser().parse_args(argv + list(extra))


def baseline():
    return {"url": URL, "repo": "example/project", "pr": 7, "head": "head",
            "reviewer": "bot", "until": "review-response", "outcome": "pending",
            "capturedAt": "2026-11-11T10:00:00Z", "reviewIds": [1]}


def review(identifier=2, state="COMMENTED", **changes):
    return {"id": identifier, "state": state, "user": {"login": "bot"},
            "submitted_at": "2026-11-11T10:00:02Z", "commit_id": "head", **changes}


def check(identifier=1, name="test", app=15368, conclusion="success", **changes):
    return {"id": identifier, "name": name, "app": {"id": app}, "status": "completed",
            "conclusion": conclusion, "started_at": "2026-11-11T10:00:00Z", **changes}


class FakeAPI:
    def __init__(self, responses):
        self.responses = responses
        self.calls = []

    def get(self, endpoint, **kwargs):
        self.calls.append((endpoint, kwargs))
        if endpoint not in self.responses:
            raise AssertionError("Unexpected endpoint: " + endpoint)
        response = self.responses[endpoint]
        if callable(response):
            response = response()
        if isinstance(response, BaseException):
            raise response
        return copy.deepcopy(response)


def ci_api(*, checks=None, statuses=None, rules=None, classic=None, metadata=None,
           merge_checks=None, merge_statuses=None, behind=0):
    return FakeAPI({PULL: PR,
        ROOT + "/branches/main": metadata if metadata is not None else {"protected": True, "protection": {"enabled": False}},
        ROOT + "/branches/main/protection": classic if classic is not None else w.Failure("transport-error", "404", status=404),
        ROOT + "/rules/branches/main?per_page=100": rules if rules is not None else [{"type": "required_status_checks", "parameters": {
            "required_status_checks": [{"context": "test", "integration_id": 15368}],
            "strict_required_status_checks_policy": True}}],
        ROOT + "/commits/head/check-runs?per_page=100&filter=all": checks if checks is not None else [check()],
        ROOT + "/commits/head/statuses?per_page=100": statuses or [],
        ROOT + "/commits/test-merge": {"sha": "test-merge", "parents": [{"sha": "base"}, {"sha": "head"}]},
        ROOT + "/commits/test-merge/check-runs?per_page=100&filter=all": merge_checks or [],
        ROOT + "/commits/test-merge/statuses?per_page=100": merge_statuses or [],
        ROOT + "/compare/base...head": {"behind_by": behind}})


class ReviewTests(unittest.TestCase):
    def observe(self, reviews, args=None, pr=PR):
        args = args or arguments("review-response")
        args.baseline_ids = {1}
        args.requested_time = w.timestamp(REQUESTED)
        return w.observe(FakeAPI({PULL: pr, PULL + "/reviews?per_page=100": reviews}), w.target(URL), args)

    def test_all_submitted_review_outcomes_are_responses(self):
        for state in ("COMMENTED", "CHANGES_REQUESTED", "APPROVED"):
            with self.subTest(state=state):
                result = self.observe([review(state=state)])
                self.assertEqual(result["outcome"], "success")
                self.assertEqual(result["evidence"]["reviews"][0]["state"], state)

    def test_pending_dismissed_baseline_wrong_actor_head_and_old_time_excluded(self):
        for item in (review(state="PENDING"), review(state="DISMISSED"), review(identifier=1),
                     review(user={"login": "someone"}), review(commit_id="other"),
                     review(submitted_at=REQUESTED), review(submitted_at=None)):
            with self.subTest(review=item):
                self.assertEqual(self.observe([item])["outcome"], "pending")

    def test_snapshot_captures_all_ids_even_other_actors_and_pending(self):
        rows = [review(identifier=1), review(identifier=2, state="PENDING"), review(identifier=3, user={"login": "other"})]
        result = self.observe(rows, arguments("review-response", "snapshot"))
        self.assertEqual(result["reviewIds"], [1, 2, 3])
        self.assertEqual(result["reviews"], rows)
        self.assertEqual(result["reviewer"], "bot")
        self.assertIsNone(result["mergeSha"])

    def test_closed_review_snapshot_still_collects_all_review_ids(self):
        result = self.observe([review()], arguments("review-response", "snapshot"), pr={**PR, "state": "closed"})
        self.assertEqual(result["reviewIds"], [2])
        self.assertEqual(result["outcome"], "closed")

    def test_unknown_mergeability_does_not_block_review(self):
        self.assertEqual(self.observe([review()], pr={**PR, "mergeable": None})["outcome"], "success")

    def test_head_race_prevents_success(self):
        responses = iter([PR, {**PR, "head": {"sha": "new"}}])
        args = arguments("review-response")
        args.baseline_ids, args.requested_time = set(), w.timestamp(REQUESTED)
        result = w.observe(FakeAPI({PULL: lambda: next(responses), PULL + "/reviews?per_page=100": [review()]}), w.target(URL), args)
        self.assertEqual(result["outcome"], "invalidated")
        self.assertEqual(result["head"], "new")

    def test_valid_baseline(self):
        args = arguments("review-response")
        with patch.object(Path, "read_text", return_value=json.dumps(baseline())):
            w.validate_baseline(args, w.target(URL))
        self.assertEqual(args.baseline_ids, {1})

    def test_baseline_identity_head_reviewer_time_and_ids_validation(self):
        for field, value in (("url", URL + "0"), ("repo", "other/repo"), ("pr", 8),
                             ("head", "different"), ("reviewer", "other"),
                             ("capturedAt", "2026-11-11T10:00:02Z"),
                             ("reviewIds", ["1"]), ("outcome", "invalidated")):
            with self.subTest(field=field), patch.object(Path, "read_text", return_value=json.dumps({**baseline(), field: value})):
                with self.assertRaises(w.Failure) as error:
                    w.validate_baseline(arguments("review-response"), w.target(URL))
                self.assertEqual(error.exception.outcome, "invalid-input")

    def test_naive_request_timestamp_rejected(self):
        with self.assertRaises(w.Failure):
            w.timestamp("2026-11-11T10:00:01")


class ChecksTests(unittest.TestCase):
    def observe(self, api):
        return w.observe(api, w.target(URL), arguments("required-checks"))

    def test_ruleset_only_policy_despite_disabled_classic_metadata(self):
        result = self.observe(ci_api())
        self.assertEqual(result["outcome"], "success")
        self.assertEqual(result["evidence"]["policy"]["required"], [{"context": "test", "appId": 15368}])
        self.assertTrue(result["evidence"]["policy"]["strict"])
        self.assertEqual(result["evidence"]["observation"]["sha"], "head")

    def test_classic_and_rules_are_combined_without_unpinned_duplicate(self):
        classic = {"required_status_checks": {"contexts": ["lint"], "checks": [{"context": "lint", "app_id": 7}], "strict": False}}
        api = ci_api(classic=classic, checks=[check(), check(identifier=2, name="lint", app=7)])
        result = self.observe(api)
        self.assertEqual(result["outcome"], "success")
        self.assertEqual(len(result["evidence"]["policy"]["required"]), 2)

    def test_classic_404_without_known_absence_fails_closed(self):
        for metadata in ({"protected": True}, {"protected": True, "protection": {"enabled": True}}):
            with self.subTest(metadata=metadata), self.assertRaises(w.Failure) as error:
                self.observe(ci_api(metadata=metadata))
            self.assertEqual(error.exception.outcome, "unknown-policy")

    def test_known_unprotected_branch_with_no_rules_has_no_required_checks(self):
        result = self.observe(ci_api(metadata={"protected": False}, rules=[], checks=[]))
        self.assertEqual(result["outcome"], "success")
        self.assertEqual(result["evidence"]["policy"]["required"], [])

    def test_required_workflows_are_explicitly_unsupported(self):
        for kind in ("workflows", "required_workflows"):
            with self.subTest(kind=kind), self.assertRaises(w.Failure) as error:
                self.observe(ci_api(rules=[{"type": kind}]))
            self.assertEqual(error.exception.outcome, "unknown-policy")

    def test_missing_and_wrong_app_never_pass(self):
        for checks in ([], [check(app=999)]):
            with self.subTest(checks=checks):
                result = self.observe(ci_api(checks=checks))
                self.assertEqual(result["outcome"], "pending")
                self.assertEqual(result["evidence"]["missing"][0]["condition"], "missing")

    def test_status_cannot_impersonate_pinned_app(self):
        result = self.observe(ci_api(checks=[], statuses=[{"id": 1, "context": "test", "state": "success"}]))
        self.assertEqual(result["outcome"], "pending")

    def test_check_status_collision_requires_both_successes(self):
        for state, outcome in (("failure", "checks-failed"), ("pending", "pending"), ("success", "success")):
            with self.subTest(state=state):
                result = self.observe(ci_api(statuses=[{"id": 2, "context": "test", "state": state}]))
                self.assertEqual(result["outcome"], outcome)

    def test_unpinned_status_only_is_supported(self):
        classic = {"required_status_checks": {"contexts": ["legacy"], "checks": [], "strict": False}}
        result = self.observe(ci_api(classic=classic, rules=[], checks=[], statuses=[{"id": 1, "context": "legacy", "state": "success"}]))
        self.assertEqual(result["outcome"], "success")

    def test_latest_rerun_by_identity_supersedes_success_even_before_start(self):
        rows = [check(identifier=2, status="queued", conclusion=None, started_at=None), check(identifier=1)]
        result = self.observe(ci_api(checks=rows))
        self.assertEqual(result["outcome"], "pending")
        self.assertEqual(result["evidence"]["observation"]["checks"][0]["id"], 2)

    def test_latest_status_supersedes_old_failure(self):
        statuses = [{"id": 9, "context": "test", "state": "success"}, {"id": 8, "context": "test", "state": "failure"}]
        self.assertEqual(self.observe(ci_api(statuses=statuses))["outcome"], "success")

    def test_required_check_terminal_failure_and_accepted_conclusions(self):
        for conclusion in ("success", "neutral", "skipped", "failure", "cancelled", "timed_out", "action_required", "stale"):
            with self.subTest(conclusion=conclusion):
                expected = "success" if conclusion in ("success", "neutral", "skipped") else "checks-failed"
                self.assertEqual(self.observe(ci_api(checks=[check(conclusion=conclusion)]))["outcome"], expected)

    def test_test_merge_observations_take_precedence_even_unrelated(self):
        result = self.observe(ci_api(merge_checks=[check(conclusion="failure")]))
        self.assertEqual(result["outcome"], "checks-failed")
        self.assertEqual(result["evidence"]["observation"]["sha"], "test-merge")
        result = self.observe(ci_api(merge_checks=[check(name="unrelated")]))
        self.assertEqual(result["outcome"], "pending")

    def test_absent_test_merge_falls_back_to_head(self):
        api = ci_api()
        api.responses[ROOT + "/commits/test-merge/check-runs?per_page=100&filter=all"] = w.Failure("transport-error", "404", status=404)
        self.assertEqual(self.observe(api)["evidence"]["observation"]["sha"], "head")

    def test_stale_test_merge_is_not_used_for_current_head(self):
        api = ci_api(checks=[check(conclusion="failure")], merge_checks=[check()])
        api.responses[ROOT + "/commits/test-merge"]["parents"] = [{"sha": "base"}, {"sha": "old-head"}]
        result = self.observe(api)
        self.assertEqual(result["outcome"], "checks-failed")
        self.assertEqual(result["evidence"]["observation"]["sha"], "head")
        self.assertEqual(result["evidence"]["ignoredTestMerge"]["sha"], "test-merge")

    def test_strict_policy_checks_ancestry_not_review_blocking(self):
        self.assertEqual(self.observe(ci_api(behind=1))["outcome"], "pending")
        self.assertEqual(self.observe(ci_api(behind=0))["outcome"], "success")

    def test_ci_target_race_returns_pending(self):
        api = ci_api()
        values = iter([PR, {**PR, "merge_commit_sha": "new-test-merge"}])
        api.responses[PULL] = lambda: next(values)
        self.assertEqual(self.observe(api)["evidence"]["missing"], ["stable-ci-target"])

    def test_base_repository_metadata_change_preserves_check_outcome(self):
        initial = {**PR, "base": {**PR["base"], "repo": {"pushed_at": "2026-11-11T10:00:00Z"}}}
        final = {**PR, "base": {**PR["base"], "repo": {"pushed_at": "2026-11-11T10:00:01Z"}}}
        for conclusion, outcome in (("success", "success"), ("failure", "checks-failed")):
            with self.subTest(conclusion=conclusion):
                api = ci_api(checks=[check(conclusion=conclusion)])
                values = iter([initial, final])
                api.responses[PULL] = lambda: next(values)
                result = self.observe(api)
                self.assertEqual(result["outcome"], outcome)
                self.assertNotIn("stable-ci-target", result["evidence"]["missing"])

    def test_actual_base_ref_or_sha_change_requires_reobservation(self):
        for changed in ({"ref": "release"}, {"sha": "new-base"}):
            with self.subTest(changed=changed):
                api = ci_api()
                values = iter([PR, {**PR, "base": {**PR["base"], **changed}}])
                api.responses[PULL] = lambda: next(values)
                result = self.observe(api)
                self.assertEqual(result["outcome"], "pending")
                self.assertEqual(result["evidence"]["missing"], ["stable-ci-target"])


class LifecycleTests(unittest.TestCase):
    def test_head_invalidation_all_purposes(self):
        for purpose in ("merged", "required-checks", "review-response"):
            with self.subTest(purpose=purpose):
                result = w.observe(FakeAPI({PULL: {**PR, "head": {"sha": "new"}}}), w.target(URL), arguments(purpose))
                self.assertEqual(result["outcome"], "invalidated")

    def test_closed_unmerged_is_terminal(self):
        result = w.observe(FakeAPI({PULL: {**PR, "state": "closed"}}), w.target(URL), arguments())
        self.assertEqual(result["outcome"], "closed")
        self.assertIsNone(result["mergeSha"])

    def test_actual_merged_fact_and_nullable_merge_sha(self):
        for sha in (None, "actual-merged-commit"):
            with self.subTest(sha=sha):
                result = w.observe(FakeAPI({PULL: {**PR, "merged": True, "merge_commit_sha": sha}}), w.target(URL), arguments())
                self.assertEqual(result["outcome"], "success")
                self.assertTrue(result["merged"])
                self.assertEqual(result["mergeSha"], sha)

    def test_merged_wrong_head_invalidates_on_initial_read(self):
        pr = {**PR, "merged": True, "head": {"sha": "unexpected-head"}, "merge_commit_sha": "actual-merge"}
        result = w.observe(FakeAPI({PULL: pr}), w.target(URL), arguments())
        self.assertEqual(result["outcome"], "invalidated")
        self.assertEqual(result["head"], "unexpected-head")
        self.assertTrue(result["merged"])

    def test_merged_wrong_head_invalidates_on_final_read(self):
        pr = {**PR, "merged": True, "head": {"sha": "unexpected-head"}, "merge_commit_sha": "actual-merge"}
        values = iter([PR, pr])
        result = w.observe(FakeAPI({PULL: lambda: next(values)}), w.target(URL), arguments())
        self.assertEqual(result["outcome"], "invalidated")
        self.assertEqual(result["head"], "unexpected-head")
        self.assertTrue(result["merged"])

    def test_run_timeout_retains_last_observation_and_missing_condition(self):
        clock = Mock(return_value=0.0)
        api = FakeAPI({PULL: PR})
        api.remaining = lambda: None
        def sleep(seconds):
            clock.return_value += seconds
        result, code = w.run(arguments("merged", "wait", "--timeout", "2"), clock=clock, sleep=sleep,
                             api_factory=lambda *args, **kwargs: api)
        self.assertEqual(code, 1)
        self.assertEqual(result["outcome"], "timeout")
        self.assertEqual(result["evidence"]["missing"], ["merged"])
        self.assertEqual(result["evidence"]["lastObservation"]["head"], "head")

    def test_transient_errors_are_finite_auth_is_immediate(self):
        for outcome, transient, expected_calls in (("transport-error", True, 3), ("auth-error", False, 1)):
            with self.subTest(outcome=outcome):
                api = Mock()
                api.get.side_effect = w.Failure(outcome, "error", transient=transient)
                result, code = w.run(arguments(), sleep=lambda _: None, api_factory=lambda *a, **k: api)
                self.assertEqual(api.get.call_count, expected_calls)
                self.assertEqual(result["outcome"], outcome)
                self.assertEqual(code, 1)

    def test_snapshot_pending_is_successful_collection_not_wait_success(self):
        api = FakeAPI({PULL: PR})
        api.remaining = lambda: None
        result, code = w.run(arguments("merged", "snapshot"), api_factory=lambda *a, **k: api)
        self.assertEqual((result["outcome"], code), ("pending", 0))

    def test_invalid_positive_values_are_rejected(self):
        for value in ("0", "-1", "nan", "inf"):
            with self.subTest(value=value), self.assertRaises(Exception):
                w.positive(value)


    def test_cancel_during_sleep_preserves_last_observation(self):
        api = FakeAPI({PULL: PR})
        api.remaining = lambda: None
        def cancel(_seconds):
            raise w.Cancelled()
        result, code = w.run(arguments(), sleep=cancel, api_factory=lambda *a, **k: api)
        self.assertEqual((result["outcome"], code), ("cancelled", 130))
        self.assertEqual(result["evidence"]["lastObservation"]["head"], "head")
        self.assertEqual(result["evidence"]["missing"], ["merged"])


class TransportTests(unittest.TestCase):
    def api(self, **kwargs):
        return w.GitHub(time.monotonic() + 10, kwargs.pop("api_timeout", 1), **kwargs)

    def test_paginated_lists_and_objects_merge_all_pages(self):
        for key, payload in ((None, [[{"id": 1}], [{"id": 2}]]),
                             ("check_runs", [{"check_runs": [{"id": 1}]}, {"check_runs": [{"id": 2}]}])):
            process = Mock(returncode=0)
            process.communicate.return_value = (json.dumps(payload), "")
            with self.subTest(key=key), patch.object(w.subprocess, "Popen", return_value=process) as popen:
                self.assertEqual(self.api().get("repos/example/project/items?per_page=100", pages=True, key=key), [{"id": 1}, {"id": 2}])
                command = popen.call_args.args[0]
                self.assertIn("--paginate", command)
                self.assertIn("--slurp", command)
                self.assertNotIn("--jq", command)
                self.assertEqual(command[command.index("--method") + 1], "GET")

    def test_auth_errors_do_not_retry_or_disclose_stderr(self):
        for stderr in ("gh: HTTP 401 secret-token", "gh: HTTP 403 secret-token", "Please run gh auth login secret-token"):
            process = Mock(returncode=1)
            process.communicate.return_value = ("", stderr)
            with self.subTest(stderr=stderr), patch.object(w.subprocess, "Popen", return_value=process), self.assertRaises(w.Failure) as error:
                self.api().get(PULL)
            self.assertEqual(error.exception.outcome, "auth-error")
            self.assertFalse(error.exception.transient)
            self.assertNotIn("secret-token", error.exception.reason)

    def test_malformed_pagination_and_json_fail_closed(self):
        for stdout in ("not-json", '{}', '[{"unexpected": []}]'):
            process = Mock(returncode=0)
            process.communicate.return_value = (stdout, "")
            with self.subTest(stdout=stdout), patch.object(w.subprocess, "Popen", return_value=process), self.assertRaises(w.Failure):
                self.api().get(PULL, pages=True, key="check_runs")

    def test_subprocess_budget_is_minimum_of_call_and_total_remaining(self):
        process = Mock(returncode=0)
        process.communicate.return_value = ('{}', '')
        with patch.object(w.subprocess, "Popen", return_value=process):
            w.GitHub(12, 30, clock=lambda: 10).get(PULL)
        self.assertEqual(process.communicate.call_args.kwargs["timeout"], 2)

    def test_expired_deadline_starts_no_process(self):
        with patch.object(w.subprocess, "Popen") as popen, self.assertRaises(w.Failure) as error:
            w.GitHub(1, 30, clock=lambda: 2).get(PULL)
        popen.assert_not_called()
        self.assertEqual(error.exception.outcome, "timeout")

    def test_hanging_real_child_is_killed_and_reaped(self):
        real_popen = subprocess.Popen
        children = []
        def spawn(_command, **kwargs):
            child = real_popen([sys.executable, "-c", "import time; time.sleep(60)"], **kwargs)
            children.append(child)
            return child
        with patch.object(w.subprocess, "Popen", side_effect=spawn), self.assertRaises(w.Failure) as error:
            self.api(api_timeout=0.05).get(PULL)
        self.assertEqual(error.exception.outcome, "transport-error")
        self.assertIsNotNone(children[0].returncode)
        with self.assertRaises(ProcessLookupError):
            os.kill(children[0].pid, 0)

    def test_keyboard_interrupt_and_sigterm_cancellation_kill_active_process_group(self):
        for interruption in (KeyboardInterrupt(), w.Cancelled()):
            process = Mock(pid=12345)
            process.communicate.side_effect = [interruption, ("", "")]
            with self.subTest(interruption=type(interruption).__name__), patch.object(w.subprocess, "Popen", return_value=process), patch.object(w.os, "killpg") as kill:
                with self.assertRaises(type(interruption)):
                    self.api().get(PULL)
                kill.assert_called_once_with(12345, signal.SIGKILL)
                self.assertEqual(process.communicate.call_count, 2)

    def test_real_cli_sigterm_reaps_hanging_gh_child(self):
        read_fd, write_fd = os.pipe()
        script = f"""
import importlib.util, os, subprocess, sys
spec = importlib.util.spec_from_file_location("waiter", {str(Path(w.__file__).resolve())!r})
w = importlib.util.module_from_spec(spec)
spec.loader.exec_module(w)
original = subprocess.Popen
def spawn(command, **kwargs):
    child = original([sys.executable, "-c", "import time; time.sleep(60)"], **kwargs)
    communicate = child.communicate
    notified = False
    def ready(*args, **kwargs):
        nonlocal notified
        if not notified:
            os.write({write_fd}, (str(child.pid) + "\\n").encode())
            notified = True
        return communicate(*args, **kwargs)
    child.communicate = ready
    return child
w.subprocess.Popen = spawn
sys.exit(w.main(["wait", {URL!r}, "--until", "merged", "--expected-head", "head", "--timeout", "10"]))
"""
        process = None
        child_pid = None
        try:
            process = subprocess.Popen([sys.executable, "-c", script], pass_fds=(write_fd,),
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                       start_new_session=True)
            os.close(write_fd)
            write_fd = None
            self.assertTrue(select.select([read_fd], [], [], 5)[0], "gh child did not start")
            child_pid = int(os.read(read_fd, 100).strip())
            os.kill(process.pid, signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 130, stderr)
            self.assertEqual(json.loads(stdout)["outcome"], "cancelled")
            with self.assertRaises(ProcessLookupError):
                os.kill(child_pid, 0)
        finally:
            os.close(read_fd)
            if write_fd is not None:
                os.close(write_fd)
            if process is not None and process.poll() is None:
                process.kill()
                process.communicate()
            if child_pid is not None:
                try:
                    os.killpg(child_pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass

    def test_cli_sigterm_handler_emits_one_json_and_restores_handler(self):
        previous = signal.getsignal(signal.SIGTERM)
        def cancelled(_args):
            handler = signal.getsignal(signal.SIGTERM)
            handler(signal.SIGTERM, None)
        stream = io.StringIO()
        with patch.object(w, "run", side_effect=cancelled), patch.object(sys, "stdout", stream):
            code = w.main(["snapshot", URL, "--until", "merged"])
        self.assertEqual(code, 130)
        self.assertEqual(json.loads(stream.getvalue())["outcome"], "cancelled")
        self.assertIs(signal.getsignal(signal.SIGTERM), previous)


if __name__ == "__main__":
    unittest.main()
