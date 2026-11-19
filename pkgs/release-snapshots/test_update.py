#!/usr/bin/env python3
"""Unit tests for camoufox fallback handling in pkgs/release-snapshots/update.py."""
import contextlib
from email.message import Message
import importlib.util
import io
import json
from pathlib import Path
import sys
from unittest.mock import patch
from urllib.error import HTTPError, URLError

sys.dont_write_bytecode = True

UPDATE_PATH = Path(__file__).resolve().with_name("update.py")
spec = importlib.util.spec_from_file_location("release_snapshots_update", UPDATE_PATH)
assert spec and spec.loader
update = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = update
spec.loader.exec_module(update)

FAKE_LOCK = {
    "root": "root",
    "nodes": {
        "root": {"inputs": {"camofox-browser-source": "camofox-browser-source"}},
        "camofox-browser-source": {
            "locked": {
                "type": "git",
                "url": "https://github.com/jo-inc/camofox-browser.git",
                "rev": "31376c27db94204ffdc635ae71a7f61328e91a5e",
            }
        },
    },
}

PREVIOUS_SNAPSHOT = {
    "assets": [
        {
            "browser_download_url": "https://github.com/daijro/camoufox/releases/download/v152.0.4-beta.30/camoufox-152.0.4-beta.30-mac.arm64.zip",
            "digest": "sha256:3b43e766574f286a6a63296cf58b660b7a3120952086c869b4df4c9a71604bc3",
            "name": "camoufox-152.0.4-beta.30-mac.arm64.zip",
        },
        {
            "browser_download_url": "https://github.com/daijro/camoufox/releases/download/v152.0.4-beta.30/camoufox-152.0.4-beta.30-lin.arm64.zip",
            "digest": "sha256:60447260af8bebdb0ec3f2aa72f687b879e5598367303de2e3fdbc7a5be8c124",
            "name": "camoufox-152.0.4-beta.30-lin.arm64.zip",
        },
    ],
    "draft": False,
    "prerelease": False,
    "tag_name": "v152.0.4-beta.30",
}


class FakeResponse:
    def __init__(self, body: bytes):
        self._body = body

    def read(self) -> bytes:
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


def make_urlopen(download_js: bytes, api_handler):
    def fake_urlopen(req, timeout=120):
        url = req.full_url if hasattr(req, "full_url") else str(req)
        if url.endswith("/lib/camoufox-download.js"):
            return FakeResponse(download_js)
        return api_handler(url)

    return fake_urlopen


def http_error(url: str, code: int, msg: str = "error") -> HTTPError:
    return HTTPError(url, code, msg, Message(), None)


def call_with_mock(download_js: bytes, api_handler, previous):
    stderr = io.StringIO()
    with (
        patch.object(update, "github_token", return_value=None),
        patch.object(update, "urlopen", side_effect=make_urlopen(download_js, api_handler)),
        contextlib.redirect_stderr(stderr),
    ):
        result = update.camoufox_release(FAKE_LOCK, previous)
    return result, stderr.getvalue()


def assert_raises_runtime(download_js: bytes, api_handler, previous):
    try:
        call_with_mock(download_js, api_handler, previous)
    except RuntimeError as exc:
        return exc
    raise AssertionError("expected RuntimeError, but call succeeded")


# 1. HTTP 404 with matching previous snapshot -> keep previous + warn to stderr
js_same = b"export const BUNDLED_CAMOUFOX_RELEASE = '152.0.4-beta.30';\n"
res, err = call_with_mock(
    js_same,
    lambda url: (_ for _ in ()).throw(http_error(url, 404, "Not Found")),
    PREVIOUS_SNAPSHOT,
)
assert res == PREVIOUS_SNAPSHOT, res
assert "warning: daijro/camoufox returned HTTP 404; keeping existing camoufox snapshot v152.0.4-beta.30" in err, err
assert "declares" not in err, err

