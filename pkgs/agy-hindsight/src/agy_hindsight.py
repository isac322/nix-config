#!/usr/bin/env python3
"""Hindsight long-term memory for the Antigravity CLI (agy), scoped like OMP.

OMP runs Hindsight in `per-project-tagged` mode: every agent writes to one
shared bank, project-scoped writes carry a `project:<name>` tag, and recall
filters on that tag with `tags_match: any`, so untagged ("global") memories
surface in every project. The project name is the lowercased basename of the
repository's primary checkout, so every linked worktree of a repository shares
one tag. This program reproduces that contract for agy so both agents read and
write the same memories:

  hook pre-invocation   first model call of a conversation: inject the
                        project's mental models and a recall for the prompt
  hook stop             every third user turn: retain the whole conversation
  retain-session ...    background worker the stop hook detaches
  mcp                   stdio MCP server with OMP's retain/recall/reflect tools

Runs that another agent started (OMP sets PI_SESSION_FILE, agy sets
ANTIGRAVITY_AGENT=1 for its commands) keep memory off, like OMP's launcher;
AGY_NESTED_MEMORY=1 turns it back on.
"""

from __future__ import annotations

import concurrent.futures
import datetime as dt
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path, PurePath

# OMP's Hindsight defaults (packages/coding-agent/src/hindsight/settings.ts).
RECALL_BUDGET = "mid"
RECALL_MAX_TOKENS = 1024
RECALL_TYPES = ["world", "experience"]
RECALL_MAX_QUERY_CHARS = 800
RETAIN_EVERY_N_TURNS = 3
MENTAL_MODEL_BUDGET_CHARS = 16_000
TAGS_MATCH = "any"
PREAMBLE = (
    "Relevant memories from past conversations (prioritize recent when conflicting). "
    "Only use memories that are directly useful to continue this conversation; ignore the rest:"
)
# `context` names the writer for Hindsight's extraction; OMP sends "omp".
RETAIN_CONTEXT = "agy"
PROJECT_TAG_PREFIX = "project:"

# The PreInvocation hook runs under a 30 s agy timeout; recall alone can take ~10 s.
RECALL_TIMEOUT_S = 25
REQUEST_TIMEOUT_S = 30
RETAIN_TIMEOUT_S = 60
REFLECT_TIMEOUT_S = 120

MEMORY_BLOCK_RE = re.compile(r"<memories>[\s\S]*?</memories>|<mental_models>[\s\S]*?</mental_models>")
USER_REQUEST_RE = re.compile(r"<USER_REQUEST>([\s\S]*?)</USER_REQUEST>")
AGY_WRAPPER_RE = re.compile(r"<(ADDITIONAL_METADATA|USER_SETTINGS_CHANGE)>[\s\S]*?</\1>")
SUBSTANTIVE_RE = re.compile(r"[^\W_]")
TRUNCATION_MARKER = "\n\n…[mental-model snapshot truncated at render budget]"


