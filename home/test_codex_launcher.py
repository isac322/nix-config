#!/usr/bin/env python3
"""Test home/codex-launcher.nix with synthetic env/HOME/target; retain fixtures in a scratch directory."""
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
source = Path(__file__).with_name("codex-launcher.nix").resolve()

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

for forbidden in ("cc" "lb", "cc_" "lb", "cc-" "lb", "run" "bear"):
    assert forbidden not in rendered.stdout.lower(), f"forbidden token {forbidden!r} in rendered launcher"

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
    order = []
    for i in range(0, len(prefix), 2):
        assert prefix[i] == "-c", prefix
        k, v = prefix[i + 1].split("=", 1)
        pairs[k] = v
        order.append(k)
    return pairs, order


def expected_provider_fields(pid, base_url, env_key):
    return {
        f"model_providers.{pid}.name": '"OpenAI"',
        f"model_providers.{pid}.base_url": f'"{base_url}"',
        f"model_providers.{pid}.env_key": f'"{env_key}"',
        f"model_providers.{pid}.wire_api": '"responses"',
        f"model_providers.{pid}.supports_websockets": "true",
        f"model_providers.{pid}.supports_standalone_web_search": "true",
        f"model_providers.{pid}.http_headers.x-openai-actor-authorization": f'"{pid}"',
        f"model_providers.{pid}.capabilities.remote_compaction": '"v2"',
        f"model_providers.{pid}.capabilities.external_web_access": "true",
    }


home_empty = root / "home-empty"
home_empty.mkdir()

# 1. Neither origin set, no env.sh -> passthrough untouched
got = run(["exec", "--skip-git-repo-check", "hello world"], home=home_empty)
assert got["argv"] == ["exec", "--skip-git-repo-check", "hello world"], got

# 2. Only CODEX_CUSTOM_ORIGIN (with trailing slashes) + preserves empty/quoted/spaced user args
user_args = ["exec", "--cd", "/tmp/a b", "", 'say "hi"']
got = run(
    user_args,
    home=home_empty,
    extra_env={"CODEX_CUSTOM_ORIGIN": "https://proxy-a.example.invalid///"},
)
pairs, _ = split_overrides(got["argv"], user_args)
expected = {
    "model_provider": '"custom"',
    "service_tier": '"fast"',
    "web_search": '"live"',
    "features.standalone_web_search": "true",
    "experimental_realtime_ws_base_url": '"https://proxy-a.example.invalid/openai/backend-api/codex/realtime"',
    **expected_provider_fields(
        "custom",
        "https://proxy-a.example.invalid/openai/backend-api/codex",
        "CODEX_CUSTOM_API_KEY",
    ),
}
assert pairs == expected, (pairs, expected)

# 3. Only CLIPROXYAPI_ORIGIN (with trailing slash)
got = run(
    [],
    home=home_empty,
    extra_env={"CLIPROXYAPI_ORIGIN": "https://proxy-b.example.invalid/"},
)
pairs, _ = split_overrides(got["argv"], [])
expected = {
    "model_provider": '"cliproxyapi"',
    "service_tier": '"fast"',
    "web_search": '"live"',
    "features.standalone_web_search": "true",
    "experimental_realtime_ws_base_url": '"https://proxy-b.example.invalid/v1/realtime"',
    **expected_provider_fields(
        "cliproxyapi",
        "https://proxy-b.example.invalid/v1",
        "CLIPROXYAPI_API_KEY",
    ),
}
assert pairs == expected, (pairs, expected)

# 4. Both origins set -> default selects custom, registers both, realtime points to custom
both_env = {
    "CODEX_CUSTOM_ORIGIN": "https://proxy-a.example.invalid",
    "CLIPROXYAPI_ORIGIN": "https://proxy-b.example.invalid",
}
got = run(["app-server"], home=home_empty, extra_env=both_env)
pairs, _ = split_overrides(got["argv"], ["app-server"])
expected_both = {
    **expected_provider_fields(
        "custom",
        "https://proxy-a.example.invalid/openai/backend-api/codex",
        "CODEX_CUSTOM_API_KEY",
    ),
    **expected_provider_fields(
        "cliproxyapi",
        "https://proxy-b.example.invalid/v1",
        "CLIPROXYAPI_API_KEY",
    ),
}
assert pairs == {
    "model_provider": '"custom"',
    "service_tier": '"fast"',
    "web_search": '"live"',
    "features.standalone_web_search": "true",
    "experimental_realtime_ws_base_url": '"https://proxy-a.example.invalid/openai/backend-api/codex/realtime"',
    **expected_both,
}, pairs

