{
  fetchurl,
  lib,
  stdenvNoCC,
  manifestFiles,
}:

let
  release = import ../release-manifest.nix { inherit lib; };
  manifestFile = manifestFiles.${stdenvNoCC.hostPlatform.system};
  npm = release.npm manifestFile;
in
stdenvNoCC.mkDerivation {
  pname = "vercel-cli";
  inherit (npm) version;

  src = fetchurl {
    url = npm.tarball;
    hash = npm.integrity;
  };
  sourceRoot = "package";

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/vercel "$out/bin/vercel"
    ln -s vercel "$out/bin/vc"
    runHook postInstall
  '';

  doInstallCheck = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME="$TMPDIR/home"
    export VERCEL_TELEMETRY_DISABLED=1
    mkdir -p "$HOME"
    "$out/bin/vercel" --version | grep -qF "${npm.version}"
    runHook postInstallCheck
  '';

  meta = {
    description = "Command-line interface for Vercel";
    homepage = "https://vercel.com/docs/cli";
    license = lib.licenses.asl20;
    mainProgram = "vercel";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}
