#!/usr/bin/env python3

import argparse
import base64
import functools
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from typing import Any, Callable
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qsl, quote, urlencode, urlsplit, urlunsplit
from urllib.request import Request, urlopen

GITHUB_API = "https://api.github.com/repos"
USER_AGENT = "nix-config-release-updater/1"


@functools.cache
def github_token() -> str | None:
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        return token
    try:
        result = subprocess.run(
            ["gh", "auth", "token", "--hostname", "github.com"],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0:
            token = result.stdout.strip()
            if token:
                return token
    except (FileNotFoundError, OSError):
        pass
    return None


def request_headers(url: str) -> dict[str, str]:
    headers = {"User-Agent": USER_AGENT}
    if url.startswith("https://api.github.com/"):
        headers["Accept"] = "application/vnd.github+json"
        headers["X-GitHub-Api-Version"] = "2022-11-28"
        token = github_token()
        if token:
            headers["Authorization"] = f"Bearer {token}"
    return headers


def fetch_bytes(url: str) -> bytes:
    try:
        with urlopen(Request(url, headers=request_headers(url)), timeout=120) as response:
            return response.read()
    except (HTTPError, URLError) as error:
        raise RuntimeError(f"failed to fetch {url}: {error}") from error


def fetch_json(url: str) -> Any:
    try:
        return json.loads(fetch_bytes(url))
    except json.JSONDecodeError as error:
        raise RuntimeError(f"invalid JSON from {url}: {error}") from error


def sha256_digest(url: str) -> str:
    digest = hashlib.sha256()
    try:
        with urlopen(Request(url, headers=request_headers(url)), timeout=120) as response:
            while chunk := response.read(1024 * 1024):
                digest.update(chunk)
    except (HTTPError, URLError) as error:
        raise RuntimeError(f"failed to hash {url}: {error}") from error
    return f"sha256:{digest.hexdigest()}"


def select_assets(
    release: dict[str, Any],
    names: list[str],
    previous_release: dict[str, Any] | None = None,
) -> dict[str, Any]:
    assets = {asset["name"]: asset for asset in release.get("assets", [])}
    previous_assets = {
        asset["name"]: asset for asset in (previous_release or {}).get("assets", [])
    }
    selected = []
    for name in names:
        if name not in assets:
            raise RuntimeError(f"release {release.get('tag_name')} does not contain {name}")
        asset = assets[name]
        url = asset["browser_download_url"]
        digest = asset.get("digest")
        previous = previous_assets.get(name, {})
        if (
            (not isinstance(digest, str) or not digest.startswith("sha256:"))
            and previous.get("browser_download_url") == url
            and isinstance(previous.get("digest"), str)
            and previous["digest"].startswith("sha256:")
        ):
            digest = previous["digest"]
        if not isinstance(digest, str) or not digest.startswith("sha256:"):
            print(f"hashing {name}", file=sys.stderr)
            digest = sha256_digest(url)
        selected.append(
            {
                "browser_download_url": url,
                "digest": digest,
                "name": name,
            }
        )
    return {
        "assets": selected,
        "draft": bool(release.get("draft", False)),
        "prerelease": bool(release.get("prerelease", False)),
        "tag_name": release["tag_name"],
    }


def github_latest(
    repository: str,
    tag_prefix: str,
    asset_names: Callable[[str], list[str]],
    previous_release: dict[str, Any] | None,
) -> dict[str, Any]:
    release = fetch_json(f"{GITHUB_API}/{repository}/releases/latest")
    tag = release["tag_name"]
    if not tag.startswith(tag_prefix):
        raise RuntimeError(f"unexpected latest tag for {repository}: {tag}")
    version = tag.removeprefix(tag_prefix)
    return select_assets(release, asset_names(version), previous_release)


def posthog_release(
    previous_releases: list[dict[str, Any]] | None,
) -> list[dict[str, Any]]:
    page = 1
    while True:
        releases = fetch_json(
            f"{GITHUB_API}/PostHog/posthog/releases?per_page=100&page={page}"
        )
        release = next(
            (
                item
                for item in releases
                if not item.get("draft")
                and not item.get("prerelease")
                and item.get("tag_name", "").startswith("posthog-cli/v")
            ),
            None,
        )
        if release is not None:
            break
        if len(releases) < 100:
            raise RuntimeError("no stable PostHog CLI release found")
        page += 1

    previous_release = previous_releases[0] if previous_releases else None
    return [
        select_assets(
            release,
            [
                "posthog-cli-aarch64-apple-darwin.tar.gz",
                "posthog-cli-x86_64-apple-darwin.tar.gz",
                "posthog-cli-aarch64-unknown-linux-gnu.tar.gz",
                "posthog-cli-x86_64-unknown-linux-gnu.tar.gz",
            ],
            previous_release,
        )
    ]


def npm_latest(package_name: str, include_dependencies: bool = False) -> dict[str, Any]:
    package = fetch_json(f"https://registry.npmjs.org/{quote(package_name, safe='')}/latest")
    dist = package.get("dist", {})
    if not isinstance(dist.get("tarball"), str) or not isinstance(dist.get("integrity"), str):
        raise RuntimeError(f"npm metadata for {package_name} has no tarball integrity")
    snapshot = {
        "dist": {
            "integrity": dist["integrity"],
            "tarball": dist["tarball"],
        },
        "version": package["version"],
    }
    if include_dependencies:
        snapshot["dependencies"] = package.get("dependencies", {})
    return snapshot


def beardrive_checksums() -> str:
    url = "https://github.com/runbear-io/beardrive/releases/latest/download/checksums.txt"
    text = fetch_bytes(url).decode("utf-8")
    lines = [line for line in text.splitlines() if line]
    pattern = re.compile(
        r"^[0-9a-f]{64}  beardrive_[0-9]+\.[0-9]+\.[0-9]+_(darwin|linux)_(amd64|arm64)\.tar\.gz$"
    )
    if len(lines) != 4 or any(pattern.fullmatch(line) is None for line in lines):
        raise RuntimeError("BearDrive checksums do not contain the four expected assets")
    return "\n".join(lines) + "\n"


def gajae_manifest() -> dict[str, Any]:
    url = "https://github.com/Yeachan-Heo/gajae-code/releases/latest/download/gajae-release-binaries-v1.json"
    manifest = fetch_json(url)
    wanted = {"gjc-darwin-arm64", "gjc-darwin-x64", "gjc-linux-arm64", "gjc-linux-x64"}
    binaries = [
        {
            key: binary[key]
            for key in ("name", "sha256", "size")
            if key in binary
        }
        for binary in manifest.get("binaries", [])
        if binary.get("name") in wanted
    ]
    if {binary.get("name") for binary in binaries} != wanted:
        raise RuntimeError("Gajae Code manifest does not contain every supported binary")
    return {
        "binaries": sorted(binaries, key=lambda binary: binary["name"]),
        "release_channel": manifest.get("release_channel", "stable"),
        "release_version": manifest["release_version"],
        "schema": manifest.get("schema", "gajae-release-binaries-v1"),
        "schema_version": manifest.get("schema_version", 1),
        "tag": manifest.get("tag", f"v{manifest['release_version']}"),
    }


def build_snapshot(previous_snapshot: dict[str, Any] | None) -> dict[str, Any]:
    previous_releases = (previous_snapshot or {}).get("releaseManifests", {})

    def latest(
        key: str,
        repository: str,
        tag_prefix: str,
        asset_names: Callable[[str], list[str]],
    ) -> dict[str, Any]:
        return github_latest(
            repository,
            tag_prefix,
            asset_names,
            previous_releases.get(key),
        )

    releases = {
        "axiom": latest(
            "axiom",
            "axiomhq/cli",
            "v",
            lambda version: [
                f"axiom_{version}_darwin_arm64.tar.gz",
                f"axiom_{version}_linux_arm64.tar.gz",
                f"axiom_{version}_linux_amd64.tar.gz",
            ],
        ),
        "bun": latest(
            "bun",
            "oven-sh/bun",
            "bun-v",
            lambda _version: [
                "bun-darwin-aarch64.zip",
                "bun-linux-aarch64.zip",
                "bun-linux-x64.zip",
            ],
        ),
        "camoufox": latest(
            "camoufox",
            "daijro/camoufox",
            "v",
            lambda version: [
                f"camoufox-{version}-mac.arm64.zip",
                f"camoufox-{version}-lin.arm64.zip",
            ],
        ),
        "deskpad": latest(
            "deskpad",
            "Stengo/DeskPad",
            "v",
            lambda _version: ["DeskPad.app.zip"],
        ),
        "displayplacer": latest(
            "displayplacer",
            "jakehilborn/displayplacer",
            "v",
            lambda version: [f"displayplacer-apple-v{version.replace('.', '')}"],
        ),
        "langfuse": npm_latest("langfuse-cli", include_dependencies=True),
        "omp": latest(
            "omp",
            "can1357/oh-my-pi",
            "v",
            lambda _version: [
                "omp-darwin-arm64",
                "omp-linux-musl-arm64",
                "omp-linux-musl-x64",
            ],
        ),
        "posthog": posthog_release(previous_releases.get("posthog")),
        "sentry": latest(
            "sentry",
            "getsentry/cli",
            "",
            lambda _version: [
                "sentry-darwin-arm64",
                "sentry-linux-arm64",
                "sentry-linux-x64",
            ],
        ),
        "slack": latest(
            "slack",
            "slackapi/slack-cli",
            "v",
            lambda version: [
                f"slack_cli_{version}_macOS_arm64.tar.gz",
                f"slack_cli_{version}_linux_arm64.tar.gz",
                f"slack_cli_{version}_linux_amd64.tar.gz",
            ],
        ),
        "vercelDarwinArm64": npm_latest("@vercel/vc-native-darwin-arm64"),
        "vercelLinuxArm64": npm_latest("@vercel/vc-native-linux-arm64"),
        "vercelLinuxX64": npm_latest("@vercel/vc-native-linux-x64"),
    }
    return {
        "beardriveChecksums": beardrive_checksums(),
        "gajaeCodeManifest": gajae_manifest(),
        "releaseManifests": releases,
        "schema": 1,
    }

# Root inputs whose own flake.lock must be replicated into this repository's
# lock graph. Their nested inputs are deliberately NOT `follows`-ed: the
# packages taken from these flakes are built against the exact revisions the
# parent pinned, which is what makes the store paths match the parent's binary
# cache (cache.numtide.com, FlakeHub). Nix's `github:` fetcher is disallowed in
# this repository, so every nested input is re-declared in flake.nix as an
# immutable `git+https` (or pinned tarball) URL inside the AUTOGENERATED block
# below the input. The declared URL here is the floating intent; the pinned
# revision is written into flake.nix by sync_parent_locks so the lock update
# cannot race a moving upstream HEAD.
PARENT_LOCK_INPUTS = {
    "llm-agents": "git+https://github.com/numtide/llm-agents.nix.git?shallow=1",
    "nix-homebrew": "git+https://github.com/zhaofengli/nix-homebrew.git?shallow=1",
    "determinate": "https://flakehub.com/f/DeterminateSystems/determinate/3",
}


def nix_json(*arguments: str) -> Any:
    result = subprocess.run(
        ["nix", *arguments],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f"nix {' '.join(arguments)} failed: {result.stderr.strip()}")
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(f"nix {' '.join(arguments)} returned invalid JSON") from error


def resolve_parent(name: str, url: str) -> dict[str, Any]:
    metadata = nix_json("flake", "metadata", "--json", "--no-write-lock-file", "--refresh", url)
    locked = metadata["locked"]
    parent_lock = metadata.get("locks")
    if not isinstance(parent_lock, dict) or parent_lock.get("root") not in parent_lock.get("nodes", {}):
        raise RuntimeError(f"{name}: upstream provides no usable flake lock graph")
    pin_url = input_override({"locked": locked})
    if pin_url is None:
        raise RuntimeError(f"{name}: parent cannot be pinned to a remote source")
    fetched = nix_json("flake", "prefetch", "--json", pin_url)
    if locked.get("narHash") and locked["narHash"] != fetched["hash"]:
        raise RuntimeError(f"{name}: resolved parent content changed while fetching")
    locked["narHash"] = fetched["hash"]
    return {"pin_url": pin_url, "lock": parent_lock, "locked": locked}


def input_override(node: dict[str, Any]) -> str | None:
    """Preserve source content while pinning every remote input immutably."""
    locked = node.get("locked") or {}
    kind = locked.get("type")
    if kind == "github":
        url = f"https://github.com/{locked['owner']}/{locked['repo']}.git"
    elif kind == "git":
        url = locked["url"].removeprefix("git+")
    elif kind == "file":
        return "file+" + locked["url"].removeprefix("file+")
    elif kind == "tarball":
        return locked["url"]
    elif kind == "path":
        return None
    else:
        raise RuntimeError(f"unsupported locked transport {kind!r} in parent lock")
    parsed = urlsplit(url)
    query = dict(parse_qsl(parsed.query))
    query.pop("ref", None)
    query["rev"] = locked["rev"]
    if parsed.hostname == "github.com":
        if not parsed.path.endswith(".git"):
            parsed = parsed._replace(path=parsed.path + ".git")
        query["shallow"] = "1"
    elif locked.get("shallow"):
        query["shallow"] = "1"
    for key in ("dir", "submodules", "lfs"):
        if key in locked:
            value = locked[key]
            query[key] = str(int(value)) if isinstance(value, bool) else str(value)
    return "git+" + urlunsplit(parsed._replace(query=urlencode(query)))


def nix_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False).replace("${", r"\${")


