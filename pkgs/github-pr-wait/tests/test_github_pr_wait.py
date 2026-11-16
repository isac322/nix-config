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
      "merged": False, "merge_commit_sha": None, "state": "open", "mergeable": None,
      "mergeable_state": "blocked"}
REQUESTED = "2026-11-11T10:00:01Z"


def arguments(purpose="merged", command="wait", *extra):
    argv = [command, URL, "--until", purpose]
    if command == "wait":
        argv += ["--expected-head", "head", "--timeout", "10", "--interval", "1"]
    if purpose in ("current-response", "after-request"):
        argv += ["--reviewer", "bot"]
        if command == "wait" and purpose == "after-request":
            argv += ["--baseline", "baseline.json", "--requested-after", REQUESTED]
    return w.parser().parse_args(argv + list(extra))


def baseline():
    return {"url": URL, "repo": "example/project", "pr": 7, "head": "head",
            "reviewer": "bot", "until": "after-request", "outcome": "pending",
            "capturedAt": "2026-11-11T10:00:00Z", "reviewIds": [1],
            "reviews": [review(identifier=1, submitted_at="2026-11-11T10:00:00Z")]}


def review(identifier=2, state="COMMENTED", **changes):
    return {"id": identifier, "state": state, "user": {"login": "bot"},
            "submitted_at": "2026-11-11T10:00:02Z", "commit_id": "head", **changes}


def check_node(identifier=1, name="test", status="COMPLETED", conclusion="SUCCESS",
               required=True):
    return {"__typename": "CheckRun", "databaseId": identifier, "name": name,
            "status": status, "conclusion": conclusion, "isRequired": required}


def status_node(context="test", state="SUCCESS", required=True):
    return {"__typename": "StatusContext", "context": context, "state": state,
            "isRequired": required}


def rollup_page(nodes, *, has_next=False, end_cursor=None):
    return {"repository": {"object": {"statusCheckRollup": {
        "contexts": {"pageInfo": {"hasNextPage": has_next, "endCursor": end_cursor},
                     "nodes": copy.deepcopy(nodes)}}}}}


class FakeAPI:
    def __init__(self, responses, graphql_responses=None):
        self.responses = responses
        self.graphql_responses = graphql_responses or [rollup_page([])]
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

    def graphql(self, query, variables):
        self.calls.append(("graphql", {"query": query, **variables}))
        response = self.graphql_responses
        if callable(response):
            response = response(query, variables)
        elif isinstance(response, list):
            cursors = [None, *[
                page["repository"]["object"]["statusCheckRollup"]["contexts"]["pageInfo"]["endCursor"]
                for page in response[:-1]]]
            response = response[cursors.index(variables.get("after"))]
        if isinstance(response, BaseException):
            raise response
        return copy.deepcopy(response)


def ci_api(*, checks=None, rules=None, classic=None, metadata=None,
           rollup_pages=None, behind=0):
    checks = checks if checks is not None else [check_node()]
    if rollup_pages is None:
        rollup_pages = [rollup_page(checks)]
    responses = {
        PULL: PR,
        ROOT + "/branches/main": metadata if metadata is not None else {
            "protected": True, "protection": {"enabled": False}},
        ROOT + "/branches/main/protection": classic if classic is not None else
            w.Failure("transport-error", "404", status=404),
        ROOT + "/rules/branches/main?per_page=100": rules if rules is not None else
            [{"type": "required_status_checks", "parameters": {
                "required_status_checks": [{"context": "test", "integration_id": 15368}],
                "strict_required_status_checks_policy": True}}],
        ROOT + "/compare/base...head": {"behind_by": behind},
    }
    return FakeAPI(responses, rollup_pages)


