# BearDrive is not in nixpkgs. Upstream publishes static Go binaries for every
# platform this configuration manages; packaging those exact release artifacts
# avoids rebuilding its large cloud-storage dependency graph on every node.
{
  fetchurl,
  lib,
  stdenvNoCC,
  versionCheckHook,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "beardrive";
  version = "0.15.0";

  src =
    {
      "aarch64-darwin" = fetchurl {
        url = "https://github.com/runbear-io/beardrive/releases/download/v${finalAttrs.version}/beardrive_${finalAttrs.version}_darwin_arm64.tar.gz";
        hash = "sha256-WGHxoqzdWx5yUdt8/FYuhYa73gvLudCwO/gWelyjb7Q=";
      };
      "x86_64-darwin" = fetchurl {
        url = "https://github.com/runbear-io/beardrive/releases/download/v${finalAttrs.version}/beardrive_${finalAttrs.version}_darwin_amd64.tar.gz";
        hash = "sha256-V3yLkRBn3OkNLzAnsWIPslGzisMs60RLGC3BEUOtgNA=";
      };
      "aarch64-linux" = fetchurl {
        url = "https://github.com/runbear-io/beardrive/releases/download/v${finalAttrs.version}/beardrive_${finalAttrs.version}_linux_arm64.tar.gz";
        hash = "sha256-hVl62Suo5449wrq4hIdq8/Kv5TfvzSA5QsE8ViBoasI=";
      };
      "x86_64-linux" = fetchurl {
        url = "https://github.com/runbear-io/beardrive/releases/download/v${finalAttrs.version}/beardrive_${finalAttrs.version}_linux_amd64.tar.gz";
        hash = "sha256-lu6UZwj/YvHU80n9BvrrG9gtBY6v98XxTQGQPstw4kA=";
      };
    }
    .${stdenvNoCC.hostPlatform.system}
      or (throw "BearDrive does not publish a binary for ${stdenvNoCC.hostPlatform.system}");

  sourceRoot = ".";
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 bdrive "$out/bin/bdrive"
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;

  meta = {
    description = "Offline-first shared file system for AI agents";
    homepage = "https://github.com/runbear-io/beardrive";
    license = lib.licenses.agpl3Only;
    mainProgram = "bdrive";
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
    maintainers = [ ];
  };
})
