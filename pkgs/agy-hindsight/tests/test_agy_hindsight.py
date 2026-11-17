import importlib.util
import io
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("agy_hindsight", Path(__file__).parents[1] / "src/agy_hindsight.py")
h = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(h)


def git(*args, cwd):
    subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True,
                   env={**os.environ, "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1",
                        "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
                        "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"})


def event(kind, content, source="MODEL", created="2026-11-17T00:00:00Z"):
    return json.dumps({"type": kind, "source": source, "content": content, "created_at": created})


def user(text):
    return event("USER_INPUT", f"<USER_REQUEST>\n{text}\n</USER_REQUEST>\n<ADDITIONAL_METADATA>\ntime\n</ADDITIONAL_METADATA>",
                 source="USER_EXPLICIT")


def assistant(text):
    return event("PLANNER_RESPONSE", text)


class FakeHindsight:
    """Records requests and answers like the Hindsight REST API."""

    def __init__(self, models=None, results=None):
        self.calls = []
        self.models = models or []
        self.results = results or []

    def __call__(self, cfg, method, path, body, timeout):
        self.calls.append((method, path, body))
        if path.startswith("/mental-models"):
            return {"items": self.models, "total": len(self.models)}
        if path == "/memories/recall":
            return {"results": self.results}
        if path == "/reflect":
            return {"text": "synthesis"}
        return {}


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.cfg = h.Config({"AGY_HINDSIGHT_API_URL": "http://hs", "AGY_HINDSIGHT_GLOBAL_SCOPE": "1",
                             "AGY_HINDSIGHT_STATE_DIR": str(self.root / "state")})

    def tearDown(self):
        self.tmp.cleanup()

    def transcript(self, *lines):
        path = self.root / "transcript_full.jsonl"
        path.write_text("\n".join(lines) + "\n")
        return str(path)


class ProjectLabel(Base):
    def test_linked_worktree_shares_primary_checkout_tag(self):
        main = self.root / "My-Repo"
        main.mkdir()
        git("init", "-q", cwd=main)
        git("commit", "-q", "--allow-empty", "-m", "x", cwd=main)
        git("worktree", "add", "-q", str(self.root / "wt-feature"), cwd=main)
        (main / "sub").mkdir()
        self.assertEqual(h.project_tags(str(main / "sub")), ["project:my-repo"])
        self.assertEqual(h.project_tags(str(self.root / "wt-feature")), ["project:my-repo"])

    def test_bare_repository_worktree_uses_bare_directory(self):
        seed = self.root / "seed"
        seed.mkdir()
        git("init", "-q", cwd=seed)
        git("commit", "-q", "--allow-empty", "-m", "x", cwd=seed)
        git("clone", "-q", "--bare", str(seed), str(self.root / "Hub.git"), cwd=self.root)
        git("worktree", "add", "-q", str(self.root / "co"), cwd=self.root / "Hub.git")
        self.assertEqual(h.project_label(str(self.root / "co")), "hub.git")

    def test_outside_repository_uses_directory_name(self):
        plain = self.root / "Scratch"
        plain.mkdir()
        self.assertEqual(h.project_label(str(plain)), "scratch")


class TranscriptParsing(Base):
    def test_unwraps_prompts_and_counts_only_explicit_user_turns(self):
        t = h.read_transcript(self.transcript(
            user("first ask"),
            event("SYSTEM_MESSAGE", "hook text", source="SYSTEM_SDK"),
            assistant(""),
            assistant("answer <memories>old</memories>"),
            user("second"),
        ))
        self.assertEqual(t.user_turns, 2)
        self.assertEqual([m["content"] for m in t.messages], ["first ask", "answer", "second"])
        self.assertFalse(t.injected)

    def test_subagent_conversation_has_no_user_turns(self):
        t = h.read_transcript(self.transcript(
            event("SYSTEM_MESSAGE", "delegated task", source="SYSTEM"), assistant("done")))
        self.assertEqual(t.user_turns, 0)


