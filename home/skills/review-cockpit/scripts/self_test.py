#!/usr/bin/env python3
"""Run isolated HTTP/CLI regressions; optionally inspect a live workspace read-only."""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import http.client
import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from typing import Any

from cockpit import builder, load_json, save_json, validate
from server import CockpitHTTPServer, ReportHandler

SCRIPTS = Path(__file__).resolve().parent
LIVE_ROOT: Path | None = None


def cli(*arguments: str) -> str:
    result = subprocess.run(
        [sys.executable, str(SCRIPTS / "cockpit.py"), *arguments],
        capture_output=True,
        text=True,
        check=True,
        timeout=60,
    )
    return result.stdout


def fixture() -> dict[str, Any]:
    questions = [
        {
            "id": "q1",
            "question": "Which payment policy?",
            "options": [
                {"id": "strict", "label": "Strict payments", "description": "Reject mismatches"},
                {"id": "relaxed", "label": "Flexible payments", "description": "Allow exceptions"},
            ],
        },
        {
            "id": "q2",
            "question": "Which audit policy?",
            "options": [
                {"id": "audit", "label": "Record an audit trail", "description": "Keep evidence"},
                {"id": "minimal", "label": "Minimal audit", "description": "Retain summaries"},
            ],
        },
    ]
    return {
        "repo": "acme/widget-engine",
        "base_branch": "trunk",
        "base_sha": "base123",
        "latest_release": {"tag": "v1.2.3", "publishedAt": None, "url": None},
        "items": [
            {
                "number": 1,
                "type": "issue",
                "title": "Payments",
                "area": "payments",
                "status": {
                    "state": "awaiting_decision",
                    "decisions": questions,
                    "summary": "password=hidden at /home/person/private",
                },
            },
            {
                "number": 2,
                "type": "pr",
                "title": "Auth merged",
                "area": "auth",
                "status": {"state": "merged", "merge_result": {"state": "merged"}},
            },
            {
                "number": 3,
                "type": "issue",
                "title": "Billing closed",
                "area": " billing_ui",
                "status": {"state": "closed"},
            },
            {
                "number": 4,
                "type": "issue",
                "title": "Awaiting owner",
                "area": "auth",
                "status": {"state": "awaiting_decision"},
            },
            {
                "number": 5,
                "type": "issue",
                "title": "Synthetic QA",
                "area": "payments",
                "status": {"state": "awaiting_decision"},
            },
            {
                "number": 6,
                "type": "pr",
                "title": "Verified ready",
                "area": "general",
                "head": "head6",
                "status": {"state": "ready", "current_head": "head6"},
            },
            {
                "number": 7,
                "type": "pr",
                "title": "Unverified ready",
                "area": "general",
                "head": "head7",
                "status": {"state": "ready", "current_head": "head7"},
            },
        ],
    }


