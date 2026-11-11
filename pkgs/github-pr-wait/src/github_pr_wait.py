#!/usr/bin/env python3
"""읽기 전용 GitHub PR 관찰기. 종료 코드 0은 머지 승인이 아니다."""
import argparse
import datetime as dt
import json
import math
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
from urllib.parse import quote


# 이 CLI는 github.com만 지원한다. slug가 생략돼도 Actions 앱을 식별한다.
GITHUB_ACTIONS_APP_ID = 15368
PR_ACTION_EVENTS = frozenset((
    "push", "pull_request", "pull_request_review", "pull_request_target",
    "deployment", "deployment_status",
))


class Failure(Exception):
    def __init__(self, outcome, reason, *, transient=False, status=None):
        super().__init__(reason)
        self.outcome = outcome
        self.reason = reason
        self.transient = transient
        self.status = status


class Cancelled(BaseException):
    pass


def timestamp(value):
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            raise ValueError
        return parsed.astimezone(dt.timezone.utc)
    except (ValueError, AttributeError, TypeError):
        raise Failure("invalid-input", "시간은 시간대가 있는 ISO 8601 형식이어야 합니다.") from None


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def positive(value):
    try:
        number = float(value)
        if not math.isfinite(number) or number <= 0:
            raise ValueError
        return number
    except ValueError:
        raise argparse.ArgumentTypeError("유한한 양수를 지정하세요.") from None


def target(url):
    match = re.fullmatch(r"https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/pull/([1-9][0-9]*)/?", url)
    if not match:
        raise Failure("invalid-input", "https://github.com/OWNER/REPO/pull/NUMBER URL이 필요합니다.")
    owner, repo, number = match.groups()
    return {"url": f"https://github.com/{owner}/{repo}/pull/{number}",
            "repo": f"{owner}/{repo}", "pr": int(number)}


class GitHub:
    def __init__(self, deadline, api_timeout, clock=time.monotonic):
        self.deadline = deadline
        self.api_timeout = api_timeout
        self.clock = clock

    def remaining(self):
        remaining = self.deadline - self.clock()
        if remaining <= 0:
            raise Failure("timeout", "전체 대기 시간이 끝났습니다.")
        return remaining

    @staticmethod
    def stop(process):
        # gh가 자식 프로세스를 만들더라도 이 호출이 만든 프로세스 그룹만 종료한다.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.communicate()

    def get(self, endpoint, *, pages=False, key=None):
        remaining = self.remaining()
        command = ["gh", "api", "--hostname", "github.com", "--method", "GET",
                   "-H", "Accept: application/vnd.github+json", endpoint]
        if pages:
            command += ["--paginate", "--slurp"]
        process = None
        try:
            process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                       text=True, start_new_session=True)
            stdout, stderr = process.communicate(timeout=min(self.api_timeout, remaining))
        except subprocess.TimeoutExpired:
            self.stop(process)
            self.remaining()
            raise Failure("transport-error", "GitHub API 호출 제한 시간을 초과했습니다.", transient=True) from None
        except (KeyboardInterrupt, Cancelled):
            if process is not None:
                self.stop(process)
            raise
        except OSError:
            raise Failure("transport-error", "gh 실행 파일을 시작할 수 없습니다.") from None
        self.remaining()
        if process.returncode:
            # stderr는 토큰 등 민감한 정보를 포함할 수 있어 출력하지 않는다.
            match = re.search(r"\bHTTP\s+(\d{3})\b", stderr)
            status = int(match.group(1)) if match else None
            if status == 429 or (status == 403 and "rate limit" in stderr.lower()):
                # 응답 헤더의 재시도 시각을 모르는 상태에서는 추가 요청을 보내지 않는다.
                raise Failure("rate-limited", "GitHub API 요청 한도에 도달했습니다. 제한 해제 후 다시 시도하세요.",
                              status=status)
            if status in (401, 403) or "gh auth login" in stderr or "GH_TOKEN" in stderr:
                raise Failure("auth-error", "GitHub 인증 또는 접근 권한을 확인하세요.", status=status)
            raise Failure("transport-error", "GitHub API 요청에 실패했습니다.",
                          transient=status is None or status >= 500, status=status)
        try:
            value = json.loads(stdout)
        except ValueError:
            raise Failure("transport-error", "GitHub API가 올바른 JSON을 반환하지 않았습니다.") from None
        if not pages:
            if not isinstance(value, dict):
                raise Failure("transport-error", "GitHub API 객체 응답이 필요합니다.")
            return value
        if not isinstance(value, list):
            raise Failure("transport-error", "GitHub API 페이지 목록 응답이 필요합니다.")
        result = []
        totals = set()
        for page in value:
            rows = page.get(key) if key and isinstance(page, dict) else page
            if not isinstance(rows, list) or not all(isinstance(row, dict) for row in rows):
                raise Failure("transport-error", "GitHub API 페이지 형식을 해석할 수 없습니다.")
            result.extend(rows)
            if key == "workflow_runs":
                total = page.get("total_count")
                if type(total) is not int or total < 0:
                    raise Failure("unknown-policy", "워크플로 실행 목록의 전체 개수를 확인할 수 없습니다.")
                totals.add(total)
        if key == "workflow_runs" and totals != {len(result)}:
            raise Failure("unknown-policy", "워크플로 실행 목록이 불완전하거나 조회 중 변경되었습니다.")
        return result


