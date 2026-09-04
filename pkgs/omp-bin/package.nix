{
  fetchurl,
  lib,
  stdenvNoCC,
  manifestFile,
}:

let
  release = import ../release-manifest.nix { inherit lib; };
  asset = release.github {
    inherit manifestFile;
    assetName =
      {
        "aarch64-darwin" = "omp-darwin-arm64";
        "aarch64-linux" = "omp-linux-musl-arm64";
        "x86_64-linux" = "omp-linux-musl-x64";
      }
      .${stdenvNoCC.hostPlatform.system}
        or (throw "OMP does not publish a binary for ${stdenvNoCC.hostPlatform.system}");
  };
in
stdenvNoCC.mkDerivation {
  pname = "omp-bin";
  inherit (asset) version;

  src = fetchurl { inherit (asset) url hash; };
  dontUnpack = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/omp"
    runHook postInstall
  '';

  doInstallCheck = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;
  installCheckPhase = ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    runHook preInstallCheck
    "$out/bin/omp" --version | grep -qF "${asset.version}"
    "$out/bin/omp" --smoke-test | grep -qF "smoke-test: ok"
    runHook postInstallCheck
  '';

  meta = {
    description = "Terminal-based coding agent with multi-model support";
    homepage = "https://github.com/can1357/oh-my-pi";
    license = lib.licenses.mit;
    mainProgram = "omp";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}
