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


# GitHub가 PR별로 계산한 필수 여부(isRequired)와 상태로 판정한다. 앱 고정, check run과 commit status,
# 재실행 대체를 직접 해석하면 GitHub의 머지 판단과 어긋나 끝나지 않는 대기를 만든다.
# check suite와 시각은 GitHub에서 아직 진행 중인 일이 남았는지 판단하는 데만 쓴다.
ROLLUP_QUERY = """
query($owner: String!, $name: String!, $sha: GitObjectID!, $pr: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    object(oid: $sha) {
      ... on Commit {
        checkSuites(first: 100) {
          pageInfo { hasNextPage }
          nodes { status conclusion updatedAt app { databaseId } }
        }
        statusCheckRollup {
          contexts(first: 100, after: $after) {
            pageInfo { hasNextPage endCursor }
            nodes {
              __typename
              ... on CheckRun {
                databaseId name status conclusion startedAt completedAt isRequired(pullRequestNumber: $pr)
              }
              ... on StatusContext { context state createdAt isRequired(pullRequestNumber: $pr) }
            }
          }
        }
      }
    }
  }
}
"""
GITHUB_ACTIONS_APP_ID = 15368
# 진행 중인 일이 없는 상태가 이 시간 동안 이어지면 GitHub에서 더 보고될 검사가 없다고 본다.
DEFAULT_SETTLE_SECONDS = 120.0


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


def utcnow():
    return dt.datetime.now(dt.timezone.utc)


def now():
    return utcnow().isoformat().replace("+00:00", "Z")


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

    def run(self, command):
        remaining = self.remaining()
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
            return json.loads(stdout)
        except ValueError:
            raise Failure("transport-error", "GitHub API가 올바른 JSON을 반환하지 않았습니다.") from None

    def get(self, endpoint, *, pages=False):
        command = ["gh", "api", "--hostname", "github.com", "--method", "GET",
                   "-H", "Accept: application/vnd.github+json", endpoint]
        if pages:
            command += ["--paginate", "--slurp"]
        value = self.run(command)
        if not pages:
            if not isinstance(value, dict):
                raise Failure("transport-error", "GitHub API 객체 응답이 필요합니다.")
            return value
        if not isinstance(value, list):
            raise Failure("transport-error", "GitHub API 페이지 목록 응답이 필요합니다.")
        result = []
        for page in value:
            if not isinstance(page, list) or not all(isinstance(row, dict) for row in page):
                raise Failure("transport-error", "GitHub API 페이지 형식을 해석할 수 없습니다.")
            result.extend(page)
        return result

    def graphql(self, query, variables):
        command = ["gh", "api", "graphql", "--hostname", "github.com", "-f", f"query={query}"]
        for key, value in variables.items():
            # 정수는 -F로 타입을 유지하고 문자열은 -f로 그대로 전달한다.
            command += ["-F" if type(value) is int else "-f", f"{key}={value}"]
        value = self.run(command)
        if not isinstance(value, dict) or value.get("errors") or not isinstance(value.get("data"), dict):
            raise Failure("transport-error", "GitHub GraphQL 응답을 해석할 수 없습니다.")
        return value["data"]


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