def policy(api, root, pr):
    branch = quote(pr["base"]["ref"], safe="")
    metadata = api.get(f"{root}/branches/{branch}")
    try:
        classic = api.get(f"{root}/branches/{branch}/protection")
    except Failure as error:
        known_absent = metadata.get("protected") is False or metadata.get("protection", {}).get("enabled") is False
        if error.status != 404:
            raise
        if not known_absent:
            raise Failure("unknown-policy", "클래식 브랜치 보호 정책의 부재와 접근 권한 부족을 구별할 수 없습니다.") from None
        classic = {}
    rules = api.get(f"{root}/rules/branches/{branch}?per_page=100", pages=True)
    required = set()
    strict = False

    def add(context, app):
        if not isinstance(context, str) or not context or (app is not None and (type(app) is not int or app < -1)):
            raise Failure("unknown-policy", "필수 검사 식별자를 해석할 수 없습니다.")
        required.add((context, None if app in (None, -1) else app))

    checks = classic.get("required_status_checks")
    if checks is not None:
        if (not isinstance(checks, dict)
                or not isinstance(checks.get("contexts"), list)
                or not isinstance(checks.get("checks"), list)
                or type(checks.get("strict", False)) is not bool):
            raise Failure("unknown-policy", "클래식 필수 검사 정책 형식이 올바르지 않습니다.")
        strict = checks.get("strict", False)
        explicit = checks["checks"]
        for check in explicit:
            if not isinstance(check, dict) or "app_id" not in check:
                raise Failure("unknown-policy", "클래식 필수 검사의 앱 제한을 확인할 수 없습니다.")
            add(check.get("context"), check["app_id"])
        named = {check.get("context") for check in explicit}
        for context in checks["contexts"]:
            if context not in named:
                add(context, None)
    for rule in rules:
        kind = rule.get("type")
        if not isinstance(kind, str) or not kind:
            raise Failure("unknown-policy", "브랜치 규칙 종류를 확인할 수 없습니다.")
        if kind in ("workflows", "required_workflows"):
            raise Failure("unknown-policy", "필수 워크플로 정책은 지원하지 않습니다. GitHub에서 직접 확인하세요.")
        if kind == "required_status_checks":
            parameters = rule.get("parameters")
            if (not isinstance(parameters, dict)
                    or not isinstance(parameters.get("required_status_checks"), list)
                    or type(parameters.get("strict_required_status_checks_policy")) is not bool):
                raise Failure("unknown-policy", "규칙 집합의 필수 검사 정책을 해석할 수 없습니다.")
            strict = strict or parameters["strict_required_status_checks_policy"]
            for check in parameters["required_status_checks"]:
                add(check.get("context"), check.get("integration_id"))
    return {"required": [{"context": context, "appId": app}
                          for context, app in sorted(required, key=lambda x: (x[0], x[1] or -1))],
            "strict": bool(strict), "classic": classic, "rules": rules}


