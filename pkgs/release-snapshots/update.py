#!/usr/bin/env python3

import argparse
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
from urllib.parse import quote
from urllib.request import Request, urlopen

GITHUB_API = "https://api.github.com/repos"
USER_AGENT = "nix-config-release-updater/1"


def request_headers(url: str) -> dict[str, str]:
    headers = {"User-Agent": USER_AGENT}
    if url.startswith("https://api.github.com/"):
        headers["Accept"] = "application/vnd.github+json"
        headers["X-GitHub-Api-Version"] = "2022-11-28"
        token = os.environ.get("GITHUB_TOKEN")
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
    releases = fetch_json(f"{GITHUB_API}/PostHog/posthog/releases?per_page=100")
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
    if release is None:
        raise RuntimeError("no stable PostHog CLI release found")
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
        description="Refresh stable release snapshots and flake inputs atomically."
    )
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument(
        "--snapshot-only",
        action="store_true",
        help=argparse.SUPPRESS,
    )
    arguments = parser.parse_args()

    repository = find_repository(arguments.repo.resolve())
    snapshot_path = repository / "pkgs" / "release-snapshots.json"
    lock_path = repository / "flake.lock"
    previous_snapshot = snapshot_path.read_bytes() if snapshot_path.exists() else None
    previous_lock = lock_path.read_bytes() if lock_path.exists() else None

    previous_data = json.loads(previous_snapshot) if previous_snapshot is not None else None

    try:
        snapshot = build_snapshot(previous_data)
        serialized = (json.dumps(snapshot, indent=2, sort_keys=True) + "\n").encode()
        if serialized != previous_snapshot:
            atomic_write(snapshot_path, serialized)
            print(f"updated {snapshot_path.relative_to(repository)}")
        else:
            print(f"unchanged {snapshot_path.relative_to(repository)}")

        if not arguments.snapshot_only:
            subprocess.run(["nix", "flake", "update"], cwd=repository, check=True)
    except BaseException:
        restore(snapshot_path, previous_snapshot)
        restore(lock_path, previous_lock)
        raise

    for name, manifest in sorted(snapshot["releaseManifests"].items()):
        release = manifest[0] if isinstance(manifest, list) else manifest
        version = release.get("version") or release.get("tag_name")
        print(f"{name}: {version}")
    print(f"beardrive: {snapshot['beardriveChecksums'].split('_', 2)[1]}")
    print(f"gajae-code: {snapshot['gajaeCodeManifest']['release_version']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
