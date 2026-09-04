# Gajae Code publishes one self-contained executable per supported platform.
# The version-controlled upstream manifest snapshot avoids rebuilding its Bun
# workspace and native addons while keeping every host on one verified release.
{
  autoPatchelfHook,
  fetchurl,
  lib,
  stdenvNoCC,
  versionCheckHook,
  writableTmpDirAsHomeHook,
  manifestFile,
}:

let
  manifest = builtins.fromJSON (builtins.readFile manifestFile);

  binaryFor =
    name:
    let
      matches = builtins.filter (b: b.name == name) manifest.binaries;
    in
    if matches == [ ] then
      throw "Gajae Code manifest missing binary for ${name}"
    else
      builtins.head matches;

  systemToBinaryName = {
    "aarch64-darwin" = "gjc-darwin-arm64";
    "x86_64-darwin" = "gjc-darwin-x64";
    "aarch64-linux" = "gjc-linux-arm64";
    "x86_64-linux" = "gjc-linux-x64";
  };

  targetBinaryName =
    systemToBinaryName.${stdenvNoCC.hostPlatform.system}
      or (throw "Gajae Code does not publish a binary for ${stdenvNoCC.hostPlatform.system}");

  targetBinary = binaryFor targetBinaryName;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "gajae-code";
  version = manifest.release_version;

  src = fetchurl {
    url = "https://github.com/Yeachan-Heo/gajae-code/releases/download/v${manifest.release_version}/${targetBinary.name}";
    sha256 = targetBinary.sha256;
  };
  strictDeps = true;
  dontUnpack = true;
  dontBuild = true;
  # Bun appends the compiled application payload to the executable. Stripping
  # the Linux release leaves a runnable bare Bun binary instead of Gajae Code.
  dontStrip = true;

  # The Linux releases use conventional /lib ELF interpreters, which NixOS
  # does not provide. Patch only those; preserving the Darwin release unchanged
  # keeps its embedded ad-hoc signature and Bun payload intact.
  nativeBuildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [ autoPatchelfHook ];
  dontFixup = stdenvNoCC.hostPlatform.isDarwin;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/gjc"
    runHook postInstall
  '';

  nativeInstallCheckInputs = [
    versionCheckHook
    writableTmpDirAsHomeHook
  ];
  doInstallCheck = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;
  versionCheckProgramArg = "--version";
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/gjc" --smoke-test
    runHook postInstallCheck
  '';

  meta = {
    description = "Coding-agent harness with plan-gated execution";
    homepage = "https://gajae-code.com";
    changelog = "https://github.com/Yeachan-Heo/gajae-code/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "gjc";
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
})
