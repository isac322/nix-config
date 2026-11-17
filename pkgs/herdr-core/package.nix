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
    install -Dm755 herdr-core "$out/bin/herdr-core"
    ln -s herdr-core "$out/bin/hc"
    ${lib.optionalString stdenvNoCC.hostPlatform.isDarwin ''
      # Store the signed bundle without a `.app` directory suffix and never
      # execute its inner binary inside $out: macOS attaches `com.apple.macl`
      # (App Management TCC) to a `.app` bundle as soon as its executable runs,
      # which blocks nix-daemon's post-build `lchflags` on hosts where the
      # daemon lacks Full Disk Access.
      mkdir -p "$out/share/herdr-core"
      cp -pR "Herdr Core.app" "$out/share/herdr-core/bundle"
    ''}
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
