{
  lib,
  stdenv,
  apiPort ? 9377,
}:

stdenv.mkDerivation {
  pname = "camofox-url-handler";
  version = "1.0.0";

  dontUnpack = true;

  buildPhase = ''
    runHook preBuild

    $CC -fobjc-arc -fblocks -Wall -Wextra \
      -DCAMOFOX_API_PORT=${toString apiPort} \
      -framework Cocoa -framework Foundation \
      ${./main.m} -o camofox-url-handler

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    app="$out/Applications/Camofox.app"
    mkdir -p "$app/Contents/MacOS" "$out/bin"
    install -m 0755 camofox-url-handler "$app/Contents/MacOS/camofox-url-handler"
    install -m 0644 ${./Info.plist} "$app/Contents/Info.plist"
    ln -s ../Applications/Camofox.app/Contents/MacOS/camofox-url-handler \
      "$out/bin/camofox-open-url"

    runHook postInstall
  '';

  postFixup = ''
    /usr/bin/codesign --force --sign - \
      --identifier com.bhyoo.camofox-url-handler \
      "$out/Applications/Camofox.app"
  '';

  meta = {
    description = "LaunchServices bridge from HTTP URLs to the managed Camofox daemon";
    license = lib.licenses.mit;
    mainProgram = "camofox-open-url";
    platforms = [ "aarch64-darwin" ];
    maintainers = [ ];
  };
}