class PreInvocation(Base):
    def payload(self, path, invocation=0):
        return {"invocationNum": invocation, "transcriptPath": path, "workspacePaths": [str(self.root)]}

    def test_first_call_injects_scoped_models_and_project_recall(self):
        fake = FakeHindsight(
            models=[
                {"name": "User Preferences", "content": "prefers Korean", "tags": []},
                {"name": "Project Decisions", "content": "use nix", "tags": [f"project:{self.root.name.lower()}"]},
                {"name": "Project Decisions", "content": "other repo", "tags": ["project:elsewhere"]},
            ],
            results=[{"text": "fact one", "type": "world", "mentioned_at": "2026-11-01"}],
        )
        with patch.object(h, "_request", fake):
            out = h.pre_invocation(self.payload(self.transcript(user("how do we deploy?"))), self.cfg)
        text = out["injectSteps"][0]["systemMessage"]["systemMessage"]
        self.assertIn("prefers Korean", text)
        self.assertIn("use nix", text)
        self.assertNotIn("other repo", text)
        self.assertIn("- fact one [world] (2026-11-01)", text)
        recall_body = next(b for m, p, b in fake.calls if p == "/memories/recall")
        self.assertEqual(recall_body["query"], "how do we deploy?")
        self.assertEqual(recall_body["tags"], [f"project:{self.root.name.lower()}"])
        self.assertEqual(recall_body["tags_match"], "any")

    def test_injects_once_per_conversation(self):
        fake = FakeHindsight(results=[{"text": "x"}])
        with patch.object(h, "_request", fake):
            first_turn = self.transcript(user("q"))
            self.assertEqual(h.pre_invocation(self.payload(first_turn, invocation=1), self.cfg), {})
            already = self.transcript(user("q"), event("SYSTEM_MESSAGE", "<memories>x</memories>", "SYSTEM_SDK"))
            self.assertEqual(h.pre_invocation(self.payload(already), self.cfg), {})
            second_turn = self.transcript(user("q"), assistant("a"), user("next"))
            self.assertEqual(h.pre_invocation(self.payload(second_turn), self.cfg), {})
            subagent = self.transcript(event("SYSTEM_MESSAGE", "task", "SYSTEM"))
            self.assertEqual(h.pre_invocation(self.payload(subagent), self.cfg), {})
        self.assertEqual(fake.calls, [])

    def test_server_failure_injects_nothing(self):
        def down(*_):
            raise h.HindsightError("down")
        with patch.object(h, "_request", down):
            self.assertEqual(h.pre_invocation(self.payload(self.transcript(user("q"))), self.cfg), {})


class Retain(Base):
    def test_stop_retains_every_third_user_turn_with_full_session(self):
        spawned = []
        lines = [user("a"), assistant("1"), user("b"), assistant("2")]
        payload = {"conversationId": "c1", "transcriptPath": self.transcript(*lines),
                   "workspacePaths": [str(self.root)]}
        h.stop(payload, self.cfg, spawn=spawned.append)
        self.assertEqual(spawned, [])
        payload["transcriptPath"] = self.transcript(*lines, user("c"), assistant("3"))
        h.stop(payload, self.cfg, spawn=spawned.append)
        self.assertEqual(len(spawned), 1)

        fake = FakeHindsight()
        with patch.object(h, "_request", fake):
            h.retain_session(self.cfg, *spawned[0][1:])
        method, path, body = fake.calls[0]
        item = body["items"][0]
        self.assertEqual((method, path, body["async"]), ("POST", "/memories", True))
        self.assertEqual(item["document_id"], "c1")
        self.assertEqual(item["tags"], [f"project:{self.root.name.lower()}"])
        self.assertEqual(item["context"], "agy")
        self.assertIn("[role: user]\n[timestamp: 2026-11-17T00:00:00Z]\nc\n[user:end]", item["content"])

        spawned.clear()
        h.stop(payload, self.cfg, spawn=spawned.append)
        self.assertEqual(spawned, [], "the same three turns are not retained twice")

    def test_failed_retain_is_retried_on_next_stop(self):
        payload = {"conversationId": "c2", "transcriptPath": self.transcript(user("a"), user("b"), user("c")),
                   "workspacePaths": [str(self.root)]}

        def down(*_):
            raise h.HindsightError("down")
        with patch.object(h, "_request", down), self.assertRaises(h.HindsightError):
            h.retain_session(self.cfg, "c2", payload["transcriptPath"], str(self.root))
        spawned = []
        h.stop(payload, self.cfg, spawn=spawned.append)
        self.assertEqual(len(spawned), 1)