def parent_override_lines(name: str, parent: dict[str, Any]) -> list[str]:
    lines = [f'{name}.url = {nix_string(parent["pin_url"])};']
    nodes = parent["lock"]["nodes"]

    def walk(node_name: str, path: tuple[str, ...], active: frozenset[str]) -> None:
        if node_name in active:
            raise RuntimeError(f"{name}: cyclic non-follows input at {'/'.join(path)}")
        for input_name, edge in sorted(nodes[node_name].get("inputs", {}).items()):
            parts = (*path, input_name)
            attribute = name + "".join(".inputs." + nix_string(part) for part in parts)
            if isinstance(edge, list):
                target_path = "/".join((name, *edge))
                lines.append(f"{attribute}.follows = {nix_string(target_path)};")
                continue
            target = nodes[edge]
            url = input_override(target)
            if url is not None:
                lines.append(f"{attribute}.url = {nix_string(url)};")
                if target.get("flake") is False:
                    lines.append(f"{attribute}.flake = false;")
            walk(edge, parts, active | {node_name})

    walk(parent["lock"]["root"], (), frozenset())
    return lines


def splice_block(text: str, name: str, lines: list[str]) -> str:
    marker = f"AUTOGENERATED {name.upper()} INPUTS"
    pattern = re.compile(
        rf"^([ \t]*)# >>> {re.escape(marker)} <<<\n.*?^([ \t]*)# <<< {re.escape(marker)} <<<\n?",
        re.DOTALL | re.MULTILINE,
    )
    matches = list(pattern.finditer(text))
    if len(matches) != 1:
        raise RuntimeError(
            f"flake.nix must contain exactly one '# >>> {marker} <<<' block, found {len(matches)}"
        )
    indent = matches[0].group(1)
    body = [f"{indent}# >>> {marker} <<<"]
    body.append(f"{indent}# Generated by `nix run .#update-packages`; do not edit by hand.")
    body.extend(indent + line for line in lines)
    body.append(f"{indent}# <<< {marker} <<<")
    return pattern.sub(lambda _: "\n".join(body) + "\n", text, count=1)


