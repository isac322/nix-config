#!/usr/bin/env python3
"""Validate destination-aware writing artifacts without external side effects."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

DESTINATIONS = {"github_pr", "linear", "beardrive", "workplace_report"}
MODES = {"compose", "edit", "transform", "content_plan", "review", "publish"}
STATUSES = {"draft", "ready", "blocked"}
CLAIM_STATUSES = {"supported", "unknown", "contradicted"}
CLAIM_KINDS = {"request", "observation", "implementation", "unknown", "inference", "contradicted"}
MARKUP_RE = re.compile(r"<\/?(?:html|body|head|script|style|div)\b", re.IGNORECASE)


def fail(message: str) -> int:
    print(json.dumps({"status": "invalid", "errors": [message]}, ensure_ascii=False))
    return 2


def load(path: str) -> dict[str, Any]:
    try:
        value = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"input_read_failed:{error}") from error
    if not isinstance(value, dict):
        raise ValueError("input_must_be_object")
    return value


def route(task: dict[str, Any]) -> dict[str, Any]:
    destinations = task.get("destinations", [])
    if not isinstance(destinations, list):
        return {"status": "blocked", "reason": "destinations_must_be_list", "destinations": []}
    unknown = [value for value in destinations if value not in DESTINATIONS]
    mode = task.get("mode", "edit" if task.get("existing_artifact") else "compose")
    if unknown:
        return {"status": "blocked", "reason": "destination_unsupported", "unknown": unknown, "destinations": []}
    if not destinations:
        return {"status": "blocked", "reason": "destination_missing", "destinations": []}
    if mode not in MODES:
        return {"status": "blocked", "reason": "mode_unsupported", "mode": mode, "destinations": destinations}
    return {"status": "ready", "mode": mode, "destinations": destinations}



def plan(task: dict[str, Any]) -> dict[str, Any]:
    routing = route(task)
    locale = task.get("locale", "en")
    contracts = {
        "github_pr": {
            "artifact": "github_pr_draft",
            "locale": "en",
            "reader": "reviewer",
            "sections": ["Summary", "Changes", "Validation", "Not verified"],
            "forbid": ["publish", "invented tests", "unsupported Fixes claim"],
        },
        "linear": {
            "artifact": "linear_draft",
            "locale": locale,
            "reader": "team",
            "sections": ["Status", "Evidence", "Unknowns"],
            "forbid": ["guessed team/project/owner/priority", "draft mutation"],
        },
        "beardrive": {
            "artifact": "beardrive_semantic_report",
            "locale": locale,
            "reader": "report reader",
            "sections": ["Summary", "Evidence", "Unknowns"],
            "forbid": ["HTML/CSS/JS", "bdrive init", "authentication", "sync"],
        },
        "workplace_report": {
            "artifact": "workplace_report",
            "locale": locale,
            "reader": "manager or team",
            "sections": ["Conclusion", "Impact", "Evidence", "Risks", "Next actions"],
            "forbid": ["invented status", "invented owner or deadline"],
        },
    }
    if routing["status"] != "ready":
        return {"status": "blocked", "route": routing}
    return {
        "status": "ready",
        "mode": routing["mode"],
        "revision": task.get("current_revision", task.get("revision")),
        "destinations": [
            {"destination": destination, **contracts[destination]} for destination in routing["destinations"]
        ],
    }

def claims_by_id(task: dict[str, Any]) -> dict[str, dict[str, Any]]:
    claims = task.get("claims", [])
    if not isinstance(claims, list):
        raise ValueError("claims_must_be_list")
    result: dict[str, dict[str, Any]] = {}
    for claim in claims:
        if not isinstance(claim, dict):
            raise ValueError("claim_must_be_object")
        claim_id = claim.get("id")
        if not isinstance(claim_id, str) or not claim_id:
            raise ValueError("claim_id_missing")
        if claim_id in result:
            raise ValueError(f"claim_id_duplicate:{claim_id}")
        status = claim.get("status")
        if status not in CLAIM_STATUSES:
            raise ValueError(f"claim_status_invalid:{claim_id}")
        kind = claim.get("kind")
        if kind not in CLAIM_KINDS:
            raise ValueError(f"claim_kind_invalid:{claim_id}")
        sources = claim.get("source_refs")
        if not isinstance(sources, list) or not sources:
            raise ValueError(f"claim_source_missing:{claim_id}")
        result[claim_id] = claim
    return result


def validate_artifact(artifact: dict[str, Any], destination: str, claims: dict[str, dict[str, Any]], revision: str) -> list[str]:
    errors: list[str] = []
    if artifact.get("destination") != destination:
        errors.append(f"wrong_destination:{destination}")
    if artifact.get("revision") != revision:
        errors.append(f"stale_artifact:{destination}")
    if artifact.get("status") not in STATUSES:
        errors.append(f"artifact_status_invalid:{destination}")
    if not isinstance(artifact.get("title"), str) or not artifact["title"].strip():
        errors.append(f"title_missing:{destination}")
    sections = artifact.get("sections")
    if not isinstance(sections, list) or not sections:
        errors.append(f"sections_missing:{destination}")
        return errors
    for index, section in enumerate(sections):
        if not isinstance(section, dict):
            errors.append(f"section_not_object:{destination}:{index}")
            continue
        if not isinstance(section.get("heading"), str) or not section["heading"].strip():
            errors.append(f"section_heading_missing:{destination}:{index}")
        if not isinstance(section.get("text"), str) or not section["text"].strip():
            errors.append(f"section_text_missing:{destination}:{index}")
        claim_ids = section.get("claim_ids")
        if not isinstance(claim_ids, list) or not claim_ids:
            errors.append(f"section_claims_missing:{destination}:{index}")
            continue
        assertive = section.get("assertive", True)
        for claim_id in claim_ids:
            claim = claims.get(claim_id)
            if claim is None:
                errors.append(f"claim_unknown:{destination}:{claim_id}")
            elif assertive and (
                claim["status"] != "supported"
                or claim["kind"] in {"request", "unknown", "inference", "contradicted"}
            ):
                errors.append(f"claim_not_supported:{destination}:{claim_id}")
    serialized = json.dumps(artifact, ensure_ascii=False)
    if destination == "beardrive" and MARKUP_RE.search(serialized):
        errors.append("renderer_boundary_violation:beardrive")
    return errors


def validate(bundle: dict[str, Any]) -> dict[str, Any]:
    task = bundle.get("task")
    if not isinstance(task, dict):
        return {"status": "invalid", "errors": ["task_missing"]}
    try:
        claims = claims_by_id(task)
    except ValueError as error:
        return {"status": "invalid", "errors": [str(error)]}
    routing = route(task)
    errors: list[str] = []
    if routing["status"] != "ready":
        errors.append(routing["reason"])
    revision = task.get("current_revision")
    source_revision = task.get("revision")
    if not isinstance(source_revision, str) or not source_revision:
        errors.append("revision_missing")
    if not isinstance(revision, str) or not revision:
        errors.append("current_revision_missing")
    elif source_revision != revision:
        errors.append("stale_revision")
    artifacts = bundle.get("artifacts", [])
    if not isinstance(artifacts, list):
        errors.append("artifacts_must_be_list")
        artifacts = []
    seen: set[str] = set()
    for artifact in artifacts:
        if not isinstance(artifact, dict):
            errors.append("artifact_must_be_object")
            continue
        destination = artifact.get("destination")
        if destination in seen:
            errors.append(f"artifact_duplicate:{destination}")
        seen.add(destination)
        if destination in DESTINATIONS:
            errors.extend(validate_artifact(artifact, destination, claims, revision))
        else:
            errors.append(f"artifact_destination_invalid:{destination}")
    expected = set(routing.get("destinations", []))
    if routing["status"] == "ready":
        missing = expected - seen
        extra = seen - expected
        errors.extend(f"artifact_missing:{value}" for value in sorted(missing))
        errors.extend(f"artifact_out_of_scope:{value}" for value in sorted(extra))
    return {
        "status": "blocked" if errors else "ready",
        "errors": errors,
        "route": routing,
        "artifact_count": len(artifacts),
        "claim_count": len(claims),
    }


def main() -> int:
    parser = argparse.ArgumentParser(prog="jevify-writing")
    parser.add_argument("command", choices=("route", "plan", "validate"))
    parser.add_argument("input", type=Path)
    args = parser.parse_args()
    try:
        value = load(str(args.input))
    except ValueError as error:
        return fail(str(error))
    if args.command == "route":
        print(json.dumps(route(value), ensure_ascii=False, sort_keys=True))
        return 0
    if args.command == "plan":
        result = plan(value)
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return 0 if result["status"] == "ready" else 1
    result = validate(value)
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if result["status"] == "ready" else 1


if __name__ == "__main__":
    sys.exit(main())