class Mcp(Base):
    def run_mcp(self, messages, enabled=True):
        out = io.StringIO()
        stdin = io.StringIO("".join(json.dumps(m) + "\n" for m in messages))
        h.serve_mcp(self.cfg, enabled, stdin=stdin, stdout=out)
        return [json.loads(line) for line in out.getvalue().splitlines()]

    def call(self, name, arguments, enabled=True):
        return self.run_mcp([{"jsonrpc": "2.0", "id": 1, "method": "tools/call",
                              "params": {"name": name, "arguments": arguments}}], enabled)[0]["result"]

    def test_lists_omp_memory_tools(self):
        replies = self.run_mcp([
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18"}},
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
        ])
        self.assertEqual(replies[0]["result"]["protocolVersion"], "2025-06-18")
        self.assertEqual([t["name"] for t in replies[1]["result"]["tools"]], ["recall", "retain", "reflect"])

    def test_tools_scope_to_client_workspace_root_not_server_cwd(self):
        workspace = self.root / "Client-Repo"
        workspace.mkdir()
        fake = FakeHindsight()
        with patch.object(h, "_request", fake), patch.object(h.os, "getcwd", return_value="/plugins/nix-managed"):
            replies = self.run_mcp([
                {"jsonrpc": "2.0", "id": 1, "method": "initialize",
                 "params": {"capabilities": {"roots": {"listChanged": True}}}},
                {"jsonrpc": "2.0", "method": "notifications/initialized"},
                {"jsonrpc": "2.0", "id": "roots-1", "result": {"roots": [{"uri": workspace.as_uri()}]}},
                {"jsonrpc": "2.0", "id": 2, "method": "tools/call",
                 "params": {"name": "retain", "arguments": {"items": [{"content": "fact"}]}}},
            ])
        self.assertEqual(replies[1], {"jsonrpc": "2.0", "id": "roots-1", "method": "roots/list"})
        self.assertEqual(fake.calls[0][2]["items"][0]["tags"], ["project:client-repo"])

    def test_retain_scopes_project_and_global_items(self):
        fake = FakeHindsight()
        with patch.object(h, "_request", fake), patch.object(h.os, "getcwd", return_value=str(self.root)):
            result = self.call("retain", {"items": [{"content": "repo fact"},
                                                    {"content": "user likes tea", "scope": "global"}]})
        self.assertEqual(result["content"][0]["text"], "2 memories queued.")
        items = fake.calls[0][2]["items"]
        self.assertEqual(items[0]["tags"], [f"project:{self.root.name.lower()}"])
        self.assertNotIn("tags", items[1])

    def test_global_retain_rejected_when_global_scope_off(self):
        self.cfg.global_scope = False
        fake = FakeHindsight()
        with patch.object(h, "_request", fake):
            result = self.call("retain", {"items": [{"content": "x", "scope": "global"}]})
        self.assertTrue(result["isError"])
        self.assertEqual(fake.calls, [])

    def test_recall_and_reflect_are_project_scoped(self):
        fake = FakeHindsight(results=[{"text": "fact", "type": "experience"}])
        with patch.object(h, "_request", fake), patch.object(h.os, "getcwd", return_value=str(self.root)):
            recalled = self.call("recall", {"query": "q"})["content"][0]["text"]
            reflected = self.call("reflect", {"query": "q", "context": "c"})["content"][0]["text"]
        self.assertIn("Found 1 relevant memory", recalled)
        self.assertEqual(reflected, "synthesis")
        for _, _, body in fake.calls:
            self.assertEqual(body["tags"], [f"project:{self.root.name.lower()}"])
            self.assertEqual(body["tags_match"], "any")

    def test_agent_started_run_exposes_no_tools(self):
        replies = self.run_mcp([{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}], enabled=False)
        self.assertEqual(replies[0]["result"]["tools"], [])


class NestedGuard(unittest.TestCase):
    def test_agent_started_runs_disable_memory(self):
        self.assertTrue(h.memory_enabled({}))
        self.assertFalse(h.memory_enabled({"PI_SESSION_FILE": "/x"}))
        self.assertFalse(h.memory_enabled({"ANTIGRAVITY_AGENT": "1"}))
        self.assertTrue(h.memory_enabled({"ANTIGRAVITY_AGENT": "1", "AGY_NESTED_MEMORY": "1"}))


class MentalModelBudget(unittest.TestCase):
    def test_render_stays_within_budget_and_marks_truncation(self):
        models = [{"name": f"M{i}", "content": "x" * 5000} for i in range(5)]
        block = h.render_mental_models(models, budget=4000)
        self.assertLessEqual(len(block), 4000)
        self.assertTrue(block.startswith("<mental_models>\n# M0\n"))
        self.assertIn("truncated at render budget", block)
        self.assertTrue(block.endswith("</mental_models>"))


if __name__ == "__main__":
    unittest.main()
