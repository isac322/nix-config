"""Required-check eligibility at the GitHub REST/subprocess boundary."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import Mock, patch


SPEC = importlib.util.spec_from_file_location(
    "github_pr_wait_actions_eligibility",
    Path(__file__).parents[1] / "src/github_pr_wait.py")
w = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(w)
URL = "https://github.com/example/project/pull/7"
ROOT = "repos/example/project"
PULL = ROOT + "/pulls/7"
ALLOWED = ("push", "pull_request", "pull_request_review", "pull_request_target",
           "deployment", "deployment_status")
EXCLUDED = ("workflow_dispatch", "schedule", "repository_dispatch", "workflow_run",
            "workflow_call", "merge_group", "pull_request_review_comment", "release")


class Pages(list):
    """Already-slurped gh pagination, including deliberately malformed pages."""


class HTTPError:
    def __init__(self, status, message="Not Found"):
        self.status = status
        self.message = message


class RESTBoundary(w.GitHub):
    """Keep the real get decoder; replace only gh's process and REST bodies."""
    def __init__(self, responses):
        super().__init__(100, 10, clock=lambda: 0)
        self.responses = responses
        self.calls = []

    def get(self, endpoint, *, pages=False, key=None):
        self.calls.append((endpoint, {"pages": pages, "key": key}))
        if endpoint not in self.responses:
            raise AssertionError("Unexpected endpoint: " + endpoint)
        value = self.responses[endpoint]
        if isinstance(value, BaseException):
            raise value
        if isinstance(value, HTTPError):
            process = Mock(returncode=1)
            process.communicate.return_value = (
                json.dumps({"message": value.message}),
                f"gh: {value.message} (HTTP {value.status})")
        else:
            value = copy.deepcopy(value)
            if pages and not isinstance(value, Pages):
                value = [value]
            process = Mock(returncode=0)
            process.communicate.return_value = (json.dumps(value), "")
        with patch.object(w.subprocess, "Popen", return_value=process) as popen:
            result = super().get(endpoint, pages=pages, key=key)
        command = popen.call_args.args[0]
        if command[command.index("--method") + 1] != "GET":
            raise AssertionError("Only read-only GitHub requests are permitted")
        if pages and ("--paginate" not in command or "--slurp" not in command):
            raise AssertionError("Workflow association must consume all pages")
        return result


def runs_endpoint(suite):
    return ROOT + f"/actions/runs?check_suite_id={suite}&per_page=100"


def check(identifier=1, suite=90, *, name="ci", app=None, **changes):
    row = {"id": identifier, "name": name,
           "app": {"id": 15368} if app is None else app,
           "status": "completed", "conclusion": "success", "head_sha": "head",
           "started_at": "2026-11-11T10:00:00Z", "check_suite": {"id": suite},
           "pull_requests": []}
    row.update(changes)
    return row


def workflow(suite=90, event="pull_request", identifier=10, **changes):
    return {"id": identifier, "check_suite_id": suite, "event": event,
            "head_sha": "head", "head_branch": "feature", "pull_requests": [],
            **changes}


def run_page(*rows):
    return {"total_count": len(rows), "workflow_runs": list(rows)}


def status(state="success"):
    return {"id": 50, "context": "ci", "state": state}


