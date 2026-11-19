#!/usr/bin/env python3
"""Test home/agy-launcher.nix with synthetic HOME/PWD/target; retain fixtures in a supplied scratch directory."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--scratch-dir", type=Path, required=True)
args = parser.parse_args()

root = args.scratch_dir.resolve()
root.mkdir(parents=True, exist_ok=True)
source = Path(__file__).with_name("agy-launcher.nix").resolve()
jq_bin = shutil.which("jq")
assert jq_bin, "jq must be available on PATH to run agy launcher tests"

target = root / "target"
target.write_text(
    f"#!{sys.executable}\nimport json, sys\nprint(json.dumps(sys.argv[1:]))\n"
)
target.chmod(0o700)

expression = f'''import {source} {{
  writeTextFile = attrs: attrs.text;
  jq = {json.dumps(jq_bin)};
}} {json.dumps(str(target))}'''
rendered = subprocess.run(
    ["nix", "eval", "--impure", "--raw", "--expr", expression],
    text=True,
    capture_output=True,
    check=True,
)
launcher = root / "agy"
launcher.write_text(rendered.stdout)
launcher.chmod(0o755)
subprocess.run(["/bin/sh", "-n", str(launcher)], check=True)


def run(argv, cwd, home, extra_env=None):
    env = {
        k: v
        for k, v in os.environ.items()
        if k not in {"AGY_NO_AUTO_TRUST", "HOME", "PWD"}
    }
    env["HOME"] = str(home)
    env["PWD"] = str(cwd)
    if extra_env:
        env.update(extra_env)
    res = subprocess.run(
        ["/bin/sh", str(launcher), *argv],
        cwd=cwd,
        env=env,
        text=True,
        capture_output=True,
        check=True,
    )
    return json.loads(res.stdout)


def extract_single_settings(received_argv):
    matches = []
    i = 0
    while i < len(received_argv):
        a = received_argv[i]
        if a == "--":
            break
        if a in ("--settings", "-settings"):
            assert i + 1 < len(received_argv), f"dangling {a} in {received_argv}"
            matches.append(received_argv[i + 1])
            i += 2
            continue
        if a.startswith("--settings=") or a.startswith("-settings="):
            matches.append(a.split("=", 1)[1])
        i += 1
    return matches


# 2. Symlink workspace preserves both logical and physical paths + existing settings.json untouched
home_ok = root / "home-ok"
settings_dir = home_ok / ".gemini" / "antigravity-cli"
settings_dir.mkdir(parents=True)
settings_file = settings_dir / "settings.json"
settings_file.write_text(
    json.dumps({"model": "Orchestrator (Neon)", "trustedWorkspaces": ["/existing/repo/"]})
)
before_sha = hashlib.sha256(settings_file.read_bytes()).hexdigest()

real_ws = root / "real-workspace"
real_ws.mkdir()
link_ws = root / "link-workspace"
if not link_ws.exists():
    link_ws.symlink_to(real_ws)

got = run([], cwd=link_ws, home=home_ok)
s_list = extract_single_settings(got)
assert len(s_list) == 1, got
merged = json.loads(s_list[0])
assert merged["trustedWorkspaces"] == sorted(
    {"/existing/repo", str(link_ws), str(real_ws.resolve())}
), merged
assert hashlib.sha256(settings_file.read_bytes()).hexdigest() == before_sha

# 3. Missing or broken settings.json still trusts current workspace
home_missing = root / "home-missing"
home_missing.mkdir()
got = run([], cwd=real_ws, home=home_missing)
merged = json.loads(extract_single_settings(got)[0])
assert merged == {"trustedWorkspaces": [str(real_ws.resolve())]}, merged

home_broken = root / "home-broken"
(home_broken / ".gemini" / "antigravity-cli").mkdir(parents=True)
(home_broken / ".gemini" / "antigravity-cli" / "settings.json").write_text("{broken")
got = run([], cwd=real_ws, home=home_broken)
merged = json.loads(extract_single_settings(got)[0])
assert merged == {"trustedWorkspaces": [str(real_ws.resolve())]}, merged

# 4. Paths with spaces and repeated --add-dir / --add-dir=
space_ws = root / "space dir"
extra_a = root / "extra a"
extra_b = root / "extra b"
for d in (space_ws, extra_a, extra_b):
    d.mkdir()
got = run(
    ["--add-dir", str(extra_a), f"--add-dir={extra_b}", "--model", "Orchestrator (Neon)"],
    cwd=space_ws,
    home=home_missing,
)
merged = json.loads(extract_single_settings(got)[0])
assert set(merged["trustedWorkspaces"]) == {
    str(space_ws),
    str(space_ws.resolve()),
    str(extra_a),
    str(extra_a.resolve()),
    str(extra_b),
    str(extra_b.resolve()),
}, merged
assert got[2:] == [
    "--add-dir",
    str(extra_a),
    f"--add-dir={extra_b}",
    "--model",
    "Orchestrator (Neon)",
], got

# 5. Value-consuming flags whose values look like subcommands or help still receive --settings
for argv in (["-p", "help"], ["-i", "models"], ["--project", "models"]):
    got = run(argv, cwd=real_ws, home=home_missing)
    assert len(extract_single_settings(got)) == 1, (argv, got)
    assert got[2:] == argv, (argv, got)

# 6. Subcommands and help/version flags pass through without --settings
for argv in (
    ["models"],
    ["mcp", "list"],
    ["acp"],
    ["help"],
    ["--log-file", "/tmp/x", "models"],
    ["--help"],
    ["-h"],
    ["--version"],
):
    got = run(argv, cwd=real_ws, home=home_ok)
    assert got == argv, (argv, got)

# 7. User --settings (inline, file, explicit trustedWorkspaces) merges cleanly and drops duplicate --settings
got = run(["--settings", '{"colorScheme":"dark"}', "--sandbox"], cwd=real_ws, home=home_ok)
assert extract_single_settings(got) == [got[1]], got
merged = json.loads(got[1])
assert merged["colorScheme"] == "dark", merged
assert set(merged["trustedWorkspaces"]) == {"/existing/repo", str(real_ws.resolve())}, merged
assert got[2:] == ["--sandbox"], got

user_settings_file = root / "user-settings.json"
user_settings_file.write_text(json.dumps({"verbosity": "high"}))
got = run([f"--settings={user_settings_file}", "--agent", "foo"], cwd=real_ws, home=home_ok)
assert extract_single_settings(got) == [got[1]], got
merged = json.loads(got[1])
assert merged["verbosity"] == "high", merged
assert set(merged["trustedWorkspaces"]) == {"/existing/repo", str(real_ws.resolve())}, merged
assert got[2:] == ["--agent", "foo"], got

got = run(
    ["--settings", '{"trustedWorkspaces":["/custom"],"notifications":false}'],
    cwd=real_ws,
    home=home_ok,
)
assert len(got) == 2 and got[0] == "--settings", got
merged = json.loads(got[1])
assert merged["notifications"] is False, merged
assert merged["trustedWorkspaces"] == sorted(["/custom", str(real_ws.resolve())]), merged

# 8. -p "--settings" preserves "--settings" as the value of -p
got = run(
    ["-p", "--settings", "--settings", '{"colorScheme":"light"}'],
    cwd=real_ws,
    home=home_missing,
)
assert got[0] == "--settings" and got[2:] == ["-p", "--settings"], got
merged = json.loads(got[1])
assert merged["colorScheme"] == "light" and merged["trustedWorkspaces"] == [str(real_ws.resolve())], merged

# 9. Invalid user --settings passes through unchanged so agy reports its own error
bad_argv = ["--settings", "{broken"]
assert run(bad_argv, cwd=real_ws, home=home_missing) == bad_argv

# 10. AGY_NO_AUTO_TRUST=1 disables injection
assert run(["--sandbox"], cwd=real_ws, home=home_ok, extra_env={"AGY_NO_AUTO_TRUST": "1"}) == ["--sandbox"]

# 11. Arguments after `--` are left untouched
got = run(["--", "--settings", "foo"], cwd=real_ws, home=home_missing)
assert got[0] == "--settings" and got[2:] == ["--", "--settings", "foo"], got
assert json.loads(got[1]) == {"trustedWorkspaces": [str(real_ws.resolve())]}, got

print("PASS: agy launcher syntax, trust injection/merge, subcommand pass-through, flag edge cases, and opt-out.")
