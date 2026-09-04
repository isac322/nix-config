{
  fetchurl,
  lib,
  makeWrapper,
  nodejs_24,
  stdenvNoCC,
  manifestFile,
}:

let
  release = import ../release-manifest.nix { inherit lib; };
  npm = release.npm manifestFile;
in
assert npm.package.dependencies == { };
stdenvNoCC.mkDerivation {
  pname = "langfuse-cli";
  inherit (npm) version;

  src = fetchurl {
    url = npm.tarball;
    hash = npm.integrity;
  };
  sourceRoot = "package";
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/langfuse-cli"
    cp -R . "$out/lib/langfuse-cli"
    makeWrapper ${nodejs_24}/bin/node "$out/bin/langfuse" \
      --add-flags "$out/lib/langfuse-cli/bin/langfuse.mjs"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/langfuse" --help > /dev/null
    runHook postInstallCheck
  '';

  meta = {
    description = "Command line interface for Langfuse";
    homepage = "https://github.com/langfuse/langfuse-cli";
    license = lib.licenses.mit;
    mainProgram = "langfuse";
    platforms = lib.platforms.unix;
    maintainers = [ ];
  };
}