class ReviewTests(unittest.TestCase):
    def observe(self, reviews, args=None, pr=PR):
        args = args or arguments("after-request")
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
                     review(submitted_at="2026-11-11T10:00:00Z"), review(submitted_at=None)):
            with self.subTest(review=item):
                self.assertEqual(self.observe([item])["outcome"], "pending")

    def test_snapshot_captures_all_ids_even_other_actors_and_pending(self):
        rows = [review(identifier=1), review(identifier=2, state="PENDING"), review(identifier=3, user={"login": "other"})]
        result = self.observe(rows, arguments("after-request", "snapshot"))
        self.assertEqual(result["reviewIds"], [1, 2, 3])
        self.assertEqual(result["reviews"], rows)
        self.assertEqual(result["reviewer"], "bot")
        self.assertIsNone(result["mergeSha"])

    def test_closed_review_snapshot_still_collects_all_review_ids(self):
        result = self.observe([review()], arguments("after-request", "snapshot"), pr={**PR, "state": "closed"})
        self.assertEqual(result["reviewIds"], [2])
        self.assertEqual(result["outcome"], "closed")

    def test_unknown_mergeability_does_not_block_review(self):
        self.assertEqual(self.observe([review()], pr={**PR, "mergeable": None})["outcome"], "success")

    def test_head_race_prevents_success(self):
        responses = iter([PR, {**PR, "head": {"sha": "new"}}])
        args = arguments("after-request")
        args.baseline_ids, args.requested_time = set(), w.timestamp(REQUESTED)
        result = w.observe(FakeAPI({PULL: lambda: next(responses), PULL + "/reviews?per_page=100": [review()]}), w.target(URL), args)
        self.assertEqual(result["outcome"], "invalidated")
        self.assertEqual(result["head"], "new")

    def test_valid_baseline(self):
        args = arguments("after-request")
        with patch.object(Path, "read_text", return_value=json.dumps(baseline())):
            w.validate_baseline(args, w.target(URL))
        self.assertEqual(args.baseline_ids, {1})

    def test_baseline_identity_reviewer_time_and_ids_validation(self):
        for field, value in (("url", URL + "0"), ("repo", "other/repo"), ("pr", 8),
                             ("reviewer", "other"),
                             ("capturedAt", "2026-11-11T10:00:02Z"),
                             ("reviewIds", ["1"]), ("outcome", "invalidated")):
            with self.subTest(field=field), patch.object(Path, "read_text", return_value=json.dumps({**baseline(), field: value})):
                with self.assertRaises(w.Failure) as error:
                    w.validate_baseline(arguments("after-request"), w.target(URL))
                self.assertEqual(error.exception.outcome, "invalid-input")

    def test_naive_request_timestamp_rejected(self):
        with self.assertRaises(w.Failure):
            w.timestamp("2026-11-11T10:00:01")

    def wait_for(self, reviews, args, record=None):
        api = FakeAPI({PULL: PR, PULL + "/reviews?per_page=100": reviews})
        api.remaining = lambda: 10
        clock = Mock(return_value=0.0)

        def advance(seconds):
            clock.return_value += seconds

        sleep = Mock(side_effect=advance)
        with patch.object(Path, "read_text", return_value=json.dumps(record or baseline())):
            result, code = w.run(args, clock=clock, sleep=sleep, api_factory=lambda *a, **k: api)
        return result, code, sleep

    def test_current_response_observes_newest_review_without_request(self):
        old = review(identifier=1, submitted_at="2026-11-11T09:00:00Z", state="APPROVED")
        newest = review(identifier=3, state="CHANGES_REQUESTED")
        result, code, sleep = self.wait_for([newest, old, review()], arguments("current-response"))
        self.assertEqual((result["outcome"], code), ("success", 0))
        self.assertEqual(result["evidence"]["reviews"], [newest])
        sleep.assert_not_called()

    def test_current_response_rejects_wrong_actor_head_and_unsubmitted_reviews(self):
        for item in (review(user={"login": "other"}), review(commit_id="old-head"),
                     review(state="DISMISSED"), review(state="PENDING"), review(submitted_at=None)):
            with self.subTest(review=item):
                result, code, _ = self.wait_for([item], arguments("current-response", "wait", "--timeout", "2"))
                self.assertEqual((result["outcome"], code), ("timeout", 1))
                self.assertEqual(result["evidence"]["missing"], ["current-response"])

    def test_review_modes_reject_mixed_or_missing_request_inputs(self):
        for purpose, extra in (("current-response", ("--baseline", "baseline.json")),
                               ("current-response", ("--requested-after", REQUESTED)),
                               ("after-request", ("--baseline", "")),
                               ("after-request", ("--requested-after", ""))):
            with self.subTest(purpose=purpose, extra=extra), self.assertRaises(w.Failure) as error:
                w.run(arguments(purpose, "wait", *extra))
            self.assertEqual(error.exception.outcome, "invalid-input")

    def test_request_in_same_second_returns_without_waiting(self):
        for requested in (REQUESTED, "2026-11-11T10:00:01.500000Z"):
            with self.subTest(requested=requested):
                result, code, sleep = self.wait_for(
                    [review(submitted_at=REQUESTED)],
                    arguments("after-request", "wait", "--requested-after", requested))
                self.assertEqual((result["outcome"], code), ("order-unproven", 1))
                self.assertEqual(result["evidence"]["missing"], ["review-order"])
                sleep.assert_not_called()

    def test_definite_fresh_response_wins_over_ambiguous_candidate(self):
        definite = review(identifier=3)
        for rows in ([review(submitted_at=REQUESTED), definite],
                     [definite, review(submitted_at=REQUESTED)]):
            with self.subTest(rows=rows):
                result, code, _ = self.wait_for(rows, arguments("after-request"))
                self.assertEqual((result["outcome"], code), ("success", 0))
                self.assertEqual(result["evidence"]["reviews"], [definite])

    def test_excluded_same_second_reviews_do_not_trigger_ambiguity(self):
        for item in (review(identifier=1, submitted_at=REQUESTED),
                     review(user={"login": "other"}, submitted_at=REQUESTED),
                     review(commit_id="other", submitted_at=REQUESTED),
                     review(state="DISMISSED", submitted_at=REQUESTED)):
            with self.subTest(review=item):
                result, code, _ = self.wait_for([item], arguments("after-request", "wait", "--timeout", "2"))
                self.assertEqual((result["outcome"], code), ("timeout", 1))

    def test_pre_push_baseline_accepts_new_target_response(self):
        result, code, sleep = self.wait_for(
            [review()], arguments("after-request"), {**baseline(), "head": "pre-push-head"})
        self.assertEqual((result["outcome"], code), ("success", 0))
        self.assertEqual(result["evidence"]["reviews"][0]["id"], 2)
        sleep.assert_not_called()

    def test_pre_push_baseline_excludes_previous_target_response(self):
        old_target = review(identifier=1)
        result, code, _ = self.wait_for(
            [old_target], arguments("after-request", "wait", "--timeout", "2"),
            {**baseline(), "head": "pre-push-head", "reviews": [old_target]})
        self.assertEqual((result["outcome"], code), ("timeout", 1))
        self.assertEqual(result["evidence"]["missing"], ["after-request"])


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
        api = ci_api(classic=classic, checks=[check_node(), check_node(identifier=2, name="lint")])
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
        for nodes in ([], [check_node(required=False)]):
            with self.subTest(nodes=nodes):
                result = self.observe(ci_api(rollup_pages=[rollup_page(nodes)]))
                self.assertEqual(result["outcome"], "pending")
                self.assertEqual(result["evidence"]["missing"][0]["condition"], "missing")

    def test_required_status_context_can_satisfy_pinned_requirement(self):
        classic = {"required_status_checks": {
            "contexts": ["test"], "checks": [{"context": "test", "app_id": 15368}],
            "strict": False}}
        result = self.observe(ci_api(classic=classic, rules=[],
                                     rollup_pages=[rollup_page([status_node()])]))
        self.assertEqual(result["outcome"], "success")

    def test_pending_and_expected_status_contexts_stay_pending(self):
        for state in ("PENDING", "EXPECTED"):
            with self.subTest(state=state):
                classic = {"required_status_checks": {
                    "contexts": ["test"], "checks": [{"context": "test", "app_id": None}],
                    "strict": False}}
                result = self.observe(ci_api(classic=classic, rules=[],
                                             rollup_pages=[rollup_page([status_node(state=state)])]))
                self.assertEqual(result["outcome"], "pending")
                self.assertEqual(result["evidence"]["missing"][0]["condition"], "status-pending")

    def test_status_context_names_are_case_insensitive(self):
        classic = {"required_status_checks": {
            "contexts": ["test"], "checks": [{"context": "test", "app_id": None}],
            "strict": False}}
        result = self.observe(ci_api(classic=classic, rules=[],
                                     rollup_pages=[rollup_page([status_node(context="TEST")])]))
        self.assertEqual(result["outcome"], "success")

    def test_required_check_terminal_failure_and_accepted_conclusions(self):
        for conclusion in ("success", "neutral", "skipped", "failure", "cancelled",
                           "timed_out", "action_required", "stale"):
            with self.subTest(conclusion=conclusion):
                expected = "success" if conclusion in ("success", "neutral", "skipped") else "checks-failed"
                self.assertEqual(self.observe(ci_api(checks=[
                    check_node(conclusion=conclusion.upper())]))["outcome"], expected)

    def test_required_check_status_collision_requires_both_successes(self):
        for state, expected in (("FAILURE", "checks-failed"), ("PENDING", "pending"),
                                ("SUCCESS", "success")):
            with self.subTest(state=state):
                result = self.observe(ci_api(rollup_pages=[
                    rollup_page([check_node(), status_node(state=state)])]))
                self.assertEqual(result["outcome"], expected)

    def test_later_rollup_page_failure_prevents_false_success(self):
        pages = [rollup_page([check_node(identifier=1, name="build")],
                             has_next=True, end_cursor="cursor"),
                 rollup_page([check_node(identifier=2, name="test", conclusion="FAILURE")])]
        rules = [{"type": "required_status_checks", "parameters": {
            "required_status_checks": [{"context": "build", "integration_id": 15368},
                                       {"context": "test", "integration_id": 15368}],
            "strict_required_status_checks_policy": False}}]
        result = self.observe(ci_api(rules=rules, rollup_pages=pages))
        self.assertEqual(result["outcome"], "checks-failed")
        self.assertEqual(result["evidence"]["failed"][0]["context"], "test")

    def pr_8828(self, vercel_required=True):
        url = "https://github.com/runbear-io/plugbear/pull/8828"
        root = "repos/runbear-io/plugbear"
        head = "60da3a93fd0d122a5a4a7748016859cb8291494d"
        vercel = ("Vercel – runbear-app", "Vercel – runbear-docs",
                  "Vercel – runbear-landing")
        actions = ("Build Worker", "Detect Prisma Changes", "Lint (Biome)",
                   "Prisma Migration Check", "Test")
        required = ([{"context": name, "app_id": 8329} for name in vercel]
                    + [{"context": name, "app_id": 15368} for name in actions])
        nodes = [status_node(context=name, required=vercel_required) for name in vercel]
        nodes.extend(check_node(identifier=index, name=name,
                                 conclusion="SKIPPED" if name == "Prisma Migration Check" else "SUCCESS")
                     for index, name in enumerate(actions, 1))
        nodes.extend(status_node(context=name, required=False) for name in
                     ("Vercel – runbear-storybook", "Vercel – runbear-studio", "Totoro PR Review"))
        nodes.extend([
            check_node(identifier=6, name="Push Revalidation", conclusion="SKIPPED", required=False),
            check_node(identifier=7, name="Crawler Integration Tests", required=False),
        ])
        api = FakeAPI({
            root + "/pulls/8828": {**PR, "head": {"sha": head}},
            root + "/branches/main": {"protected": True},
            root + "/branches/main/protection": {"required_status_checks": {
                "contexts": [row["context"] for row in required],
                "checks": required, "strict": False}},
            root + "/rules/branches/main?per_page=100": [],
        }, [rollup_page(nodes)])
        args = w.parser().parse_args([
            "wait", url, "--until", "required-checks", "--expected-head", head,
            "--timeout", "10"])
        return w.observe(api, w.target(url), args), api

    def test_pr_8828_vercel_status_contexts_and_skipped_prisma_pass(self):
        result, api = self.pr_8828()
        self.assertEqual(result["outcome"], "success")
        self.assertEqual(result["head"], "60da3a93fd0d122a5a4a7748016859cb8291494d")
        self.assertEqual(result["evidence"]["missing"], [])
        self.assertEqual(result["evidence"]["failed"], [])
        graphql_calls = [variables for endpoint, variables in api.calls if endpoint == "graphql"]
        self.assertEqual((graphql_calls[0]["owner"], graphql_calls[0]["name"],
                          graphql_calls[0]["pr"], graphql_calls[0]["sha"]),
                         ("runbear-io", "plugbear", 8828, result["head"]))

    def test_pr_8828_nonrequired_same_names_remain_missing(self):
        result, _ = self.pr_8828(vercel_required=False)
        self.assertEqual(result["outcome"], "pending")
        self.assertEqual({row["context"] for row in result["evidence"]["missing"]},
                         {"Vercel – runbear-app", "Vercel – runbear-docs",
                          "Vercel – runbear-landing"})
        self.assertTrue(all(row["condition"] == "missing"
                            for row in result["evidence"]["missing"]))

    def test_strict_policy_checks_ancestry_not_review_blocking(self):
        self.assertEqual(self.observe(ci_api(behind=1))["outcome"], "needs-action")
        self.assertEqual(self.observe(ci_api(behind=0))["outcome"], "success")

    def test_strict_behind_returns_for_action_without_sleeping(self):
        for checks, expected in (([check_node()], "needs-action"),
                                 ([check_node(conclusion="FAILURE")], "checks-failed"),
                                 ([check_node(status="QUEUED", conclusion=None)], "needs-action")):
            with self.subTest(expected=expected, checks=checks):
                api = ci_api(behind=1, checks=checks)
                api.remaining = lambda: 10
                sleep = Mock()
                result, code = w.run(arguments("required-checks"), clock=lambda: 0,
                                     sleep=sleep, api_factory=lambda *a, **k: api)
                self.assertEqual((result["outcome"], code), (expected, 1))
                self.assertIn({"condition": "head-behind-base", "commits": 1}, result["evidence"]["missing"])
                sleep.assert_not_called()


    def test_base_repository_metadata_change_preserves_check_outcome(self):
        initial = {**PR, "base": {**PR["base"], "repo": {"pushed_at": "2026-11-11T10:00:00Z"}}}
        final = {**PR, "base": {**PR["base"], "repo": {"pushed_at": "2026-11-11T10:00:01Z"}}}
        for conclusion, outcome in (("success", "success"), ("failure", "checks-failed")):
            with self.subTest(conclusion=conclusion):
                api = ci_api(checks=[check_node(conclusion=conclusion.upper())])
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
        for purpose in ("merged", "required-checks", "after-request", "current-response"):
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

    def test_graphql_command_preserves_typed_variables(self):
        process = Mock(returncode=0)
        process.communicate.return_value = (json.dumps({"data": {"repository": {}}}), "")
        with patch.object(w.subprocess, "Popen", return_value=process) as popen:
            self.assertEqual(self.api().graphql("query", {
                "owner": "example", "name": "project", "sha": "head", "pr": 7}),
                             {"repository": {}})
        command = popen.call_args.args[0]
        self.assertEqual(command[:3], ["gh", "api", "graphql"])
        self.assertIn("-f", command)
        self.assertIn("-F", command)
        self.assertIn("pr=7", command)

    def test_graphql_auth_errors_do_not_retry_or_disclose_stderr(self):
        process = Mock(returncode=1)
        process.communicate.return_value = ("", "gh: HTTP 401 " + "secret-token")
        with patch.object(w.subprocess, "Popen", return_value=process), self.assertRaises(w.Failure) as error:
            self.api().graphql("query", {})
        self.assertEqual(error.exception.outcome, "auth-error")
        self.assertNotIn("secret-token", error.exception.reason)

    def test_graphql_errors_array_fails_closed(self):
        process = Mock(returncode=0)
        process.communicate.return_value = (json.dumps({
            "data": {"repository": {}}, "errors": [{"message": "forbidden"}]}), "")
        with patch.object(w.subprocess, "Popen", return_value=process), self.assertRaises(w.Failure) as error:
            self.api().graphql("query", {})
        self.assertEqual(error.exception.outcome, "transport-error")

    def test_malformed_graphql_json_fails_closed(self):
        for stdout in ("not-json", "{}", '{"data": null}', '{"errors": []}'):
            process = Mock(returncode=0)
            process.communicate.return_value = (stdout, "")
            with self.subTest(stdout=stdout), patch.object(w.subprocess, "Popen", return_value=process), self.assertRaises(w.Failure):
                self.api().graphql("query", {})

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