def scenario(checks=(), *, workflows=None, statuses=(), merge_checks=None,
             merge_statuses=(), requirements=(("ci", 15368),)):
    pr = {"head": {"sha": "head"}, "base": {"ref": "main", "sha": "base"},
          "merged": False, "state": "open",
          "merge_commit_sha": "test-merge" if merge_checks is not None else None}
    responses = {
        PULL: pr,
        ROOT + "/branches/main": {"protected": True},
        ROOT + "/branches/main/protection": {"required_status_checks": {
            "strict": False, "contexts": [name for name, _app in requirements],
            "checks": [{"context": name, "app_id": app} for name, app in requirements]}},
        ROOT + "/rules/branches/main?per_page=100": [],
        ROOT + "/commits/head/check-runs?per_page=100&filter=all": {
            "total_count": len(checks), "check_runs": list(checks)},
        ROOT + "/commits/head/statuses?per_page=100": list(statuses),
    }
    if merge_checks is not None:
        responses.update({
            ROOT + "/commits/test-merge": {
                "parents": [{"sha": "head"}, {"sha": "base"}]},
            ROOT + "/commits/test-merge/check-runs?per_page=100&filter=all": {
                "total_count": len(merge_checks), "check_runs": list(merge_checks)},
            ROOT + "/commits/test-merge/statuses?per_page=100": list(merge_statuses),
        })
    for suite, value in (workflows or {}).items():
        responses[runs_endpoint(suite)] = value
    return RESTBoundary(responses)


def arguments(command="snapshot"):
    argv = [command, URL, "--until", "required-checks"]
    if command == "wait":
        argv += ["--expected-head", "head", "--timeout", "10", "--interval", "1"]
    return w.parser().parse_args(argv)


def observe(api):
    return w.observe(api, w.target(URL), arguments())


def execute(api, command="snapshot"):
    def no_sleep(_seconds):
        raise AssertionError("A terminal observation must not sleep")
    return w.run(arguments(command), clock=lambda: 0, sleep=no_sleep,
                 api_factory=lambda *_args, **_kwargs: api)