def verify_transport_content(parents: dict[str, Any]) -> None:
    """Check Git conversions against the hashes resolved in the upstream lock."""
    checked: set[tuple[str, str]] = set()
    for name, parent in parents.items():
        for node in parent["lock"]["nodes"].values():
            locked = node.get("locked") or {}
            if locked.get("type") not in ("github", "git"):
                continue
            url = input_override(node)
            expected = locked.get("narHash")
            if not url or not expected:
                raise RuntimeError(f"{name}: Git input has no content hash")
            if (url, expected) in checked:
                continue
            fetched = nix_json("flake", "prefetch", "--json", url)
            if fetched.get("hash") != expected:
                raise RuntimeError(f"{name}: Git transport changes source content for {url}")
            checked.add((url, expected))


def sync_parent_locks(flake_path: Path) -> tuple[dict[str, Any], bool]:
    parents = {name: resolve_parent(name, url) for name, url in PARENT_LOCK_INPUTS.items()}
    verify_transport_content(parents)
    original = flake_path.read_text()
    text = original
    for name, parent in parents.items():
        text = splice_block(text, name, parent_override_lines(name, parent))
    if text != original:
        atomic_write(flake_path, text.encode())
    return parents, text != original


def resolve_edge(
    nodes: dict[str, Any], edge: Any, root: str = "root",
    seen: frozenset[tuple[str, ...]] = frozenset(),
) -> str:
    if isinstance(edge, str):
        if edge not in nodes:
            raise RuntimeError(f"lock references missing node {edge}")
        return edge
    if not isinstance(edge, list):
        raise RuntimeError(f"invalid lock edge {edge!r}")
    path = tuple(edge)
    if path in seen:
        raise RuntimeError(f"cyclic follows path {'/'.join(path)}")
    current = root
    for segment in path:
        target = nodes[current].get("inputs", {}).get(segment)
        if target is None:
            raise RuntimeError(f"unresolved follows path {'/'.join(path)}")
        current = resolve_edge(nodes, target, root, seen | {path})
    return current


