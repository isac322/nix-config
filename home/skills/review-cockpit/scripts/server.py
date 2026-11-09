#!/usr/bin/env python3
"""Private, evidence-first review cockpit with durable owner decisions."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from contextlib import suppress
from datetime import UTC, datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlsplit

MAX_BODY_BYTES = 16 * 1024
MAX_TEXT_CHARS = 4_000
MAX_BODY_CHARS = 1_200
ACTIONS = {"approve", "defer", "request_changes", "add_info"}
AREA_LABELS_DEFAULT = {
    "core": "핵심 기능",
    "api": "API",
    "ui": "사용자 화면",
    "cli": "명령줄",
    "docs": "문서",
    "test": "테스트",
    "build": "빌드",
    "ci": "지속적 통합",
    "deps": "의존성",
    "security": "보안",
    "general": "일반",
    "orchestration": "오케스트레이션",
    "session": "세션",
    "capture": "화면 캡처",
    "protocol": "프로토콜",
    "accessibility": "접근성",
    "input": "입력",
    "process": "프로세스",
    "packaging": "패키징",
}
ACTION_LABELS = {
    "approve": "승인",
    "defer": "보류",
    "request_changes": "변경 요청",
    "add_info": "정보 제공",
}
HARNESS_ALIASES = {
    "claude": "claude-code",
    "claude-code": "claude-code",
    "claude_code": "claude-code",
    "claudecode": "claude-code",
    "codex": "codex",
    "openai-codex": "codex",
    "omp": "omp",
    "oh-my-pi": "omp",
    "omo": "omo",
    "oh-my-opencode": "omo",
    "oh_my_opencode": "omo",
    "opencode": "opencode",
    "aider": "aider",
    "cursor": "cursor",
    "cursor-agent": "cursor",
    "goose": "goose",
    "unknown": "unknown",
}
HARNESS_LABELS = {
    "claude-code": "Claude Code",
    "codex": "Codex",
    "omp": "OMP",
    "omo": "OMO",
    "opencode": "OpenCode",
    "aider": "Aider",
    "cursor": "Cursor",
    "goose": "Goose",
    "unknown": "하네스 미특정",
}
HARNESS_PROCESS_PATTERNS = (
    ("claude-code", re.compile(r"(?:^|/)(?:claude|claude-code)(?:\s|$)", re.I)),
    ("codex", re.compile(r"(?:^|/)(?:codex)(?:\s|$)", re.I)),
    ("omp", re.compile(r"(?:^|/)(?:omp)(?:\s|$)", re.I)),
    ("omo", re.compile(r"(?:^|/)(?:omo|oh-my-opencode)(?:\s|$)", re.I)),
    ("opencode", re.compile(r"(?:^|/)(?:opencode)(?:\s|$)", re.I)),
    ("aider", re.compile(r"(?:^|/)(?:aider)(?:\s|$)", re.I)),
    ("cursor", re.compile(r"(?:^|/)(?:cursor-agent|cursor)(?:\s|$)", re.I)),
    ("goose", re.compile(r"(?:^|/)(?:goose)(?:\s|$)", re.I)),
)


def normalize_harness(value: Any) -> str | None:
    text = str(value or "").strip().lower().replace(" ", "-")
    if not text:
        return None
    if text in HARNESS_ALIASES:
        return HARNESS_ALIASES[text]
    if re.fullmatch(r"[a-z0-9][a-z0-9_-]{1,31}", text):
        return text
    return None


def harness_label(harness_id: str) -> str:
    return HARNESS_LABELS.get(
        harness_id, harness_id.upper() if len(harness_id) <= 4 else harness_id
    )


def pid_is_alive(raw_pid: Any) -> bool:
    if isinstance(raw_pid, bool) or not isinstance(raw_pid, int) or raw_pid <= 0:
        return False
    try:
        os.kill(raw_pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False
    return True


def probe_machine_harnesses() -> list[dict[str, str]]:
    """Inspect local process table and CWDs to find running agent harnesses."""
    matched: dict[str, tuple[str, str]] = {}
    with suppress(OSError, subprocess.SubprocessError):
        ps_out = subprocess.check_output(
            ["ps", "-eo", "pid,comm,args"],
            text=True,
            errors="replace",
            timeout=2,
        )
        for line in ps_out.splitlines()[1:]:
            parts = line.strip().split(None, 2)
            if len(parts) < 3:
                continue
            pid_str, comm, args = parts
            if (
                "__omp_worker" in args
                or "codegraph-mcp" in args
                or "cockpit.py" in args
                or "server.py" in args
            ):
                continue
            for harness_id, pattern in HARNESS_PROCESS_PATTERNS:
                if pattern.search(comm) or pattern.search(args):
                    matched[pid_str] = (harness_id, args)
                    break
    if not matched:
        return []
    cwds: dict[str, str] = {}
    if sys.platform.startswith("linux") and Path("/proc").is_dir():
        for pid_str in matched:
            with suppress(OSError):
                cwds[pid_str] = os.readlink(f"/proc/{pid_str}/cwd")
    else:
        with suppress(OSError, subprocess.SubprocessError):
            lsof_out = subprocess.check_output(
                ["lsof", "-a", "-d", "cwd", "-p", ",".join(matched.keys()), "-Fn"],
                text=True,
                errors="replace",
                timeout=2,
            )
            current_pid: str | None = None
            for line in lsof_out.splitlines():
                if line.startswith("p"):
                    current_pid = line[1:].strip()
                elif line.startswith("n") and current_pid in matched:
                    cwds[current_pid] = line[1:].strip()
    return [
        {
            "pid": pid_str,
            "harness": harness_id,
            "args": args,
            "cwd": cwds.get(pid_str, ""),
        }
        for pid_str, (harness_id, args) in matched.items()
    ]


def _matches_group_target(text: str, group_id: str, item_ids: list[str]) -> bool:
    if not text:
        return False
    lowered = text.lower()
    if len(group_id) >= 4 and re.search(
        rf"(?<![a-z0-9]){re.escape(group_id.lower())}(?![a-z0-9])", lowered
    ):
        return True
    for item_id in item_ids:
        parts = str(item_id).lower().split(":", 1)
        num = parts[-1].strip()
        if not num.isdigit():
            continue
        if re.search(
            rf"(?<![a-z0-9])(?:issue[-_/\s#]*{num}|pr[-_/\s#]*{num}|pull[-_/\s#]*{num}|wt/{num}(?:[-_][a-z0-9]+)?|#{num})(?![0-9])",
            lowered,
        ):
            return True
    return False


def _infer_path_harness(path_text: str) -> str | None:
    lowered = path_text.lower()
    for marker, harness_id in (
        ("/.omp/", "omp"),
        ("/.claude/", "claude-code"),
        ("/.codex/", "codex"),
        ("/.omo/", "omo"),
        ("/.opencode/", "opencode"),
        ("/.aider", "aider"),
        ("/.cursor/", "cursor"),
    ):
        if marker in lowered:
            return harness_id
    return None


def detect_group_activity(
    *,
    group_id: str,
    group: dict[str, Any],
    owner_status: dict[str, Any],
    completed: bool,
    root: Path,
    machine_procs: list[dict[str, str]],
) -> dict[str, Any]:
    item_ids = [str(item) for item in group.get("items", []) if isinstance(item, str)]
    harnesses: list[str] = []
    sources: list[str] = []
    active = False

    def add_harness(raw_value: Any) -> None:
        if isinstance(raw_value, list):
            for entry in raw_value:
                add_harness(entry)
            return
        normalized = normalize_harness(raw_value)
        if normalized and normalized not in harnesses:
            harnesses.append(normalized)

    activity_path = root / "groups" / group_id / "activity.json"
    activity_doc = read_json(activity_path, None)
    explicit_inactive = False
    if isinstance(activity_doc, dict):
        raw_active = activity_doc.get("active")
        if raw_active is None:
            raw_active = activity_doc.get("in_progress")
        if raw_active is None and isinstance(activity_doc.get("state"), str):
            raw_active = activity_doc["state"].strip().lower() in {
                "working",
                "active",
                "running",
                "in_progress",
            }
        pid = activity_doc.get("pid")
        if pid is not None and not pid_is_alive(pid):
            raw_active = False
        if raw_active is True:
            active = True
            sources.append("workspace")
            add_harness(activity_doc.get("harness") or activity_doc.get("harnesses"))
        elif raw_active is False:
            explicit_inactive = True

    if not explicit_inactive and not completed:
        raw_state = str(owner_status.get("state", "")).strip().lower()
        status_in_progress = (
            owner_status.get("in_progress") is True
            or owner_status.get("active") is True
            or raw_state in {"running", "in_progress", "working"}
        )
        status_pid = owner_status.get("pid")
        if status_pid is not None and not pid_is_alive(status_pid):
            status_in_progress = False
        if status_in_progress:
            active = True
            if "workspace" not in sources:
                sources.append("workspace")
            add_harness(
                owner_status.get("harness")
                or owner_status.get("active_harness")
                or owner_status.get("harnesses")
            )

    group_dir = str((root / "groups" / group_id).resolve())
    for proc in machine_procs:
        combined = f"{proc.get('args', '')} {proc.get('cwd', '')}"
        if group_dir in combined or _matches_group_target(combined, group_id, item_ids):
            active = True
            if "process" not in sources:
                sources.append("process")
            add_harness(proc.get("harness"))
            inferred = _infer_path_harness(proc.get("cwd", ""))
            if inferred:
                add_harness(inferred)

    if active:
        specific = [h for h in harnesses if h != "unknown"]
        if specific:
            harnesses = specific
        elif "unknown" not in harnesses:
            harnesses.append("unknown")
    else:
        harnesses = []

    labels = [harness_label(h) for h in harnesses]
    specific_labels = [harness_label(h) for h in harnesses if h != "unknown"]
    if active:
        label = f"{', '.join(specific_labels)} 작업 중" if specific_labels else "작업 중"
        summary = (
            f"현재 {', '.join(specific_labels)} 하네스에서 이 항목을 처리 중입니다."
            if specific_labels
            else "현재 이 항목에 대한 관련 작업이 진행 중입니다."
        )
    else:
        label = "유휴"
        summary = "현재 감지된 활성 하네스 작업이 없습니다."
    return {
        "active": active,
        "state": "working" if active else "idle",
        "harnesses": harnesses,
        "harnessLabels": labels,
        "label": label,
        "sources": sources,
        "summary": summary,
    }


def area_label(area: str) -> str:
    return AREA_LABELS_DEFAULT.get(area, area.replace("-", " ").replace("_", " ").strip())


def safe_release(value: Any) -> dict[str, Any] | None:
    if not isinstance(value, dict):
        return None
    return {
        "tag": redact_text(value.get("tag", "")),
        "publishedAt": redact_text(value["publishedAt"]) if value.get("publishedAt") else None,
        "url": redact_text(value["url"]) if value.get("url") else None,
    }


STATE_LABELS = {
    "passed": "통과",
    "pass": "통과",
    "green": "통과",
    "approved": "통과",
    "complete": "통과",
    "completed": "통과",
    "ready": "통과",
    "pending": "대기",
    "running": "대기",
    "in_progress": "대기",
    "blocked": "대기",
    "unknown": "미확인",
    "missing": "미확인",
    "failed": "실패",
    "fail": "실패",
    "error": "실패",
    "red": "실패",
}
PATH_RE = re.compile(r"(?<![A-Za-z0-9_])(?:/Users|/home|/private|/tmp|/data|/var/tmp)/[^\s`\"']+")
SECRET_RE = re.compile(r"(?i)(?:token|secret|password|api[_-]?key|authorization)\s*[:=]\s*[^\s,;]+")


def read_json(path: Path, default: Any) -> Any:
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError, TypeError):
        return default


def redact_text(value: Any, limit: int = MAX_TEXT_CHARS) -> str:
    if value is None:
        return ""
    if not isinstance(value, str):
        value = str(value)
    value = SECRET_RE.sub(
        lambda match: match.group(0).split(":")[0].split("=")[0] + "=[redacted]", value
    )
    value = PATH_RE.sub("[경로 생략]", value)
    value = value.replace("\x00", "")
    if len(value) > limit:
        return value[: limit - 1].rstrip() + "…"
    return value


def safe_scalar(value: Any) -> Any:
    if isinstance(value, bool | int | float) or value is None:
        return value
    if isinstance(value, str):
        return redact_text(value)
    if isinstance(value, list):
        return [safe_scalar(item) for item in value[:40]]
    if isinstance(value, dict):
        return {str(key)[:80]: safe_scalar(item) for key, item in list(value.items())[:40]}
    return redact_text(value)


def norm_state(value: Any) -> str:
    text = str(value or "unknown").strip().lower().replace("-", "_").replace(" ", "_")
    aliases = {
        "pass": "passed",
        "green": "passed",
        "approved": "passed",
        "complete": "passed",
        "completed": "passed",
        "ready": "passed",
        "fail": "failed",
        "error": "failed",
        "red": "failed",
        "running": "pending",
        "in_progress": "pending",
        "missing": "unknown",
    }
    known = {
        "passed",
        "pending",
        "unknown",
        "failed",
        "blocked",
        "needs_information",
        "awaiting_decision",
        "research_complete",
        "implemented_pending_qa",
        "approved_not_implemented",
        "merged",
    }
    text = aliases.get(text, text)
    return text if text in known else "unknown"


def state_label(state: str) -> str:
    return {
        "passed": "통과",
        "pending": "실행 대기",
        "unknown": "미확인",
        "failed": "실패",
        "blocked": "진행 차단",
        "needs_information": "정보 필요",
        "awaiting_decision": "방향 승인 필요",
        "research_complete": "조사 완료 · QA 전",
        "ready": "검토 준비 완료",
        "implemented_pending_qa": "구현 완료 · QA 대기",
        "approved_not_implemented": "승인됨 · 구현 전",
        "merged": "병합됨",
    }.get(state, "미확인")


def first_text(data: dict[str, Any], *keys: str) -> str:
    for key in keys:
        value = data.get(key)
        if isinstance(value, str) and value.strip():
            return redact_text(value.strip(), MAX_TEXT_CHARS)
    return ""


def body_excerpt(body: Any, limit: int = MAX_BODY_CHARS) -> str:
    text = redact_text(body, limit)
    lines = [
        line.strip()
        for line in text.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    return " ".join(lines)[:limit].rstrip()


def compact_status(data: Any) -> dict[str, Any]:
    if not isinstance(data, dict):
        return {"state": "unknown", "label": "미확인", "summary": redact_text(data, 600)}
    raw_state = first_text(data, "state", "status", "verdict", "result", "outcome")
    state = norm_state(raw_state)
    summary = first_text(data, "summary", "headline", "message", "notes", "reason", "detail")
    details = data.get("checks", data.get("results", data.get("evidence")))
    result: dict[str, Any] = {"state": state, "label": state_label(state)}
    if raw_state:
        result["reportedState"] = raw_state
    if summary:
        result["summary"] = summary
    if details is not None:
        result["details"] = safe_scalar(details)
    for key in ("startedAt", "finishedAt", "updatedAt", "command", "commit", "head"):
        if key in data and isinstance(data[key], (str, int, float)):
            result[key] = redact_text(data[key], 300)
    return result


def logical_path(root: Path, path: Path, prefix: str) -> str | None:
    try:
        relative = path.resolve().relative_to(root.resolve())
    except ValueError:
        return None
    return f"{prefix}/{relative.as_posix()}"


def classify_artifact(path: Path) -> str:
    name = path.name.lower()
    if name == "status.json":
        return "status"
    if "plan" in name or "assignment" in name or "research" in name:
        return "plan"
    if "review" in name:
        return "review"
    if "qa" in name:
        return "qa"
    return "artifact"


def find_known_fields(value: Any, wanted: set[str]) -> dict[str, str]:
    found: dict[str, str] = {}

    def visit(item: Any) -> None:
        if isinstance(item, dict):
            aliases = {
                "original_url": "originalUrl",
                "replacement_url": "replacementUrl",
                "originalPrUrl": "originalUrl",
                "replacementPrUrl": "replacementUrl",
                "original_pr_url": "originalUrl",
                "replacement_pr_url": "replacementUrl",
                "original_comment_url": "originalCommentUrl",
                "original_comment_status": "originalCommentStatus",
                "attribution_method": "attributionMethod",
                "no_merge_state": "noMergeState",
                "merge_authorization": "mergeAuthorization",
            }
            for key, child in item.items():
                if key in wanted and isinstance(child, (str, int, float, bool)):
                    found.setdefault(aliases.get(key, key), redact_text(child, 800))
                visit(child)
        elif isinstance(item, list):
            for child in item[:50]:
                visit(child)

    visit(value)
    return found


def extract_links(value: Any, evidence_root: Path) -> list[dict[str, str]]:
    links: list[dict[str, str]] = []

    def visit(item: Any, key_hint: str = "") -> None:
        if isinstance(item, dict):
            for key, child in item.items():
                visit(child, str(key))
            return
        if isinstance(item, list):
            for child in item[:50]:
                visit(child, key_hint)
            return
        if not isinstance(item, str):
            return
        text = item.strip()
        if text.startswith("https://") and len(text) <= 800:
            links.append({"label": key_hint or "외부 링크", "href": text})
            return
        if key_hint.lower() in {"path", "file", "artifact", "screenshot", "video", "evidence"}:
            candidate = Path(text)
            if not candidate.is_absolute():
                candidate = evidence_root / text.removeprefix("evidence/")
            try:
                resolved = candidate.resolve()
                relative = resolved.relative_to(evidence_root.resolve())
            except (OSError, ValueError):
                return
            if resolved.is_file():
                links.append({"label": key_hint, "href": "/evidence/" + relative.as_posix()})

    visit(value)
    unique: list[dict[str, str]] = []
    seen: set[str] = set()
    for link in links:
        if link["href"] not in seen:
            unique.append(link)
            seen.add(link["href"])
    return unique[:30]


def decision_questions(raw: Any) -> list[dict[str, Any]]:
    questions: list[dict[str, Any]] = []
    if not isinstance(raw, list):
        return questions
    for entry in raw[:30]:
        if not isinstance(entry, dict):
            continue
        question = first_text(entry, "question", "title")
        if not question:
            continue
        question_fingerprint = hashlib.sha256(question.encode("utf-8")).hexdigest()[:12]
        decision_id = (
            first_text(entry, "id", "decisionId", "decision_id")
            or f"decision-{question_fingerprint}"
        )
        options: list[dict[str, Any]] = []
        for option in entry.get("options", [])[:30]:
            data = option if isinstance(option, dict) else {"label": option}
            label = first_text(data, "label", "title", "text", "name")
            if not label:
                continue
            fingerprint = hashlib.sha256(label.encode("utf-8")).hexdigest()[:12]
            option_id = first_text(data, "id", "optionId", "option_id") or f"option-{fingerprint}"
            options.append(
                {
                    "id": option_id,
                    "label": label,
                    "description": first_text(data, "description", "summary"),
                    "tradeoffs": safe_scalar(data.get("tradeoffs", data.get("trade_offs", []))),
                    "pros": safe_scalar(data.get("pros", [])),
                    "cons": safe_scalar(data.get("cons", [])),
                }
            )
        questions.append(
            {
                "id": decision_id,
                "question": question,
                "options": options,
                "recommended": safe_scalar(entry.get("recommended", "")),
                "rationale": first_text(entry, "rationale", "reason"),
            }
        )
    return questions


def normalize_decision_record(value: Any) -> dict[str, Any]:
    """Return the keyed-answer form without discarding unrelated record fields."""
    if not isinstance(value, dict):
        return {}
    record = dict(value)
    answers = record.get("answers")
    answers = dict(answers) if isinstance(answers, dict) else {}
    decision_id = record.get("decisionId")
    option_id = record.get("optionId")
    if isinstance(decision_id, str) and isinstance(option_id, str) and decision_id not in answers:
        answers[decision_id] = {
            "action": record.get("action") if isinstance(record.get("action"), str) else "approve",
            "optionId": option_id,
            "savedAt": record.get("savedAt") if isinstance(record.get("savedAt"), str) else "",
        }
    record.pop("decisionId", None)
    record.pop("optionId", None)
    record["answers"] = answers
    return record


def decision_route_state(decision: dict[str, Any] | None) -> str:
    if not isinstance(decision, dict):
        return "pending"
    return {
        "approve": "passed",
        "defer": "pending",
        "request_changes": "failed",
        "add_info": "unknown",
    }.get(str(decision.get("action")), "pending")


def verified_assessment(
    records: list[dict[str, Any]],
    kind: str,
    current_head: str,
) -> dict[str, Any]:
    candidates = [record for record in records if record["kind"] == kind]
    if not candidates:
        activity = "QA 실행" if kind == "qa" else "독립 리뷰"
        return {
            "state": "pending",
            "label": "실행 대기",
            "verified": False,
            "summary": f"{activity} 결과가 아직 없습니다. 계획과 소스 조사는 통과 증거가 아닙니다.",
        }
    latest = candidates[-1]
    data = latest["data"]
    assessment = {**compact_status(data), "source": latest["source"], "links": latest["links"]}
    head = first_text(data, "head", "commit", "head_sha", "commit_sha", "reviewed_head", "revision")
    executed = data.get("executed") is True
    independent = data.get("independent") is True
    exact_head = bool(current_head and head and head == current_head)
    verified = executed and exact_head and (kind != "review" or independent)
    assessment.update(
        {
            "verified": verified,
            "executed": executed,
            "exactHead": exact_head,
            "head": head,
            "currentHead": current_head,
            "independent": independent,
        }
    )
    if assessment["state"] in {"passed", "ready"} and not verified:
        assessment["state"] = "pending"
        assessment["label"] = "증거 확인 대기"
        assessment["verificationNote"] = (
            "통과 표기가 있어도 executed=true, 현재 head 일치, "
            "리뷰의 independent=true가 모두 필요합니다."
        )
    return assessment


class ReportBuilder:
    def __init__(self, root: Path, evidence_root: Path, decisions_path: Path) -> None:
        self.root = root.resolve()
        self.evidence_root = evidence_root.resolve()
        self.decisions_path = decisions_path.resolve()
        self.groups_path = self.root / "groups.json"
        self.contract_path = self.root / "run-contract.json"
        self.classification_path = self.root / "classification.json"

    def _item_view(
        self,
        item: str,
        group: dict[str, Any],
        classification: dict[str, Any],
    ) -> dict[str, Any]:
        source: dict[str, Any] = {}
        expected = item.replace(":", "-") + ".json"
        for raw_path in group.get("input_paths", []):
            path = Path(str(raw_path))
            if not path.is_absolute():
                path = self.root / path
            if path.name == expected and path.resolve().is_relative_to(self.root):
                loaded = read_json(path, {})
                if isinstance(loaded, dict):
                    source = loaded
                    break
        metadata = source.get("metadata", {})
        if not isinstance(metadata, dict):
            metadata = {}
        verdict = classification.get("verdicts", {}).get(item, {})
        return {
            "id": item,
            "type": metadata.get("type", item.split(":")[0]),
            "title": redact_text(metadata.get("title", item)),
            "author": redact_text(metadata.get("author", "")),
            "url": metadata.get("url"),
            "head": metadata.get("head") or "",
            "updatedAt": metadata.get("updated_at"),
            "problem": body_excerpt(source.get("body", "")),
            "classification": safe_scalar(verdict),
        }

    def _artifacts(self, group_id: str) -> list[dict[str, Any]]:
        records: list[dict[str, Any]] = []
        for directory in (self.root / "groups" / group_id, self.evidence_root / group_id):
            if not directory.is_dir():
                continue
            for path in sorted(directory.rglob("*.json")):
                resolved = path.resolve()
                if not resolved.is_relative_to(directory.resolve()) or path.name in {
                    "assignment.json",
                    "activity.json",
                }:
                    continue
                data = read_json(path, None)
                if not isinstance(data, dict):
                    continue
                records.append(
                    {
                        "kind": classify_artifact(path),
                        "name": path.name,
                        "source": (
                            resolved.relative_to(self.root).as_posix()
                            if resolved.is_relative_to(self.root)
                            else f"evidence/{group_id}/{path.name}"
                        ),
                        "data": data,
                        "links": extract_links(data, self.evidence_root),
                    }
                )
        return records

    def build(self) -> dict[str, Any]:
        groups = read_json(self.groups_path, [])
        contract = read_json(self.contract_path, {})
        classification = read_json(self.classification_path, {})
        saved = read_json(self.decisions_path, {})
        saved = saved.get("decisions", {}) if isinstance(saved, dict) else {}
        if not isinstance(saved, dict):
            saved = {}
        views: list[dict[str, Any]] = []
        machine_procs = probe_machine_harnesses()
        for group in groups if isinstance(groups, list) else []:
            if not isinstance(group, dict):
                continue
            group_id = group.get("id", "")
            if not isinstance(group_id, str) or not re.fullmatch(
                r"[a-z0-9][a-z0-9-]{1,63}", group_id
            ):
                continue
            owner_status = read_json(self.root / "groups" / group_id / "status.json", {})
            if not isinstance(owner_status, dict):
                owner_status = {}
            records = self._artifacts(group_id)
            items = [
                self._item_view(item, group, classification)
                for item in group.get("items", [])
                if isinstance(item, str)
            ]
            original = owner_status.get("original_pr") or {}
            replacement = owner_status.get("replacement_pr") or {}
            if not isinstance(original, dict):
                original = {}
            if not isinstance(replacement, dict):
                replacement = {}
            pr = next((item for item in items if item.get("type") == "pr"), {})
            stored_raw = saved.get(group_id)
            stored_decision = (
                normalize_decision_record(stored_raw) if isinstance(stored_raw, dict) else None
            )
            synthetic = (
                isinstance(stored_decision, dict) and stored_decision.get("synthetic") is True
            )
            head = (
                first_text(owner_status, "current_head", "head", "head_sha")
                or first_text(replacement, "head", "head_sha")
                or first_text(original, "head")
                or str(pr.get("head") or contract.get("base_sha", ""))
            )
            merge_result_raw = owner_status.get("merge_result")
            merge_result = (
                safe_scalar(merge_result_raw) if isinstance(merge_result_raw, dict) else None
            )
            qa = verified_assessment(records, "qa", head)
            review = verified_assessment(records, "review", head)
            blockers = owner_status.get("blockers", [])
            status = compact_status(owner_status)
            raw_state = str(owner_status.get("state", "unknown")).strip().lower()
            ready = bool(
                qa.get("verified")
                and review.get("verified")
                and qa["state"] == "passed"
                and review["state"] == "passed"
                and status["state"] == "passed"
                and not blockers
            )
            if ready:
                status.update({"state": "passed", "label": "통과"})
            elif status["state"] == "passed":
                status.update({"state": "pending", "label": "증거 확인 대기"})
            priority_raw = str(owner_status.get("priority", "normal"))
            priority_key = priority_raw.strip().lower()
            priority = (
                "high"
                if (
                    priority_key in {"p0", "p1", "high", "critical", "structural"}
                    or priority_key.startswith(("p0 ", "p1 "))
                )
                else "low"
                if priority_key in {"p3", "low"}
                else "normal"
            )
            provenance = find_known_fields(
                owner_status,
                {
                    "originalUrl",
                    "replacementUrl",
                    "originalCommentUrl",
                    "originalCommentStatus",
                    "attributionMethod",
                    "noMergeState",
                    "original_url",
                    "replacement_url",
                    "original_comment_url",
                    "original_comment_status",
                    "attribution_method",
                    "no_merge_state",
                    "original_pr_url",
                    "replacement_pr_url",
                },
            )
            briefing = {
                "hasPullRequest": bool(pr or replacement),
                "originalUrl": (
                    original.get("url") or pr.get("url") or provenance.get("originalUrl")
                ),
                "replacementUrl": replacement.get("url") or provenance.get("replacementUrl"),
                "originalAuthor": (
                    original.get("author_login") or original.get("author_name") or pr.get("author")
                ),
                "attributionMethod": provenance.get(
                    "attributionMethod", "cherry-pick -x (교체 시 적용 규칙; 실행 여부는 별도 증거)"
                ),
                "attributionRule": redact_text(owner_status.get("attribution_rule", "")),
                "originalComment": {
                    "url": provenance.get("originalCommentUrl"),
                    "status": provenance.get("originalCommentStatus", "댓글 게시 증거 미제공"),
                },
                "noMergeState": (
                    "검토 승인 기록은 GitHub 실행을 트리거하지 않습니다. "
                    "실제 실행 결과는 별도로 표시하며, 병합은 릴리스가 아닙니다."
                ),
                "mergeAuthorization": False,
            }
            phase = redact_text(owner_status.get("phase", group.get("phase", "unknown")))
            reported = str(owner_status.get("reported", status.get("reportedState", "")))
            completed = bool(merge_result and merge_result.get("state") == "merged") or (
                raw_state in {"merged", "closed"}
                or reported in {"closed", "completed"}
                or phase
                in {
                    "merged",
                    "merged-unreleased",
                    "closed-without-merge",
                    "completed",
                    "historical-out-of-current-scope",
                }
            )
            questions = decision_questions(owner_status.get("decisions", []))
            has_owner_decision = isinstance(stored_decision, dict) and not synthetic
            is_whole_group_deferred = (
                has_owner_decision and stored_decision.get("action") == "defer"
            )
            answers = stored_decision.get("answers", {}) if has_owner_decision else {}
            is_overview = bool(
                group.get("overview") is True
                or owner_status.get("overview") is True
                or owner_status.get("kind") == "overview"
                or isinstance(owner_status.get("decision_units"), list)
            )
            needs_decision = (
                not completed
                and not is_overview
                and (
                    (
                        bool(questions)
                        and not is_whole_group_deferred
                        and any(question["id"] not in answers for question in questions)
                    )
                    or (
                        not has_owner_decision
                        and (
                            ready
                            or status["state"]
                            in {
                                "awaiting_decision",
                                "ready",
                                "blocked",
                                "needs_information",
                                "research_complete",
                                "implemented_pending_qa",
                            }
                            or phase == "pr-ci-passed"
                        )
                    )
                )
            )
            area = redact_text(group.get("area", "general")).strip() or "general"
            views.append(
                {
                    "id": group_id,
                    "title": redact_text(group.get("title", group_id)),
                    "area": area,
                    "areaLabel": area_label(area),
                    "owner": redact_text(group.get("owner", "")),
                    "phase": redact_text(owner_status.get("phase", group.get("phase", "unknown"))),
                    "items": items,
                    "currentHead": head,
                    "what": first_text(owner_status, "summary") or "담당자의 요약이 아직 없습니다.",
                    "why": first_text(owner_status, "why_needed") or "필요성 설명이 아직 없습니다.",
                    "problem": (
                        first_text(owner_status, "problem", "summary")
                        or "문제 설명이 아직 없습니다."
                    ),
                    "importance": (
                        first_text(owner_status, "user_impact")
                        or "사용자 영향 설명이 아직 없습니다."
                    ),
                    "priority": priority,
                    "prioritySource": redact_text(priority_raw),
                    "evidenceLevel": safe_scalar(owner_status.get("evidence_level", "미제공")),
                    "proposedChanges": safe_scalar(owner_status.get("proposed_changes", [])),
                    "risks": safe_scalar(owner_status.get("risks", [])),
                    "blockers": safe_scalar(blockers),
                    "nextAction": first_text(owner_status, "next_action"),
                    "questions": questions,
                    "qaPlan": safe_scalar(owner_status.get("qa", [])),
                    "sourceRefs": safe_scalar(owner_status.get("source_refs", [])),
                    "qa": qa,
                    "review": review,
                    "status": status,
                    "artifacts": [
                        {
                            "kind": record["kind"],
                            "source": record["source"],
                            "name": record["name"],
                            **compact_status(record["data"]),
                            "links": record["links"],
                        }
                        for record in records
                    ],
                    "route": [
                        qa["state"],
                        review["state"],
                        decision_route_state(stored_decision)
                        if isinstance(stored_decision, dict) and not synthetic
                        else "pending",
                    ],
                    "ready": ready,
                    "completed": completed,
                    "needsDecision": needs_decision,
                    "agentActivity": detect_group_activity(
                        group_id=group_id,
                        group=group,
                        owner_status=owner_status,
                        completed=completed,
                        root=self.root,
                        machine_procs=machine_procs,
                    ),
                    "decision": (
                        safe_scalar(stored_decision)
                        if isinstance(stored_decision, dict) and not synthetic
                        else None
                    ),
                    "qaDecision": {
                        "record": safe_scalar(stored_decision),
                        "synthetic": True,
                        "label": "브라우저 QA 저장 시험 · 사용자 결정 아님",
                    }
                    if synthetic
                    else None,
                    "prBriefing": briefing,
                    **({"mergeResult": merge_result} if merge_result is not None else {}),
                    "links": [link for record in records for link in record["links"]][:40],
                }
            )
        counts = {kind: {} for kind in ("qa", "review", "status")}
        for view in views:
            for kind in counts:
                state = view[kind]["state"]
                counts[kind][state] = counts[kind].get(state, 0) + 1
        return {
            "generatedAt": datetime.now(UTC).isoformat(),
            "repository": contract.get("repo") or "unknown/repository",
            "baseBranch": contract.get("base_branch") or "main",
            "latestRelease": safe_release(contract.get("latest_release")),
            "baseSha": contract.get("base_sha") or "",
            "boundary": redact_text(contract.get("boundary", "")),
            "areaCatalog": [
                {"id": area, "label": area_label(area)}
                for area in sorted({view["area"] for view in views})
            ],
            "harnessCatalog": [
                {"id": harness_id, "label": harness_label(harness_id)}
                for harness_id in sorted(
                    {h for view in views for h in view["agentActivity"]["harnesses"]}
                )
            ],
            "groups": views,
            "summary": {
                "total": len(views),
                "active": sum(not view["completed"] for view in views),
                "completed": sum(view["completed"] for view in views),
                "working": sum(view["agentActivity"]["active"] for view in views),
                "idle": sum(not view["agentActivity"]["active"] for view in views),
                "needsDecision": sum(view["needsDecision"] for view in views),
                "ready": sum(view["ready"] for view in views),
                "decisions": sum(view["decision"] is not None for view in views),
                "syntheticDecisions": sum(view["qaDecision"] is not None for view in views),
                "storedDecisions": sum(
                    view["decision"] is not None or view["qaDecision"] is not None for view in views
                ),
                **counts,
            },
            "methodAudit": {
                "classificationFrozen": bool(
                    self.classification_path.is_file() and classification.get("frozen") is True
                ),
                "classificationSource": "classification.json",
                "baseSha": contract.get("base_sha"),
                "excludedAuthors": contract.get(
                    "excluded_authors",
                    [value for value in (contract.get("login"), "dependabot[bot]") if value],
                ),
                "excludedCounts": safe_scalar(contract.get("excluded", {})),
                "excludedNote": (
                    "제외 대상과 수는 실행 계약을 따릅니다. 분류는 실행 증거가 아닙니다."
                ),
                "includedItems": [item["id"] for view in views for item in view["items"]],
            },
            "actions": sorted(ACTIONS),
        }

    def build_handoff(self) -> dict[str, Any]:
        """Resolve saved choices into an execution briefing without granting merge permission."""
        report = self.build()
        queue: list[dict[str, Any]] = []
        undecided: list[dict[str, Any]] = []
        for view in report["groups"]:
            decision = view["decision"]
            if view["needsDecision"]:
                answers = decision.get("answers", {}) if decision else {}
                undecided.append(
                    {
                        "groupId": view["id"],
                        "title": view["title"],
                        "statusState": view["status"]["state"],
                        "unansweredQuestions": sum(
                            question["id"] not in answers for question in view["questions"]
                        ),
                        "nextAction": view["nextAction"],
                    }
                )
            if not isinstance(decision, dict):
                continue
            questions = {question["id"]: question for question in view["questions"]}
            resolved: list[dict[str, Any]] = []
            for question_id, answer in decision.get("answers", {}).items():
                if not isinstance(answer, dict):
                    continue
                question = questions.get(question_id, {})
                option_id = answer.get("optionId", "")
                option = next(
                    (item for item in question.get("options", []) if item["id"] == option_id),
                    {},
                )
                resolved.append(
                    {
                        "decisionId": question_id,
                        "question": question.get("question", question_id),
                        "action": answer.get("action", "approve"),
                        "optionId": option_id,
                        "optionLabel": option.get("label", option_id),
                    }
                )
            action = decision.get("action", "")
            choices = "; ".join(
                f"{answer['question']}: {answer['optionLabel']}"
                f" ({ACTION_LABELS.get(answer['action'], answer['action'])})"
                for answer in resolved
            )
            summary_parts = [f"기록된 상태: {ACTION_LABELS.get(action, action)}"]
            if choices:
                summary_parts.append(f"선택: {choices}")
            if decision.get("note"):
                summary_parts.append(f"메모: {decision['note']}")
            instruction = " · ".join(summary_parts)
            queue.append(
                {
                    "groupId": view["id"],
                    "title": view["title"],
                    "area": view["area"],
                    "items": [item["id"] for item in view["items"]],
                    "currentHead": view["currentHead"],
                    "ready": view["ready"],
                    "completed": view["completed"],
                    "action": action,
                    "actionLabel": ACTION_LABELS.get(action, action),
                    "note": decision.get("note", ""),
                    "savedAt": decision.get("savedAt", ""),
                    "answers": resolved,
                    "nextAction": view["nextAction"],
                    "agentInstruction": instruction,
                }
            )
        counts = {
            "totalGroups": report["summary"]["total"],
            "activeGroups": report["summary"]["active"],
            "completedGroups": report["summary"]["completed"],
            "decidedCount": len(queue),
            "approvedCount": sum(item["action"] == "approve" for item in queue),
            "deferredCount": sum(item["action"] == "defer" for item in queue),
            "changesRequestedCount": sum(item["action"] == "request_changes" for item in queue),
            "infoRequestedCount": sum(item["action"] == "add_info" for item in queue),
            "undecidedCount": len(undecided),
        }
        raw_doc = read_json(self.decisions_path, {})
        sub_raw = raw_doc.get("submission") if isinstance(raw_doc, dict) else None
        submission = (
            {
                "submitted": bool(sub_raw.get("submitted") is True),
                "submittedAt": (
                    redact_text(sub_raw.get("submittedAt", ""))
                    if sub_raw.get("submittedAt")
                    else None
                ),
                "note": redact_text(sub_raw.get("note", ""), 2_000),
            }
            if isinstance(sub_raw, dict)
            else {"submitted": False, "submittedAt": None, "note": ""}
        )
        result = {
            key: report[key]
            for key in (
                "generatedAt",
                "repository",
                "baseBranch",
                "baseSha",
            )
        }
        result.update(
            {
                "submission": submission,
                "counts": counts,
                "queue": queue,
                "undecided": undecided,
            }
        )
        result["resumePrompt"] = handoff_prompt(result)
        return result


def handoff_prompt(handoff: dict[str, Any]) -> str:
    """Render recorded owner feedback as a clean Markdown summary."""
    lines = [
        "# 수집된 검토 피드백 요약",
        f"- 저장소: {handoff['repository']}",
        f"- 기준 브랜치: {handoff['baseBranch']}",
        f"- 기준 커밋: {handoff['baseSha'] or '미기록'}",
    ]
    if handoff.get("submission", {}).get("submittedAt"):
        lines.append(f"- 제출 시각: {handoff['submission']['submittedAt']}")
    if handoff.get("submission", {}).get("note"):
        lines.append(f"- 전체 제출 메모: {handoff['submission']['note']}")
    sections = (
        (
            "승인 · 수정 요청 · 정보 추가",
            lambda item: not item["completed"] and item["action"] != "defer",
        ),
        ("보류", lambda item: not item["completed"] and item["action"] == "defer"),
        ("완료된 항목", lambda item: item["completed"]),
    )
    for title, predicate in sections:
        lines.extend(["", f"## {title}"])
        entries = [item for item in handoff["queue"] if predicate(item)]
        if not entries:
            lines.append("- 없음")
        for item in entries:
            lines.append(f"- [{item['groupId']}] {item['title']} — {item['actionLabel']}")
            for answer in item["answers"]:
                lines.append(
                    f"  - {answer['question']}: **{answer['optionLabel']}**"
                    f" ({ACTION_LABELS.get(answer['action'], answer['action'])};"
                    f" {answer['decisionId']} / {answer['optionId']})"
                )
            if item["note"]:
                lines.append(f"  - 메모: {item['note']}")
    lines.extend(["", "## 남은 미결정 항목"])
    for item in handoff["undecided"]:
        lines.append(
            f"- [{item['groupId']}] {item['title']}:"
            f" 미응답 {item['unansweredQuestions']}개; {item['nextAction']}"
        )
    if not handoff["undecided"]:
        lines.append("- 없음")
    return "\n".join(lines) + "\n"


def allowed_evidence_path(evidence_root: Path, request_path: str) -> Path | None:
    decoded = unquote(request_path)
    if not decoded or "\x00" in decoded or "\\" in decoded:
        return None
    candidate = (evidence_root / decoded).resolve()
    try:
        candidate.relative_to(evidence_root.resolve())
    except ValueError:
        return None
    if not candidate.is_file():
        return None
    return candidate


class CockpitHTTPServer(ThreadingHTTPServer):
    config: dict[str, Any]


class ReportHandler(BaseHTTPRequestHandler):
    server_version = "review-cockpit/1"

    @property
    def config(self) -> dict[str, Any]:
        server = self.server
        if isinstance(server, CockpitHTTPServer):
            return server.config
        return getattr(server, "config", {})

    def _host_allowed(self) -> bool:
        host = self.headers.get("Host", "").strip().lower()
        return host in self.config["allowed_hosts"]

    def _origin_allowed(self) -> bool:
        origin = self.headers.get("Origin")
        if not origin:
            return True
        parsed = urlsplit(origin)
        return (
            parsed.scheme in {"http", "https"}
            and parsed.netloc.lower() == self.headers.get("Host", "").lower()
        )

    def _send_json(self, payload: Any, status: int = HTTPStatus.OK) -> None:
        encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(encoded)

    def _error(self, status: int, message: str) -> None:
        self._send_json({"error": message}, status)

    def do_GET(self) -> None:
        if not self._host_allowed() or not self._origin_allowed():
            self._error(HTTPStatus.FORBIDDEN, "허용되지 않은 호스트입니다.")
            return
        parsed = urlsplit(self.path)
        if parsed.path == "/api/report":
            self._send_json(self.config["builder"].build())
            return
        if parsed.path == "/api/handoff":
            self._send_json(self.config["builder"].build_handoff())
            return
        if parsed.path.startswith("/evidence/"):
            evidence_path = allowed_evidence_path(
                self.config["evidence_root"], parsed.path.removeprefix("/evidence/")
            )
            if evidence_path is None:
                self._error(HTTPStatus.NOT_FOUND, "증거 파일을 찾을 수 없습니다.")
                return
            self._serve_file(evidence_path)
            return
        self._serve_static(parsed.path)

    def do_HEAD(self) -> None:
        self.do_GET()

    def do_POST(self) -> None:
        if not self._host_allowed() or not self._origin_allowed():
            self._error(HTTPStatus.FORBIDDEN, "허용되지 않은 요청입니다.")
            return
        request_path = urlsplit(self.path).path
        if request_path not in {"/api/decisions", "/api/submit"}:
            self._error(HTTPStatus.NOT_FOUND, "경로를 찾을 수 없습니다.")
            return
        raw_length = self.headers.get("Content-Length")
        try:
            length = (
                int(raw_length or "0") if request_path == "/api/submit" else int(raw_length or "-1")
            )
        except ValueError:
            length = -1
        if length < 0 or length > MAX_BODY_BYTES:
            self._error(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, "요청 크기가 제한을 초과했습니다.")
            return
        if length == 0 and request_path == "/api/submit":
            payload: Any = {}
        else:
            try:
                payload = json.loads(self.rfile.read(length).decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                self._error(HTTPStatus.BAD_REQUEST, "JSON 요청을 읽을 수 없습니다.")
                return
        if not isinstance(payload, dict):
            self._error(HTTPStatus.BAD_REQUEST, "객체 형식의 요청이 필요합니다.")
            return
        if request_path == "/api/submit":
            submit_note = payload.get("note", "")
            if not isinstance(submit_note, str) or len(submit_note) > 2_000:
                self._error(HTTPStatus.BAD_REQUEST, "메모는 2,000자 이내여야 합니다.")
                return
            try:
                submission = self._persist_submission(submit_note)
            except OSError:
                self._error(HTTPStatus.INTERNAL_SERVER_ERROR, "제출 상태를 저장하지 못했습니다.")
                return
            handoff = self.config["builder"].build_handoff()
            self._send_json(
                {
                    "ok": True,
                    "submission": submission,
                    "handoff": handoff,
                    "message": "피드백이 제출되었습니다. 대기 중인 에이전트가 즉시 전달받습니다.",
                }
            )
            return
        group_id = payload.get("groupId")
        action = payload.get("action")
        note = payload.get("note", "")
        decision_id = payload.get("decisionId")
        option_id = payload.get("optionId")
        report = self.config["builder"].build()
        group = next(
            (entry for entry in report.get("groups", []) if entry.get("id") == group_id), None
        )
        if not isinstance(group_id, str) or not isinstance(group, dict):
            self._error(HTTPStatus.BAD_REQUEST, "알 수 없는 그룹입니다.")
            return
        if not isinstance(action, str) or action not in ACTIONS:
            self._error(HTTPStatus.BAD_REQUEST, "허용되지 않은 결정입니다.")
            return
        if not isinstance(note, str) or len(note) > 2_000:
            self._error(HTTPStatus.BAD_REQUEST, "메모는 2,000자 이내여야 합니다.")
            return
        questions = group.get("questions", [])
        supplied_choice = decision_id is not None or option_id is not None
        if (questions and action != "defer") or supplied_choice:
            if not isinstance(decision_id, str) or not isinstance(option_id, str):
                self._error(
                    HTTPStatus.BAD_REQUEST,
                    "질문이 있는 그룹은 전체 보류 외에 정책 선택지를 골라 주세요.",
                )
                return
            question = next((entry for entry in questions if entry.get("id") == decision_id), None)
            option_ids = (
                {entry.get("id") for entry in question.get("options", [])}
                if isinstance(question, dict)
                else set()
            )
            if not isinstance(question, dict) or option_id not in option_ids:
                self._error(HTTPStatus.BAD_REQUEST, "알 수 없는 결정 선택지입니다.")
                return
        decision = {
            "action": action,
            "note": redact_text(note, 2_000),
            "mergeAuthorization": False,
            "savedAt": datetime.now(UTC).isoformat(),
        }
        try:
            stored = self._persist_decision(group_id, decision, decision_id, option_id)
        except OSError:
            self._error(HTTPStatus.INTERNAL_SERVER_ERROR, "결정을 저장하지 못했습니다.")
            return
        self._send_json(
            {"ok": True, "decision": stored, "message": "결정이 기록되었습니다. 병합하지 않습니다."}
        )

    def _persist_decision(
        self,
        group_id: str,
        decision: dict[str, Any],
        decision_id: Any,
        option_id: Any,
    ) -> dict[str, Any]:
        path: Path = self.config["decisions_path"]
        path.parent.mkdir(parents=True, exist_ok=True)
        lock_path = path.with_suffix(path.suffix + ".lock")
        with lock_path.open("a+", encoding="utf-8") as lock_handle:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
            current = read_json(path, {})
            if not isinstance(current, dict):
                current = {}
            entries = current.get("decisions")
            if not isinstance(entries, dict):
                entries = {}
            entry = normalize_decision_record(entries.get(group_id))
            if entry.get("synthetic") is True and decision["action"] != "add_info":
                entry.pop("synthetic", None)
                entry.pop("source", None)
                entry.pop("meaning", None)
            entry.update(decision)
            answers = entry.get("answers", {})
            answers = dict(answers) if isinstance(answers, dict) else {}
            if isinstance(decision_id, str) and isinstance(option_id, str):
                answer = answers.get(decision_id)
                answer = dict(answer) if isinstance(answer, dict) else {}
                answer.update(
                    {
                        "action": decision["action"],
                        "optionId": option_id,
                        "savedAt": decision["savedAt"],
                    }
                )
                answers[decision_id] = answer
            entry["answers"] = answers
            entries[group_id] = entry
            document = dict(current)
            document["version"] = 1
            document["decisions"] = entries
            if isinstance(document.get("submission"), dict):
                document["submission"] = {
                    **document["submission"],
                    "submitted": False,
                }
            self._atomic_write_json(path, document)
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
        return entry

    def _persist_submission(self, note: str) -> dict[str, Any]:
        path: Path = self.config["decisions_path"]
        path.parent.mkdir(parents=True, exist_ok=True)
        lock_path = path.with_suffix(path.suffix + ".lock")
        submission = {
            "submitted": True,
            "submittedAt": datetime.now(UTC).isoformat(),
            "note": redact_text(note, 2_000),
        }
        with lock_path.open("a+", encoding="utf-8") as lock_handle:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
            current = read_json(path, {})
            if not isinstance(current, dict):
                current = {}
            entries = current.get("decisions")
            if not isinstance(entries, dict):
                entries = {}
            document = dict(current)
            document["version"] = 1
            document["decisions"] = entries
            document["submission"] = submission
            self._atomic_write_json(path, document)
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
        return submission

    def _atomic_write_json(self, path: Path, document: dict[str, Any]) -> None:
        fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent), text=True)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(document, handle, ensure_ascii=False, indent=2)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temp_name, path)
        finally:
            if os.path.exists(temp_name):
                os.unlink(temp_name)

    def _serve_static(self, request_path: str) -> None:
        safe_path = "/index.html" if request_path in {"", "/"} else request_path
        static_files = {
            "/index.html": "index.html",
            "/styles.css": "styles.css",
            "/app.js": "app.js",
        }
        filename = static_files.get(safe_path)
        if filename is None:
            self._error(HTTPStatus.NOT_FOUND, "페이지를 찾을 수 없습니다.")
            return
        path = self.config["web_root"] / filename
        self._serve_file(path)

    def _serve_file(self, path: Path) -> None:
        try:
            content = path.read_bytes()
        except OSError:
            self._error(HTTPStatus.NOT_FOUND, "파일을 찾을 수 없습니다.")
            return
        content_type = {
            ".html": "text/html; charset=utf-8",
            ".css": "text/css; charset=utf-8",
            ".js": "text/javascript; charset=utf-8",
            ".json": "application/json; charset=utf-8",
            ".png": "image/png",
            ".jpg": "image/jpeg",
            ".jpeg": "image/jpeg",
            ".webp": "image/webp",
            ".mp4": "video/mp4",
            ".webm": "video/webm",
        }.get(path.suffix.lower(), "application/octet-stream")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        if path.suffix.lower() == ".html":
            self.send_header(
                "Content-Security-Policy",
                "default-src 'self'; img-src 'self' https:; media-src 'self' https:; "
                "style-src 'self'; script-src 'self'; connect-src 'self'; "
                "frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
            )
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(content)

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A002
        # Avoid logging request bodies, paths outside the report, or host details.
        super().log_message("%s", format % args)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True, help="scratch report root")
    parser.add_argument("--web", type=Path, default=None, help="web source directory")
    parser.add_argument(
        "--evidence-root", type=Path, default=None, help="designated evidence directory"
    )
    parser.add_argument("--decisions", type=Path, default=None, help="durable decisions JSON path")
    parser.add_argument("--bind", default="127.0.0.1", help="bind address (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=8787, help="listen port (default: 8787)")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    bind = args.bind.strip().lower()
    if bind == "0.0.0.0" or bind == "::":
        raise SystemExit("refusing wildcard bind")
    if not 1024 <= args.port <= 65535:
        raise SystemExit("port must be between 1024 and 65535")
    root = args.root.resolve()
    default_web = root / "web"
    if not (default_web / "index.html").is_file():
        default_web = Path(__file__).resolve().parent.parent / "assets" / "web"
    web_root = (args.web or default_web).resolve()
    evidence_root = (args.evidence_root or root / "evidence").resolve()
    decisions_path = (args.decisions or root / "decisions.json").resolve()
    if not web_root.is_dir() or not (web_root / "index.html").is_file():
        raise SystemExit("web directory or index.html is missing")
    if not evidence_root.is_dir():
        raise SystemExit("evidence directory is missing")
    allowed_hosts = {
        f"{bind}:{args.port}",
        f"127.0.0.1:{args.port}",
        f"localhost:{args.port}",
        f"[::1]:{args.port}",
    }
    builder = ReportBuilder(root, evidence_root, decisions_path)
    server = CockpitHTTPServer((bind, args.port), ReportHandler)
    server.config = {
        "builder": builder,
        "web_root": web_root,
        "evidence_root": evidence_root,
        "decisions_path": decisions_path,
        "allowed_hosts": allowed_hosts,
    }
    print(f"review surface listening on {bind}:{args.port}", flush=True)
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
