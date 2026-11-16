"""GitHub state contracts at the REST and GraphQL subprocess boundaries."""
import copy
import json
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from test_github_pr_wait import (
    FakeAPI, PR, PULL, ROOT, URL, arguments, baseline, check_node, review, rollup_page,
    status_node, w,
)


class RESTBodies(FakeAPI):
    """Feed policy and review JSON through the real REST decoder."""

    def remaining(self):
        return 100

    def get(self, endpoint, **kwargs):
        body = super().get(endpoint, **kwargs)
        stdout = json.dumps([body] if kwargs.get("pages") else body)
        process = Mock(returncode=0)
        process.communicate.return_value = (stdout, "")
        with patch.object(w.subprocess, "Popen", return_value=process):
            return w.GitHub(100, 10, clock=lambda: 0).get(endpoint, **kwargs)

    def graphql(self, query, variables):
        body = super().graphql(query, variables)
        process = Mock(returncode=0)
        process.communicate.return_value = (json.dumps({"data": body}), "")
        with patch.object(w.subprocess, "Popen", return_value=process):
            return w.GitHub(100, 10, clock=lambda: 0).graphql(query, variables)


def check_row(status="COMPLETED", conclusion="SUCCESS", identifier=10,
              name="ci", required=True):
    return check_node(identifier, name, status, conclusion, required)


def status_row(state="PENDING", context="ci", required=True):
    return status_node(context=context, state=state, required=required)


def contract_api(*, checks=None, statuses=None, pr=None, classic=None, rules=None,
                 rollup_pages=None):
    checks = checks if checks is not None else []
    statuses = statuses if statuses is not None else []
    nodes = [*checks, *statuses]
    if rollup_pages is None:
        rollup_pages = [rollup_page(nodes)]
    responses = {
        PULL: copy.deepcopy(pr if pr is not None else {**PR, "merge_commit_sha": None}),
        ROOT + "/branches/main": {"name": "main", "protected": True,
                                  "commit": {"sha": "base"}},
        ROOT + "/branches/main/protection": classic if classic is not None else {
            "required_status_checks": {"strict": False, "contexts": ["ci"],
                                       "checks": [{"context": "ci", "app_id": None}]}},
        ROOT + "/rules/branches/main?per_page=100": rules if rules is not None else [],
        ROOT + "/compare/base...head": {"status": "identical", "ahead_by": 0, "behind_by": 0},
    }
    return RESTBodies(responses, rollup_pages)


def review_row(identifier=10, state="COMMENTED", **changes):
    row = review(identifier=identifier, state=state, node_id=f"review-{identifier}",
                 body="Review response", html_url=URL + f"#pullrequestreview-{identifier}",
                 pull_request_url=f"https://api.github.com/{PULL}", author_association="NONE",
                 _links={"html": {"href": URL},
                         "pull_request": {"href": f"https://api.github.com/{PULL}"}})
    if state == "PENDING":
        row.pop("submitted_at")
    row.update(changes)
    return row


def review_api(rows, pr=None):
    return RESTBodies({PULL: copy.deepcopy(PR if pr is None else pr),
                       PULL + "/reviews?per_page=100": rows})


def observe_review(api, requested="2026-11-11T10:00:01Z"):
    args = arguments("after-request")
    args.baseline_ids = {1}
    args.requested_time = w.timestamp(requested)
    return w.observe(api, w.target(URL), args)