def node_fingerprint(node: dict[str, Any]) -> tuple[Any, Any, Any]:
    locked = node.get("locked") or {}
    # URLs intentionally change when github inputs become Git inputs.
    return locked.get("rev"), locked.get("narHash"), node.get("flake", True)


def verify_lock_graph(lock: dict[str, Any], parents: dict[str, Any]) -> None:
    nodes = lock["nodes"]
    root = lock["root"]
    for name, node in nodes.items():
        for label in ("original", "locked"):
            source = node.get(label) or {}
            if source.get("type") == "github":
                raise RuntimeError(f"{name}: disallowed github fetcher in {label}")
            if source.get("type") == "git" and urlsplit(source.get("url", "")).hostname == "github.com":
                if not source.get("shallow") or not source["url"].endswith(".git"):
                    raise RuntimeError(f"{name}: GitHub Git input must use .git and shallow=1")

    for name, parent in parents.items():
        our_root = resolve_edge(nodes, nodes[root]["inputs"][name], root)
        if node_fingerprint({"locked": parent["locked"]}) != node_fingerprint(nodes[our_root]):
            raise RuntimeError(f"{name}: locked parent differs from the resolved source")
        parent_nodes = parent["lock"]["nodes"]
        parent_root = parent["lock"]["root"]
        compared: set[tuple[str, str]] = set()

        def compare(expected: str, actual: str) -> None:
            if (expected, actual) in compared:
                return
            compared.add((expected, actual))
            if expected != parent_root and node_fingerprint(parent_nodes[expected]) != node_fingerprint(nodes[actual]):
                raise RuntimeError(f"{name}: locked content of {actual} diverges from the parent lock")
            expected_inputs = parent_nodes[expected].get("inputs", {})
            actual_inputs = nodes[actual].get("inputs", {})
            if expected_inputs.keys() != actual_inputs.keys():
                raise RuntimeError(f"{name}: input names changed below {actual}")
            for input_name, edge in expected_inputs.items():
                ours = actual_inputs[input_name]
                if isinstance(edge, list) and ours != [name, *edge]:
                    raise RuntimeError(f"{name}: follows relationship changed for {input_name}")
                compare(
                    resolve_edge(parent_nodes, edge, parent_root),
                    resolve_edge(nodes, ours, root),
                )

        compare(parent_root, our_root)


