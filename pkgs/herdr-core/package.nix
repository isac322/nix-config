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
        "aarch64-darwin" = "herdr-core-macos-aarch64.tar.gz";
        "aarch64-linux" = "herdr-core-linux-aarch64.tar.gz";
        "x86_64-linux" = "herdr-core-linux-x86_64.tar.gz";
      }
      .${stdenvNoCC.hostPlatform.system}
        or (throw "herdr-core does not publish a binary for ${stdenvNoCC.hostPlatform.system}");
  };
in
stdenvNoCC.mkDerivation {
  pname = "herdr-core";
  inherit (asset) version;

  src = fetchurl { inherit (asset) url hash; };
  sourceRoot = ".";
  # Preserve the upstream Developer ID signature and notarization ticket on
  # `Herdr Core.app` and the static musl ELF build-id note on Linux.
  dontFixup = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    ${
      if stdenvNoCC.hostPlatform.isDarwin then
        ''
          mkdir -p "$out/Applications"
          cp -pR "Herdr Core.app" "$out/Applications/Herdr Core.app"
          ln -s "../Applications/Herdr Core.app/Contents/MacOS/herdr-core" "$out/bin/herdr-core"
          ln -s herdr-core "$out/bin/hc"
        ''
      else
        ''
          install -Dm755 herdr-core "$out/bin/herdr-core"
          ln -s herdr-core "$out/bin/hc"
        ''
    }
    runHook postInstall
  '';

  doInstallCheck = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/herdr-core" --version | grep -qF "hc ${asset.version}"
    "$out/bin/hc" --version | grep -qF "hc ${asset.version}"
    runHook postInstallCheck
  '';

  meta = {
    description = "Terminal runtime for coding agents that stay alive after you leave";
    homepage = "https://herdr.dev/core/";
    license = lib.licenses.asl20;
    mainProgram = "hc";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}