class CockpitRegression(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="review-cockpit-test-")
        self.addCleanup(self.temporary.cleanup)
        scratch = Path(self.temporary.name)
        self.root = scratch / "workspace"
        items = scratch / "items.json"
        save_json(items, fixture())
        result = json.loads(
            cli(
                "init",
                "--root",
                str(self.root),
                "--items-json",
                str(items),
                "--repo",
                "acme/widget-engine",
            )
        )
        self.assertTrue(result["ok"])
        save_json(
            self.root / "decisions.json",
            {
                "version": 1,
                "decisions": {
                    "group-5": {
                        "action": "approve",
                        "synthetic": True,
                        "marker": "keep-me",
                        "mergeAuthorization": False,
                        "answers": {},
                    },
                },
            },
            overwrite=True,
        )
        for kind in ("qa", "review"):
            save_json(
                self.root / "groups" / "group-6" / f"{kind}.json",
                {
                    "state": "passed",
                    "executed": True,
                    "independent": kind == "review",
                    "head": "head6",
                },
            )
            save_json(
                self.root / "groups" / "group-7" / f"{kind}.json",
                {
                    "state": "passed",
                    "executed": True,
                    "independent": True,
                    "head": "old-head",
                },
            )
        self.http = CockpitHTTPServer(("127.0.0.1", 0), ReportHandler)
        self.port = self.http.server_address[1]
        self.host = f"127.0.0.1:{self.port}"
        self.http.config = {
            "builder": builder(self.root),
            "web_root": self.root / "web",
            "evidence_root": self.root / "evidence",
            "decisions_path": self.root / "decisions.json",
            "allowed_hosts": {self.host},
        }
        self.thread = threading.Thread(target=self.http.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop_server)

    def stop_server(self) -> None:
        self.http.shutdown()
        self.http.server_close()
        self.thread.join(timeout=5)

    def request(
        self,
        method: str,
        path: str,
        payload: Any = None,
        headers: dict[str, str] | None = None,
    ) -> tuple[int, Any]:
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        data = json.dumps(payload).encode() if payload is not None else None
        request_headers = {"Host": self.host, **(headers or {})}
        if data is not None:
            request_headers["Content-Type"] = "application/json"
        try:
            connection.request(method, path, body=data, headers=request_headers)
            response = connection.getresponse()
            raw = response.read()
            value = (
                json.loads(raw)
                if "application/json" in response.getheader("Content-Type", "")
                else raw
            )
            return response.status, value
        finally:
            connection.close()

    def post(
        self,
        question: str | None = None,
        option: str | None = None,
        action: str = "approve",
        group: str = "group-1",
    ) -> dict[str, Any]:
        status, result = self.request(
            "POST",
            "/api/decisions",
            {
                "groupId": group,
                "action": action,
                "decisionId": question,
                "optionId": option,
                "note": "Owner decision",
            },
        )
        self.assertEqual(status, 200, result)
        self.assertIs(result["decision"]["mergeAuthorization"], False)
        return result["decision"]

    def answers(self) -> dict[str, Any]:
        return load_json(self.root / "decisions.json")["decisions"]["group-1"]["answers"]

    def test_report_security_and_initial_handoff(self) -> None:
        status, html = self.request("GET", "/")
        self.assertEqual(status, 200)
        self.assertIn(b"<html", html.lower())
        status, report = self.request("GET", "/api/report")
        self.assertEqual(status, 200)
        self.assertEqual(report["repository"], "acme/widget-engine")
        self.assertEqual(report["baseBranch"], "trunk")
        self.assertEqual(report["baseSha"], "base123")
        self.assertEqual(report["latestRelease"]["tag"], "v1.2.3")
        self.assertEqual(report["summary"]["completed"], 2)
        self.assertEqual(report["summary"]["active"], 5)
        self.assertEqual(report["summary"]["needsDecision"], 4)
        self.assertEqual(report["summary"]["ready"], 1)
        catalog = {area["id"]: area["label"] for area in report["areaCatalog"]}
        self.assertEqual(catalog["payments"], "payments")
        self.assertEqual(catalog["auth"], "auth")
        self.assertEqual(catalog["billing_ui"], "billing ui")
        self.assertNotIn("기타 영역", catalog.values())
        payment = report["groups"][0]
        self.assertNotIn("hidden", payment["what"])
        self.assertNotIn("/home/person", payment["what"])
        status, handoff = self.request("GET", "/api/handoff")
        self.assertEqual(status, 200)
        self.assertEqual(handoff["queue"], [])
        self.assertEqual(handoff["counts"]["undecidedCount"], 4)
        self.assertEqual(validate(self.root)["summary"], report["summary"])
        self.assertEqual(
            self.request("GET", "/api/report", headers={"Host": "evil.invalid"})[0], 403
        )
        self.assertEqual(
            self.request(
                "GET",
                "/api/report",
                headers={
                    "Origin": "https://evil.invalid",
                },
            )[0],
            403,
        )
        for path in ("/evidence/../run-contract.json", "/evidence/%2e%2e/run-contract.json"):
            self.assertEqual(self.request("GET", path)[0], 404)
        for payload in (
            {"groupId": "missing-group", "action": "defer"},
            {"groupId": "group-1", "action": "merge"},
            {"groupId": "group-1", "action": "approve"},
            {"groupId": "group-1", "action": "request_changes"},
            {"groupId": "group-1", "action": "add_info"},
            {"groupId": "group-1", "action": "approve", "decisionId": "q1", "optionId": "missing"},
        ):
            self.assertEqual(self.request("POST", "/api/decisions", payload)[0], 400)
        self.assertEqual(
            self.request(
                "POST",
                "/api/decisions",
                {
                    "groupId": "group-1",
                    "action": "defer",
                },
                {"Origin": "https://evil.invalid"},
            )[0],
            403,
        )
        self.assertEqual(
            self.request(
                "POST",
                "/api/decisions",
                {
                    "groupId": "group-1",
                    "action": "defer",
                    "note": "x" * 20000,
                },
            )[0],
            413,
        )
        outside = self.root / "evidence" / "outside.json"
        outside.symlink_to(self.root / "run-contract.json")
        self.assertEqual(self.request("GET", "/evidence/outside.json")[0], 404)

    def test_multi_question_atomic_merge_and_handoff(self) -> None:
        self.post("q1", "strict")
        self.post("q2", "audit")
        saved = self.answers()
        self.assertEqual(set(saved), {"q1", "q2"})
        self.post(action="defer")
        self.assertEqual(self.answers(), saved)
        self.post("q1", "relaxed")
        self.assertEqual(self.answers()["q2"], saved["q2"])
        self.assertEqual(self.answers()["q1"]["optionId"], "relaxed")
        saved = self.answers()
        synthetic_before = load_json(self.root / "decisions.json")["decisions"]["group-5"]
        self.post("q1", "relaxed", action="add_info")
        self.assertEqual(self.answers()["q2"], saved["q2"])
        self.assertEqual(self.answers()["q1"]["optionId"], "relaxed")
        self.assertEqual(
            load_json(self.root / "decisions.json")["decisions"]["group-5"], synthetic_before
        )
        self.post(action="add_info", group="group-5")
        marker = load_json(self.root / "decisions.json")["decisions"]["group-5"]
        self.assertIs(marker["synthetic"], True)
        self.assertEqual(marker["marker"], "keep-me")
        self.post(action="approve", group="group-5")
        promoted = load_json(self.root / "decisions.json")["decisions"]["group-5"]
        self.assertNotIn("synthetic", promoted)
        save_json(
            self.root / "decisions.json",
            {
                "version": 1,
                "decisions": {
                    **load_json(self.root / "decisions.json")["decisions"],
                    "group-5": synthetic_before,
                },
            },
            overwrite=True,
        )
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            futures = [
                pool.submit(self.post, "q1", "strict"),
                pool.submit(self.post, "q2", "audit"),
            ]
            for future in futures:
                future.result(timeout=10)
        self.assertEqual(self.answers()["q1"]["optionId"], "strict")
        self.assertEqual(self.answers()["q2"]["optionId"], "audit")
        status, handoff = self.request("GET", "/api/handoff")
        self.assertEqual(status, 200)
        self.assertEqual([item["groupId"] for item in handoff["queue"]], ["group-1"])
        self.assertEqual(handoff["counts"]["approvedCount"], 1)
        self.assertEqual(handoff["counts"]["undecidedCount"], 3)
        labels = {answer["optionLabel"] for answer in handoff["queue"][0]["answers"]}
        self.assertEqual(labels, {"Strict payments", "Record an audit trail"})
        cli_handoff = json.loads(cli("handoff", "--root", str(self.root), "--format", "json"))
        self.assertEqual(cli_handoff["queue"], handoff["queue"])
        prompt = cli("handoff", "--root", str(self.root), "--format", "prompt")
        env_run = subprocess.run(
            [
                sys.executable,
                str(SCRIPTS / "cockpit.py"),
                "handoff",
                "--format",
                "prompt",
            ],
            capture_output=True,
            text=True,
            check=True,
            timeout=30,
            env={**os.environ, "REVIEW_COCKPIT_ROOT": str(self.root)},
        )
        self.assertEqual(env_run.stdout, prompt)
        self.assertIn("Strict payments", prompt)
        self.assertIn("Record an audit trail", prompt)
        self.assertIn("acme/widget-engine", prompt)
        self.assertNotIn("Synthetic QA — 승인", prompt)
        self.assertTrue(json.loads(cli("validate", "--root", str(self.root)))["ok"])
        wildcard = subprocess.run(
            [
                sys.executable,
                str(SCRIPTS / "cockpit.py"),
                "serve",
                "--root",
                str(self.root),
                "--bind",
                "0.0.0.0",
                "--port",
                "8788",
            ],
            capture_output=True,
            text=True,
            check=False,
            timeout=15,
        )
        self.assertNotEqual(wildcard.returncode, 0)

    def test_legacy_migration_and_refresh_preserves_records(self) -> None:
        document = load_json(self.root / "decisions.json")
        document["decisions"]["group-1"] = {
            "action": "approve",
            "decisionId": "q1",
            "optionId": "strict",
            "savedAt": "earlier",
            "mergeAuthorization": False,
            "customField": "preserve",
        }
        save_json(self.root / "decisions.json", document, overwrite=True)
        self.post("q2", "audit")
        record = load_json(self.root / "decisions.json")["decisions"]["group-1"]
        self.assertEqual(record["answers"]["q1"]["optionId"], "strict")
        self.assertEqual(record["answers"]["q2"]["optionId"], "audit")
        self.assertNotIn("decisionId", record)
        self.assertEqual(record["customField"], "preserve")
        paths = [self.root / "decisions.json", self.root / "groups" / "group-1" / "status.json"]
        before = [path.read_bytes() for path in paths]
        cli("init", "--root", str(self.root), "--from-workspace", str(self.root))
        self.assertEqual([path.read_bytes() for path in paths], before)

    def test_import_and_active_handoff(self) -> None:
        self.post(action="defer", group="group-2")
        all_records = json.loads(cli("handoff", "--root", str(self.root), "--format", "json"))
        self.assertEqual(all_records["counts"]["decidedCount"], 1)
        active = json.loads(
            cli(
                "handoff",
                "--root",
                str(self.root),
                "--format",
                "json",
                "--only-active",
            )
        )
        self.assertEqual(active["queue"], [])
        self.assertEqual(active["counts"]["decidedCount"], 0)
        cloned = self.root.parent / "cloned"
        cli("init", "--root", str(cloned), "--from-workspace", str(self.root))
        self.assertEqual(
            load_json(cloned / "decisions.json"), load_json(self.root / "decisions.json")
        )
        self.assertEqual(builder(cloned).build()["groups"][0]["items"][0]["title"], "Payments")
        self.assertTrue(validate(cloned)["ok"])

    def test_harness_activity_detection_and_cli(self) -> None:
        cli(
            "activity",
            "--root",
            str(self.root),
            "--group",
            "group-1",
            "--state",
            "working",
            "--harness",
            "claude-code",
            "--pid",
            str(os.getpid()),
        )
        cli(
            "activity",
            "--root",
            str(self.root),
            "--group",
            "group-4",
            "--state",
            "working",
        )
        cli(
            "activity",
            "--root",
            str(self.root),
            "--group",
            "group-6",
            "--state",
            "working",
            "--harness",
            "codex",
            "--pid",
            "99999999",
        )
        status, report = self.request("GET", "/api/report")
        self.assertEqual(status, 200)
        groups = {group["id"]: group for group in report["groups"]}
        self.assertTrue(groups["group-1"]["agentActivity"]["active"])
        self.assertEqual(groups["group-1"]["agentActivity"]["harnesses"], ["claude-code"])
        self.assertEqual(groups["group-1"]["agentActivity"]["label"], "Claude Code 작업 중")
        self.assertTrue(groups["group-4"]["agentActivity"]["active"])
        self.assertEqual(groups["group-4"]["agentActivity"]["harnesses"], ["unknown"])
        self.assertEqual(groups["group-4"]["agentActivity"]["label"], "작업 중")
        self.assertFalse(groups["group-6"]["agentActivity"]["active"])
        catalog = {entry["id"]: entry["label"] for entry in report["harnessCatalog"]}
        self.assertEqual(catalog.get("claude-code"), "Claude Code")
        self.assertEqual(catalog.get("unknown"), "하네스 미특정")
        cli("activity", "--root", str(self.root), "--group", "group-1", "--state", "idle")
        status, report_after = self.request("GET", "/api/report")
        self.assertEqual(status, 200)
        groups_after = {group["id"]: group for group in report_after["groups"]}
        self.assertFalse(groups_after["group-1"]["agentActivity"]["active"])
        self.post("q1", "strict")
        sub_status, sub_resp = self.request("POST", "/api/submit", {"note": "Ready to process"})
        self.assertEqual(sub_status, 200)
        self.assertIs(sub_resp["submission"]["submitted"], True)
        waited = cli("wait", "--root", str(self.root), "--timeout", "3", "--format", "prompt")
        self.assertIn("Ready to process", waited)
        self.assertIn("Strict payments", waited)
        self.post("q2", "audit")
        _, handoff_after_edit = self.request("GET", "/api/handoff")
        self.assertIs(handoff_after_edit["submission"]["submitted"], False)

    def test_validation_rejects_bad_schema(self) -> None:
        save_json(self.root / "decisions.json", {"decisions": []}, overwrite=True)
        with self.assertRaises(ValueError):
            validate(self.root)


class LiveReadOnlyRegression(unittest.TestCase):
    def test_live_commands_do_not_mutate_decisions(self) -> None:
        if LIVE_ROOT is None:
            self.skipTest("--live-root was not provided")
        root = LIVE_ROOT
        assert root is not None
        path = root / "decisions.json"
        before = hashlib.sha256(path.read_bytes()).hexdigest()
        try:
            self.assertTrue(json.loads(cli("validate", "--root", str(root)))["ok"])
            self.assertIn(
                "summary", json.loads(cli("status", "--root", str(root), "--format", "json"))
            )
            handoff = json.loads(cli("handoff", "--root", str(root), "--format", "json"))
            self.assertIn("resumePrompt", handoff)
            self.assertTrue(cli("handoff", "--root", str(root), "--format", "prompt"))
        finally:
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), before)


def main() -> None:
    global LIVE_ROOT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--live-root", type=Path)
    parser.add_argument("--root", type=Path)
    args, remaining = parser.parse_known_args()
    target_root = args.live_root or args.root
    LIVE_ROOT = target_root.resolve() if target_root else None
    unittest.main(argv=[sys.argv[0], *remaining])


if __name__ == "__main__":
    main()
