{
  fetchurl,
  lib,
  stdenvNoCC,
  versionCheckHook,
  manifestFile,
}:

let
  releaseManifest = import ../release-manifest.nix { inherit lib; };
  assetName =
    {
      "aarch64-darwin" = "posthog-cli-aarch64-apple-darwin.tar.gz";
      "x86_64-darwin" = "posthog-cli-x86_64-apple-darwin.tar.gz";
      "aarch64-linux" = "posthog-cli-aarch64-unknown-linux-gnu.tar.gz";
      "x86_64-linux" = "posthog-cli-x86_64-unknown-linux-gnu.tar.gz";
    }
    .${stdenvNoCC.hostPlatform.system}
      or (throw "PostHog CLI does not publish a binary for ${stdenvNoCC.hostPlatform.system}");
  release = releaseManifest.githubTagged {
    inherit manifestFile assetName;
    tagPrefix = "posthog-cli/v";
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "posthog-cli";
  inherit (release) version;

  src = fetchurl {
    inherit (release) url hash;
  };

  installPhase = ''
    runHook preInstall
    install -Dm755 posthog-cli "$out/bin/posthog-cli"
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;

  meta = {
    description = "Command line interface for PostHog";
    homepage = "https://github.com/PostHog/posthog/tree/master/rust/cli";
    license = lib.licenses.mit;
    mainProgram = "posthog-cli";
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
    maintainers = [ ];
  };
})
