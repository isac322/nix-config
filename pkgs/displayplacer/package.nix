# Upstream publishes a standalone Apple Silicon executable for each release.
{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "displayplacer";
  version = "1.4.0";

  src = fetchurl {
    url = "https://github.com/jakehilborn/displayplacer/releases/download/v${finalAttrs.version}/displayplacer-apple-v140";
    hash = "sha256-BXLD0pGOR8fguddyOQeGTi6itTudOwI3l2n//PRPfqA=";
  };

  dontUnpack = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin"
    install -m 0755 "$src" "$out/bin/displayplacer"

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
})
