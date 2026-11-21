#!/usr/bin/env python3
"""Test home/codex-launcher.nix and static Nix config privacy; retain fixtures in a scratch directory."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--scratch-dir", type=Path, required=True)
args = parser.parse_args()

root = args.scratch_dir.resolve()
root.mkdir(parents=True, exist_ok=True)
home_dir = Path(__file__).resolve().parent
repo_root = home_dir.parent
source = home_dir / "codex-launcher.nix"

target = root / "target"
target.write_text(
    f"#!{sys.executable}\n"
    "import json, os, sys\n"
    "print(json.dumps({\n"
    "    'argv': sys.argv[1:],\n"
    "    'keys': {k: os.environ.get(k) for k in ('CODEX_CUSTOM_ORIGIN', 'CODEX_CUSTOM_API_KEY', 'CLIPROXYAPI_ORIGIN', 'CLIPROXYAPI_API_KEY')},\n"
    "}))\n"
)
target.chmod(0o700)

expression = f'''import {source} {{
  writeTextFile = attrs: attrs.text;
}} {json.dumps(str(target))}'''
rendered = subprocess.run(
    ["nix", "eval", "--impure", "--raw", "--expr", expression],
    text=True,
    capture_output=True,
    check=True,
)

# Check rendered launcher and Nix sources contain no private/legacy hostnames or tokens.
privacy_targets = [
    ("rendered codex-launcher", rendered.stdout),
    ("modules/common.nix", (repo_root / "modules" / "common.nix").read_text()),
    ("lib/mcp.nix", (repo_root / "lib" / "mcp.nix").read_text()),
]
for label, content in privacy_targets:
    lowered = content.lower()
    for forbidden in ("cc" "lb", "cc_" "lb", "cc-" "lb", "run" "bear"):
        assert forbidden not in lowered, f"forbidden token {forbidden!r} in {label}"

launcher = root / "codex"
launcher.write_text(rendered.stdout)
launcher.chmod(0o755)
subprocess.run(["/bin/sh", "-n", str(launcher)], check=True)


def run(argv, home, extra_env=None):
    env = {
        k: v
        for k, v in os.environ.items()
        if k
        not in {
            "CODEX_HOME",
            "CODEX_NO_CUSTOM_PROVIDER",
            "CODEX_CUSTOM_ORIGIN",
            "CODEX_CUSTOM_API_KEY",
            "CLIPROXYAPI_ORIGIN",
            "CLIPROXYAPI_API_KEY",
            "HOME",
        }
    }
    env["HOME"] = str(home)
    if extra_env:
        env.update(extra_env)
    res = subprocess.run(
        ["/bin/sh", str(launcher), *argv],
        env=env,
        text=True,
        capture_output=True,
        check=True,
    )
    return json.loads(res.stdout)


def split_overrides(argv, user_tail):
    if user_tail:
        assert argv[-len(user_tail) :] == user_tail, (argv, user_tail)
        prefix = argv[: -len(user_tail)]
    else:
        prefix = argv
    assert len(prefix) % 2 == 0, prefix
    pairs = {}
    for i in range(0, len(prefix), 2):
        assert prefix[i] == "-c", prefix
        k, v = prefix[i + 1].split("=", 1)
        assert k not in pairs, f"duplicate -c key {k!r} in {prefix}"
        pairs[k] = v
    return pairs


home_empty = root / "home-empty"
home_empty.mkdir()

# 1. Neither origin set, no env.sh, no user config -> ONLY model_provider="openai"
got = run(["exec", "--skip-git-repo-check", "hello world"], home=home_empty)
pairs = split_overrides(got["argv"], ["exec", "--skip-git-repo-check", "hello world"])
assert pairs == {"model_provider": '"openai"'}, pairs

# 2. Only CODEX_CUSTOM_ORIGIN (trailing slashes) + spaced/empty/quoted user args
user_args = ["exec", "--cd", "/tmp/a b", "", 'say "hi"']
got = run(
    user_args,
    home=home_empty,
    extra_env={"CODEX_CUSTOM_ORIGIN": "https://proxy-a.example.invalid///"},
)
pairs = split_overrides(got["argv"], user_args)
assert pairs == {
    "model_providers.custom.base_url": '"https://proxy-a.example.invalid/openai/backend-api/codex"',
    "experimental_realtime_ws_base_url": '"https://proxy-a.example.invalid/openai/backend-api/codex/realtime"',
}, pairs

# 3. Only CLIPROXYAPI_ORIGIN (trailing slash) -> falls back default provider to cliproxyapi
got = run(
    [],
    home=home_empty,
    extra_env={"CLIPROXYAPI_ORIGIN": "https://proxy-b.example.invalid/"},
)
pairs = split_overrides(got["argv"], [])
assert pairs == {
    "model_provider": '"cliproxyapi"',
    "model_providers.cliproxyapi.base_url": '"https://proxy-b.example.invalid/v1"',
    "experimental_realtime_ws_base_url": '"https://proxy-b.example.invalid/v1/realtime"',
}, pairs

# 4. Both origins set -> ONLY the 3 URLs, realtime points to custom
both_env = {
    "CODEX_CUSTOM_ORIGIN": "https://proxy-a.example.invalid",
    "CLIPROXYAPI_ORIGIN": "https://proxy-b.example.invalid",
}
got = run(["app-server"], home=home_empty, extra_env=both_env)
pairs = split_overrides(got["argv"], ["app-server"])
expected_urls_only = {
    "model_providers.custom.base_url": '"https://proxy-a.example.invalid/openai/backend-api/codex"',
    "model_providers.cliproxyapi.base_url": '"https://proxy-b.example.invalid/v1"',
}
assert pairs == {
    **expected_urls_only,
    "experimental_realtime_ws_base_url": '"https://proxy-a.example.invalid/openai/backend-api/codex/realtime"',
}, pairs

# 5. All 6 CLI -c/--config forms overriding model_provider=cliproxyapi
for flag_args in (
    ["-c", "model_provider=cliproxyapi", "exec", "hi"],
    ["--config", 'model_provider="cliproxyapi"'],
    ["-c=model_provider='cliproxyapi'"],
    ["--config=model_provider = cliproxyapi"],
    ["-cmodel_provider=cliproxyapi"],
    ["exec", "-c", "model_provider=openai", "-c", "model_provider=cliproxyapi", "--cd=/tmp", "hi"],
):
    got = run(flag_args, home=home_empty, extra_env=both_env)
    pairs = split_overrides(got["argv"], flag_args)
    assert pairs == {
        **expected_urls_only,
        "experimental_realtime_ws_base_url": '"https://proxy-b.example.invalid/v1/realtime"',
    }, (flag_args, pairs)

# 6. CLI -c model_provider=openai -> omits model_provider and realtime URL, keeps both base_urls
got = run(["-c", "model_provider=openai"], home=home_empty, extra_env=both_env)
pairs = split_overrides(got["argv"], ["-c", "model_provider=openai"])
assert pairs == expected_urls_only, pairs

# 7. CLI -c experimental_realtime_ws_base_url=... -> omits launcher's realtime URL, keeps both base_urls
rt_args = ["-c", 'experimental_realtime_ws_base_url="https://override.example/rt"']
got = run(rt_args, home=home_empty, extra_env=both_env)
pairs = split_overrides(got["argv"], rt_args)
assert pairs == expected_urls_only, pairs

# 8. User config.toml (~/.codex/config.toml and CODEX_HOME/config.toml) inspections
home_cpa = root / "home-cpa"
(home_cpa / ".codex").mkdir(parents=True)
(home_cpa / ".codex" / "config.toml").write_text(
    '# top-level comment\n'
    'model = "gpt-6.2-sol"\n'
    'model_provider = "cliproxyapi" # comment after quoted value\n\n'
    '[features]\n'
    'daemon_auto_start = false\n'
)
got = run(["exec"], home=home_cpa, extra_env=both_env)
pairs = split_overrides(got["argv"], ["exec"])
assert pairs == {
    **expected_urls_only,
    "experimental_realtime_ws_base_url": '"https://proxy-b.example.invalid/v1/realtime"',
}, pairs

# Same for single-quoted openai in CODEX_HOME override, plus CLI -c beats file provider
custom_codex_home = root / "custom-codex-home"
custom_codex_home.mkdir()
(custom_codex_home / "config.toml").write_text("model_provider = 'openai'\r\n")
got = run(["exec"], home=home_cpa, extra_env={**both_env, "CODEX_HOME": str(custom_codex_home)})
pairs = split_overrides(got["argv"], ["exec"])
assert pairs == expected_urls_only, pairs

# CLI -c model_provider=cliproxyapi wins over file's model_provider='openai' for realtime URL
got = run(
    ["-c", "model_provider=cliproxyapi"],
    home=home_cpa,
    extra_env={**both_env, "CODEX_HOME": str(custom_codex_home)},
)
pairs = split_overrides(got["argv"], ["-c", "model_provider=cliproxyapi"])
assert pairs == {
    **expected_urls_only,
    "experimental_realtime_ws_base_url": '"https://proxy-b.example.invalid/v1/realtime"',
}, pairs

# model_provider appearing ONLY inside a [table] after top-level is ignored
home_table_only = root / "home-table-only"
(home_table_only / ".codex").mkdir(parents=True)
(home_table_only / ".codex" / "config.toml").write_text(
    'model = "gpt-6.2-sol"\n'
    '[projects."/tmp"]\n'
    'model_provider = "cliproxyapi"\n'
    'experimental_realtime_ws_base_url = "https://ignored.example/rt"\n'
)
got = run(["exec"], home=home_table_only, extra_env=both_env)
pairs = split_overrides(got["argv"], ["exec"])
assert pairs == {
    **expected_urls_only,
    "experimental_realtime_ws_base_url": '"https://proxy-a.example.invalid/openai/backend-api/codex/realtime"',
}, pairs

# 9. User config.toml with top-level experimental_realtime_ws_base_url -> omits launcher's realtime URL
home_user_rt = root / "home-user-rt"
(home_user_rt / ".codex").mkdir(parents=True)
(home_user_rt / ".codex" / "config.toml").write_text(
    'experimental_realtime_ws_base_url = "https://user.example/rt" # comment\n'
)
got = run(["exec"], home=home_user_rt, extra_env=both_env)
pairs = split_overrides(got["argv"], ["exec"])
assert pairs == expected_urls_only, pairs

# 10. Scrubbed env (launchd simulation) with ~/.config/agents/env.sh
home_envsh = root / "home-envsh"
(home_envsh / ".config" / "agents").mkdir(parents=True)
(home_envsh / ".config" / "agents" / "env.sh").write_text(
    'export CODEX_CUSTOM_ORIGIN="https://envsh-a.example.invalid/"\n'
    'export CODEX_CUSTOM_API_KEY="synthetic-custom-key"\n'
    'export CLIPROXYAPI_ORIGIN="https://envsh-b.example.invalid"\n'
    'export CLIPROXYAPI_API_KEY="synthetic-cpa-key"\n'
)
got = run(["exec"], home=home_envsh)
pairs = split_overrides(got["argv"], ["exec"])
assert pairs == {
    "model_providers.custom.base_url": '"https://envsh-a.example.invalid/openai/backend-api/codex"',
    "model_providers.cliproxyapi.base_url": '"https://envsh-b.example.invalid/v1"',
    "experimental_realtime_ws_base_url": '"https://envsh-a.example.invalid/openai/backend-api/codex/realtime"',
}, pairs
assert got["keys"] == {
    "CODEX_CUSTOM_ORIGIN": "https://envsh-a.example.invalid/",
    "CODEX_CUSTOM_API_KEY": "synthetic-custom-key",
    "CLIPROXYAPI_ORIGIN": "https://envsh-b.example.invalid",
    "CLIPROXYAPI_API_KEY": "synthetic-cpa-key",
}, got["keys"]

# 11. Explicit empty CODEX_CUSTOM_ORIGIN="" suppresses env.sh fallback
got = run(["exec"], home=home_envsh, extra_env={"CODEX_CUSTOM_ORIGIN": ""})
pairs = split_overrides(got["argv"], ["exec"])
assert pairs == {"model_provider": '"openai"'}, pairs

# 12. CODEX_NO_CUSTOM_PROVIDER=1 -> ONLY model_provider="openai" before user args
got = run(["exec"], home=home_envsh, extra_env={"CODEX_NO_CUSTOM_PROVIDER": "1"})
assert got["argv"] == ["-c", 'model_provider="openai"', "exec"], got
got = run(
    ["-c", "model_provider=cliproxyapi"],
    home=home_envsh,
    extra_env={"CODEX_NO_CUSTOM_PROVIDER": "1"},
)
assert got["argv"] == ["-c", 'model_provider="openai"', "-c", "model_provider=cliproxyapi"], got

# 13. Help/version/completion pass-through (even with CODEX_NO_CUSTOM_PROVIDER=1)
for pass_args in (
    ["--help"],
    ["-h"],
    ["--version"],
    ["-V"],
    ["help"],
    ["completion", "zsh"],
):
    assert run(pass_args, home=home_empty, extra_env=both_env)["argv"] == pass_args, pass_args
    assert (
        run(pass_args, home=home_envsh, extra_env={"CODEX_NO_CUSTOM_PROVIDER": "1"})["argv"]
        == pass_args
    ), pass_args

# 14. `--` delimiter stops -c scanning; malformed origins are ignored cleanly
dd_args = ["exec", "--", "-c", "model_provider=cliproxyapi"]
got = run(dd_args, home=home_empty, extra_env=both_env)
pairs = split_overrides(got["argv"], dd_args)
assert pairs == {
    **expected_urls_only,
    "experimental_realtime_ws_base_url": '"https://proxy-a.example.invalid/openai/backend-api/codex/realtime"',
}, pairs

for bad in (
    "ftp://bad.example",
    "https://bad example.invalid",
    'https://bad".example.invalid',
    "https://bad\\.example.invalid",
    "https://bad\n.example.invalid",
    "https://",
    "http://",
    "https:///path-no-host",
):
    got = run(["exec"], home=home_empty, extra_env={"CODEX_CUSTOM_ORIGIN": bad})
    pairs = split_overrides(got["argv"], ["exec"])
    assert pairs == {"model_provider": '"openai"'}, (bad, pairs)

print("PASS: codex launcher syntax, minimal URL injection, user TOML/-c precedence, env.sh fallback, pass-through, and privacy checks.")
