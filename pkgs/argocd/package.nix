{
  fetchurl,
  installShellFiles,
  lib,
  stdenvNoCC,
  manifestFile,
}:

let
  release = import ../release-manifest.nix { inherit lib; };
  asset = release.github {
    inherit manifestFile;
    assetName =
      {
        "aarch64-darwin" = "argocd-darwin-arm64";
        "aarch64-linux" = "argocd-linux-arm64";
        "x86_64-linux" = "argocd-linux-amd64";
      }
      .${stdenvNoCC.hostPlatform.system}
        or (throw "Argo CD does not publish a CLI binary for ${stdenvNoCC.hostPlatform.system}");
  };
  canExecute = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;
in
stdenvNoCC.mkDerivation {
  pname = "argocd";
  inherit (asset) version;

  src = fetchurl { inherit (asset) url hash; };
  dontUnpack = true;
  dontFixup = true;
  nativeBuildInputs = [ installShellFiles ];

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/argocd"
    runHook postInstall
  '';

  postInstall = lib.optionalString canExecute ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    installShellCompletion --cmd argocd \
      --bash <("$out/bin/argocd" completion bash) \
      --zsh <("$out/bin/argocd" completion zsh) \
      --fish <("$out/bin/argocd" completion fish)
  '';

  doInstallCheck = canExecute;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/argocd" version --client --short | grep -qF "argocd: v${asset.version}+"
    runHook postInstallCheck
  '';

  meta = {
    description = "Command-line client for Argo CD";
    homepage = "https://argo-cd.readthedocs.io/";
    license = lib.licenses.asl20;
    mainProgram = "argocd";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}