def npm_source_overrides(lock: dict[str, Any], previous: dict[str, Any]) -> dict[str, Any]:
    nodes = lock["nodes"]
    edge = nodes[lock["root"]]["inputs"].get("pi-codegraph-source")
    if edge is None:
        raise RuntimeError("flake.lock has no pi-codegraph-source input")
    locked = nodes[resolve_edge(nodes, edge, lock["root"])]["locked"]
    match = re.fullmatch(r"https://github\.com/([^/]+)/([^/]+?)(?:\.git)?", locked.get("url", ""))
    if locked.get("type") != "git" or not match:
        raise RuntimeError("pi-codegraph-source must be a locked GitHub Git source")
    package_lock = fetch_json(
        f"https://raw.githubusercontent.com/{match[1]}/{match[2]}/{locked['rev']}/package-lock.json"
    )
    if not isinstance(package_lock.get("packages"), dict):
        raise RuntimeError("pi-codegraph package-lock.json has no packages map")
    previous_overrides = previous.get("piCodegraph", {})
    overrides: dict[str, Any] = {}
    for path, entry in sorted(package_lock["packages"].items()):
        if entry.get("integrity") is not None:
            continue
        resolved = entry.get("resolved") or ""
        if not resolved.startswith(("https://", "http://")):
            continue
        version = entry.get("version")
        if not version:
            raise RuntimeError(f"pi-codegraph: missing version for unhashed package {path}")
        reused = previous_overrides.get(path, {})
        if (
            reused.get("version") == version
            and reused.get("resolved") == resolved
            and re.fullmatch(r"sha512-[A-Za-z0-9+/]{86}==", reused.get("integrity", ""))
        ):
            overrides[path] = reused
            continue
        digest = hashlib.sha512()
        with urlopen(Request(resolved, headers=request_headers(resolved)), timeout=60) as response:
            for block in iter(lambda: response.read(1024 * 1024), b""):
                digest.update(block)
        overrides[path] = {
            "version": version,
            "resolved": resolved,
            "integrity": "sha512-" + base64.b64encode(digest.digest()).decode(),
        }
    return {"piCodegraph": overrides}


