#!/usr/bin/env python3
"""Test the launcher with synthetic credentials; retain fixtures in a supplied scratch directory."""
import argparse
import json
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--scratch-dir", type=Path, required=True)
args = parser.parse_args()
root = args.scratch_dir.resolve()
root.mkdir(parents=True, exist_ok=True)
source = Path(__file__).with_name("omp-launcher.nix").resolve()
target = root / "target"
target.write_text('#!/bin/sh\nprintf "token=%s\\n" "${HINDSIGHT_API_TOKEN:-unset}"\nprintf "arg=%s\\n" "$@"\n')
target.chmod(0o700)
sops = root / "sops"
sops.write_text('#!/bin/sh\ncase "${QA_SOPS_MODE:-valid}" in valid) printf synthetic-qa-token;; empty) :;; fail) exit 1;; esac\n')
sops.chmod(0o700)


def render(darwin):
    expression = f'''import {source} {{
      writeText = name: text: "{root}/no-memory.yml";
      writeTextFile = attrs: attrs.text;
      isDarwin = {str(darwin).lower()};
      sops = {json.dumps(str(sops))};
    }} {json.dumps(str(target))}'''
    result = subprocess.run(["nix", "eval", "--impure", "--raw", "--expr", expression],
                            text=True, capture_output=True, check=True)
    launcher = root / ("darwin-launcher" if darwin else "linux-launcher")
    launcher.write_text(result.stdout)
    subprocess.run(["/bin/sh", "-n", str(launcher)], check=True)
    return launcher


def run(launcher, overrides):
    env = {k: v for k, v in os.environ.items()
           if k not in {"PI_SESSION_FILE", "OMP_NESTED_MEMORY", "HINDSIGHT_API_TOKEN"}}
    env.update(overrides)
    return subprocess.run(["/bin/sh", str(launcher), "--version"], env=env,
                          text=True, capture_output=True)


linux = render(False)
darwin = render(True)
for launcher in (linux, darwin):
    result = run(launcher, {"HINDSIGHT_API_TOKEN": "explicit-qa-token"})
    assert result.returncode == 0 and "token=explicit-qa-token" in result.stdout
    result = run(launcher, {"PI_SESSION_FILE": "nested", "QA_SOPS_MODE": "fail"})
    assert result.returncode == 0 and "token=unset" in result.stdout
    assert "arg=--config" in result.stdout and "no-memory.yml" in result.stdout
result = run(linux, {})
assert result.returncode == 0 and "token=synthetic-qa-token" in result.stdout
for mode in ("empty", "fail"):
    result = run(linux, {"QA_SOPS_MODE": mode})
    assert result.returncode == 1 and not result.stdout
    assert "token is missing or inaccessible" in result.stderr
result = run(linux, {"PI_SESSION_FILE": "nested", "OMP_NESTED_MEMORY": "1"})
assert result.returncode == 0 and "token=synthetic-qa-token" in result.stdout
assert "arg=--config" not in result.stdout
print("PASS: env override, SOPS load/failure/empty, nested no-memory and opt-in; Darwin syntax/env/nested paths.")
