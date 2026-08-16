# @askjo/camofox-browser is published with its JavaScript already built, but
# without a lock file.  Keep the upstream manifest and a generated lock beside
# this expression so buildNpmPackage can fetch the complete dependency graph as
# a fixed-output derivation instead of consulting npm while it builds.
#
# The package's postinstall script runs `npx camoufox-js fetch`.  Lifecycle
# scripts are deliberately disabled: Camoufox is the separate immutable Nix
# package below, and downloading another copy during either build or runtime
# would be both impure and the wrong architecture-selection boundary.
{
  lib,
  buildNpmPackage,
  fetchurl,
  makeWrapper,
  camoufox,
}:

buildNpmPackage (finalAttrs: {
  pname = "camofox-browser";
  version = "1.13.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/@askjo/camofox-browser/-/camofox-browser-${finalAttrs.version}.tgz";
    hash = "sha256-QftpwzCdTkK2E7gAnXk7jzCIo66+lnnFqQYetlKLzo0=";
  };

  # npm's published tarball has no lock file.  Copy both files because this
  # lock was generated from the repository manifest, before npm normalized the
  # manifest for publication, and npm ci requires the pair to agree.
  #
  # Camofox defaults to headless upstream.  CAMOFOX_HEADLESS=false is the
  # explicit Darwin headful path: Linux still disables headless whenever its
  # existing virtual display starts, while a missing Linux display and every
  # unset environment retain the upstream true default.

  # Upstream's sessionKey only selected the group used when a tab was created.
  # Listing and every tabId operation still searched all groups under userId,
  # so clients sharing cookies also shared tab visibility and control. Keep the
  # REST compatibility path when no sessionKey is supplied, but make the MCP
  # adapter send it on every operation and enforce that group on the server.
  patches = [ ./session-isolation.patch ];
  postPatch = ''
    cp ${./package.json} package.json
    cp ${./package-lock.json} package-lock.json

    substituteInPlace lib/config.js \
      --replace-fail \
        "    camoufoxCacheDir: camoufoxCacheDir()," \
        "    camoufoxCacheDir: camoufoxCacheDir(),
    headless: process.env.CAMOFOX_HEADLESS !== 'false'," \
      --replace-fail \
        "      CAMOFOX_DISABLE_DEFAULT_ADDONS: process.env.CAMOFOX_DISABLE_DEFAULT_ADDONS," \
        "      CAMOFOX_DISABLE_DEFAULT_ADDONS: process.env.CAMOFOX_DISABLE_DEFAULT_ADDONS,
      CAMOFOX_HEADLESS: process.env.CAMOFOX_HEADLESS,"

    substituteInPlace server.js \
      --replace-fail \
        "        headless: useVirtualDisplay ? false : true," \
        "        headless: useVirtualDisplay ? false : CONFIG.headless,"

    # Camoufox's Darwin protocol schema rejects Playwright's implicit default
    # viewport because it includes an isMobile field.  Session creation and
    # launch validation already use viewport=null; keep the idle health probe
    # on the same compatible path so it does not restart a healthy browser
    # every three minutes.
    substituteInPlace server.js \
      --replace-fail \
        "    testContext = await browser.newContext();" \
        "    testContext = await browser.newContext({ viewport: null });"

    # A temporary executable symlink outside Camoufox.app breaks macOS
    # bundle-relative XPCOM lookup.  Launch the resolved app binary directly;
    # the Camoufox package exposes camoufox-js resources beside it.
    substituteInPlace lib/camoufox-executable.js \
      --replace-fail \
        "    executablePath: ensureLaunchShim(resolvedExecutable, resourceDir)," \
        "    executablePath: platform() === 'darwin'
      ? realpathSync(resolvedExecutable)
      : ensureLaunchShim(resolvedExecutable, resourceDir),"
  '';

  npmDepsHash = "sha256-YwBkv61aYF/I3Ge/PzHyZhveBfx+Os+LaVsNxN4tE6Y=";

  # --include=optional is intentional.  impit supplies its native N-API module
  # through optional platform packages, and the Darwin build needs
  # impit-darwin-arm64.  --ignore-scripts keeps those prebuilt artifacts while
  # suppressing every lifecycle hook, especially the Camoufox downloader.
  npmFlags = [
    "--ignore-scripts"
    "--include=optional"
  ];
  dontNpmBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  # Both public entry points can start or locate the browser.  Give each the
  # same immutable executable and skip flags so neither the server nor MCP path
  # can fall through to a per-user network download.  The upstream crash
  # reporter is opt-out; packaged invocations opt out centrally here.
  postInstall = ''
    for program in camofox-browser camofox-browser-mcp; do
      wrapProgram "$out/bin/$program" \
        --set CAMOUFOX_EXECUTABLE "${camoufox}/Applications/Camoufox.app/Contents/MacOS/camoufox" \
        --set CAMOUFOX_SKIP_DOWNLOAD 1 \
        --set CAMOFOX_SKIP_DOWNLOAD 1 \
        --set PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD 1 \
        --set CAMOFOX_CRASH_REPORT_ENABLED false
    done
  '';

  meta = {
    description = "Camofox browser automation server and MCP integration";
    homepage = "https://github.com/jo-inc/camofox-browser";
    license = lib.licenses.mit;
    mainProgram = "camofox-browser";
    platforms = [ "aarch64-darwin" ];
    maintainers = [ ];
  };
})