# 2. HTTP 410 and HTTP 451 with bumped bundled version -> warn with declared version + keep previous
js_newer = b"export const BUNDLED_CAMOUFOX_RELEASE = '153.0.0-beta.1';\n"
for code in (410, 451):
    res, err = call_with_mock(
        js_newer,
        lambda url, c=code: (_ for _ in ()).throw(http_error(url, c, "Gone")),
        PREVIOUS_SNAPSHOT,
    )
    assert res == PREVIOUS_SNAPSHOT, (code, res)
    assert (
        f"warning: daijro/camoufox returned HTTP {code}; keeping existing camoufox snapshot "
        f"v152.0.4-beta.30 (camofox-browser declares v153.0.0-beta.1)"
    ) in err, (code, err)

# 3. Transient server/network errors (HTTP 500, HTTP 429, URLError) must still fail fast
for exc_factory in (
    lambda url: http_error(url, 500, "Internal Server Error"),
    lambda url: http_error(url, 429, "Too Many Requests"),
    lambda _url: URLError("dns temporary failure"),
):
    assert_raises_runtime(
        js_same,
        lambda url, mk=exc_factory: (_ for _ in ()).throw(mk(url)),
        PREVIOUS_SNAPSHOT,
    )

# 4. Missing or incomplete previous snapshot on 404 must still fail instead of returning broken data
bad_digest_prev = {
    **PREVIOUS_SNAPSHOT,
    "assets": [
        PREVIOUS_SNAPSHOT["assets"][0],
        {**PREVIOUS_SNAPSHOT["assets"][1], "digest": "sha256:"},
    ],
}
missing_asset_prev = {**PREVIOUS_SNAPSHOT, "assets": [PREVIOUS_SNAPSHOT["assets"][0]]}
empty_url_prev = {
    **PREVIOUS_SNAPSHOT,
    "assets": [{**PREVIOUS_SNAPSHOT["assets"][0], "browser_download_url": ""}, PREVIOUS_SNAPSHOT["assets"][1]],
}
for bad_prev in (None, {}, missing_asset_prev, bad_digest_prev, empty_url_prev):
    assert_raises_runtime(
        js_same,
        lambda url: (_ for _ in ()).throw(http_error(url, 404, "Not Found")),
        bad_prev,
    )

# 5. Upstream HTTP 200 recovery resumes normal manifest refresh
new_release_payload = {
    "tag_name": "v153.0.0-beta.1",
    "draft": False,
    "prerelease": False,
    "assets": [
        {
            "name": "camoufox-153.0.0-beta.1-mac.arm64.zip",
            "browser_download_url": "https://example.test/camoufox-153.0.0-beta.1-mac.arm64.zip",
            "digest": "sha256:" + "a" * 64,
        },
        {
            "name": "camoufox-153.0.0-beta.1-lin.arm64.zip",
            "browser_download_url": "https://example.test/camoufox-153.0.0-beta.1-lin.arm64.zip",
            "digest": "sha256:" + "b" * 64,
        },
    ],
}
res_ok, err_ok = call_with_mock(
    js_newer,
    lambda _url: FakeResponse(json.dumps(new_release_payload).encode()),
    PREVIOUS_SNAPSHOT,
)
assert res_ok["tag_name"] == "v153.0.0-beta.1", res_ok
assert [a["name"] for a in res_ok["assets"]] == [
    "camoufox-153.0.0-beta.1-mac.arm64.zip",
    "camoufox-153.0.0-beta.1-lin.arm64.zip",
], res_ok
assert err_ok == "", err_ok

# 6. Missing BUNDLED_CAMOUFOX_RELEASE constant in camofox-download.js fails explicitly
assert_raises_runtime(
    b"// no release declared\n",
    lambda _url: FakeResponse(b"{}"),
    PREVIOUS_SNAPSHOT,
)

print("PASS: update.py camoufox fallback and error propagation checks passed.")