def latest(rows, identity):
    result = {}
    for row in rows:
        key = identity(row)
        # 증가하는 ID로 재실행을 구별한다. 아직 시작하지 않은 새 실행도 이전 성공보다 우선한다.
        rank = (row.get("id", 0), row.get("created_at") or row.get("started_at") or "")
        previous = result.get(key)
        if previous is None or rank > previous[0]:
            result[key] = (rank, row)
    return [entry[1] for entry in result.values()]


def eligible_checks(api, root, checks):
    events = {}
    eligible = []
    for check in checks:
        if (check.get("app") or {}).get("id") != GITHUB_ACTIONS_APP_ID:
            eligible.append(check)
            continue
        suite = (check.get("check_suite") or {}).get("id")
        if type(suite) is not int or suite <= 0:
            raise Failure("unknown-policy", "Actions 검사의 check suite를 확인할 수 없습니다.")
        if suite not in events:
            runs = api.get(f"{root}/actions/runs?check_suite_id={suite}&per_page=100",
                           pages=True, key="workflow_runs")
            if not runs or any(
                    type(run.get("check_suite_id")) is not int or run["check_suite_id"] != suite
                    or not isinstance(run.get("event"), str) or not run["event"]
                    for run in runs):
                raise Failure("unknown-policy", "Actions 검사의 실행 이벤트를 확인할 수 없습니다.")
            suite_events = {run["event"] for run in runs}
            if len(suite_events) != 1:
                raise Failure("unknown-policy", "동일 check suite의 실행 이벤트가 일치하지 않습니다.")
            events[suite] = suite_events.pop()
        if events[suite] in PR_ACTION_EVENTS:
            eligible.append(check)
    return eligible


def commit_observation(api, root, sha):
    ref = quote(sha, safe="")
    checks = api.get(f"{root}/commits/{ref}/check-runs?per_page=100&filter=all", pages=True, key="check_runs")
    statuses = api.get(f"{root}/commits/{ref}/statuses?per_page=100", pages=True)
    return {"sha": sha, "checks": latest(eligible_checks(api, root, checks),
                                        lambda row: (row.get("name"), (row.get("app") or {}).get("id"))),
            "statuses": latest(statuses, lambda row: row["context"].lower())}


def evaluate_checks(required, observed):
    missing, failed = [], []
    for requirement in required:
        context, app = requirement["context"], requirement["appId"]
        checks = [row for row in observed["checks"] if row.get("name") == context
                  and (app is None or (row.get("app") or {}).get("id") == app)]
        statuses = [row for row in observed["statuses"] if row["context"].lower() == context.lower()]
        label = {"context": context, "appId": app}
        if not checks and (not statuses or app is not None):
            missing.append({**label, "condition": "missing"})
        # 같은 이름의 check와 status는 모두 통과해야 한다. 고정 app의 대리로 status를 사용하지 않는다.
        for check in checks:
            if check.get("status") != "completed":
                missing.append({**label, "condition": "check-pending", "id": check.get("id")})
            elif check.get("conclusion") not in ("success", "neutral", "skipped"):
                failed.append({**label, "condition": "check-failed", "id": check.get("id"), "conclusion": check.get("conclusion")})
        for status in statuses:
            if status.get("state") == "pending":
                missing.append({**label, "condition": "status-pending", "id": status.get("id")})
            elif status.get("state") != "success":
                failed.append({**label, "condition": "status-failed", "id": status.get("id"), "state": status.get("state")})
    return missing, failed


