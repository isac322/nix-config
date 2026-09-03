# @askjo/camofox-browser is published with its JavaScript already built, but
# without a lock file. Keep the upstream manifest and a generated lock beside
# this expression so buildNpmPackage can fetch the complete dependency graph as
# a fixed-output derivation instead of consulting npm while it builds.
#
# The package's postinstall script runs `npx camoufox-js fetch`. Lifecycle
# scripts are deliberately disabled: Camoufox is the separate immutable Nix
# package below, and downloading another copy during either build or runtime
# would be both impure and the wrong architecture-selection boundary.
{
  lib,
  stdenv,
  buildNpmPackage,
  fetchurl,
  makeWrapper,
  camoufox,
}:

let
  camoufoxExecutable =
    if stdenv.hostPlatform.isDarwin then
      "${camoufox}/Applications/Camoufox.app/Contents/MacOS/camoufox"
    else
      "${camoufox}/lib/camoufox/camoufox-bin";
  camoufoxResourceDir =
    if stdenv.hostPlatform.isDarwin then
      "${camoufox}/Applications/Camoufox.app/Contents/Resources"
    else
      "${camoufox}/lib/camoufox";
  cachedExecutable =
    if stdenv.hostPlatform.isDarwin then "Camoufox.app/Contents/MacOS/camoufox" else "camoufox-bin";
in
buildNpmPackage (finalAttrs: {
  pname = "camofox-browser";
  version = "1.13.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/@askjo/camofox-browser/-/camofox-browser-${finalAttrs.version}.tgz";
    hash = "sha256-QftpwzCdTkK2E7gAnXk7jzCIo66+lnnFqQYetlKLzo0=";
  };

  # npm's published tarball has no lock file. Copy both files because this
  # lock was generated from the repository manifest, before npm normalized the
  # manifest for publication, and npm ci requires the pair to agree.
  #
  # Camofox defaults to headless upstream. CAMOFOX_HEADLESS=false is the
  # explicit Darwin headful path: Linux still disables headless whenever its
  # existing virtual display starts, while a missing Linux display and every
  # unset environment retain the upstream true default.
  #
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
        "function camoufoxCacheDir(env = process.env) {" \
        "function camoufoxCacheDir(env = process.env) { const installDir = (env.CAMOUFOX_INSTALL_DIR || \"\").trim(); if (installDir) return installDir;" \
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
    # viewport because it includes an isMobile field. Session creation and
    # launch validation already use viewport=null; keep the idle health probe
    # on the same compatible path so it does not restart a healthy browser
    # every three minutes.
    substituteInPlace server.js \
      --replace-fail \
        "    testContext = await browser.newContext();" \
        "    testContext = await browser.newContext({ viewport: null });"

    # A temporary executable symlink outside Camoufox.app breaks macOS
    # bundle-relative XPCOM lookup. Launch the resolved app binary directly;
    # Linux keeps the compatibility shim camoufox-js expects.
    substituteInPlace lib/camoufox-executable.js \
      --replace-fail \
        "    executablePath: ensureLaunchShim(resolvedExecutable, resourceDir)," \
        "    executablePath: platform() === 'darwin'
      ? realpathSync(resolvedExecutable)
      : ensureLaunchShim(resolvedExecutable, resourceDir),"
  '';

  npmDepsHash = "sha256-YwBkv61aYF/I3Ge/PzHyZhveBfx+Os+LaVsNxN4tE6Y=";

  # --include=optional is intentional. impit supplies its native N-API module
  # through optional platform packages, including both Darwin and Linux arm64.
  # --ignore-scripts keeps those prebuilt artifacts while suppressing every
  # lifecycle hook, especially the Camoufox downloader.
  npmFlags = [
    "--ignore-scripts"
    "--include=optional"
  ];
  dontNpmBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  # Only the REST server launches Camoufox. Give camoufox-js the complete
  # platform-correct compatibility layout it expects as another immutable store
  # tree rather than letting it create a per-user download cache. The MCP entry
  # point only forwards requests to that server and needs none of this browser
  # environment.
  postInstall = ''
    installDir="$out/share/camoufox-js"
    mkdir -p "$(dirname "$installDir/${cachedExecutable}")"
    ln -s ${camoufoxExecutable} "$installDir/${cachedExecutable}"
    ln -s ${camoufoxResourceDir}/properties.json "$installDir/properties.json"
    ln -s ${camoufoxResourceDir}/version.json "$installDir/version.json"
    ln -s ${camoufoxResourceDir}/fontconfig "$installDir/fontconfig"

    wrapProgram "$out/bin/camofox-browser" \
      --set CAMOUFOX_EXECUTABLE "${camoufoxExecutable}" \
      --set CAMOUFOX_INSTALL_DIR "$installDir" \
      --set CAMOFOX_DISABLE_DEFAULT_ADDONS 1 \
      --set CAMOFOX_CRASH_REPORT_ENABLED false \
      --set SENTRY_DSN ""
  '';

  meta = {
    description = "Camofox browser automation server and MCP integration";
    homepage = "https://github.com/jo-inc/camofox-browser";
    license = lib.licenses.mit;
    mainProgram = "camofox-browser";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
    ];
    maintainers = [ ];
  };
})
