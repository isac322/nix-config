{
  fetchurl,
  installShellFiles,
  lib,
  stdenvNoCC,
  manifestFile,
}:

let
  release = import ../release-manifest.nix { inherit lib; };
  target =
    {
      "aarch64-darwin" = "aarch64-apple-darwin";
      "aarch64-linux" = "aarch64-unknown-linux-musl";
      "x86_64-linux" = "x86_64-unknown-linux-musl";
    }
    .${stdenvNoCC.hostPlatform.system}
      or (throw "ntn does not publish a binary for ${stdenvNoCC.hostPlatform.system}");
  # ntn.dev, not GitHub: the source repository is private. The snapshot is
  # GitHub-release shaped so the same asset selection applies.
  asset = release.github {
    inherit manifestFile;
    assetName = "ntn-${target}.tar.gz";
  };
  canRun = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;
in
stdenvNoCC.mkDerivation {
  pname = "ntn";
  inherit (asset) version;

  src = fetchurl { inherit (asset) url hash; };

  nativeBuildInputs = [ installShellFiles ];

  # The completion scripts call back into the binary by absolute path, so they
  # are generated from the installed copy rather than the unpacked one.
  installPhase = ''
    runHook preInstall
    install -Dm755 ntn "$out/bin/ntn"
  ''
  + lib.optionalString canRun ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    installShellCompletion --cmd ntn \
      --bash <("$out/bin/ntn" completions bash) \
      --fish <("$out/bin/ntn" completions fish) \
      --zsh <("$out/bin/ntn" completions zsh)
  ''
  + ''
    runHook postInstall
  '';

  doInstallCheck = canRun;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    "$out/bin/ntn" --version | grep -qxF "ntn ${asset.version}"
    runHook postInstallCheck
  '';

  meta = {
    description = "Notion CLI for the public API, file uploads and Notion Workers";
    homepage = "https://ntn.dev";
    license = lib.licenses.mit;
    mainProgram = "ntn";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
}
