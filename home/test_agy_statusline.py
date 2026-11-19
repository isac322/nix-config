#!/usr/bin/env python3
"""Regression tests for agy custom statusLine and title scripts."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parent

parser = argparse.ArgumentParser()
parser.add_argument("--statusline-bin", type=Path, default=ROOT / "agy" / "statusline.sh")
parser.add_argument("--title-bin", type=Path, default=ROOT / "agy" / "title.sh")
parser.add_argument(
    "--empty-path",
    action="store_true",
    help="Clear PATH when executing the binaries (for Nix store build verification).",
)
args = parser.parse_args()

ANSI_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
CNTRL_RE = re.compile(r"[\x00-\x1f\x7f]")


def strip_ansi(text: str) -> str:
    return ANSI_RE.sub("", text)


def run_bin(binary: Path, payload: str, *, home: str = "/Users/bhyoo", extra_env: dict[str, str] | None = None):
    env = {} if args.empty_path else dict(os.environ)
    if args.empty_path:
        env["PATH"] = ""
    env["HOME"] = home
    if extra_env:
        env.update(extra_env)
    return subprocess.run(
        [str(binary)],
        input=payload,
        env=env,
        text=True,
        capture_output=True,
        check=True,
    )


def run_status(payload: dict | str, **kwargs) -> tuple[str, str]:
    raw = payload if isinstance(payload, str) else json.dumps(payload)
    res = run_bin(args.statusline_bin, raw, **kwargs)
    assert res.stderr == "", f"unexpected stderr from statusline: {res.stderr!r}"
    return res.stdout, strip_ansi(res.stdout)


def run_title(payload: dict | str, **kwargs) -> str:
    raw = payload if isinstance(payload, str) else json.dumps(payload)
    res = run_bin(args.title_bin, raw, **kwargs)
    assert res.stderr == "", f"unexpected stderr from title: {res.stderr!r}"
    return res.stdout


# 1. Realistic active payload: segments, icons, powerline separators, running-only subagent count, no trailing bg 0
full_payload = {
    "cwd": "/Users/bhyoo/etc/nix-darwin",
    "workspace": {"current_dir": "/Users/bhyoo/etc/nix-darwin", "project_dir": "/Users/bhyoo/etc/nix-darwin"},
    "cycle_mode": "accept-edits",
    "agent": {"name": "coordinator"},
    "model": {"id": "orchestrator-neon", "display_name": "Orchestrator (Neon)"},
    "version": "1.5.11",
    "cost": {"total_usd": 0.4213, "subagent_usd": 0.12, "estimated": False},
    "context_window": {
        "total_input_tokens": 88244,
        "total_output_tokens": 61074,
        "used_percentage": 14.24,
        "current_usage": {"input_tokens": 63382, "output_tokens": 346},
    },
    "subagents": [
        {"name": "a1", "role": "research", "status": "running"},
        {"name": "a2", "role": "review", "status": "completed"},
        {"name": "a3", "role": "check", "status": "running"},
    ],
    "task_count": 1,
    "agent_state": "working",
}
raw_out, plain_out = run_status(full_payload)
expected_plain = (
    " ~/etc/nix-darwin \uE0B0"
    " \U000f06a9 coordinator \uE0B0"
    " accept-edits \uE0B0"
    " Orchestrator (Neon) \uE0B0"
    " v1.5.11 \uE0B0"
    " $0.42 \uE0B0"
    " 88.2K/61.1K \uE0B0"
    " \U000f0f85 14% \uE0B0"
    " \U000f06a9 2 sub · 1 task \uE0B0"
)
assert plain_out == expected_plain, f"unexpected statusline:\n got: {plain_out!r}\nwant: {expected_plain!r}"
assert "\033[48;5;0m" not in raw_out, f"end cap must reset to terminal default bg, not black bg 0: {raw_out!r}"
assert raw_out.endswith("\033[0m"), f"statusline must end with SGR reset: {raw_out!r}"

# 2. Initial startup payload (model null, current_usage null, zero usage, omitted cost/subagents)
startup_payload = {
    "cwd": "/Users/bhyoo/project",
    "workspace": {"current_dir": "/Users/bhyoo/project"},
    "model": None,
    "version": "v1.5.11",
    "context_window": {
        "total_input_tokens": 0,
        "total_output_tokens": 0,
        "used_percentage": 0,
        "current_usage": None,
    },
    "agent_state": "initializing",
}
_, plain_startup = run_status(startup_payload)
assert plain_startup == " ~/project \uE0B0 v1.5.11 \uE0B0", plain_startup

# 3. Model effort deduplication
_, plain_argon = run_status(
    {
        "cwd": "/tmp/ws",
        "model": {"display_name": "Gemini 4 Argon (Medium)", "effort": "medium"},
    }
)
assert "Gemini 4 Argon (Medium) (medium)" not in plain_argon and "Gemini 4 Argon (Medium)" in plain_argon, plain_argon

_, plain_neon_high = run_status(
    {
        "cwd": "/tmp/ws",
        "model": {"display_name": "Orchestrator (Neon)", "effort": "high"},
    }
)
assert "Orchestrator (Neon) (high)" in plain_neon_high, plain_neon_high

# 4. Exact $HOME vs prefix boundary (/Users/bhyoo2 must NOT become ~2)
_, p_exact = run_status({"cwd": "/Users/bhyoo"}, home="/Users/bhyoo")
_, p_sub = run_status({"cwd": "/Users/bhyoo/a/b"}, home="/Users/bhyoo/")
_, p_sibling = run_status({"cwd": "/Users/bhyoo2/a"}, home="/Users/bhyoo")
assert p_exact == " ~ \uE0B0", p_exact
assert p_sub == " ~/a/b \uE0B0", p_sub
assert p_sibling == " /Users/bhyoo2/a \uE0B0", p_sibling

# 5. Locale independence (comma decimal locales must not break printf floats)
for loc_env in (
    {"LC_NUMERIC": "de_DE.UTF-8"},
    {"LC_ALL": "de_DE.UTF-8", "LC_NUMERIC": "de_DE.UTF-8"},
):
    _, p_loc = run_status(
        {
            "cwd": "/tmp/ws",
            "cost": {"total_usd": 0.4213, "estimated": False},
            "context_window": {"used_percentage": 14.24, "current_usage": {"input_tokens": 10}},
        },
        extra_env=loc_env,
    )
    assert " $0.42 \uE0B0" in p_loc and " \U000f0f85 14% \uE0B0" in p_loc, (loc_env, p_loc)

# 6. Cost thresholds & estimate prefix, token rounding, high-usage red alert (>= 90%)
for small_cost in (0, 0.0, 0.001, 0.0049):
    _, p_small = run_status({"cwd": "/tmp/ws", "cost": {"total_usd": small_cost}})
    assert "$" not in p_small, (small_cost, p_small)

_, p_est = run_status({"cwd": "/tmp/ws", "cost": {"total_usd": 0.421, "estimated": True}})
assert " ~$0.42 \uE0B0" in p_est, p_est

_, p_tok = run_status(
    {
        "cwd": "/tmp/ws",
        "context_window": {
            "total_input_tokens": 999999,
            "total_output_tokens": 1234567,
            "used_percentage": 92.4,
            "current_usage": {"input_tokens": 100},
        },
    }
)
raw_tok, _ = run_status(
    {
        "cwd": "/tmp/ws",
        "context_window": {
            "total_input_tokens": 999999,
            "total_output_tokens": 1234567,
            "used_percentage": 92.4,
            "current_usage": {"input_tokens": 100},
        },
    }
)
assert " 1.0M/1.2M \uE0B0" in p_tok, p_tok
assert " \U000f0f85 92% \uE0B0" in p_tok, p_tok
assert "\033[48;5;1m\033[38;5;254m \U000f0f85 92% " in raw_tok, raw_tok

# 7. Auto mode (red), confirmation pending (red), error fallback (red), sandbox & vim mode
raw_auto, plain_auto = run_status(
    {
        "cwd": "/tmp/ws",
        "cycle_mode": "auto",
        "vim": {"mode": "NORMAL"},
        "sandbox": {"enabled": True},
        "pending_input_count": 2,
        "tool_confirmation_pending": True,
        "agent_state": "reviewing",
    }
)
assert "\033[48;5;1m\033[38;5;254m auto " in raw_auto, raw_auto
assert " NORMAL \uE0B0 sandbox \uE0B0 ⏸ 2 queued · confirm \uE0B0" in plain_auto, plain_auto
assert "\033[48;5;1m\033[38;5;254m ⏸ 2 queued · confirm " in raw_auto, raw_auto

raw_err, plain_err = run_status({"cwd": "/tmp/ws", "agent_state": "error"})
assert plain_err.endswith(" ✗ error \uE0B0"), plain_err
assert "\033[48;5;1m\033[38;5;254m ✗ error " in raw_err, raw_err

# 8. Title: all agent states, path edge cases, control chars/newlines, 60-char truncation, plain 1-line text
state_cases = [
    ({"workspace": {"current_dir": "/a/nix-darwin"}, "agent_state": "working"}, "⚙ nix-darwin\n"),
    ({"workspace": {"current_dir": "/a/nix-darwin"}, "agent_state": "tool_use"}, "⚙ nix-darwin\n"),
    ({"workspace": {"current_dir": "/a/nix-darwin"}, "agent_state": "idle"}, "✓ nix-darwin\n"),
    ({"workspace": {"current_dir": "/a/nix-darwin"}, "agent_state": "reviewing"}, "⏸ nix-darwin\n"),
    (
        {
            "workspace": {"current_dir": "/a/nix-darwin"},
            "agent_state": "working",
            "tool_confirmation_pending": True,
        },
        "⏸ nix-darwin\n",
    ),
    ({"workspace": {"current_dir": "/a/nix-darwin"}, "agent_state": "error"}, "✗ nix-darwin\n"),
    ({"workspace": {"current_dir": "/a/nix-darwin"}, "agent_state": "initializing"}, "… nix-darwin\n"),
    ({"workspace": {"current_dir": "/a/nix-darwin"}, "agent_state": "authenticating"}, "… nix-darwin\n"),
]
for payload, expected in state_cases:
    got = run_title(payload)
    assert got == expected, (payload, got, expected)

assert run_title({"cwd": "/", "agent_state": "idle"}) == "✓ /\n"
assert run_title({"cwd": "///", "agent_state": "idle"}) == "✓ /\n"
assert run_title({"cwd": "/Users/bhyoo/repo///", "agent_state": "idle"}) == "✓ repo\n"
assert run_title({"cwd": "", "agent_state": "idle"}) == "✓ agy\n"

long_title = "line1\n\tline2   \x1b[31m" + ("가" * 70)
got_sanitized = run_title(
    {
        "cwd": "/Users/bhyoo/proj",
        "agent_state": "working",
        "conversation_title": f"  {long_title}  ",
    }
)
assert got_sanitized.count("\n") == 1 and got_sanitized.endswith("\n"), repr(got_sanitized)
line = got_sanitized.rstrip("\n")
assert not ANSI_RE.search(line) and not CNTRL_RE.search(line), repr(line)
prefix = "⚙ proj — "
assert line.startswith(prefix), repr(line)
conv_part = line[len(prefix) :]
assert len(conv_part) == 60 and conv_part.endswith("…"), (len(conv_part), repr(conv_part))

# 9. Malformed / non-object / empty-object inputs must never fail (exit 0, empty stderr)
for bad in ("", "{broken", "null", "[]"):
    raw_s, plain_s = run_status(bad)
    t_out = run_title(bad)
    assert raw_s == "" and plain_s == "", (bad, raw_s)
    assert t_out == "", (bad, t_out)

raw_empty, plain_empty = run_status("{}")
assert raw_empty == "" and plain_empty == "", repr(raw_empty)
assert run_title("{}") == "… agy\n"

print(
    f"PASS: agy statusline ({args.statusline_bin}) & title ({args.title_bin})"
    + (" [empty PATH]" if args.empty_path else "")
)