class OfficialCheckStateContracts(unittest.TestCase):
    def test_every_documented_nonterminal_status_stays_pending(self):
        for state in ("QUEUED", "REQUESTED", "WAITING", "PENDING", "IN_PROGRESS"):
            with self.subTest(state=state):
                result = w.observe(contract_api(
                    checks=[check_row(status=state, conclusion=None)]),
                    w.target(URL), arguments("required-checks"))
                self.assertEqual(result["outcome"], "pending")
                self.assertEqual(result["evidence"]["failed"], [])
                self.assertEqual(result["evidence"]["missing"][0]["condition"], "check-pending")

    def test_wait_progresses_across_check_states(self):
        states = iter(("QUEUED", "REQUESTED", "WAITING", "PENDING", "IN_PROGRESS", "COMPLETED"))
        api = contract_api()
        observations = []
        clock = Mock(return_value=0.0)

        def advance(seconds=0):
            state = next(states)
            observations.append(state)
            api.graphql_responses = [rollup_page([
                check_row(status=state, conclusion="SUCCESS" if state == "COMPLETED" else None)])]
            clock.return_value += seconds

        advance()
        result, code = w.run(arguments("required-checks"), clock=clock, sleep=advance,
                             api_factory=lambda *a, **k: api)
        self.assertEqual((result["outcome"], code), ("success", 0))
        self.assertEqual(observations, ["QUEUED", "REQUESTED", "WAITING", "PENDING",
                                        "IN_PROGRESS", "COMPLETED"])

    def test_null_app_is_valid_for_unpinned_check(self):
        result = w.observe(contract_api(checks=[check_row()]), w.target(URL),
                           arguments("required-checks"))
        self.assertEqual(result["outcome"], "success")

    def test_loose_policy_does_not_require_up_to_date_head(self):
        api = contract_api(checks=[check_row()])
        api.responses[ROOT + "/compare/base...head"]["behind_by"] = 3
        result = w.observe(api, w.target(URL), arguments("required-checks"))
        self.assertEqual(result["outcome"], "success")
        self.assertNotIn(ROOT + "/compare/base...head", [endpoint for endpoint, _ in api.calls])

    def test_check_names_are_case_sensitive(self):
        result = w.observe(contract_api(checks=[check_row(name="CI")]),
                           w.target(URL), arguments("required-checks"))
        self.assertEqual(result["outcome"], "pending")
        self.assertEqual(result["evidence"]["missing"][0]["condition"], "missing")

    def test_nonrequired_failures_do_not_block_required_success(self):
        nodes = [check_row(), check_row(identifier=11, conclusion="FAILURE", required=False),
                 status_row(state="ERROR", required=False)]
        result = w.observe(contract_api(rollup_pages=[rollup_page(nodes)]),
                           w.target(URL), arguments("required-checks"))
        self.assertEqual(result["outcome"], "success")
        self.assertEqual(result["evidence"]["failed"], [])

    def test_null_rollup_leaves_policy_requirement_missing(self):
        page = {"repository": {"object": {"statusCheckRollup": None}}}
        result = w.observe(contract_api(rollup_pages=[page]), w.target(URL),
                           arguments("required-checks"))
        self.assertEqual(result["outcome"], "pending")
        self.assertEqual(result["evidence"]["observation"]["contexts"], [])
        self.assertEqual(result["evidence"]["missing"][0]["condition"], "missing")

    def test_required_false_same_name_does_not_satisfy_policy(self):
        result = w.observe(contract_api(checks=[check_row(required=False)]),
                           w.target(URL), arguments("required-checks"))
        self.assertEqual(result["outcome"], "pending")
        self.assertEqual(result["evidence"]["missing"][0]["condition"], "missing")

    def test_later_rollup_page_failure_is_terminal(self):
        pages = [rollup_page([check_row(name="build")], has_next=True, end_cursor="cursor"),
                 rollup_page([check_row(identifier=11, name="test", conclusion="FAILURE")])]
        rules = [{"type": "required_status_checks", "parameters": {
            "required_status_checks": [{"context": "build", "integration_id": 15368},
                                       {"context": "test", "integration_id": 15368}],
            "strict_required_status_checks_policy": False}}]
        result = w.observe(contract_api(classic={}, rules=rules, rollup_pages=pages),
                           w.target(URL), arguments("required-checks"))
        self.assertEqual(result["outcome"], "checks-failed")


