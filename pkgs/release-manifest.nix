{ lib }:

let
  readJson = file: builtins.fromJSON (builtins.readFile file);

  sha256HexToSri =
    digest:
    builtins.convertHash {
      hash = lib.removePrefix "sha256:" digest;
      hashAlgo = "sha256";
      toHashFormat = "sri";
    };
in
{
  github =
    {
      manifestFile,
      assetName,
      tagPrefix ? "v",
      fallbackHashes ? { },
    }:
    let
      manifest = readJson manifestFile;
      version = lib.removePrefix tagPrefix manifest.tag_name;
      wantedName = if builtins.isFunction assetName then assetName version else assetName;
      asset = lib.findFirst (
        candidate: candidate.name == wantedName
      ) (throw "Release ${manifest.tag_name} does not contain ${wantedName}") manifest.assets;
      digest = asset.digest or null;
      hash =
        if digest != null then
          sha256HexToSri digest
        else
          fallbackHashes.${version} or (throw "Release asset ${wantedName} has no sha256 digest");
    in
    {
      inherit version hash;
      url = asset.browser_download_url;
    };

  githubTagged =
    {
      manifestFile,
      assetName,
      tagPrefix,
      fallbackHashes ? { },
    }:
    let
      releases = readJson manifestFile;
      manifest = lib.findFirst (
        candidate: !candidate.draft && !candidate.prerelease && lib.hasPrefix tagPrefix candidate.tag_name
      ) (throw "No stable release tag starts with ${tagPrefix}") releases;
      version = lib.removePrefix tagPrefix manifest.tag_name;
      wantedName = if builtins.isFunction assetName then assetName version else assetName;
      asset = lib.findFirst (
        candidate: candidate.name == wantedName
      ) (throw "Release ${manifest.tag_name} does not contain ${wantedName}") manifest.assets;
      digest = asset.digest or null;
      hash =
        if digest != null then
          sha256HexToSri digest
        else
          fallbackHashes.${version} or (throw "Release asset ${wantedName} has no sha256 digest");
    in
    {
      inherit version hash;
      url = asset.browser_download_url;
    };

  npm =
    manifestFile:
    let
      manifest = readJson manifestFile;
    in
    {
      inherit (manifest) version;
      inherit (manifest.dist) tarball integrity;
      package = manifest;
    };

  crate =
    indexFile:
    let
      releases = map builtins.fromJSON (
        builtins.filter (line: line != "") (lib.splitString "\n" (builtins.readFile indexFile))
      );
      release = lib.last (builtins.filter (candidate: !candidate.yanked) releases);
    in
    {
      version = release.vers;
      hash = sha256HexToSri release.cksum;
    };
}