def commit_observation(api, selected, sha):
    owner, name = selected["repo"].split("/")
    contexts = []
    # 조회하지 못한 suite가 있으면 진행 여부를 모르는 것이므로 정체로 판단하지 않는다.
    suites = None
    after = None
    while True:
        variables = {"owner": owner, "name": name, "sha": sha, "pr": selected["pr"]}
        if after is not None:
            variables["after"] = after
        commit = (api.graphql(ROLLUP_QUERY, variables).get("repository") or {}).get("object")
        if not isinstance(commit, dict):
            raise Failure("transport-error", "PR head 커밋을 조회할 수 없습니다.")
        if after is None:
            suites = check_suites(commit.get("checkSuites"))
        rollup = commit.get("statusCheckRollup")
        if rollup is None:
            if after is not None:
                raise Failure("transport-error", "검사 목록이 조회 도중 사라졌습니다.")
            break
        page = rollup["contexts"]
        for node in page["nodes"]:
            if type(node.get("isRequired")) is not bool:
                raise Failure("unknown-policy", "GitHub가 계산한 필수 여부를 확인할 수 없습니다.")
            if node.get("__typename") == "CheckRun":
                contexts.append({"kind": "check", "name": node["name"], "id": node.get("databaseId"),
                                 "status": node["status"], "conclusion": node.get("conclusion"),
                                 "required": node["isRequired"],
                                 "activityAt": node.get("completedAt") or node.get("startedAt")})
            elif node.get("__typename") == "StatusContext":
                contexts.append({"kind": "status", "name": node["context"], "state": node["state"],
                                 "required": node["isRequired"], "activityAt": node.get("createdAt")})
            else:
                raise Failure("unknown-policy", "알 수 없는 검사 종류입니다.")
        if not page["pageInfo"]["hasNextPage"]:
            break
        after = page["pageInfo"]["endCursor"]
        if not isinstance(after, str) or not after:
            raise Failure("transport-error", "검사 목록의 다음 페이지를 확인할 수 없습니다.")
    return {"sha": sha, "contexts": contexts, "suites": suites}


def check_suites(connection):
    if not isinstance(connection, dict) or not isinstance(connection.get("nodes"), list):
        return None
    if (connection.get("pageInfo") or {}).get("hasNextPage") is not False:
        return None
    suites = []
    for node in connection["nodes"]:
        if not isinstance(node, dict) or not isinstance(node.get("status"), str):
            return None
        suites.append({"appId": (node.get("app") or {}).get("databaseId"), "status": node["status"],
                       "conclusion": node.get("conclusion"), "activityAt": node.get("updatedAt")})
    return suites


def activity_time(value):
    try:
        return timestamp(value) if isinstance(value, str) else None
    except Failure:
        return None


def progress(missing, observed, pr):
    """필수 조건이 남았을 때 GitHub 쪽에서 아직 진행 중인 일과 사람 조치가 필요한 이유를 모은다."""
    pinned = {row.get("appId") for row in missing if row.get("appId") is not None}
    in_flight, blockers = [], []
    for row in observed["contexts"]:
        if row["kind"] == "check" and row["status"] == "WAITING":
            blockers.append({"condition": "deployment-approval-required", "context": row["name"]})
        elif row["kind"] == "check" and row["status"] != "COMPLETED":
            in_flight.append({"context": row["name"], "kind": "check", "status": row["status"]})
        elif row["kind"] == "status" and row["state"] == "PENDING":
            in_flight.append({"context": row["name"], "kind": "status", "state": row["state"]})
    suites = observed.get("suites")
    if suites is None:
        in_flight.append({"condition": "check-suites-unobserved"})
    for suite in suites or []:
        if suite["conclusion"] == "ACTION_REQUIRED":
            blockers.append({"condition": "workflow-approval-required", "appId": suite["appId"]})
        elif suite["status"] == "WAITING":
            blockers.append({"condition": "deployment-approval-required", "appId": suite["appId"]})
        # 설치만 되고 쓰이지 않는 앱의 suite는 영원히 QUEUED로 남으므로 Actions와
        # 미충족 필수 검사를 맡은 앱의 suite만 진행 중으로 본다.
        elif suite["status"] != "COMPLETED" and (suite["appId"] == GITHUB_ACTIONS_APP_ID or suite["appId"] in pinned):
            in_flight.append({"kind": "suite", "appId": suite["appId"], "status": suite["status"]})
    # 충돌이 있으면 pull_request workflow가 시작되지 않는다.
    if pr.get("mergeable") is False:
        blockers.append({"condition": "merge-conflict"})
    times = [activity_time(row.get("activityAt")) for row in observed["contexts"] + (suites or [])]
    times = [value for value in times if value is not None]
    last = max(times).isoformat().replace("+00:00", "Z") if times else None
    return {"inFlight": in_flight, "blockers": blockers, "lastActivityAt": last}


def same_context(row, context):
    # commit status context는 대소문자를 구별하지 않고, check run 이름은 구별한다.
    return row["name"].lower() == context.lower() if row["kind"] == "status" else row["name"] == context


