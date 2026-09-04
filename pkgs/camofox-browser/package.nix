# @askjo/camofox-browser publishes built JavaScript and a complete npm lock.
# importNpmLock turns every registry tarball into an immutable store reference,
# so source and dependencies can move together with the upstream revision.
#
# The package's postinstall script runs `npx camoufox-js fetch`. Lifecycle
# scripts are deliberately disabled: Camoufox is the separate immutable Nix
# package below, and downloading another copy during either build or runtime
# would be both impure and the wrong architecture-selection boundary.
{
  lib,
  stdenv,
  buildNpmPackage,
  importNpmLock,
  makeWrapper,
  jq,
  camoufox,
  source,
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
  package = builtins.fromJSON (builtins.readFile "${source}/package.json");
  rawNpmDeps = importNpmLock { npmRoot = source; };
  npmDeps = rawNpmDeps.overrideAttrs (previous: {
    nativeBuildInputs = (previous.nativeBuildInputs or [ ]) ++ [ jq ];
    buildCommand = (previous.buildCommand or "") + ''
      glob=$(jq -r '.packages["node_modules/glob"].resolved' "$out/package-lock.json")
      testExclude=$(jq -r '.packages["node_modules/test-exclude"].resolved' "$out/package-lock.json")
      jq --arg glob "$glob" --arg testExclude "$testExclude" '
        .overrides |= walk(
          if . == "13.0.6" then $glob
          elif . == "8.0.0" then $testExclude
          else .
          end
        )
      ' "$out/package.json" > package.json
      mv package.json "$out/package.json"
    '';
  });
  cachedExecutable =
    if stdenv.hostPlatform.isDarwin then "Camoufox.app/Contents/MacOS/camoufox" else "camoufox-bin";
in
buildNpmPackage {
  pname = "camofox-browser";
  inherit (package) version;

  src = source;

  # Use the upstream source and lock file as one flake input. importNpmLock
  # consumes every registry integrity from that lock directly, so dependency
  # changes do not require a separately maintained npmDepsHash.
  # Upstream defaults to headless unless its interactive mode is `desktop`.
  # The wrapper selects that mode only on Darwin; Linux keeps the upstream
  # virtual-display path and remains headless if Xvfb is unavailable.
  #
  # Upstream's sessionKey only selected the group used when a tab was created.
  # Listing and every tabId operation still searched all groups under userId,
  # so clients sharing cookies also shared tab visibility and control. Keep the
  # REST compatibility path when no sessionKey is supplied, but make the MCP
  # adapter send it on every operation and enforce that group on the server.
  patches = [ ./session-isolation.patch ];
  postPatch = ''
    substituteInPlace lib/config.js \
      --replace-fail \
        "function camoufoxCacheDir(env = process.env) {" \
        "function camoufoxCacheDir(env = process.env) { const installDir = (env.CAMOUFOX_INSTALL_DIR || \"\").trim(); if (installDir) return installDir;" \



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

  inherit npmDeps;
  npmConfigHook = importNpmLock.npmConfigHook;

  # --include=optional is intentional. impit supplies its native N-API module
  # through optional platform packages, including both Darwin and Linux arm64.
  # --ignore-scripts keeps those prebuilt artifacts while suppressing every
  # lifecycle hook, especially the Camoufox downloader.
  npmFlags = [
    "--ignore-scripts"
    "--include=optional"
    "--omit=dev"
    "--legacy-peer-deps"
  ];
  dontNpmBuild = true;
  dontBuild = true;
  dontNpmPrune = true;

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
      ${lib.optionalString stdenv.hostPlatform.isDarwin "--set CAMOFOX_INTERACTIVE desktop \\"}
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
}
