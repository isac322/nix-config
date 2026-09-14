{
  buildNpmPackage,
  fetchurl,
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
    {
      name,
      source,
      packageLock ? builtins.fromJSON (builtins.readFile "${source}/package-lock.json"),
      integrityContractLock ? packageLock,
      packageSourceOverrides ? { },
      missingIntegrityOverrides ? { },
    }:
    let
      package = builtins.fromJSON (builtins.readFile "${source}/package.json");
      missingIntegrityModules = lib.filterAttrs (
        _: module:
        module ? resolved
        && module.resolved != null
        && (lib.hasPrefix "http://" module.resolved || lib.hasPrefix "https://" module.resolved)
        && (!(module ? integrity) || module.integrity == null)
      ) integrityContractLock.packages;
      missingIntegrityPaths = builtins.attrNames missingIntegrityModules;
      expectedMissingIntegrityPaths = builtins.attrNames missingIntegrityOverrides;
      missingIntegritySourceOverrides =
        assert lib.assertMsg (missingIntegrityPaths == expectedMissingIntegrityPaths)
          "${name}: package-lock.json missing-integrity paths changed: ${builtins.toJSON missingIntegrityPaths}";
        assert lib.assertMsg (lib.all
          (
            path:
            let
              locked = missingIntegrityModules.${path};
              expected = missingIntegrityOverrides.${path};
            in
            (locked.version or null) == expected.version && locked.resolved == expected.resolved
          )
          expectedMissingIntegrityPaths
        ) "${name}: a missing-integrity package version or resolved URL changed";
        lib.mapAttrs (
          _: expected:
          fetchurl {
            url = expected.resolved;
            hash = expected.integrity;
          }
        ) missingIntegrityOverrides;
      resolvedPackageSourceOverrides = packageSourceOverrides // missingIntegritySourceOverrides;
    in
    buildNpmPackage {
      pname = name;
      inherit (package) version;
      src = source;
      npmDeps = importNpmLock {
        npmRoot = source;
        inherit packageLock;
        packageSourceOverrides = resolvedPackageSourceOverrides;
      };
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

  piCodegraphPackageLock = builtins.fromJSON (
    builtins.readFile "${sourceInputs.piCodegraph}/package-lock.json"
  );
  piCodingAgentPath = "node_modules/@earendil-works/pi-coding-agent";
  piCodingAgentExpected = {
    version = "0.85.1";
    resolved = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-0.85.1.tgz";
    integrity = "sha512-FGRN+OHbWaefBPGaTggAdLjrIHW+s2PzLyglz/5dfLzb9of7uuXMXYC0fJIeZTw+shS32o2cuQ9jF7YSDuL/oQ==";
  };
  piCodingAgentLocked = piCodegraphPackageLock.packages.${piCodingAgentPath} or { };
  piCodingAgentWithoutShrinkwrap =
    assert lib.assertMsg (
      (piCodingAgentLocked.version or null) == piCodingAgentExpected.version
      && (piCodingAgentLocked.resolved or null) == piCodingAgentExpected.resolved
      && (piCodingAgentLocked.integrity or null) == piCodingAgentExpected.integrity
      && (piCodingAgentLocked.hasShrinkwrap or false)
    ) "pi-codegraph: pi-coding-agent shrinkwrap contract changed";
    stdenvNoCC.mkDerivation {
      name = "pi-coding-agent-without-shrinkwrap-${piCodingAgentExpected.version}.tgz";
      src = fetchurl {
        url = piCodingAgentExpected.resolved;
        hash = piCodingAgentExpected.integrity;
      };
      dontUnpack = true;
      installPhase = ''
        runHook preInstall
        mkdir source
        tar -xzf "$src" -C source
        test -f source/package/npm-shrinkwrap.json
        rm source/package/npm-shrinkwrap.json
        tar --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner \
          -cf - -C source package | gzip -n > "$out"
        runHook postInstall
      '';
    };
  piCodegraphPackageLockWithoutShrinkwrap = piCodegraphPackageLock // {
    packages = piCodegraphPackageLock.packages // {
      ${piCodingAgentPath} = builtins.removeAttrs piCodingAgentLocked [
        "hasShrinkwrap"
        "integrity"
      ];
    };
  };

  piCodegraphMissingIntegrityOverrides = {
    "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/chord" = {
      version = "0.85.1";
      resolved = "https://registry.npmjs.org/@earendil-works/chord/-/chord-0.85.1.tgz";
      integrity = "sha512-VDlkEC3dhCzQ5fcyH1OhG19dq+6jCn+rqc/iXFivwDYGR5anwo2RCiXij9PpHhqNR5GuhhE+Er69Zi1Sn4eY6w==";
    };
    "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-agent-core" = {
      version = "0.85.1";
      resolved = "https://registry.npmjs.org/@earendil-works/pi-agent-core/-/pi-agent-core-0.85.1.tgz";
      integrity = "sha512-hIXIP3eAWueAYiAl8aMvWCvvZ8Q5gT3Dip5bE5uJyIGh4+YlWRjtMLI4BaeoXoSs93zndjue61u1B/vhefLnuA==";
    };
    "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai" = {
      version = "0.85.1";
      resolved = "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-0.85.1.tgz";
      integrity = "sha512-+VgVIJDkDO2efYJKEEqvPTH4zmnIaXdAppGbO+vKFA9qy5PdhFiAenuFAkU+oiCSfOC4dMHDyrjdQeL4ZoC5CQ==";
    };
    "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-telemetry" = {
      version = "0.85.1";
      resolved = "https://registry.npmjs.org/@earendil-works/pi-telemetry/-/pi-telemetry-0.85.1.tgz";
      integrity = "sha512-Bg/YN6kA7Swja/NQxka8xFdecb4E/auIEGF2G5A25EaQXhRnPj300/7/KpgsDDMYUzHTDAv4RyUxaQPJKW81Rw==";
    };
    "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-tui" = {
      version = "0.85.1";
      resolved = "https://registry.npmjs.org/@earendil-works/pi-tui/-/pi-tui-0.85.1.tgz";
      integrity = "sha512-OIzw9efInmO4WOBnD4TxcTdBjmzvYJpzslkgoUro946nEGoYWg5rwv1p4fDt3/JvMx9QybryUCUwlm7j8Dreig==";
    };
  };

  plugins = {
    "pi-anthropic-web-fetch" = sourcePackage "pi-anthropic-web-fetch" sourceInputs.piAnthropicWebFetch;
    "pi-google-url-context" = sourcePackage "pi-google-url-context" sourceInputs.piGoogleUrlContext;
    "pi-anthropic-web-search" =
      sourcePackage "pi-anthropic-web-search" sourceInputs.piAnthropicWebSearch;
    "pi-openai-web-search" = sourcePackage "pi-openai-web-search" sourceInputs.piOpenaiWebSearch;
    "pi-google-google-search" =
      sourcePackage "pi-google-google-search" sourceInputs.piGoogleGoogleSearch;
    "@isac322/pi-codegraph" = npmPackage {
      name = "pi-codegraph";
      source = sourceInputs.piCodegraph;
      missingIntegrityOverrides = piCodegraphMissingIntegrityOverrides;
      integrityContractLock = piCodegraphPackageLock;
      packageLock = piCodegraphPackageLockWithoutShrinkwrap;
      packageSourceOverrides.${piCodingAgentPath} = piCodingAgentWithoutShrinkwrap;
    };
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