class ActionsEventEligibilityTests(unittest.TestCase):
    def test_reproduction_dispatch_success_cannot_satisfy_required_check(self):
        api = scenario([check()], workflows={90: run_page(workflow(event="workflow_dispatch"))})
        result, code = execute(api)
        self.assertEqual((result["outcome"], code), ("pending", 0))
        self.assertEqual(result["evidence"]["observation"]["checks"], [])
        self.assertEqual(result["evidence"]["missing"][0]["condition"], "missing")

    def test_dispatch_only_wait_expires_without_false_success(self):
        api = scenario([check()], workflows={90: run_page(workflow(event="workflow_dispatch"))})
        clock = Mock(return_value=0.0)
        api.clock, api.deadline = clock, 2.0
        args = arguments("wait")
        args.timeout = 2.0

        def advance(seconds):
            clock.return_value += seconds

        result, code = w.run(args, clock=clock, sleep=advance,
                             api_factory=lambda *_args, **_kwargs: api)
        self.assertEqual((result["outcome"], code), ("timeout", 1))
        self.assertEqual(result["evidence"]["missing"][0]["condition"], "missing")

    def test_reproduction_newer_dispatch_green_cannot_mask_eligible_failure(self):
        api = scenario([check(1, 90, conclusion="failure"), check(2, 91)], workflows={
            90: run_page(workflow(90)),
            91: run_page(workflow(91, "workflow_dispatch"))})
        result, code = execute(api, "wait")
        self.assertEqual((result["outcome"], code), ("checks-failed", 1))
        self.assertEqual(result["evidence"]["failed"][0]["id"], 1)
        self.assertEqual([row["id"] for row in result["evidence"]["observation"]["checks"]], [1])

    def test_newer_ineligible_failure_cannot_mask_valid_success(self):
        api = scenario([check(1, 90), check(2, 91, conclusion="failure")], workflows={
            90: run_page(workflow(90)), 91: run_page(workflow(91, "schedule"))})
        result, code = execute(api, "wait")
        self.assertEqual((result["outcome"], code), ("success", 0))
        self.assertEqual(result["evidence"]["observation"]["checks"][0]["id"], 1)

    def test_eligible_queued_check_survives_newer_excluded_green(self):
        api = scenario([check(1, 90, status="queued", conclusion=None, started_at=None),
                        check(2, 91)], workflows={
            90: run_page(workflow(90)), 91: run_page(workflow(91, "repository_dispatch"))})
        result = observe(api)
        self.assertEqual(result["outcome"], "pending")
        self.assertEqual(result["evidence"]["missing"][0]["condition"], "check-pending")
        self.assertEqual(result["evidence"]["missing"][0]["id"], 1)

    def test_all_six_eligible_events_are_accepted(self):
        for event in ALLOWED:
            with self.subTest(event=event):
                result = observe(scenario([check()], workflows={90: run_page(workflow(event=event))}))
                self.assertEqual(result["outcome"], "success")

    def test_other_string_events_are_excluded(self):
        for event in (*EXCLUDED, "future_unrecognized_event"):
            with self.subTest(event=event):
                result = observe(scenario([check()], workflows={90: run_page(workflow(event=event))}))
                self.assertEqual(result["outcome"], "pending")
                self.assertEqual(result["evidence"]["observation"]["checks"], [])

    def test_external_and_null_apps_need_no_workflow_mapping_even_with_misleading_slug(self):
        for app in ({"id": 7}, {"id": 7, "slug": "github-actions"},
                    {"id": "15368", "slug": "github-actions"}, {}, None):
            with self.subTest(app=app):
                row = check()
                row["app"] = app
                row.pop("check_suite")
                api = scenario([row], requirements=(("ci", None),))
                self.assertEqual(observe(api)["outcome"], "success")
                self.assertFalse(any("/actions/runs?" in endpoint for endpoint, _ in api.calls))

    def test_legacy_head_status_is_not_filtered_with_ineligible_actions_check(self):
        for state, outcome in (("success", "success"), ("pending", "pending"),
                               ("failure", "checks-failed")):
            with self.subTest(state=state):
                api = scenario([check()], statuses=[status(state)],
                               requirements=(("ci", None),),
                               workflows={90: run_page(workflow(event="workflow_dispatch"))})
                result = observe(api)
                self.assertEqual(result["outcome"], outcome)
                self.assertEqual(result["evidence"]["observation"]["checks"], [])
                self.assertEqual(result["evidence"]["observation"]["statuses"], [status(state)])

    def test_actions_integer_id_is_filtered_when_slug_is_null_absent_or_misleading(self):
        for app in ({"id": 15368}, {"id": 15368, "slug": None},
                    {"id": 15368, "slug": "external-provider"}):
            with self.subTest(app=app):
                api = scenario([check(app=app)], workflows={90: run_page(workflow(event="schedule"))})
                self.assertEqual(observe(api)["outcome"], "pending")
                self.assertIn((runs_endpoint(90), {"pages": True, "key": "workflow_runs"}), api.calls)

    def test_suite_mapping_is_cached_only_within_each_commit_observation(self):
        api = scenario([check(1, name="ci"), check(2, name="lint")],
                       workflows={90: run_page(workflow())},
                       requirements=(("ci", 15368), ("lint", 15368)))
        for expected_calls in (1, 2):
            self.assertEqual(observe(api)["outcome"], "success")
            self.assertEqual(sum(endpoint == runs_endpoint(90) for endpoint, _ in api.calls), expected_calls)

    def test_distinct_suites_keep_their_own_event_mapping(self):
        api = scenario([check(1, 90, name="ci"), check(2, 91, name="lint")], workflows={
            90: run_page(workflow(90)), 91: run_page(workflow(91, "schedule"))},
            requirements=(("ci", 15368), ("lint", 15368)))
        result = observe(api)
        self.assertEqual(result["outcome"], "pending")
        self.assertEqual(result["evidence"]["missing"][0]["context"], "lint")
        for suite in (90, 91):
            self.assertEqual(sum(endpoint == runs_endpoint(suite) for endpoint, _ in api.calls), 1)

    def test_suite_id_not_workflow_sha_branch_or_pr_list_is_the_join(self):
        row = workflow(head_sha="different-workflow-sha", head_branch="fork-feature",
                       pull_requests=[])
        api = scenario([check(pull_requests=[])], workflows={90: run_page(row)})
        result = observe(api)
        self.assertEqual(result["outcome"], "success")
        self.assertEqual(result["evidence"]["observation"]["sha"], "head")
        self.assertIn((runs_endpoint(90), {"pages": True, "key": "workflow_runs"}), api.calls)

    def test_same_event_multiple_workflow_rows_are_not_ambiguous(self):
        api = scenario([check()], workflows={90: run_page(workflow(identifier=10), workflow(identifier=11))})
        self.assertEqual(observe(api)["outcome"], "success")