def evaluate_checks(required, observed):
    missing, failed = [], []
    gated = [row for row in observed["contexts"] if row["required"]]
    # 정책에 있지만 GitHub가 필수로 인정한 결과가 아직 없으면 보고되지 않은 검사다.
    # 다른 앱이 보낸 같은 이름의 결과는 isRequired가 거짓이라 대신하지 못한다.
    for requirement in required:
        if not any(same_context(row, requirement["context"]) for row in gated):
            missing.append({"context": requirement["context"], "appId": requirement["appId"], "condition": "missing"})
    for row in gated:
        label = {"context": row["name"], "kind": row["kind"]}
        if row["kind"] == "check":
            label["id"] = row["id"]
            if row["status"] != "COMPLETED":
                missing.append({**label, "condition": "check-pending"})
            elif row["conclusion"] not in ("SUCCESS", "NEUTRAL", "SKIPPED"):
                failed.append({**label, "condition": "check-failed", "conclusion": row["conclusion"]})
        elif row["state"] in ("PENDING", "EXPECTED"):
            missing.append({**label, "condition": "status-pending"})
        elif row["state"] != "SUCCESS":
            failed.append({**label, "condition": "status-failed", "state": row["state"]})
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
            or baseline.get("reviewer", "").lower() != args.reviewer.lower()
            or baseline.get("until") != "after-request"
            or baseline.get("outcome") not in ("pending", "success")):
        raise Failure("invalid-input", "기준 스냅샷의 PR 또는 리뷰어가 일치하지 않습니다.")
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
    if terminal and not (args.command == "snapshot" and args.until in ("current-response", "after-request")):
        return result
    if args.until in ("current-response", "after-request"):
        reviews = api.get(f"{endpoint}/reviews?per_page=100", pages=True)
        result.update(reviewer=args.reviewer, reviews=reviews, reviewIds=[row["id"] for row in reviews])
        if terminal:
            result["capturedAt"] = now()
            return result
        result["evidence"]["missing"] = [args.until]
        if args.command == "wait":
            candidates = [(timestamp(row["submitted_at"]), row) for row in reviews
                          if (args.until == "current-response" or row["id"] not in args.baseline_ids)
                          and (row.get("user") or {}).get("login", "").lower() == args.reviewer.lower()
                          and row.get("state") in ("COMMENTED", "CHANGES_REQUESTED", "APPROVED")
                          and row.get("commit_id") == args.expected_head
                          and row.get("submitted_at")]
            ambiguous = []
            if args.until == "after-request":
                matching = [(submitted, row) for submitted, row in candidates
                            if submitted > args.requested_time]
                ambiguous = [row for submitted, row in candidates
                             if submitted == args.requested_time.replace(microsecond=0)]
            else:
                matching = candidates
            if matching:
                latest_review = max(matching, key=lambda item: (item[0], item[1]["id"]))[1]
                result.update(outcome="success", reason=(
                    "요청 이후 제출된 리뷰 응답을 확인했습니다." if args.until == "after-request"
                    else "현재 head에 제출된 리뷰 응답을 확인했습니다."))
                result["evidence"]["reviews"] = [latest_review]
                result["evidence"]["missing"] = []
            elif ambiguous:
                result.update(outcome="order-unproven", reason="리뷰 제출과 요청의 같은 초 내 순서를 확인할 수 없습니다.")
                result["evidence"]["reviews"] = ambiguous
                result["evidence"]["missing"] = ["review-order"]
    elif args.until == "required-checks":
        requirements = policy(api, root, pr)
        result["evidence"]["policy"] = requirements
        head = pr["head"]["sha"]
        observed = commit_observation(api, selected, head)
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
        elif any(row["condition"] == "head-behind-base" for row in missing):
            result.update(outcome="needs-action", reason="필수 검사 정책을 만족하려면 head를 최신 base에 반영해야 합니다.")
        elif not missing:
            result.update(outcome="success", reason="확인 가능한 모든 필수 검사가 통과했습니다.")
        else:
            # GitHub에서 더 진행될 일이 없는데 필수 검사가 남았으면 기다려도 끝나지 않는다.
            # push 직후에는 검사가 아직 등록되지 않았을 수 있어 조용한 시간이 settle 이상일 때만 판단한다.
            activity = progress(missing, observed, pr)
            result["evidence"]["activity"] = activity
            if not activity["inFlight"]:
                last = activity["lastActivityAt"]
                if last and (utcnow() - timestamp(last)).total_seconds() >= args.settle:
                    stalled(result)
                else:
                    activity["idle"] = True
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
    # 필수 검사 정책과 strict 비교 기준인 base가 바뀌면 재관찰한다.
    if args.until == "required-checks" and (final_pr["base"]["ref"] != pr["base"]["ref"]
                                             or final_pr["base"]["sha"] != pr["base"]["sha"]):
        result.update(outcome="pending", reason="관찰 중 CI 기준이 변경되어 재확인이 필요합니다.")
        result["evidence"]["missing"] = ["stable-ci-target"]
        result["evidence"].pop("activity", None)
    result["capturedAt"] = now()
    return result


