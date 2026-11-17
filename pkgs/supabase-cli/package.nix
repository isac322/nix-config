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
      version:
      {
        "aarch64-darwin" = "supabase_${version}_darwin_arm64.tar.gz";
        "aarch64-linux" = "supabase_${version}_linux_arm64.tar.gz";
        "x86_64-linux" = "supabase_${version}_linux_amd64.tar.gz";
      }
      .${stdenvNoCC.hostPlatform.system}
        or (throw "Supabase CLI does not publish a binary for ${stdenvNoCC.hostPlatform.system}");
  };
  canExecute = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;
in
stdenvNoCC.mkDerivation {
  pname = "supabase-cli";
  inherit (asset) version;

  src = fetchurl { inherit (asset) url hash; };
  sourceRoot = ".";
  nativeBuildInputs = [ installShellFiles ];

  # The archive holds only the binary; completions come from the binary itself.
  installPhase = ''
    runHook preInstall
    install -Dm755 supabase "$out/bin/supabase"
    runHook postInstall
  '';

  postInstall = lib.optionalString canExecute ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    installShellCompletion --cmd supabase \
      --bash <("$out/bin/supabase" completion bash) \
      --zsh <("$out/bin/supabase" completion zsh) \
      --fish <("$out/bin/supabase" completion fish)
  '';

  doInstallCheck = canExecute;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/supabase" --version | grep -qxF "${asset.version}"
    runHook postInstallCheck
  '';

  meta = {
    description = "Command-line interface for Supabase";
    homepage = "https://github.com/supabase/cli";
    license = lib.licenses.mit;
    mainProgram = "supabase";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}