class ActionsUnknownMappingTests(unittest.TestCase):
    def assert_unknown(self, api):
        result, code = execute(api)
        self.assertEqual((result["outcome"], code), ("unknown-policy", 1))

    def test_missing_or_invalid_check_suite_is_unknown_not_success(self):
        for suite in (None, {}, {"id": None}, {"id": "90"}, {"id": True},
                      {"id": 0}, {"id": -1}, {"id": 90.0}, []):
            with self.subTest(suite=suite):
                row = check()
                row["check_suite"] = suite
                self.assert_unknown(scenario([row]))
        row = check()
        row.pop("check_suite")
        self.assert_unknown(scenario([row]))

    def test_empty_missing_event_and_ambiguous_workflows_are_unknown(self):
        no_event = workflow()
        no_event.pop("event")
        no_suite = workflow()
        no_suite.pop("check_suite_id")
        bodies = [run_page(), run_page(no_event), run_page(workflow(event=None)),
                  run_page(workflow(event=7)), run_page(workflow(event={})),
                  run_page(workflow(event="")),
                  run_page(workflow(), workflow(event="push", identifier=11)),
                  run_page(workflow(), workflow(event="schedule", identifier=11)),
                  run_page(workflow(91)), run_page(no_suite),
                  run_page(workflow(check_suite_id="90")),
                  run_page(workflow(), workflow(91, identifier=11))]
        for body in bodies:
            with self.subTest(body=body):
                self.assert_unknown(scenario([check()], workflows={90: body}))

    def test_conflicting_mapping_on_later_page_is_unknown(self):
        pages = Pages([{"total_count": 2, "workflow_runs": [workflow()]},
                       {"total_count": 2, "workflow_runs": [workflow(event="schedule", identifier=11)]}])
        self.assert_unknown(scenario([check()], workflows={90: pages}))

    def test_matching_mapping_on_later_page_is_accepted(self):
        pages = Pages([{"total_count": 2, "workflow_runs": [workflow()]},
                       {"total_count": 2, "workflow_runs": [workflow(identifier=11)]}])
        self.assertEqual(observe(scenario([check()], workflows={90: pages}))["outcome"], "success")

    def test_mapping_errors_preserve_auth_rate_transport_and_deadline_outcomes(self):
        for error, outcome in ((HTTPError(401, "Bad credentials"), "auth-error"),
                               (HTTPError(403, "rate limit exceeded"), "rate-limited"),
                               (HTTPError(429), "rate-limited"),
                               (HTTPError(500), "transport-error"),
                               (w.Failure("timeout", "deadline"), "timeout")):
            with self.subTest(outcome=outcome):
                result, code = execute(scenario([check()], workflows={90: error}))
                self.assertEqual((result["outcome"], code), (outcome, 1))