def upgrade_determinate_nixd() -> None:
    """Upgrade the external Nix installation. Runs after the source transaction
    commits: it restarts the Nix daemon, so no nix subprocess may be in flight."""
    binary = "/usr/local/bin/determinate-nixd"
    command = [binary, "upgrade", "--version", "stable"]
    if os.geteuid() != 0:
        command.insert(0, "sudo")
    print("upgrading Determinate Nix installation (daemon restarts)")
    result = subprocess.run(command, check=False)
    if result.returncode != 0:
        raise RuntimeError(
            "determinate-nixd upgrade failed; the source transaction above "
            "committed successfully and was NOT rolled back"
        )


def atomic_write(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as file:
            file.write(content)
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def restore(path: Path, content: bytes | None) -> None:
    if content is None:
        path.unlink(missing_ok=True)
    else:
        atomic_write(path, content)


def find_repository(start: Path) -> Path:
    for candidate in (start, *start.parents):
        if (candidate / "flake.nix").is_file() and (candidate / "pkgs").is_dir():
            return candidate
    raise RuntimeError(f"no nix-config repository found above {start}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Refresh managed package sources; then upgrade bootstrap Nix on macOS."
    )
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--snapshot-only", action="store_true", help=argparse.SUPPRESS)
    arguments = parser.parse_args()
    bootstrap = sys.platform == "darwin" and not arguments.snapshot_only
    if bootstrap and not os.access("/usr/local/bin/determinate-nixd", os.X_OK):
        raise RuntimeError("Determinate Nix must be installed before running update-packages on macOS")

    repository = find_repository(arguments.repo.resolve())
    snapshot_path = repository / "pkgs" / "release-snapshots.json"
    lock_path = repository / "flake.lock"
    flake_path = repository / "flake.nix"
    previous = {
        path: path.read_bytes() if path.exists() else None
        for path in (snapshot_path, lock_path, flake_path)
    }
    previous_data = json.loads(previous[snapshot_path]) if previous[snapshot_path] else {}
    try:
        snapshot = build_snapshot(previous_data)
        parents: dict[str, Any] = {}
        if not arguments.snapshot_only:
            parents, _ = sync_parent_locks(flake_path)
            subprocess.run(["nix", "flake", "update"], cwd=repository, check=True)
        lock = json.loads(lock_path.read_bytes())
        verify_lock_graph(lock, parents)
        snapshot["npmSourceOverrides"] = npm_source_overrides(
            lock, previous_data.get("npmSourceOverrides", {})
        )
        serialized = (json.dumps(snapshot, indent=2, sort_keys=True) + "\n").encode()
        if serialized != previous[snapshot_path]:
            atomic_write(snapshot_path, serialized)
        print("source update completed" if not arguments.snapshot_only else "release snapshots updated; flake inputs unchanged")
    except BaseException:
        for path, content in previous.items():
            restore(path, content)
        raise

    for name, manifest in sorted(snapshot["releaseManifests"].items()):
        release = manifest[0] if isinstance(manifest, list) else manifest
        print(f"{name}: {release.get('version') or release.get('tag_name')}")
    print(f"beardrive: {snapshot['beardriveChecksums'].split('_', 2)[1]}")
    print(f"gajae-code: {snapshot['gajaeCodeManifest']['release_version']}")
    if bootstrap:
        upgrade_determinate_nixd()
    print("Run the target host's switch to install the updated packages and managed apps.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