class OfficialStatusContracts(unittest.TestCase):
    def test_status_only_error_and_failure_are_terminal(self):
        for state in ("ERROR", "FAILURE"):
            with self.subTest(state=state):
                result, code = w.run(arguments("required-checks"),
                                     api_factory=lambda *a, state=state, **k:
                                     contract_api(checks=[], statuses=[status_row(state=state)]))
                self.assertEqual((result["outcome"], code), ("checks-failed", 1))
                self.assertEqual(result["evidence"]["failed"][0]["state"], state)

    def test_status_only_pending_transitions_to_success(self):
        api = contract_api(checks=[], statuses=[status_row()])
        clock = Mock(return_value=0.0)

        def complete(seconds):
            api.graphql_responses = [rollup_page([status_row(state="SUCCESS")])]
            clock.return_value += seconds

        result, code = w.run(arguments("required-checks"), clock=clock, sleep=complete,
                             api_factory=lambda *a, **k: api)
        self.assertEqual((result["outcome"], code), ("success", 0))

    def test_context_matching_is_case_insensitive(self):
        for state, expected in (("SUCCESS", "success"), ("ERROR", "checks-failed")):
            with self.subTest(state=state):
                result = w.observe(contract_api(checks=[], statuses=[
                    status_row(state=state, context="CI")]), w.target(URL),
                    arguments("required-checks"))
                self.assertEqual(result["outcome"], expected)


class OfficialReviewContracts(unittest.TestCase):
    def test_pending_omits_submitted_at_then_same_review_is_submitted(self):
        api = review_api([review_row(state="PENDING")])
        self.assertEqual(observe_review(api)["outcome"], "pending")
        api.responses[PULL + "/reviews?per_page=100"] = [review_row()]
        result = observe_review(api)
        self.assertEqual(result["outcome"], "success")
        self.assertEqual(result["evidence"]["reviews"][0]["id"], 10)

    def test_nullable_actor_or_commit_cannot_qualify_as_named_current_head(self):
        for changes in ({"user": None}, {"commit_id": None}):
            with self.subTest(changes=changes):
                self.assertEqual(observe_review(review_api([review_row(**changes)]))["outcome"], "pending")

    def test_actor_login_matches_case_insensitively(self):
        result = observe_review(review_api([review_row(user={"login": "BoT"})]))
        self.assertEqual(result["outcome"], "success")

    def test_fractional_timestamp_boundary_and_equivalent_offset(self):
        request = "2026-11-11T10:00:01.500000Z"
        for submitted, expected in (("2026-11-11T10:00:01.499999Z", "pending"),
                                    ("2026-11-11T10:00:01.500001Z", "success"),
                                    ("2026-11-11T12:00:01.500001+02:00", "success")):
            with self.subTest(submitted=submitted):
                result = observe_review(review_api([review_row(submitted_at=submitted)]), request)
                self.assertEqual(result["outcome"], expected)

    def test_equal_second_is_not_proof_of_a_post_request_response(self):
        result = observe_review(review_api([review_row(submitted_at="2026-11-11T10:00:01Z")]))
        self.assertEqual(result["outcome"], "order-unproven")
        self.assertEqual(result["evidence"]["missing"], ["review-order"])

    def test_baseline_precision_and_case_normalized_identity(self):
        args = arguments("after-request", "wait", "--requested-after", "2026-11-11T10:00:01.500000Z")
        for captured, valid in (("2026-11-11T12:00:01.499999+02:00", True),
                                ("2026-11-11T10:00:01.500001Z", False)):
            record = {**baseline(), "url": URL.upper(), "repo": "EXAMPLE/PROJECT",
                      "reviewer": "BOT", "capturedAt": captured}
            with self.subTest(captured=captured), patch.object(Path, "read_text", return_value=json.dumps(record)):
                if valid:
                    w.validate_baseline(args, w.target(URL))
                    self.assertEqual(args.baseline_ids, {1})
                else:
                    with self.assertRaises(w.Failure) as error:
                        w.validate_baseline(args, w.target(URL))
                    self.assertEqual(error.exception.outcome, "invalid-input")

    def test_snapshot_pending_review_can_be_submitted_after_request_with_same_id(self):
        # POST .../reviews/{review_id}/events submits the existing draft; it
        # does not create a new review ID. Draft visibility is actor-dependent.
        # This models a caller permitted to see the draft, not a live incident.
        for state in ("COMMENTED", "APPROVED", "CHANGES_REQUESTED"):
            with self.subTest(state=state):
                api = review_api([review_row(state="PENDING")])
                with patch.object(w, "now", return_value="2026-11-11T10:00:00Z"):
                    snapshot, snapshot_code = w.run(arguments("after-request", "snapshot"),
                                                    api_factory=lambda *a, **k: api)
                self.assertEqual(snapshot_code, 0)
                self.assertEqual(snapshot["reviewIds"], [10])
                self.assertNotIn("submitted_at", snapshot["reviews"][0])
                api.responses[PULL + "/reviews?per_page=100"] = [review_row(state=state)]
                clock = Mock(return_value=0.0)

                def advance(seconds):
                    clock.return_value += seconds

                with patch.object(Path, "read_text", return_value=json.dumps(snapshot)):
                    result, code = w.run(arguments("after-request", "wait", "--timeout", "2"),
                                         clock=clock, sleep=advance, api_factory=lambda *a, **k: api)
                self.assertEqual((result["outcome"], code), ("success", 0))
                self.assertEqual(result["evidence"]["reviews"][0]["id"], 10)

    def test_already_submitted_baseline_review_is_not_a_new_response(self):
        api = review_api([review_row(submitted_at="2026-11-11T09:59:59Z")])
        with patch.object(w, "now", return_value="2026-11-11T10:00:00Z"):
            snapshot, _ = w.run(arguments("after-request", "snapshot"), api_factory=lambda *a, **k: api)
        clock = Mock(return_value=0.0)

        def advance(seconds):
            clock.return_value += seconds

        with patch.object(Path, "read_text", return_value=json.dumps(snapshot)):
            result, code = w.run(arguments("after-request", "wait", "--timeout", "2"),
                                 clock=clock, sleep=advance, api_factory=lambda *a, **k: api)
        self.assertEqual((result["outcome"], code), ("timeout", 1))
        self.assertEqual(result["evidence"]["missing"], ["after-request"])


