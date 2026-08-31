# Orca 1.4.190 and newer crash in the supported `orca serve` path on macOS
# before opening the runtime port (stablyai/orca#16761). A matched readiness
# probe passes 1.4.188 and fails 1.4.193, so keep the unattended server on the
# last verified release until the upstream fix ships. The interactive laptop
# continues to use the upstream Homebrew cask and Orca's own updater.
{
  fetchurl,
  lib,
  stdenvNoCC,
  undmg,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "orca";
  version = "1.4.188";

  src = fetchurl {
    url = "https://github.com/stablyai/orca/releases/download/v${finalAttrs.version}/orca-macos-arm64.dmg";
    hash = "sha256-rC7OdVj2/YkxNcUC6EshYfHGJD2KYuL7lL7G62s7JX4=";
  };

  nativeBuildInputs = [ undmg ];
  sourceRoot = ".";
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications" "$out/bin"
    cp -R Orca.app "$out/Applications/Orca.app"
    ln -s ../Applications/Orca.app/Contents/Resources/bin/orca "$out/bin/orca"

    runHook postInstall
  '';

  meta = {
    description = "IDE for orchestrating AI coding agents across terminals and worktrees";
    homepage = "https://onorca.dev/";
    license = lib.licenses.unfree;
    mainProgram = "orca";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
})
