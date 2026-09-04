{
  fetchurl,
  lib,
  stdenvNoCC,
  unzip,
  manifestFile,
}:

let
  release = import ../release-manifest.nix { inherit lib; };
  asset = release.github {
    inherit manifestFile;
    assetName = "DeskPad.app.zip";
    fallbackHashes."1.3.2" = "sha256-t6riEjZBkxd6b+sv7Wp5Qq6acF1tSRwV5HnFhYW4WuA=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "deskpad";
  inherit (asset) version;

  src = fetchurl { inherit (asset) url hash; };
  dontUnpack = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications" "$out/bin"
    ${lib.getExe unzip} -q "$src" -d "$out/Applications"
    ln -s ../Applications/DeskPad.app/Contents/MacOS/DeskPad "$out/bin/deskpad"
    runHook postInstall
  '';

  meta = {
    description = "Virtual monitor for screen sharing";
    homepage = "https://github.com/Stengo/DeskPad";
    license = lib.licenses.mit;
    mainProgram = "deskpad";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}
