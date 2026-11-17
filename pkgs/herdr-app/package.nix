# Prebuilt Linux desktop client from releases.herdr.dev.
# macOS installs the signed Herdr.app bundle via the `herdr-app` Homebrew cask
# (docs/decisions/0015-gui-apps-come-from-homebrew.md).
{
  autoPatchelfHook,
  fetchurl,
  fontconfig,
  freetype,
  lib,
  libx11,
  libxcb,
  libxkbcommon,
  makeDesktopItem,
  makeWrapper,
  stdenv,
  vulkan-loader,
  wayland,
  manifestFile,
}:

let
  release = import ../release-manifest.nix { inherit lib; };
  asset = release.github {
    inherit manifestFile;
    assetName =
      {
        "aarch64-linux" = "herdr-app-linux-aarch64.tar.gz";
        "x86_64-linux" = "herdr-app-linux-x86_64.tar.gz";
      }
      .${stdenv.hostPlatform.system}
        or (throw "herdr-app Linux package does not publish a binary for ${stdenv.hostPlatform.system}");
  };

  runtimeLibs = [
    fontconfig
    freetype
    libx11
    libxcb
    libxkbcommon
    vulkan-loader
    wayland
  ];

  desktopItem = makeDesktopItem {
    name = "herdr-app";
    desktopName = "Herdr";
    comment = "Terminals and coding agents that keep running";
    exec = "herdr-app";
    icon = "herdr-app";
    categories = [ "Development" ];
    terminal = false;
  };
in
stdenv.mkDerivation {
  pname = "herdr-app";
  inherit (asset) version;

  src = fetchurl { inherit (asset) url hash; };
  sourceRoot = "herdr-app";
  dontStrip = true;

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    stdenv.cc.cc.lib
    fontconfig
    libxcb
    libxkbcommon
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 herdr-app "$out/bin/herdr-app"
    install -Dm644 herdr-app.svg "$out/share/icons/hicolor/scalable/apps/herdr-app.svg"
    install -Dm644 "${desktopItem}/share/applications/herdr-app.desktop" "$out/share/applications/herdr-app.desktop"
    wrapProgram "$out/bin/herdr-app" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}"
    runHook postInstall
  '';

  doInstallCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/herdr-app" --version | grep -qF "herdr-app ${asset.version}"
    runHook postInstallCheck
  '';

  meta = {
    description = "Desktop app for terminals and coding agents";
    homepage = "https://herdr.dev/";
    license = lib.licenses.asl20;
    mainProgram = "herdr-app";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}