class OfficialPRTransitionContracts(unittest.TestCase):
    def test_final_closed_or_merged_invalidates_otherwise_ready_observation(self):
        for purpose in ("required-checks", "after-request", "current-response"):
            for merged, expected in ((False, "closed"), (True, "invalidated")):
                with self.subTest(purpose=purpose, merged=merged):
                    api = contract_api(checks=[check_row()]) if purpose == "required-checks" else review_api([review_row()])
                    initial = copy.deepcopy(api.responses[PULL])
                    final = {**initial, "state": "closed", "merged": merged,
                             "merge_commit_sha": "actual-merge" if merged else initial["merge_commit_sha"]}
                    reads = iter([initial, final])
                    api.responses[PULL] = lambda: next(reads)
                    if purpose == "after-request":
                        result = observe_review(api)
                    else:
                        result = w.observe(api, w.target(URL), arguments(purpose))
                    self.assertEqual(result["outcome"], expected)
                    self.assertEqual(result["evidence"]["lastObservation"]["outcome"], "success")

    def test_final_head_change_overrides_ready_checks(self):
        api = contract_api(checks=[check_row()])
        initial = copy.deepcopy(api.responses[PULL])
        reads = iter([initial, {**initial, "head": {"sha": "new-head"}}])
        api.responses[PULL] = lambda: next(reads)
        result = w.observe(api, w.target(URL), arguments("required-checks"))
        self.assertEqual(result["outcome"], "invalidated")
        self.assertEqual(result["head"], "new-head")
        self.assertEqual(result["evidence"]["lastObservation"]["outcome"], "success")

    def test_base_change_is_reobserved_before_wait_can_succeed(self):
        api = contract_api(checks=[check_row()])
        initial = copy.deepcopy(api.responses[PULL])
        updated = {**initial, "base": {"ref": "release", "sha": "release-base"}}
        reads = iter([initial, updated, updated, updated])
        api.responses[PULL] = lambda: next(reads)
        for suffix in ("", "/protection"):
            api.responses[ROOT + "/branches/release" + suffix] = copy.deepcopy(
                api.responses[ROOT + "/branches/main" + suffix])
        api.responses[ROOT + "/rules/branches/release?per_page=100"] = []
        clock = Mock(return_value=0.0)
        sleeps = []

        def advance(seconds):
            sleeps.append(seconds)
            clock.return_value += seconds

        result, code = w.run(arguments("required-checks"), clock=clock, sleep=advance,
                             api_factory=lambda *a, **k: api)
        self.assertEqual((result["outcome"], code), ("success", 0))
        self.assertEqual((result["base"], result["baseSha"]), ("release", "release-base"))
        self.assertEqual(len(sleeps), 1)
        self.assertIn(ROOT + "/branches/release/protection",
                      [endpoint for endpoint, _ in api.calls])

    def test_open_merge_sha_never_means_actually_merged(self):
        api = RESTBodies({PULL: {**PR, "mergeable": True,
                                 "merge_commit_sha": "computed-merge"}})
        result = w.observe(api, w.target(URL), arguments("merged"))
        self.assertEqual(result["outcome"], "pending")
        self.assertFalse(result["merged"])
        self.assertIsNone(result["mergeSha"])


