# T3 Code CLI (`t3`) packaged from its official GitHub Release tarball.
# Runs `t3 serve` for headless server hosting and provides the `t3` CLI without
# pulling the Electron desktop wrapper (`pkgs.t3code` in nixpkgs).
{
  autoPatchelfHook,
  fetchurl,
  lib,
  makeWrapper,
  stdenv,
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
        "aarch64-darwin" = version: "t3-${version}-darwin-arm64.tar.gz";
        "aarch64-linux" = version: "t3-${version}-linux-arm64.tar.gz";
        "x86_64-linux" = version: "t3-${version}-linux-x64.tar.gz";
      }
      .${stdenvNoCC.hostPlatform.system}
        or (throw "t3code-cli does not publish a binary for ${stdenvNoCC.hostPlatform.system}");
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "t3code-cli";
  inherit (asset) version;

  src = fetchurl { inherit (asset) url hash; };
  strictDeps = true;
  dontBuild = true;
  # `t3` is a Node Single Executable Application (SEA); stripping removes the
  # embedded application payload and leaves a bare runtime.
  dontStrip = true;
  # Keep the macOS Developer ID signature (T3 Tools, Inc.) and SEA payload
  # byte-identical so TCC grants survive updates across store paths.
  dontFixup = stdenvNoCC.hostPlatform.isDarwin;

  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  # Upstream Linux archives bundle unused musl native prebuilds (`libfff_c.so`,
  # `koffi.node`) and an optional Vulkan speech library alongside the glibc runtime.
  autoPatchelfIgnoreMissingDeps = lib.optionals stdenvNoCC.hostPlatform.isLinux [
    "libc.so"
    "libc.musl-aarch64.so.1"
    "libc.musl-x86_64.so.1"
    "libvulkan.so.1"
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/libexec/t3" "$out/bin"
    cp -a . "$out/libexec/t3/"
    makeWrapper "$out/libexec/t3/t3" "$out/bin/t3"
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ writableTmpDirAsHomeHook ];
  doInstallCheck = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;
  installCheckPhase = ''
    runHook preInstallCheck
    test -f "$out/libexec/t3/client/index.html"
    "$out/bin/t3" --version | grep -qF "t3 v${finalAttrs.version}"
    runHook postInstallCheck
  '';

  meta = {
    description = "Command-line server and control plane for T3 Code";
    homepage = "https://t3.codes";
    changelog = "https://github.com/pingdotgg/t3code/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "t3";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
  };
})
