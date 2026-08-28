# Gajae Code publishes one self-contained executable per supported platform.
# Pinning those release artifacts avoids rebuilding its Bun workspace and native
# addons while keeping every configured host on the same version.
{
  autoPatchelfHook,
  fetchurl,
  lib,
  stdenvNoCC,
  versionCheckHook,
  writableTmpDirAsHomeHook,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "gajae-code";
  version = "0.15.3";

  src =
    {
      "aarch64-darwin" = fetchurl {
        url = "https://github.com/Yeachan-Heo/gajae-code/releases/download/v${finalAttrs.version}/gjc-darwin-arm64";
        hash = "sha256-r/oKGvMXNZHkaFZ+x3o4kN8Bqkjng275w/mtMhCGnRY=";
      };
      "x86_64-darwin" = fetchurl {
        url = "https://github.com/Yeachan-Heo/gajae-code/releases/download/v${finalAttrs.version}/gjc-darwin-x64";
        hash = "sha256-BfuRe/6TOM6OvnvX1LNsfrN/+5/0SBgUotOzmj09lvU=";
      };
      "aarch64-linux" = fetchurl {
        url = "https://github.com/Yeachan-Heo/gajae-code/releases/download/v${finalAttrs.version}/gjc-linux-arm64";
        hash = "sha256-ja3YrLv14BGz4ZWoQS9BWO0rrv3y0c6UHWewiU2epbs=";
      };
      "x86_64-linux" = fetchurl {
        url = "https://github.com/Yeachan-Heo/gajae-code/releases/download/v${finalAttrs.version}/gjc-linux-x64";
        hash = "sha256-gpcs2BgwPIrnnV4S9W+wFyeqMxGXw0ebtMYU0MkF6cg=";
      };
    }
    .${stdenvNoCC.hostPlatform.system}
      or (throw "Gajae Code does not publish a binary for ${stdenvNoCC.hostPlatform.system}");

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
