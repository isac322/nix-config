# Camoufox is a Firefox fork distributed as a prebuilt browser bundle.  The
# macOS release is already a complete application, so rebuilding or flattening
# it would only discard bundle metadata that Aqua and Playwright both use.
#
# Camofox accepts an external executable, while camoufox-js expects its
# properties.json, version.json and fontconfig/ resources beside that
# executable.  The release contains properties.json; the downloader normally
# adds the other two beside an unpacked browser.  Add those package-time and
# expose all three beside the real app executable so no process needs a mutable
# per-user download cache or an out-of-bundle launch shim.
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "camoufox";
  version = "152.0.4-beta.28";

  src = fetchurl {
    url = "https://github.com/daijro/camoufox/releases/download/v${finalAttrs.version}/camoufox-${finalAttrs.version}-mac.arm64.zip";
    hash = "sha256-i3aAphgYJFz06wFQ7auBHU7ZN7ZyNRRWnnTD59+Whb0=";
  };

  # Unpack directly into Applications rather than letting unpackPhase choose
  # Camoufox.app as sourceRoot.  That keeps the complete application hierarchy
  # intact and makes the store path usable by both macOS and the external-
  # executable discovery in camofox-browser.
  dontUnpack = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications" "$out/bin"
    ${lib.getExe unzip} -q "$src" -d "$out/Applications"

    resources="$out/Applications/Camoufox.app/Contents/Resources"
    macos="$out/Applications/Camoufox.app/Contents/MacOS"
    mkdir -p "$resources/fontconfig"
    printf '%s\n' '{"version":"152.0.4","release":"beta.28"}' \
      > "$resources/version.json"

    for resource in properties.json version.json fontconfig; do
      ln -s "../Resources/$resource" "$macos/$resource"
    done

    ln -s ../Applications/Camoufox.app/Contents/MacOS/camoufox \
      "$out/bin/camoufox"

    runHook postInstall
  '';

  meta = {
    description = "Privacy-focused Firefox fork for browser automation";
    homepage = "https://github.com/daijro/camoufox";
    license = lib.licenses.mpl20;
    mainProgram = "camoufox";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
})
