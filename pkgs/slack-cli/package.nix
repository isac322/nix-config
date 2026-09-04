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
    assetName =
      version:
      {
        "aarch64-darwin" = "slack_cli_${version}_macOS_arm64.tar.gz";
        "aarch64-linux" = "slack_cli_${version}_linux_arm64.tar.gz";
        "x86_64-linux" = "slack_cli_${version}_linux_amd64.tar.gz";
      }
      .${stdenvNoCC.hostPlatform.system}
        or (throw "Slack CLI does not publish a binary for ${stdenvNoCC.hostPlatform.system}");
  };
in
stdenvNoCC.mkDerivation {
  pname = "slack-cli";
  inherit (asset) version;

  src = fetchurl { inherit (asset) url hash; };
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/slack "$out/bin/slack"
    runHook postInstall
  '';

  doInstallCheck = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    "$out/bin/slack" version --skip-update | grep -qF "v${asset.version}"
    runHook postInstallCheck
  '';

  meta = {
    description = "Command-line tool for creating, developing and deploying Slack apps";
    homepage = "https://github.com/slackapi/slack-cli";
    license = lib.licenses.asl20;
    mainProgram = "slack";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}
