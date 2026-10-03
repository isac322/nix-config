# OmO Native publishes one Bun-compiled executable per platform. Installing
# the release binary skips upstream's `curl | bash` installer, which edits
# shell profiles and writes ~/.omo/install.json, and the npm `omo-ai` path.
{
  autoPatchelfHook,
  fetchurl,
  lib,
  stdenvNoCC,
  writableTmpDirAsHomeHook,
  manifestFile,
}:

let
  release = import ../release-manifest.nix { inherit lib; };
  asset = release.github {
    inherit manifestFile;
    assetName =
      {
        "aarch64-darwin" = "omo-darwin-arm64";
        "aarch64-linux" = "omo-linux-arm64";
        "x86_64-linux" = "omo-linux-x64";
      }
      .${stdenvNoCC.hostPlatform.system}
        or (throw "OmO does not publish a binary for ${stdenvNoCC.hostPlatform.system}");
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "omo";
  inherit (asset) version;

  src = fetchurl { inherit (asset) url hash; };
  strictDeps = true;
  dontUnpack = true;
  dontBuild = true;
  # Bun appends the compiled application payload to the executable; stripping
  # it would leave a bare Bun runtime instead of omo.
  dontStrip = true;

  # The glibc Linux releases use conventional /lib ELF interpreters, which
  # NixOS does not provide. Darwin stays byte-identical so its embedded ad-hoc
  # signature and Bun payload remain intact.
  nativeBuildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [ autoPatchelfHook ];
  dontFixup = stdenvNoCC.hostPlatform.isDarwin;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/omo"
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ writableTmpDirAsHomeHook ];
  doInstallCheck = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/omo" --version | grep -qF "${finalAttrs.version}"
    runHook postInstallCheck
  '';

  meta = {
    description = "OmO Native, the standalone omo coding-agent harness";
    homepage = "https://omo.dev";
    changelog = "https://github.com/code-yeongyu/oh-my-openagent/releases/tag/v${finalAttrs.version}";
    license = {
      fullName = "Sustainable Use License 1.0";
      url = "https://github.com/code-yeongyu/oh-my-openagent/blob/dev/LICENSE.md";
      free = false;
      redistributable = false;
    };
    mainProgram = "omo";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
})
