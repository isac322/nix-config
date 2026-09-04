{
  buildNpmPackage,
  bun2nix,
  importNpmLock,
  lib,
  pkg-config,
  python3,
  stdenv,
  stdenvNoCC,
  sourceInputs,
}:

let
  sourcePackage =
    name: source:
    let
      package = builtins.fromJSON (builtins.readFile "${source}/package.json");
    in
    stdenvNoCC.mkDerivation {
      pname = name;
      inherit (package) version;
      src = source;
      dontBuild = true;
      installPhase = ''
        runHook preInstall
        mkdir -p "$out"
        cp -R . "$out/"
        runHook postInstall
      '';
    };

  npmPackage =
    name: source:
    let
      package = builtins.fromJSON (builtins.readFile "${source}/package.json");
    in
    buildNpmPackage {
      pname = name;
      inherit (package) version;
      src = source;
      npmDeps = importNpmLock { npmRoot = source; };
      npmConfigHook = importNpmLock.npmConfigHook;

      postBuild = ''
        npm prune --omit=dev --ignore-scripts
      '';

      installPhase = ''
        runHook preInstall
        mkdir -p "$out"
        cp -R . "$out/"
        runHook postInstall
      '';
    };

  contextModePackage =
    let
      source = sourceInputs.contextMode;
      package = builtins.fromJSON (builtins.readFile "${source}/package.json");
      lockLines = lib.splitString "\n" (builtins.readFile "${source}/bun.lock");
      packageLines = builtins.filter (line: builtins.match ''^    ".*": [[].*$'' line != null) lockLines;
      parseRegistryPackage =
        line:
        let
          match = builtins.match ''^    "[^"]+": [[]"([^"]+)", "", .*"(sha512-[^"]+)"[]],?$'' line;
        in
        if match == null then
          null
        else
          let
            spec = builtins.elemAt match 0;
            hash = builtins.elemAt match 1;
            parts = lib.splitString "@" spec;
            version = lib.last parts;
            packageName = lib.concatStringsSep "@" (lib.init parts);
            tarballName = lib.last (lib.splitString "/" packageName);
          in
          {
            name = spec;
            value = {
              url = "https://registry.npmjs.org/${packageName}/-/${tarballName}-${version}.tgz";
              inherit hash;
            };
          };
      parsedPackages = map parseRegistryPackage packageLines;
      registryPackages = builtins.filter (entry: entry != null) parsedPackages;
      bunNix =
        {
          fetchurl,
          ...
        }:
        assert lib.assertMsg (
          builtins.length registryPackages == builtins.length packageLines
        ) "context-mode bun.lock contains a non-registry or unhashed package";
        builtins.listToAttrs (
          map (entry: {
            inherit (entry) name;
            value = fetchurl entry.value;
          }) registryPackages
        );
      bunDeps = bun2nix.fetchBunDeps { inherit bunNix; };
    in
    stdenv.mkDerivation {
      pname = "context-mode";
      inherit (package) version;
      src = source;
      inherit bunDeps;

      nativeBuildInputs = [
        bun2nix.hook
        pkg-config
        python3
      ];
      bunInstallFlags = [
        "--production"
        "--linker=hoisted"
      ]
      ++ lib.optionals stdenv.hostPlatform.isDarwin [ "--backend=copyfile" ];
      dontUseBunBuild = true;

      installPhase = ''
        runHook preInstall
        mkdir -p "$out"
        cp -R . "$out/"
        runHook postInstall
      '';
    };

  plugins = {
    "pi-anthropic-web-fetch" = sourcePackage "pi-anthropic-web-fetch" sourceInputs.piAnthropicWebFetch;
    "pi-google-url-context" = sourcePackage "pi-google-url-context" sourceInputs.piGoogleUrlContext;
    "pi-anthropic-web-search" =
      sourcePackage "pi-anthropic-web-search" sourceInputs.piAnthropicWebSearch;
    "pi-openai-web-search" = sourcePackage "pi-openai-web-search" sourceInputs.piOpenaiWebSearch;
    "pi-google-google-search" =
      sourcePackage "pi-google-google-search" sourceInputs.piGoogleGoogleSearch;
    "@isac322/pi-codegraph" = npmPackage "pi-codegraph" sourceInputs.piCodegraph;
    "context-mode" = contextModePackage;
  };
in
stdenvNoCC.mkDerivation {
  pname = "omp-plugins";
  version = "0";

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/node_modules"

    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: drv: ''
        mkdir -p "$out/node_modules/$(dirname ${lib.escapeShellArg name})"
        cp -R ${drv} "$out/node_modules/${name}"
      '') plugins
    )}

    runHook postInstall
  '';

  passthru.pluginVersions = lib.mapAttrs (_: drv: drv.version) plugins;

  meta = {
    description = "Plugins for OMP, resolved and pinned rather than installed at run time";
    platforms = lib.platforms.all;
  };
}
