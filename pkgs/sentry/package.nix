# Sentry's current CLI from getsentry/cli. The release tarball is the published
# npm package: upstream has already bundled the monorepo sources, generated
# command metadata, and WASM helpers into dist/, so rebuilding the workspace
# would add a large pnpm dependency graph without changing the shipped program.
{
  fetchurl,
  lib,
  makeWrapper,
  nodejs_24,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "sentry";
  version = "0.42.2";

  src = fetchurl {
    url = "https://github.com/getsentry/cli/releases/download/${finalAttrs.version}/sentry-${finalAttrs.version}.tgz";
    hash = "sha256-fiucbegG0/aJJ2D/7pr6fmF4lS27MZySR/EtxHO0GSE=";
  };

  sourceRoot = "package";
  dontBuild = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/sentry"
    cp -R . "$out/lib/sentry"
    makeWrapper ${nodejs_24}/bin/node "$out/bin/sentry" \
      --add-flags "$out/lib/sentry/dist/bin.cjs"
    runHook postInstall
  '';

  doInstallCheck = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    test "$($out/bin/sentry --version)" = "${finalAttrs.version}"
    $out/bin/sentry --help > /dev/null
    runHook postInstallCheck
  '';

  meta = {
    description = "Command-line interface for Sentry developers and AI agents";
    homepage = "https://cli.sentry.dev/";
    license = lib.licenses.fsl11Asl20;
    mainProgram = "sentry";
    platforms = lib.platforms.unix;
    maintainers = [ ];
  };
})