NOW = w.timestamp("2026-11-16T05:00:00Z")
OLD = "2026-11-16T04:09:04Z"


def suite(app, status="COMPLETED", conclusion="SUCCESS", updated=OLD):
    return {"status": status, "conclusion": conclusion, "updatedAt": updated, "app": {"databaseId": app}}


def activity_page(nodes, suites):
    page = rollup_page(nodes)
    page["repository"]["object"]["checkSuites"] = {"pageInfo": {"hasNextPage": False}, "nodes": suites}
    return page


def dated(node, at=OLD):
    return {**node, "createdAt": at} if node["__typename"] == "StatusContext" else {**node, "completedAt": at}


class StalledChecksTests(unittest.TestCase):
    """필수 검사가 남았지만 GitHub에서 더 진행될 일이 없으면 기다리지 않고 needs-action을 반환한다."""

    def observe(self, page, pr=PR, *extra):
        api = ci_api(rollup_pages=[page])
        api.responses[PULL] = pr
        with patch.object(w, "utcnow", return_value=NOW):
            return w.observe(api, w.target(URL), arguments("required-checks", "snapshot", *extra))

    def test_unused_app_queued_suites_do_not_keep_a_finished_ci_waiting(self):
        # PR #8831: 충돌로 pull_request workflow가 시작되지 않았고, 설치만 된 앱 suite는 QUEUED로 남는다.
        page = activity_page([dated(status_node("Vercel – runbear-app", required=False))],
                             [suite(8329), suite(999, "QUEUED", None), suite(15368, conclusion="SKIPPED")])
        for pr, blocker in (({**PR, "mergeable": False}, "merge-conflict"), (PR, "checks-stalled")):
            with self.subTest(blocker=blocker):
                result = self.observe(page, pr)
                self.assertEqual(result["outcome"], "needs-action")
                self.assertEqual(result["evidence"]["missing"][0]["context"], "test")
                self.assertEqual([row["condition"] for row in result["evidence"]["activity"]["blockers"]], [blocker])

    def test_suite_of_the_app_owning_a_missing_requirement_keeps_waiting(self):
        api = ci_api(rollup_pages=[activity_page([], [suite(999, "QUEUED", None)])], rules=[
            {"type": "required_status_checks", "parameters": {
                "required_status_checks": [{"context": "external", "integration_id": 999}],
                "strict_required_status_checks_policy": False}}])
        with patch.object(w, "utcnow", return_value=NOW):
            result = w.observe(api, w.target(URL), arguments("required-checks", "snapshot"))
        self.assertEqual(result["outcome"], "pending")
        self.assertEqual(result["evidence"]["activity"]["inFlight"][0]["appId"], 999)

    def test_work_still_in_flight_keeps_waiting(self):
        cases = {
            "actions-suite-queued": activity_page([], [suite(15368, "QUEUED", None)]),
            "required-check-running": activity_page([dated(check_node(status="IN_PROGRESS", conclusion=None))], []),
            "other-check-queued": activity_page(
                [check_node(name="lint", status="QUEUED", conclusion=None, required=False)], []),
            "status-pending": activity_page([dated(status_node("deploy", "PENDING", required=False))], []),
            "suites-unobserved": rollup_page([dated(status_node("deploy", required=False))]),
        }
        for name, page in cases.items():
            with self.subTest(name):
                result = self.observe(page)
                self.assertEqual(result["outcome"], "pending")
                self.assertTrue(result["evidence"]["activity"]["inFlight"])

    def test_recent_activity_waits_for_the_settle_window(self):
        page = activity_page([dated(status_node("deploy", required=False), "2026-11-16T04:59:30Z")], [])
        result = self.observe(page)
        self.assertEqual(result["outcome"], "pending")
        self.assertTrue(result["evidence"]["activity"]["idle"])
        self.assertEqual(self.observe(page, PR, "--settle", "20")["outcome"], "needs-action")

    def test_approval_waits_are_reported_as_needing_action(self):
        cases = {
            "deployment-approval-required": activity_page(
                [{**check_node(status="WAITING", conclusion=None), "startedAt": OLD}], [suite(15368, "WAITING", None)]),
            "workflow-approval-required": activity_page([], [suite(15368, conclusion="ACTION_REQUIRED")]),
        }
        for condition, page in cases.items():
            with self.subTest(condition):
                result = self.observe(page)
                self.assertEqual(result["outcome"], "needs-action")
                self.assertIn(condition, [row["condition"] for row in result["evidence"]["activity"]["blockers"]])

    def test_wait_without_any_github_timestamp_stops_after_local_settle(self):
        clock = Mock(return_value=0.0)
        api = ci_api(rollup_pages=[activity_page([], [])])
        api.remaining = lambda: None
        def sleep(seconds):
            clock.return_value += seconds
        result, code = w.run(arguments("required-checks", "wait", "--settle", "3"), clock=clock, sleep=sleep,
                             api_factory=lambda *a, **k: api)
        self.assertEqual((result["outcome"], code), ("needs-action", 1))
        self.assertEqual(clock.return_value, 3.0)
        self.assertEqual(result["evidence"]["activity"]["blockers"], [{"condition": "checks-stalled"}])

    def test_new_activity_restarts_the_local_settle_window(self):
        clock = Mock(return_value=0.0)
        times = iter("2026-11-16T04:59:%02dZ" % second for second in range(30, 60))
        api = ci_api(rollup_pages=lambda *_: activity_page(
            [dated(status_node("deploy", required=False), next(times))], []))
        api.remaining = lambda: None
        def sleep(seconds):
            clock.return_value += seconds
        with patch.object(w, "utcnow", return_value=w.timestamp("2026-11-16T04:59:30Z")):
            result, _ = w.run(arguments("required-checks", "wait", "--settle", "3"), clock=clock, sleep=sleep,
                              api_factory=lambda *a, **k: api)
        self.assertEqual(result["outcome"], "timeout")


if __name__ == "__main__":
    unittest.main()