def validate_baseline(args, selected):
    try:
        baseline = json.loads(Path(args.baseline).read_text())
    except (OSError, ValueError):
        raise Failure("invalid-input", "리뷰 기준 스냅샷 JSON을 읽을 수 없습니다.") from None
    requested = timestamp(args.requested_after)
    if not isinstance(baseline, dict):
        raise Failure("invalid-input", "리뷰 기준 스냅샷은 JSON 객체여야 합니다.")
    if (baseline.get("url", "").lower() != selected["url"].lower()
            or baseline.get("repo", "").lower() != selected["repo"].lower()
            or baseline.get("pr") != selected["pr"]
            or baseline.get("head") != args.expected_head
            or baseline.get("reviewer", "").lower() != args.reviewer.lower()
            or baseline.get("until") != "review-response"
            or baseline.get("outcome") not in ("pending", "success")):
        raise Failure("invalid-input", "기준 스냅샷의 PR, head 또는 리뷰어가 일치하지 않습니다.")
    if timestamp(baseline.get("capturedAt")) > requested:
        raise Failure("invalid-input", "기준 스냅샷은 리뷰 요청보다 먼저 수집해야 합니다.")
    ids = baseline.get("reviewIds")
    if not isinstance(ids, list) or not all(type(value) is int for value in ids):
        raise Failure("invalid-input", "기준 스냅샷에 전체 리뷰 ID 목록이 필요합니다.")
    reviews = baseline.get("reviews")
    if (not isinstance(reviews, list)
            or not all(isinstance(row, dict) and type(row.get("id")) is int for row in reviews)
            or {row["id"] for row in reviews} != set(ids)):
        raise Failure("invalid-input", "기준 스냅샷에 전체 리뷰 상태가 필요합니다.")
    # 작성 중인 리뷰는 같은 ID로 제출된다. 이미 제출된 응답만 제외한다.
    drafts = {row["id"] for row in reviews
              if row.get("state") == "PENDING" and not row.get("submitted_at")}
    args.baseline_ids = set(ids) - drafts
    args.requested_time = requested


def envelope(selected, args, pr):
    merged = pr.get("merged") is True
    return {**selected, "until": args.until, "head": pr["head"]["sha"],
            "base": pr["base"]["ref"], "baseSha": pr["base"].get("sha"),
            "merged": merged, "mergeSha": pr.get("merge_commit_sha") if merged else None,
            "capturedAt": now(), "outcome": "pending", "reason": "조건을 기다리고 있습니다.",
            "evidence": {"missing": []}}


def lifecycle(result, pr, args):
    if args.command == "wait" and pr["head"]["sha"] != args.expected_head:
        result.update(outcome="invalidated", reason="PR head가 변경되었습니다.")
    elif pr.get("merged"):
        result.update(outcome="success" if args.until == "merged" else "invalidated",
                      reason="PR이 머지되었습니다.")
    elif pr.get("state") == "closed":
        result.update(outcome="closed", reason="PR이 머지되지 않고 닫혔습니다.")
    else:
        return False
    return True


