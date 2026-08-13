#!/usr/bin/env python3
"""Diff lib/ssh-audit.nix against what ssh-audit recommends today.

ssh-audit's hardening guides are generated from the same table that drives its
built-in policies, and `--get-hardening-guide` prints one as a shell script
whose payload is the literal sshd_config text. That payload is the machine
readable form of "what is recommended right now", so this reads it rather than
a web page, and compares it to the profile we actually ship.

Exit status is 0 when they agree, 1 when they drift, 2 when something went
wrong enough that no comparison was made. Drift is not a failure — it is the
whole point of running this — but it does mean a human has to decide.
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

# Every modern OS guide emits the same directives; the OS-specific parts are the
# surrounding shell (where the file goes, how the service restarts), which does
# not apply to either of our platforms. Ubuntu 26.04 is the newest server guide
# and targets the OpenSSH 10.x line both our platforms are on.
DEFAULT_GUIDE = "Ubuntu 26.04 Server"

# GSSAPI key exchange is a Debian/Ubuntu patch, not upstream OpenSSH. The
# directive is a fatal "Bad configuration option" on Apple's sshd and on
# nixpkgs' — see lib/ssh-audit.nix. Ignored on both sides of the comparison so
# that its absence never reads as drift.
NOT_UPSTREAM = {"GSSAPIKexAlgorithms"}

# HostKey lines appear in some guides (Rocky) and not others (Debian, Ubuntu).
# We express host keys through the platform's own `hostKeys` option, which
# writes those lines for us and generates the keys, so they are compared
# separately from the directive block.
HANDLED_ELSEWHERE = {"HostKey"}

REPO = Path(__file__).resolve().parents[3]
PROFILE = REPO / "lib" / "ssh-audit.nix"


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, check=True, **kw).stdout


def strip_ansi(s):
    return re.sub(r"\x1b\[[0-9;]*m", "", s)


def fetch_guide(guide):
    """Return the guide's raw text, via nix so no ssh-audit install is needed."""
    out = run(["nix", "run", "nixpkgs#ssh-audit", "--", "--get-hardening-guide", guide])
    return strip_ansi(out)


class GuideError(Exception):
    """The guide could not be read, so no comparison was made."""


def parse_guide(text):
    """Pull the sshd_config directives and the host key recipe out of a guide.

    The directive block is the argument of `echo -e "..."`, with \\n escapes and
    embedded \\" quoting. Everything outside it is shell we do not follow.
    """
    # ssh-audit answers an unknown guide name on stdout and still exits 0, so
    # this is checked here rather than by the subprocess call.
    if "Invalid guide name" in text:
        raise GuideError("no such guide")

    m = re.search(r'echo -e "(.*?)"\s*>', text, re.S)
    if not m:
        raise GuideError('guide has no `echo -e "..." >` block; its format changed')

    body = m.group(1).replace('\\"', '"').replace("\\n", "\n")

    directives = {}
    for line in body.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        key, _, value = line.partition(" ")
        if key in HANDLED_ELSEWHERE:
            continue
        directives[key] = value.strip()

    # `ssh-keygen -t rsa -b 4096 -f ...` — the size the guide wants generated,
    # which is a different number from RequiredRSASize and easy to conflate.
    keygen = {}
    for kt, bits in re.findall(
        r"ssh-keygen -t (\w+)(?: -b (\d+))? -f /etc/ssh/ssh_host_\w+_key", text
    ):
        keygen[kt] = int(bits) if bits else None

    return directives, keygen


def load_profile():
    """Our own profile, rendered into the same directive form."""
    data = json.loads(run(["nix", "eval", "--json", "-f", str(PROFILE)]))

    directives = {}
    for key, value in data["sshdSettings"].items():
        directives[key] = ",".join(value) if isinstance(value, list) else str(value)

    keygen = {k["type"]: k.get("bits") for k in data["hostKeys"].values()}
    return directives, keygen


def compare(guide_d, ours_d, guide_k, ours_k):
    problems = []

    # Directive spelling is ours to choose — sshd_config keywords are
    # case-insensitive, and NixOS names the MACs option `Macs`. Compare on a
    # normalised key so that choice does not register as drift.
    g = {k.lower(): (k, v) for k, v in guide_d.items() if k not in NOT_UPSTREAM}
    o = {k.lower(): (k, v) for k, v in ours_d.items()}

    for k in sorted(set(g) - set(o)):
        name, value = g[k]
        problems.append(f"missing: {name} {value}")

    for k in sorted(set(o) - set(g)):
        name, value = o[k]
        problems.append(f"extra (not in the guide): {name} {value}")

    for k in sorted(set(g) & set(o)):
        gname, gvalue = g[k]
        oname, ovalue = o[k]
        if gvalue != ovalue:
            problems.append(f"differs: {gname}\n    guide: {gvalue}\n    ours:  {ovalue}")

    for kt in sorted(set(guide_k) | set(ours_k)):
        want, have = guide_k.get(kt, "absent"), ours_k.get(kt, "absent")
        # `None` means ssh-keygen's own default for that type, which is what an
        # entry with no `bits` asks for. The two spellings mean the same thing.
        if want == have or (want is None and have is None):
            continue
        problems.append(f"host key {kt}: guide wants {want}, we declare {have}")

    return problems


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--guide", default=DEFAULT_GUIDE, help=f"default: {DEFAULT_GUIDE}")
    args = ap.parse_args()

    if shutil.which("nix") is None:
        print("nix is not on PATH", file=sys.stderr)
        return 2

    try:
        guide_text = fetch_guide(args.guide)
        guide_d, guide_k = parse_guide(guide_text)
    except (subprocess.CalledProcessError, GuideError) as e:
        detail = getattr(e, "stderr", None) or str(e)
        print(f"{args.guide!r}: {detail.strip()}", file=sys.stderr)
        print(
            "`nix run nixpkgs#ssh-audit -- --list-hardening-guides` shows the "
            "current names.",
            file=sys.stderr,
        )
        return 2

    ours_d, ours_k = load_profile()

    version = re.search(r"Hardening guide for (.+)", guide_text)
    print(f"guide:   {version.group(1) if version else args.guide}")
    print(f"profile: {PROFILE.relative_to(REPO)}")
    print()

    problems = compare(guide_d, ours_d, guide_k, ours_k)
    if not problems:
        print(f"No drift. {len(ours_d)} directives and {len(ours_k)} host key types agree.")
        if NOT_UPSTREAM & set(guide_d):
            skipped = ", ".join(sorted(NOT_UPSTREAM & set(guide_d)))
            print(f"({skipped} deliberately not ported — see lib/ssh-audit.nix.)")
        return 0

    print(f"{len(problems)} difference(s):\n")
    for p in problems:
        print(f"  {p}")
    print()
    print("Each one is a decision, not a task. A new directive may not exist on")
    print("Apple's sshd or on nixpkgs' — check with `sshd -t` before shipping it,")
    print("and if it is rejected, record why in lib/ssh-audit.nix rather than")
    print("dropping it silently.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