class SyntheticMalformedPolicyContracts(unittest.TestCase):
    def assert_policy_fails_closed(self, api):
        result, code = w.run(arguments("required-checks"), api_factory=lambda *a, **k: api)
        self.assertNotEqual(result["outcome"], "success")
        self.assertNotEqual(code, 0)
        self.assertIn(result["outcome"], ("unknown-policy", "transport-error"))

    def test_classic_required_arrays_cannot_be_absent_or_wrong_types(self):
        for required in ({}, {"contexts": [], "checks": {}}, {"contexts": "", "checks": []}):
            with self.subTest(required=required):
                self.assert_policy_fails_closed(contract_api(classic={"required_status_checks": required}))

    def test_classic_explicit_null_strict_is_not_false(self):
        self.assert_policy_fails_closed(contract_api(checks=[check_row()], classic={
            "required_status_checks": {"contexts": ["ci"], "checks": [], "strict": None}}))

    def test_missing_classic_app_id_cannot_remove_app_restriction(self):
        self.assert_policy_fails_closed(contract_api(checks=[check_row()], classic={
            "required_status_checks": {"contexts": ["ci"],
                                       "checks": [{"context": "ci"}], "strict": False}}))

    def test_ruleset_required_strict_boolean_cannot_be_missing_null_or_numeric(self):
        for parameters in ({"required_status_checks": [{"context": "ci"}]},
                           {"required_status_checks": [{"context": "ci"}],
                            "strict_required_status_checks_policy": None},
                           {"required_status_checks": [{"context": "ci"}],
                            "strict_required_status_checks_policy": 0}):
            with self.subTest(parameters=parameters):
                self.assert_policy_fails_closed(contract_api(checks=[check_row()], classic={}, rules=[
                    {"type": "required_status_checks", "parameters": parameters}]))

    def test_rule_without_required_type_is_not_an_empty_policy(self):
        self.assert_policy_fails_closed(contract_api(classic={}, rules=[{}]))

    def test_required_flag_must_be_boolean(self):
        for value in (None, 0, 1, "true"):
            with self.subTest(value=value):
                self.assert_policy_fails_closed(contract_api(
                    rollup_pages=[rollup_page([check_row(required=value)])]))
        node = check_row()
        node.pop("isRequired")
        self.assert_policy_fails_closed(contract_api(rollup_pages=[rollup_page([node])]))

    def test_unknown_context_kind_fails_closed(self):
        node = {"__typename": "FutureContext", "isRequired": True}
        self.assert_policy_fails_closed(contract_api(rollup_pages=[rollup_page([node])]))


if __name__ == "__main__":
    unittest.main()
