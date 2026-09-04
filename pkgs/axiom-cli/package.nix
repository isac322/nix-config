{
  fetchurl,
  installShellFiles,
  lib,
  stdenvNoCC,
  versionCheckHook,
  manifestFile,
}:

let
  release = import ../release-manifest.nix { inherit lib; };
  asset = release.github {
    inherit manifestFile;
    assetName =
      version:
      {
        "aarch64-darwin" = "axiom_${version}_darwin_arm64.tar.gz";
        "aarch64-linux" = "axiom_${version}_linux_arm64.tar.gz";
        "x86_64-linux" = "axiom_${version}_linux_amd64.tar.gz";
      }
      .${stdenvNoCC.hostPlatform.system}
        or (throw "Axiom does not publish a binary for ${stdenvNoCC.hostPlatform.system}");
  };
in
stdenvNoCC.mkDerivation {
  pname = "axiom-cli";
  inherit (asset) version;

  src = fetchurl { inherit (asset) url hash; };
  nativeBuildInputs = [ installShellFiles ];

  installPhase = ''
    runHook preInstall
    install -Dm755 axiom "$out/bin/axiom"
    installShellCompletion --cmd axiom \
      --bash completions/axiom.bash \
      --zsh completions/_axiom \
      --fish completions/axiom.fish
    installManPage man/*.1
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;

  meta = {
    description = "Command-line client for Axiom";
    homepage = "https://github.com/axiomhq/cli";
    license = lib.licenses.mit;
    mainProgram = "axiom";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}