# 5. All user -c forms overriding model_provider=cliproxyapi (including after subcommand)
for flag_args in (
    ["-c", "model_provider=cliproxyapi", "exec", "hi"],
    ["--config", 'model_provider="cliproxyapi"'],
    ["-c=model_provider='cliproxyapi'"],
    ["--config=model_provider = cliproxyapi"],
    ["-cmodel_provider=cliproxyapi"],
    ["exec", "-c", "model_provider=openai", "-c", "model_provider=cliproxyapi", "--cd=/tmp", "hi"],
):
    got = run(flag_args, home=home_empty, extra_env=both_env)
    pairs, _ = split_overrides(got["argv"], flag_args)
    assert "model_provider" not in pairs, (flag_args, pairs)
    assert pairs["experimental_realtime_ws_base_url"] == '"https://proxy-b.example.invalid/v1/realtime"', (flag_args, pairs)
    assert pairs["service_tier"] == '"fast"' and pairs["web_search"] == '"live"' and pairs["features.standalone_web_search"] == "true"
    for k, v in expected_both.items():
        assert pairs[k] == v, (flag_args, k, pairs[k], v)

# 6. User selects openai -> omits provider/realtime/fast/live defaults, keeps registered providers
got = run(["-c", "model_provider=openai"], home=home_empty, extra_env=both_env)
pairs, _ = split_overrides(got["argv"], ["-c", "model_provider=openai"])
assert pairs == expected_both, pairs

# 7. User overrides experimental_realtime_ws_base_url -> launcher omits its own realtime URL
rt_args = ["-c", 'experimental_realtime_ws_base_url="https://override.example/rt"']
got = run(rt_args, home=home_empty, extra_env=both_env)
pairs, _ = split_overrides(got["argv"], rt_args)
assert "experimental_realtime_ws_base_url" not in pairs, pairs
assert pairs["model_provider"] == '"custom"'

# 8. Scrubbed env (launchd simulation) with ~/.config/agents/env.sh
home_envsh = root / "home-envsh"
(home_envsh / ".config" / "agents").mkdir(parents=True)
(home_envsh / ".config" / "agents" / "env.sh").write_text(
    'export CODEX_CUSTOM_ORIGIN="https://envsh-a.example.invalid/"\n'
    'export CODEX_CUSTOM_API_KEY="synthetic-custom-key"\n'
    'export CLIPROXYAPI_ORIGIN="https://envsh-b.example.invalid"\n'
    'export CLIPROXYAPI_API_KEY="synthetic-cpa-key"\n'
)
got = run(["exec"], home=home_envsh)
pairs, _ = split_overrides(got["argv"], ["exec"])
assert pairs["model_provider"] == '"custom"'
assert pairs["model_providers.custom.base_url"] == '"https://envsh-a.example.invalid/openai/backend-api/codex"'
assert pairs["model_providers.cliproxyapi.base_url"] == '"https://envsh-b.example.invalid/v1"'
assert got["keys"] == {
    "CODEX_CUSTOM_ORIGIN": "https://envsh-a.example.invalid/",
    "CODEX_CUSTOM_API_KEY": "synthetic-custom-key",
    "CLIPROXYAPI_ORIGIN": "https://envsh-b.example.invalid",
    "CLIPROXYAPI_API_KEY": "synthetic-cpa-key",
}, got["keys"]

# 9. Explicit empty override CODEX_CUSTOM_ORIGIN="" suppresses env.sh fallback
got = run(["exec"], home=home_envsh, extra_env={"CODEX_CUSTOM_ORIGIN": ""})
assert got["argv"] == ["exec"], got

# 10. Opt-out, help/version/completion pass-through, `--` delimiter, malformed origins
assert run(["exec"], home=home_envsh, extra_env={"CODEX_NO_CUSTOM_PROVIDER": "1"})["argv"] == ["exec"]
for pass_args in (
    ["--help"],
    ["-h"],
    ["--version"],
    ["-V"],
    ["help"],
    ["completion", "zsh"],
):
    assert run(pass_args, home=home_empty, extra_env=both_env)["argv"] == pass_args, pass_args

dd_args = ["exec", "--", "-c", "model_provider=cliproxyapi"]
got = run(dd_args, home=home_empty, extra_env=both_env)
pairs, _ = split_overrides(got["argv"], dd_args)
assert pairs["model_provider"] == '"custom"'

for bad in (
    "ftp://bad.example",
    "https://bad example.invalid",
    'https://bad".example.invalid',
    "https://bad\\.example.invalid",
    "https://bad\n.example.invalid",
    "https://",
    "http://",
):
    got = run(["exec"], home=home_empty, extra_env={"CODEX_CUSTOM_ORIGIN": bad})
    assert got["argv"] == ["exec"], (bad, got)

print("PASS: codex launcher syntax, origin normalization, -c overrides, env.sh fallback, pass-through, and privacy checks.")