def stalled(result):
    blockers = result["evidence"]["activity"]["blockers"]
    result.update(outcome="needs-action", reason=(
        "진행 중인 검사가 없고 필수 검사를 진행하려면 조치가 필요합니다." if blockers
        else "진행 중인 검사가 없어 남은 필수 검사가 보고되지 않습니다."))
    if not blockers:
        blockers.append({"condition": "checks-stalled"})


def parser():
    result = argparse.ArgumentParser(description="읽기 전용 GitHub PR 대기. 성공은 머지 승인이 아닙니다.")
    commands = result.add_subparsers(dest="command", required=True)
    for name in ("snapshot", "wait"):
        command = commands.add_parser(name)
        command.add_argument("pr_url")
        command.add_argument("--until", required=True,
                             choices=("current-response", "after-request", "required-checks", "merged"))
        command.add_argument("--reviewer")
        command.add_argument("--api-timeout", type=positive, default=30.0)
        command.add_argument("--timeout", type=positive, default=120.0 if name == "snapshot" else None,
                             required=name == "wait")
        command.add_argument("--interval", type=positive, default=15.0)
        command.add_argument("--settle", type=positive, default=DEFAULT_SETTLE_SECONDS,
                             help="필수 검사가 남았는데 진행 중인 검사가 없는 상태를 이 초만큼 보면 needs-action으로 끝냅니다.")
        if name == "wait":
            command.add_argument("--expected-head", required=True)
            command.add_argument("--baseline")
            command.add_argument("--requested-after")
    return result


def run(args, *, clock=time.monotonic, sleep=time.sleep, api_factory=GitHub):
    selected = target(args.pr_url)
    if args.until in ("current-response", "after-request") and not args.reviewer:
        raise Failure("invalid-input", "리뷰 대기와 스냅샷에는 --reviewer가 필요합니다.")
    if args.command == "wait" and args.until == "current-response" and (args.baseline or args.requested_after):
        raise Failure("invalid-input", "현재 응답 관찰에는 --baseline 또는 --requested-after를 사용할 수 없습니다.")
    if args.command == "wait" and args.until == "after-request":
        if not args.baseline or not args.requested_after:
            raise Failure("invalid-input", "요청 이후 리뷰 대기에는 --baseline과 --requested-after가 필요합니다.")
        validate_baseline(args, selected)
    deadline = clock() + args.timeout
    api = api_factory(deadline, args.api_timeout, clock=clock)
    last = None
    failures = 0
    # GitHub 시각이 없을 때(push 직후 아무 결과도 없음) 쓰는 대기 내부의 조용한 시간 기준.
    idle_since = idle_key = None

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
            activity = observation.get("evidence", {}).get("activity") or {}
            if observation["outcome"] == "pending" and activity.get("idle"):
                if idle_since is None or idle_key != activity.get("lastActivityAt"):
                    idle_since, idle_key = clock(), activity.get("lastActivityAt")
                elif clock() - idle_since >= args.settle:
                    stalled(observation)
            else:
                idle_since = idle_key = None
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
