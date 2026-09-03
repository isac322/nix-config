# Camoufox is a Firefox fork distributed as a prebuilt browser bundle. The
# macOS release is already a complete application, so rebuilding or flattening
# it would only discard bundle metadata that Aqua and Playwright both use.
#
# Camofox accepts an external executable, while camoufox-js expects its
# properties.json, version.json and fontconfig/ resources beside that
# executable. Each release contains properties.json and fontconfig; the
# downloader normally adds version.json beside an unpacked browser. Add that
# package-time so no process needs a mutable per-user download cache.
{
  lib,
  stdenv,
  fetchurl,
  unzip,
  wrapGAppsHook3,
  autoPatchelfHook,
  patchelfUnstable,
  alsa-lib,
  curl,
  dbus-glib,
  gtk3,
  libxtst,
  libva,
  pciutils,
  pipewire,
  adwaita-icon-theme,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "camoufox";
  version = "152.0.4-beta.28";

  src = fetchurl {
    url =
      if stdenv.hostPlatform.isDarwin then
        "https://github.com/daijro/camoufox/releases/download/v${finalAttrs.version}/camoufox-${finalAttrs.version}-mac.arm64.zip"
      else
        "https://github.com/daijro/camoufox/releases/download/v${finalAttrs.version}/camoufox-${finalAttrs.version}-lin.arm64.zip";
    hash =
      if stdenv.hostPlatform.isDarwin then
        "sha256-i3aAphgYJFz06wFQ7auBHU7ZN7ZyNRRWnnTD59+Whb0="
      else
        "sha256-OhBaL8kp6Ap5tLf84sk+1ixPssh388HtKl1mocT+lo8=";
  };

  dontUnpack = true;

  # Follow nixpkgs' firefox-bin treatment for the upstream Linux binaries.
  # Firefox's relrhack needs the newer patchelf mode, while the explicit
  # runtime dependencies cover libraries loaded dynamically rather than from
  # ELF DT_NEEDED entries.
  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    wrapGAppsHook3
    autoPatchelfHook
    patchelfUnstable
  ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    gtk3
    adwaita-icon-theme
    alsa-lib
    dbus-glib
    libxtst
  ];
  runtimeDependencies = lib.optionals stdenv.hostPlatform.isLinux [
    curl
    pciutils
    libva.out
  ];
  appendRunpaths = lib.optionals stdenv.hostPlatform.isLinux [ "${pipewire}/lib" ];
  patchelfFlags = lib.optionals stdenv.hostPlatform.isLinux [ "--no-clobber-old-sections" ];

  # Keep the signed Darwin application byte-for-byte apart from the resources
  # camoufox-js requires. Linux needs the ordinary fixup phase so autoPatchelf
  # can make the prebuilt Firefox binaries runnable in the Nix store.
  dontFixup = stdenv.hostPlatform.isDarwin;

  installPhase =
    if stdenv.hostPlatform.isDarwin then
      ''
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
      ''
    else
      ''
        runHook preInstall

        browser="$out/lib/camoufox"
        mkdir -p "$browser" "$out/bin"
        ${lib.getExe unzip} -q "$src" -d "$browser"
        printf '%s\n' '{"version":"152.0.4","release":"beta.28"}' \
          > "$browser/version.json"

        # camoufox-js launches this binary name and discovers the immutable
        # properties.json, version.json and fontconfig/ tree beside it.
        ln -s ../lib/camoufox/camoufox-bin "$out/bin/camoufox"

        runHook postInstall
      '';

  meta = {
    description = "Privacy-focused Firefox fork for browser automation";
    homepage = "https://github.com/daijro/camoufox";
    license = lib.licenses.mpl20;
    mainProgram = "camoufox";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
})