def observe(api, selected, args):
    root = f"repos/{selected['repo']}"
    endpoint = f"{root}/pulls/{selected['pr']}"
    pr = api.get(endpoint)
    result = envelope(selected, args, pr)
    terminal = lifecycle(result, pr, args)
    if terminal and not (args.command == "snapshot" and args.until == "review-response"):
        return result
    if args.until == "review-response":
        reviews = api.get(f"{endpoint}/reviews?per_page=100", pages=True)
        result.update(reviewer=args.reviewer, reviews=reviews, reviewIds=[row["id"] for row in reviews])
        if terminal:
            result["capturedAt"] = now()
            return result
        result["evidence"]["missing"] = ["review-response"]
        if args.command == "wait":
            matching = [row for row in reviews
                        if row["id"] not in args.baseline_ids
                        and (row.get("user") or {}).get("login", "").lower() == args.reviewer.lower()
                        and row.get("state") in ("COMMENTED", "CHANGES_REQUESTED", "APPROVED")
                        and row.get("commit_id") == args.expected_head
                        and row.get("submitted_at")
                        and timestamp(row["submitted_at"]) > args.requested_time]
            if matching:
                result.update(outcome="success", reason="요청 이후 제출된 리뷰 응답을 확인했습니다.")
                result["evidence"]["reviews"] = matching
                result["evidence"]["missing"] = []
    elif args.until == "required-checks":
        requirements = policy(api, root, pr)
        result["evidence"]["policy"] = requirements
        head = pr["head"]["sha"]
        merge = pr.get("merge_commit_sha")
        observed = None
        if merge and merge != head:
            try:
                merge_commit = api.get(f"{root}/commits/{quote(merge, safe='')}")
            except Failure as error:
                if error.status != 404:
                    raise
            else:
                parents = {parent["sha"] for parent in merge_commit["parents"]}
                # mergeable 재계산 중 남아 있는 이전 test merge의 성공을 재사용하지 않는다.
                if {head, pr["base"]["sha"]}.issubset(parents):
                    observed = commit_observation(api, root, merge)
                else:
                    result["evidence"]["ignoredTestMerge"] = {"sha": merge, "reason": "parents-do-not-match"}
            if observed is not None and not observed["checks"] and not observed["statuses"]:
                observed = None
        if observed is None:
            observed = commit_observation(api, root, head)
        missing, failed = evaluate_checks(requirements["required"], observed)
        if requirements["strict"] and requirements["required"]:
            comparison = api.get(f"{root}/compare/{quote(pr['base']['sha'], safe='')}...{quote(head, safe='')}")
            if type(comparison.get("behind_by")) is not int:
                raise Failure("unknown-policy", "베이스 브랜치와의 최신 상태를 확인할 수 없습니다.")
            if comparison["behind_by"] > 0:
                missing.append({"condition": "head-behind-base", "commits": comparison["behind_by"]})
        result["evidence"].update(observation=observed, missing=missing, failed=failed)
        if failed:
            result.update(outcome="checks-failed", reason="필수 검사 실패를 확인했습니다.")
        elif not missing:
            result.update(outcome="success", reason="확인 가능한 모든 필수 검사가 통과했습니다.")
    else:
        result["evidence"]["missing"] = ["merged"]
    # 수집 도중 push/닫힘/머지가 발생하면 이전 관찰로 성공을 반환하지 않는다.
    final_pr = api.get(endpoint)
    final = envelope(selected, args, final_pr)
    if lifecycle(final, final_pr, args):
        final["evidence"]["lastObservation"] = result
        return final
    if final_pr["head"]["sha"] != pr["head"]["sha"]:
        final.update(outcome="invalidated", reason="관찰 중 PR head가 변경되었습니다.")
        final["evidence"]["lastObservation"] = result
        return final
    # CI 정책/검사 기준 base 또는 임시 merge commit이 바뀐 경우도 재관찰한다.
    if args.until == "required-checks" and (final_pr["base"]["ref"] != pr["base"]["ref"]
                                             or final_pr["base"]["sha"] != pr["base"]["sha"]
                                             or final_pr.get("merge_commit_sha") != pr.get("merge_commit_sha")):
        result.update(outcome="pending", reason="관찰 중 CI 기준이 변경되어 재확인이 필요합니다.")
        result["evidence"]["missing"] = ["stable-ci-target"]
    result["capturedAt"] = now()
    return result