class TestMergeEligibilityTests(unittest.TestCase):
    def test_only_ineligible_test_merge_checks_fall_back_to_eligible_head(self):
        api = scenario([check(1, 90)], merge_checks=[check(2, 91)], workflows={
            90: run_page(workflow(90)), 91: run_page(workflow(91, "workflow_dispatch"))})
        result = observe(api)
        self.assertEqual(result["outcome"], "success")
        self.assertEqual(result["evidence"]["observation"]["sha"], "head")
        self.assertEqual(result["evidence"]["observation"]["checks"][0]["id"], 1)

    def test_test_merge_legacy_status_prevents_empty_fallback_and_keeps_precedence(self):
        for state, outcome in (("success", "success"), ("pending", "pending"),
                               ("failure", "checks-failed")):
            with self.subTest(state=state):
                api = scenario([check(1, 90, conclusion="failure")], merge_checks=[check(2, 91)],
                               merge_statuses=[status(state)], requirements=(("ci", None),),
                               workflows={91: run_page(workflow(91, "schedule"))})
                result = observe(api)
                self.assertEqual(result["outcome"], outcome)
                observed = result["evidence"]["observation"]
                self.assertEqual(observed["sha"], "test-merge")
                self.assertEqual(observed["checks"], [])
                self.assertEqual(observed["statuses"], [status(state)])
                self.assertFalse(any("/commits/head/" in endpoint for endpoint, _ in api.calls))

    def test_workflow_lookup_404_is_not_test_merge_absence(self):
        api = scenario([check(1, 90)], merge_checks=[check(2, 91)],
                       workflows={91: HTTPError(404)})
        result, code = execute(api)
        self.assertEqual((result["outcome"], code), ("transport-error", 1))
        self.assertFalse(any("/commits/head/" in endpoint for endpoint, _ in api.calls))

    def test_commit_metadata_404_still_falls_back_to_head(self):
        api = scenario([check()], merge_checks=[], workflows={90: run_page(workflow())})
        api.responses[ROOT + "/commits/test-merge"] = HTTPError(404)
        result = observe(api)
        self.assertEqual(result["outcome"], "success")
        self.assertEqual(result["evidence"]["observation"]["sha"], "head")
        self.assertFalse(any("/commits/test-merge/" in endpoint for endpoint, _ in api.calls))

    def test_test_merge_checks_or_statuses_404_cannot_trigger_metadata_fallback(self):
        for suffix in ("check-runs?per_page=100&filter=all", "statuses?per_page=100"):
            with self.subTest(suffix=suffix):
                api = scenario([check()], merge_checks=[], workflows={90: run_page(workflow())})
                api.responses[ROOT + "/commits/test-merge/" + suffix] = HTTPError(404)
                result, code = execute(api)
                self.assertEqual((result["outcome"], code), ("transport-error", 1))
                self.assertFalse(any("/commits/head/" in endpoint for endpoint, _ in api.calls))


class WorkflowRunsPaginationAdapterTests(unittest.TestCase):
    def test_total_count_requires_complete_consistent_workflow_pages(self):
        cases = [
            Pages([{"total_count": 2, "workflow_runs": [workflow()]}]),
            Pages([{"total_count": 0, "workflow_runs": [workflow()]}]),
            Pages([{"total_count": 2, "workflow_runs": [workflow()]},
                   {"total_count": 3, "workflow_runs": [workflow(identifier=11)]}]),
            Pages([{"workflow_runs": [workflow()]}]),
            Pages([{"total_count": "1", "workflow_runs": [workflow()]}]),
            Pages([{"total_count": True, "workflow_runs": [workflow()]}]),
            Pages([{"total_count": -1, "workflow_runs": []}]),
            Pages([{"total_count": None, "workflow_runs": [workflow()]}]),
            Pages([{"total_count": 1.0, "workflow_runs": [workflow()]}]),
            Pages([]),
        ]
        for pages in cases:
            with self.subTest(pages=pages):
                api = RESTBoundary({runs_endpoint(90): pages})
                with self.assertRaises(w.Failure) as caught:
                    api.get(runs_endpoint(90), pages=True, key="workflow_runs")
                self.assertEqual(caught.exception.outcome, "unknown-policy")

    def test_valid_total_count_is_combined_across_all_pages(self):
        first, second = workflow(), workflow(identifier=11)
        pages = Pages([{"total_count": 2, "workflow_runs": [first]},
                       {"total_count": 2, "workflow_runs": [second]}])
        api = RESTBoundary({runs_endpoint(90): pages})
        self.assertEqual(api.get(runs_endpoint(90), pages=True, key="workflow_runs"),
                         [first, second])


if __name__ == "__main__":
    unittest.main()
