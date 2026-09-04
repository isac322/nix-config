# BearDrive publishes static Go binaries for every platform this configuration
# manages. The version-controlled upstream checksum snapshot keeps their
# version, URLs, and hashes on one verified release.
{
  checksumsFile,
  fetchurl,
  lib,
  stdenvNoCC,
  versionCheckHook,
}:

let
  checksumLines =
    let
      lines = lib.splitString "\n" (builtins.readFile checksumsFile);
    in
    if lib.last lines == "" then lib.init lines else lines;

  parseChecksumLine =
    line:
    let
      match = builtins.match "^([0-9a-f]{64})  (beardrive_([0-9]+\\.[0-9]+\\.[0-9]+)_(darwin|linux)_(amd64|arm64)\\.tar\\.gz)$" line;
    in
    if match == null then
      throw "BearDrive checksum line is malformed: ${builtins.toJSON line}"
    else
      {
        sha256 = builtins.elemAt match 0;
        filename = builtins.elemAt match 1;
        version = builtins.elemAt match 2;
      };

  parsedChecksums =
    if builtins.length checksumLines != 4 then
      throw "BearDrive checksums must contain exactly four lines; found ${toString (builtins.length checksumLines)}"
    else
      map parseChecksumLine checksumLines;

  versions = lib.unique (map (checksum: checksum.version) parsedChecksums);
  version =
    if builtins.length versions != 1 then
      throw "BearDrive checksums must contain exactly one release version; found: ${lib.concatStringsSep ", " versions}"
    else
      builtins.head versions;

  systemToAssetSuffix = {
    "aarch64-darwin" = "darwin_arm64";
    "x86_64-darwin" = "darwin_amd64";
    "aarch64-linux" = "linux_arm64";
    "x86_64-linux" = "linux_amd64";
  };

  expectedFilenames = map (suffix: "beardrive_${version}_${suffix}.tar.gz") (
    builtins.attrValues systemToAssetSuffix
  );
  actualFilenames = map (checksum: checksum.filename) parsedChecksums;
  duplicateFilenames = lib.unique (
    builtins.filter (
      filename: builtins.length (builtins.filter (candidate: candidate == filename) actualFilenames) > 1
    ) actualFilenames
  );
  missingFilenames = builtins.filter (
    filename: !(builtins.elem filename actualFilenames)
  ) expectedFilenames;

  validatedChecksums =
    if duplicateFilenames != [ ] then
      throw "BearDrive checksums contain duplicate assets: ${lib.concatStringsSep ", " duplicateFilenames}"
    else if missingFilenames != [ ] then
      throw "BearDrive checksums are missing assets: ${lib.concatStringsSep ", " missingFilenames}"
    else
      parsedChecksums;

  targetAssetSuffix =
    systemToAssetSuffix.${stdenvNoCC.hostPlatform.system}
      or (throw "BearDrive does not publish a binary for ${stdenvNoCC.hostPlatform.system}");
  targetFilename = "beardrive_${version}_${targetAssetSuffix}.tar.gz";
  targetMatches = builtins.filter (checksum: checksum.filename == targetFilename) validatedChecksums;
  targetChecksum =
    if builtins.length targetMatches != 1 then
      throw "BearDrive checksums must contain exactly one entry for ${targetFilename}"
    else
      builtins.head targetMatches;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "beardrive";
  inherit version;

  src = fetchurl {
    url = "https://github.com/runbear-io/beardrive/releases/download/v${finalAttrs.version}/${targetChecksum.filename}";
    sha256 = targetChecksum.sha256;
  };

  sourceRoot = ".";
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 bdrive "$out/bin/bdrive"
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;

  meta = {
    description = "Offline-first shared file system for AI agents";
    homepage = "https://github.com/runbear-io/beardrive";
    license = lib.licenses.agpl3Only;
    mainProgram = "bdrive";
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
    maintainers = [ ];
  };
})
