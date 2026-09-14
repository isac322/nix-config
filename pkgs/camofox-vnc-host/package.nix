{
  lib,
  stdenv,
}:

stdenv.mkDerivation {
  pname = "camofox-vnc-host";
  version = "1.0.0";

  dontUnpack = true;

  buildPhase = ''
    runHook preBuild

    $CC -fobjc-arc -Os -Wall -Wextra -Wpedantic \
      -framework Foundation -framework ApplicationServices \
      ${./main.m} -o camofox-vnc-host

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    app="$out/Applications/Camofox VNC Host.app"
    mkdir -p "$app/Contents/MacOS"
    install -m 0755 camofox-vnc-host "$app/Contents/MacOS/camofox-vnc-host"
    install -m 0644 ${./Info.plist} "$app/Contents/Info.plist"

    runHook postInstall
  '';

  postFixup = ''
    /usr/bin/codesign --force --sign - --timestamp=none \
      --identifier com.bhyoo.camofox-vnc-host \
      "$out/Applications/Camofox VNC Host.app"
  '';

  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  outputHash = "sha256-SMQw0bMM86PcMbkbf4sxcAZepqEuStNLVzIx8qykcnw=";

  meta = {
    description = "Stable macOS permission host for the managed Camofox VNC server";
    license = lib.licenses.mit;
    platforms = [ "aarch64-darwin" ];
    maintainers = [ ];
  };
}