class Config:
    def __init__(self, env: dict[str, str]):
        self.api_url = env.get("AGY_HINDSIGHT_API_URL", "").rstrip("/")
        self.bank = env.get("AGY_HINDSIGHT_BANK", "omp")
        # Same variable OMP reads; the wrapper fills it from the machine's secret store.
        self.token = env.get("HINDSIGHT_API_TOKEN", "")
        self.global_scope = env.get("AGY_HINDSIGHT_GLOBAL_SCOPE") == "1"
        self.state_dir = Path(
            env.get("AGY_HINDSIGHT_STATE_DIR")
            or Path(env.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "agy-hindsight"
        )


def memory_enabled(env: dict[str, str]) -> bool:
    if env.get("AGY_NESTED_MEMORY") == "1":
        return True
    return "PI_SESSION_FILE" not in env and env.get("ANTIGRAVITY_AGENT") != "1"


# ---------------------------------------------------------------------------
# Project scope


def _git(directory: str, *args: str) -> str | None:
    try:
        result = subprocess.run(
            ["git", "-C", directory, *args], capture_output=True, text=True, timeout=5, check=False
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return result.stdout.strip() if result.returncode == 0 and result.stdout.strip() else None


def project_label(directory: str) -> str:
    """OMP's projectLabel(): primary checkout basename, lowercased."""
    if not directory:
        return "unknown"
    root = None
    common = _git(directory, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if common:
        if PurePath(common).name == ".git":
            root = str(PurePath(common).parent)
        elif _git(common, "rev-parse", "--is-bare-repository") == "true":
            root = common
        else:
            root = _git(directory, "rev-parse", "--show-toplevel")
    name = PurePath((root or directory).rstrip("/") or "/").name.lower()
    return name or "unknown"


def project_tags(directory: str) -> list[str]:
    return [PROJECT_TAG_PREFIX + project_label(directory)]


# ---------------------------------------------------------------------------
# Hindsight HTTP


class HindsightError(RuntimeError):
    pass


def _request(cfg: Config, method: str, path: str, body: dict | None, timeout: float):
    if not cfg.api_url:
        raise HindsightError("AGY_HINDSIGHT_API_URL is not set")
    data = None if body is None else json.dumps(body).encode()
    headers = {"content-type": "application/json", "accept": "application/json"}
    if cfg.token:
        headers["authorization"] = f"Bearer {cfg.token}"
    req = urllib.request.Request(
        f"{cfg.api_url}/v1/default/banks/{urllib.request.quote(cfg.bank, safe='')}{path}",
        data=data,
        method=method,
        headers=headers,
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as err:
        detail = err.read().decode(errors="replace")[:500]
        raise HindsightError(f"{method} {path} -> HTTP {err.code}: {detail}") from err
    except (urllib.error.URLError, TimeoutError, OSError) as err:
        raise HindsightError(f"{method} {path} failed: {err}") from err
    return json.loads(raw) if raw else {}


def recall(cfg: Config, query: str, tags: list[str], timeout: float = REQUEST_TIMEOUT_S) -> list[dict]:
    body = {
        "query": query,
        "types": RECALL_TYPES,
        "max_tokens": RECALL_MAX_TOKENS,
        "budget": RECALL_BUDGET,
        "tags": tags,
        "tags_match": TAGS_MATCH,
    }
    return _request(cfg, "POST", "/memories/recall", body, timeout).get("results") or []


def reflect(cfg: Config, query: str, context: str | None, tags: list[str]) -> str:
    body = {"query": query, "budget": "low", "tags": tags, "tags_match": TAGS_MATCH}
    if context:
        body["context"] = context
    return (_request(cfg, "POST", "/reflect", body, REFLECT_TIMEOUT_S).get("text") or "").strip()


def retain(cfg: Config, items: list[dict]) -> None:
    _request(cfg, "POST", "/memories", {"items": items, "async": True}, RETAIN_TIMEOUT_S)


def list_mental_models(cfg: Config, timeout: float = REQUEST_TIMEOUT_S) -> list[dict]:
    models: list[dict] = []
    while True:
        page = _request(cfg, "GET", f"/mental-models?detail=content&limit=100&offset={len(models)}", None, timeout)
        items = page.get("items") or []
        models.extend(items)
        total = page.get("total")
        if not items or (isinstance(total, int) and len(models) >= total):
            return models


# ---------------------------------------------------------------------------
# Formatting (ports of OMP's hindsight/content.ts and mental-models.ts)


def strip_memory_tags(text: str) -> str:
    return MEMORY_BLOCK_RE.sub("", text)


def substantive(text: str) -> bool:
    return bool(SUBSTANTIVE_RE.search(text))


def format_memories(results: list[dict]) -> str:
    lines = []
    for r in results:
        type_str = f" [{r['type']}]" if r.get("type") else ""
        date_str = f" ({r['mentioned_at']})" if r.get("mentioned_at") else ""
        lines.append(f"- {r.get('text', '')}{type_str}{date_str}")
    return "\n\n".join(lines)


def memories_block(results: list[dict]) -> str:
    if not results:
        return ""
    return f"<memories>\n{PREAMBLE}\n\n{format_memories(results)}\n</memories>"


def truncate_recall_query(query: str) -> str:
    # recallContextTurns is 1 in OMP, so the query is only the latest prompt.
    query = query.strip()
    return query[:RECALL_MAX_QUERY_CHARS]


def _truncate_to(text: str, max_chars: int) -> str:
    if len(text) <= max_chars:
        return text
    if max_chars <= 1:
        return "…"
    return text[: max(0, max_chars - 1)] + "…"


def visible_mental_models(models: list[dict], tags: list[str]) -> list[dict]:
    visible = [
        m
        for m in models
        if isinstance(m.get("content"), str)
        and m["content"].strip()
        and (not m.get("tags") or any(t in tags for t in m["tags"]))
    ]
    return sorted(visible, key=lambda m: str(m.get("name", "")).casefold())


def render_mental_models(models: list[dict], budget: int = MENTAL_MODEL_BUDGET_CHARS) -> str:
    if not models:
        return ""
    clean_overhead = len("<mental_models>\n\n</mental_models>")
    if budget < clean_overhead + 64:
        return ""
    truncated_overhead = len(f"<mental_models>\n{TRUNCATION_MARKER}\n</mental_models>")
    inner = max(0, budget - truncated_overhead)
    headers = [f"# {m.get('name', '')}\n" for m in models]
    per_model = max(
        120, (inner - sum(map(len, headers)) - 2 * max(0, len(models) - 1)) // max(1, len(models))
    )
    sections: list[str] = []
    consumed = 0
    truncated = False
    for header, model in zip(headers, models):
        body = model["content"].strip()
        short = _truncate_to(body, per_model)
        truncated = truncated or len(short) < len(body)
        section = header + short
        cost = len(section) + (2 if sections else 0)
        if consumed + cost > inner and sections:
            truncated = True
            break
        sections.append(section)
        consumed += cost
    tail = TRUNCATION_MARKER if truncated else ""
    joined = "\n\n".join(sections)
    block = f"<mental_models>\n{joined}{tail}\n</mental_models>"
    if len(block) > budget:
        room = max(0, budget - (truncated_overhead if truncated else clean_overhead))
        body = "\n\n".join(sections)[:room].rstrip()
        block = f"<mental_models>\n{body}{TRUNCATION_MARKER}\n</mental_models>"
    return block


# ---------------------------------------------------------------------------
# agy transcript


class Transcript:
    """User and assistant text from agy's transcript_full.jsonl."""

    def __init__(self, messages: list[dict], user_turns: int, injected: bool):
        self.messages = messages
        self.user_turns = user_turns
        self.injected = injected

    @property
    def latest_prompt(self) -> str:
        for msg in reversed(self.messages):
            if msg["role"] == "user":
                return msg["content"]
        return ""


def _unwrap_user_request(text: str) -> str:
    match = USER_REQUEST_RE.search(text)
    return match.group(1) if match else AGY_WRAPPER_RE.sub("", text)


def read_transcript(path: str | None) -> Transcript:
    messages: list[dict] = []
    user_turns = 0
    injected = False
    try:
        lines = Path(path).read_text(encoding="utf-8").splitlines() if path else []
    except OSError:
        lines = []
    for line in lines:
        try:
            event = json.loads(line)
        except ValueError:
            continue
        content = event.get("content")
        if not isinstance(content, str):
            continue
        kind = event.get("type")
        if kind == "SYSTEM_MESSAGE":
            injected = injected or "<memories>" in content or "<mental_models>" in content
            continue
        # Subagent conversations have no USER_EXPLICIT input: their prompt is a
        # system message from the parent, so they count zero user turns.
        if kind == "USER_INPUT" and event.get("source") == "USER_EXPLICIT":
            role, text = "user", _unwrap_user_request(content)
        elif kind == "PLANNER_RESPONSE":
            role, text = "assistant", content
        else:
            continue
        text = strip_memory_tags(text).strip()
        if not substantive(text):
            continue
        if role == "user":
            user_turns += 1
        messages.append({"role": role, "content": text, "timestamp": event.get("created_at")})
    return Transcript(messages, user_turns, injected)


def retention_transcript(messages: list[dict]) -> str | None:
    parts = []
    for msg in messages:
        stamp = f"\n[timestamp: {msg['timestamp']}]" if msg.get("timestamp") else ""
        parts.append(f"[role: {msg['role']}]{stamp}\n{msg['content']}\n[{msg['role']}:end]")
    text = "\n\n".join(parts)
    return text if len(text.strip()) >= 10 else None


# ---------------------------------------------------------------------------
# Hooks


def session_directory(payload: dict) -> str:
    paths = payload.get("workspacePaths") or []
    return (paths[0] if paths else None) or payload.get("cwd") or os.getcwd()


def pre_invocation(payload: dict, cfg: Config) -> dict:
    if payload.get("invocationNum") != 0:
        return {}
    transcript = read_transcript(payload.get("transcriptPath"))
    if transcript.user_turns != 1 or transcript.injected:
        return {}
    tags = project_tags(session_directory(payload))
    query = truncate_recall_query(transcript.latest_prompt)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        models_job = pool.submit(list_mental_models, cfg, RECALL_TIMEOUT_S)
        recall_job = pool.submit(recall, cfg, query, tags, RECALL_TIMEOUT_S) if query else None
        blocks = []
        try:
            blocks.append(render_mental_models(visible_mental_models(models_job.result(), tags)))
        except HindsightError as err:
            log(cfg, f"mental models: {err}")
        if recall_job is not None:
            try:
                blocks.append(memories_block(recall_job.result()))
            except HindsightError as err:
                log(cfg, f"recall: {err}")
    text = "\n\n".join(b for b in blocks if b)
    if not text:
        return {}
    return {"injectSteps": [{"systemMessage": {"systemMessage": text}}]}


def _state_path(cfg: Config, conversation_id: str) -> Path:
    return cfg.state_dir / "conversations" / f"{conversation_id}.json"


def last_retained_turn(cfg: Config, conversation_id: str) -> int:
    try:
        return int(json.loads(_state_path(cfg, conversation_id).read_text()).get("lastRetainedTurn", 0))
    except (OSError, ValueError, AttributeError):
        return 0


def stop(payload: dict, cfg: Config, spawn=None) -> dict:
    conversation_id = payload.get("conversationId")
    path = payload.get("transcriptPath")
    if not conversation_id or not path:
        return {}
    transcript = read_transcript(path)
    if transcript.user_turns - last_retained_turn(cfg, conversation_id) < RETAIN_EVERY_N_TURNS:
        return {}
    args = ["retain-session", conversation_id, path, session_directory(payload)]
    (spawn or _detach)(args)
    return {}


def _detach(args: list[str]) -> None:
    # Hooks block agy's loop, so the HTTP write runs in its own session.
    subprocess.Popen(
        [sys.argv[0], *args],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def retain_session(cfg: Config, conversation_id: str, path: str, directory: str) -> None:
    transcript = read_transcript(path)
    if not transcript.user_turns:
        return
    content = retention_transcript(transcript.messages)
    if not content:
        return
    item = {
        "content": content,
        "document_id": conversation_id,
        "context": RETAIN_CONTEXT,
        "metadata": {"session_id": conversation_id},
        "tags": project_tags(directory),
    }
    if transcript.messages[0].get("timestamp"):
        item["timestamp"] = transcript.messages[0]["timestamp"]
    retain(cfg, [item])
    state = _state_path(cfg, conversation_id)
    state.parent.mkdir(parents=True, exist_ok=True)
    tmp = state.with_suffix(".tmp")
    tmp.write_text(json.dumps({"lastRetainedTurn": transcript.user_turns}))
    tmp.replace(state)


def log(cfg: Config, message: str) -> None:
    try:
        cfg.state_dir.mkdir(parents=True, exist_ok=True)
        stamp = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
        with open(cfg.state_dir / "errors.log", "a", encoding="utf-8") as fh:
            fh.write(f"{stamp} {message}\n")
    except OSError:
        pass


# ---------------------------------------------------------------------------
# MCP server


def tool_definitions(cfg: Config) -> list[dict]:
    item_props = {
        "content": {"type": "string", "description": "self-contained fact"},
        "context": {"type": "string", "description": "source context"},
    }
    retain_desc = (
        "Store ≥1 fact in long-term memory for future sessions.\n\n"
        "Use: durable, reusable knowledge—user preferences, project decisions, architectural choices; "
        "anything improving future responses. No ephemeral task state.\n\n"
    )
    if cfg.global_scope:
        item_props["scope"] = {
            "type": "string",
            "enum": ["project", "global"],
            "description": "storage scope; defaults to project, global is for durable cross-project knowledge",
        }
        retain_desc += (
            "`scope: global` stores an item in the shared bank every project recalls; "
            "reserve it for cross-project preferences and facts.\n"
        )
    retain_desc += (
        "Each item MUST be specific, self-contained: who, what, when, why. "
        "Batch related facts per call; deduplicated and consolidated."
    )
    return [
        {
            "name": "recall",
            "description": (
                "Search long-term memory; return raw relevance-ranked matching entries.\n\n"
                "Use proactively before questions about past conversations, user preferences, project "
                "decisions, or topics where prior context improves accuracy. When in doubt, recall first.\n\n"
                "`recall`: specific facts or entries. `reflect`: synthesized answer across many memories."
            ),
            "inputSchema": {
                "type": "object",
                "properties": {"query": {"type": "string", "description": "natural-language search query"}},
                "required": ["query"],
                "additionalProperties": False,
            },
        },
        {
            "name": "retain",
            "description": retain_desc,
            "inputSchema": {
                "type": "object",
                "properties": {
                    "items": {
                        "type": "array",
                        "minItems": 1,
                        "items": {
                            "type": "object",
                            "properties": item_props,
                            "required": ["content"],
                            "additionalProperties": False,
                        },
                    }
                },
                "required": ["items"],
                "additionalProperties": False,
            },
        },
        {
            "name": "reflect",
            "description": (
                "Synthesizes a coherent response from relevant long-term memories; unlike `recall`, blends them.\n\n"
                'Use for open-ended questions spanning many stored facts: "What do you know about this user?", '
                '"Summarize project decisions.", "What are my preferences for X?"\n\n'
                "`context` optional; focuses synthesis on a specific angle or sub-topic."
            ),
            "inputSchema": {
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "question to answer from long-term memory"},
                    "context": {"type": "string", "description": "extra guidance"},
                },
                "required": ["query"],
                "additionalProperties": False,
            },
        },
    ]


def call_tool(cfg: Config, name: str, args: dict, directory: str) -> str:
    tags = project_tags(directory)
    if name == "recall":
        results = recall(cfg, str(args.get("query", "")), tags)
        if not results:
            return "No relevant memories found."
        now = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M")
        noun = "memory" if len(results) == 1 else "memories"
        return f"Found {len(results)} relevant {noun} (as of {now} UTC):\n\n{format_memories(results)}"
    if name == "reflect":
        text = reflect(cfg, str(args.get("query", "")), args.get("context"), tags)
        return text or "No relevant information found to reflect on."
    if name == "retain":
        raw_items = args.get("items") or []
        if not isinstance(raw_items, list) or not raw_items:
            raise ValueError("items must be a non-empty array")
        if any(isinstance(i, dict) and i.get("scope") == "global" for i in raw_items) and not cfg.global_scope:
            raise ValueError("Hindsight global scope is off")
        now = dt.datetime.now(dt.timezone.utc).isoformat()
        items = []
        for raw in raw_items:
            if not isinstance(raw, dict) or not str(raw.get("content", "")).strip():
                raise ValueError("every item needs non-empty content")
            item = {
                "content": str(raw["content"]).strip(),
                "context": str(raw.get("context") or RETAIN_CONTEXT),
                "document_id": str(uuid.uuid4()),
                "timestamp": now,
            }
            if raw.get("scope") != "global":
                item["tags"] = tags
            items.append(item)
        retain(cfg, items)
        noun = "memory" if len(items) == 1 else "memories"
        return f"{len(items)} {noun} queued."
    raise ValueError(f"unknown tool: {name}")


def _root_path(roots: list) -> str | None:
    for root in roots:
        uri = root.get("uri", "") if isinstance(root, dict) else ""
        parsed = urllib.parse.urlparse(uri)
        if parsed.scheme == "file" and parsed.path:
            return urllib.parse.unquote(parsed.path)
    return None


def serve_mcp(cfg: Config, enabled: bool, stdin=sys.stdin, stdout=sys.stdout) -> None:
    # agy starts plugin MCP servers inside the plugin directory, so the
    # project comes from the client's workspace root (MCP roots), not the cwd.
    workspace = {"root": None, "supported": False, "pending": None, "requests": 0}

    def send(message: dict) -> None:
        stdout.write(json.dumps(message) + "\n")
        stdout.flush()

    def request_roots() -> None:
        if workspace["supported"]:
            workspace["requests"] += 1
            workspace["pending"] = f"roots-{workspace['requests']}"
            send({"jsonrpc": "2.0", "id": workspace["pending"], "method": "roots/list"})

    for line in stdin:
        try:
            message = json.loads(line)
        except ValueError:
            continue
        if not isinstance(message, dict):
            continue
        mid, method = message.get("id"), message.get("method")
        params = message.get("params") or {}
        if method is None:
            if mid is not None and mid == workspace["pending"]:
                workspace["root"] = _root_path((message.get("result") or {}).get("roots") or [])
            continue
        if mid is None:
            if method in ("notifications/initialized", "notifications/roots/list_changed"):
                request_roots()
            continue
        if method == "initialize":
            workspace["supported"] = "roots" in (params.get("capabilities") or {})
            result = {
                "protocolVersion": params.get("protocolVersion", "2025-03-26"),
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "agy-hindsight", "version": "1.0.0"},
            }
        elif method == "tools/list":
            result = {"tools": tool_definitions(cfg) if enabled else []}
        elif method == "tools/call":
            if not enabled:
                result = {"content": [{"type": "text", "text": "Memory is off for agent-started runs."}], "isError": True}
            else:
                try:
                    directory = workspace["root"] or os.getcwd()
                    text = call_tool(cfg, params.get("name", ""), params.get("arguments") or {}, directory)
                    result = {"content": [{"type": "text", "text": text}]}
                except (HindsightError, ValueError) as err:
                    result = {"content": [{"type": "text", "text": str(err)}], "isError": True}
        elif method == "ping":
            result = {}
        else:
            send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": f"method not found: {method}"}})
            continue
        send({"jsonrpc": "2.0", "id": mid, "result": result})


# ---------------------------------------------------------------------------


def main(argv: list[str]) -> int:
    cfg = Config(dict(os.environ))
    enabled = memory_enabled(dict(os.environ))
    if argv[:1] == ["mcp"]:
        serve_mcp(cfg, enabled)
        return 0
    if argv[:1] == ["retain-session"] and len(argv) == 4:
        try:
            retain_session(cfg, argv[1], argv[2], argv[3])
        except HindsightError as err:
            log(cfg, f"retain {argv[1]}: {err}")
            return 1
        return 0
    if argv[:1] == ["hook"] and len(argv) == 2 and argv[1] in ("pre-invocation", "stop"):
        output: dict = {}
        if enabled:
            try:
                payload = json.load(sys.stdin)
            except ValueError:
                payload = {}
            try:
                output = pre_invocation(payload, cfg) if argv[1] == "pre-invocation" else stop(payload, cfg)
            except Exception as err:  # a hook must never break the agent loop
                log(cfg, f"{argv[1]}: {err!r}")
                output = {}
        print(json.dumps(output))
        return 0
    print("usage: agy-hindsight {hook pre-invocation|hook stop|mcp}", file=sys.stderr)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
