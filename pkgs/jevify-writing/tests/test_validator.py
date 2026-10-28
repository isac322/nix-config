#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import unittest
from pathlib import Path

SOURCE = Path(__file__).parents[1] / "src" / "jevify-writing.py"
SPEC = importlib.util.spec_from_file_location("jevify_writing", SOURCE)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ValidatorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.task = {
            "destinations": ["github_pr", "linear", "beardrive"],
            "mode": "compose",
            "revision": "rev-a",
            "current_revision": "rev-a",
            "claims": [
                {
                    "id": "request-1",
                    "kind": "request",
                    "status": "unknown",
                    "source_refs": ["task"],
                },
                {
                    "id": "observed-1",
                    "kind": "observation",
                    "status": "supported",
                    "source_refs": ["test"],
                },
                {
                    "id": "unknown-1",
                    "kind": "unknown",
                    "status": "unknown",
                    "source_refs": ["scope"],
                },
            ],
        }

    def artifact(self, destination: str, claim_id: str, assertive: bool) -> dict[str, object]:
        return {
            "destination": destination,
            "revision": "rev-a",
            "status": "ready",
            "title": destination,
            "sections": [
                {
                    "heading": "Summary",
                    "text": "A source-backed statement.",
                    "claim_ids": [claim_id],
                    "assertive": assertive,
                }
            ],
        }

    def test_ambiguous_destination_blocks(self) -> None:
        result = MODULE.route({"mode": "compose", "destinations": []})
        self.assertEqual(result["status"], "blocked")
        self.assertEqual(result["reason"], "destination_missing")

    def test_unknown_destination_blocks(self) -> None:
        result = MODULE.route({"mode": "compose", "destinations": ["notion"]})
        self.assertEqual(result["status"], "blocked")
        self.assertEqual(result["reason"], "destination_unsupported")

    def test_plan_returns_destination_contracts(self) -> None:
        result = MODULE.plan(self.task)
        self.assertEqual(result["status"], "ready")
        self.assertEqual(len(result["destinations"]), 3)
        self.assertEqual(result["destinations"][0]["sections"], ["Summary", "Changes", "Validation", "Not verified"])

    def test_valid_bundle_passes(self) -> None:
        bundle = {
            "task": self.task,
            "artifacts": [self.artifact(destination, "observed-1", True) for destination in self.task["destinations"]],
        }
        result = MODULE.validate(bundle)
        self.assertEqual(result["status"], "ready")
        self.assertEqual(result["errors"], [])

    def test_stale_revision_blocks(self) -> None:
        stale = dict(self.task, current_revision="rev-b")
        result = MODULE.validate({"task": stale, "artifacts": []})
        self.assertEqual(result["status"], "blocked")
        self.assertIn("stale_revision", result["errors"])

    def test_request_cannot_be_asserted(self) -> None:
        artifact = self.artifact("github_pr", "request-1", True)
        result = MODULE.validate({"task": dict(self.task, destinations=["github_pr"]), "artifacts": [artifact]})
        self.assertEqual(result["status"], "blocked")
        self.assertIn("claim_not_supported:github_pr:request-1", result["errors"])

    def test_beardrive_markup_is_rejected(self) -> None:
        artifact = self.artifact("beardrive", "observed-1", True)
        artifact["sections"][0]["text"] = "<script>publish()</script>"
        result = MODULE.validate({"task": dict(self.task, destinations=["beardrive"]), "artifacts": [artifact]})
        self.assertEqual(result["status"], "blocked")
        self.assertIn("renderer_boundary_violation:beardrive", result["errors"])


if __name__ == "__main__":
    unittest.main()
