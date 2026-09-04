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
    assetName = version: "displayplacer-apple-v${lib.replaceStrings [ "." ] [ "" ] version}";
    fallbackHashes."1.4.0" = "sha256-BXLD0pGOR8fguddyOQeGTi6itTudOwI3l2n//PRPfqA=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "displayplacer";
  inherit (asset) version;

  src = fetchurl { inherit (asset) url hash; };
  dontUnpack = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/displayplacer"
    runHook postInstall
  '';

  meta = {
    description = "Command-line utility for macOS display layouts";
    homepage = "https://github.com/jakehilborn/displayplacer";
    license = lib.licenses.mit;
    mainProgram = "displayplacer";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}