def parser():
    result = argparse.ArgumentParser(description="읽기 전용 GitHub PR 대기. 성공은 머지 승인이 아닙니다.")
    commands = result.add_subparsers(dest="command", required=True)
    for name in ("snapshot", "wait"):
        command = commands.add_parser(name)
        command.add_argument("pr_url")
        command.add_argument("--until", required=True, choices=("review-response", "required-checks", "merged"))
        command.add_argument("--reviewer")
        command.add_argument("--api-timeout", type=positive, default=30.0)
        command.add_argument("--timeout", type=positive, default=120.0 if name == "snapshot" else None,
                             required=name == "wait")
        command.add_argument("--interval", type=positive, default=15.0)
        if name == "wait":
            command.add_argument("--expected-head", required=True)
            command.add_argument("--baseline")
            command.add_argument("--requested-after")
    return result


def run(args, *, clock=time.monotonic, sleep=time.sleep, api_factory=GitHub):
    selected = target(args.pr_url)
    if args.until == "review-response" and not args.reviewer:
        raise Failure("invalid-input", "리뷰 대기와 스냅샷에는 --reviewer가 필요합니다.")
    if args.command == "wait" and args.until == "review-response":
        if not args.baseline or not args.requested_after:
            raise Failure("invalid-input", "리뷰 대기에는 --baseline과 --requested-after가 필요합니다.")
        validate_baseline(args, selected)
    deadline = clock() + args.timeout
    api = api_factory(deadline, args.api_timeout, clock=clock)
    last = None
    failures = 0

    def cancelled():
        return {**selected, "until": args.until, "outcome": "cancelled", "reason": "사용자가 대기를 취소했습니다.",
                "evidence": {"lastObservation": last, "missing": (last or {}).get("evidence", {}).get("missing", [])}}, 130

    while True:
        try:
            api.remaining()
            observation = observe(api, selected, args)
            api.remaining()
            last = observation
            failures = 0
            if args.command == "snapshot" or observation["outcome"] != "pending":
                return observation, 0 if args.command == "snapshot" or observation["outcome"] == "success" else 1
        except Failure as error:
            failures += 1
            if args.command == "snapshot" or not error.transient or failures >= 3:
                return {**selected, "until": args.until, "outcome": error.outcome, "reason": error.reason,
                        "evidence": {"lastObservation": last, "missing": (last or {}).get("evidence", {}).get("missing", []),
                                     "consecutiveErrors": failures}}, 1
        except (Cancelled, KeyboardInterrupt):
            return cancelled()
        except (KeyError, TypeError, AttributeError, ValueError):
            return {**selected, "until": args.until, "outcome": "transport-error", "reason": "GitHub 응답 형식을 해석할 수 없습니다.",
                    "evidence": {"lastObservation": last, "missing": (last or {}).get("evidence", {}).get("missing", [])}}, 1
        remaining = deadline - clock()
        if remaining <= 0:
            return {**selected, "until": args.until, "outcome": "timeout", "reason": "전체 대기 시간이 끝났습니다.",
                    "evidence": {"lastObservation": last, "missing": (last or {}).get("evidence", {}).get("missing", [])}}, 1
        try:
            sleep(min(args.interval, remaining))
        except (Cancelled, KeyboardInterrupt):
            return cancelled()


def main(argv=None):
    args = parser().parse_args(argv)
    previous = signal.getsignal(signal.SIGTERM)

    def cancel(_signum, _frame):
        raise Cancelled()

    signal.signal(signal.SIGTERM, cancel)
    try:
        result, code = run(args)
    except Failure as error:
        result, code = {"outcome": error.outcome, "reason": error.reason, "evidence": {}}, 1
    except (Cancelled, KeyboardInterrupt):
        result, code = {"outcome": "cancelled", "reason": "사용자가 대기를 취소했습니다.", "evidence": {}}, 130
    except (KeyError, TypeError, AttributeError, ValueError):
        result, code = {"outcome": "transport-error", "reason": "GitHub 응답 또는 기준 스냅샷 형식을 해석할 수 없습니다.", "evidence": {}}, 1
    finally:
        signal.signal(signal.SIGTERM, previous)
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
    return code


if __name__ == "__main__":
    sys.exit(main())
