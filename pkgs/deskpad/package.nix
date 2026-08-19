# DeskPad is distributed as a signed universal macOS application. Preserve the
# upstream bundle intact: changing its contents would invalidate the Developer
# ID signature and make Screen Recording consent harder to identify.
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "deskpad";
  version = "1.3.2";

  src = fetchurl {
    url = "https://github.com/Stengo/DeskPad/releases/download/v${finalAttrs.version}/DeskPad.app.zip";
    hash = "sha256-t6riEjZBkxd6b+sv7Wp5Qq6acF1tSRwV5HnFhYW4WuA=";
  };

  dontUnpack = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications" "$out/bin"
    ${lib.getExe unzip} -q "$src" -d "$out/Applications"
    ln -s ../Applications/DeskPad.app/Contents/MacOS/DeskPad \
      "$out/bin/deskpad"

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
})
