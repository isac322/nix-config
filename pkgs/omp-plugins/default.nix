{
  buildNpmPackage,
  fetchurl,
  importNpmLock,
  lib,
  stdenvNoCC,
  sourceInputs,
  npmSourceOverrides ? { },
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

  piCodegraphPackageLock = builtins.fromJSON (
    builtins.readFile "${sourceInputs.piCodegraph}/package-lock.json"
  );
  piCodingAgentPath = "node_modules/@earendil-works/pi-coding-agent";
  piCodingAgentLocked = piCodegraphPackageLock.packages.${piCodingAgentPath} or { };
  piCodingAgentHasShrinkwrap = piCodingAgentLocked.hasShrinkwrap or false;

  # pi-coding-agent's published tarball carries an npm-shrinkwrap.json that
  # pins its own dependency tree. importNpmLock already resolves that tree
  # from the lock entries below, so the bundled shrinkwrap is repacked out —
  # which changes the tarball and is why the lock's integrity for this entry
  # is dropped in favor of the repacked source. When upstream stops shipping
  # the shrinkwrap the lock entry is used untouched and no override is made.
  piCodingAgentWithoutShrinkwrap =
    assert lib.assertMsg (
      (piCodingAgentLocked.resolved or null) != null
      && lib.hasPrefix "https://" piCodingAgentLocked.resolved
      && (piCodingAgentLocked.integrity or null) != null
    ) "pi-codegraph: pi-coding-agent lock entry lost its resolved URL or integrity";
    stdenvNoCC.mkDerivation {
      name = "pi-coding-agent-without-shrinkwrap-${piCodingAgentLocked.version}.tgz";
      src = fetchurl {
        url = piCodingAgentLocked.resolved;
        hash = piCodingAgentLocked.integrity;
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
  piCodegraphPackageLockWithoutShrinkwrap =
    if piCodingAgentHasShrinkwrap then
      piCodegraphPackageLock
      // {
        packages = piCodegraphPackageLock.packages // {
          ${piCodingAgentPath} = builtins.removeAttrs piCodingAgentLocked [
            "hasShrinkwrap"
            "integrity"
          ];
        };
      }
    else
      piCodegraphPackageLock;

  plugins = {
    "pi-anthropic-web-fetch" = sourcePackage "pi-anthropic-web-fetch" sourceInputs.piAnthropicWebFetch;
    "pi-google-url-context" = sourcePackage "pi-google-url-context" sourceInputs.piGoogleUrlContext;
    "@isac322/pi-codegraph" = npmPackage {
      name = "pi-codegraph";
      source = sourceInputs.piCodegraph;
      # The snapshot's piCodegraph map is maintained by update-packages: it
      # holds a verified tarball hash for every lock entry that has an
      # HTTP(S) resolved URL but no integrity field.
      missingIntegrityOverrides = npmSourceOverrides;
      integrityContractLock = piCodegraphPackageLock;
      packageLock = piCodegraphPackageLockWithoutShrinkwrap;
      packageSourceOverrides = lib.optionalAttrs piCodingAgentHasShrinkwrap {
        ${piCodingAgentPath} = piCodingAgentWithoutShrinkwrap;
      };
    };
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
        ln -s ${drv} "$out/node_modules/${name}"
      '') plugins
    )}

    runHook postInstall
  '';

  passthru = {
    inherit plugins;
    pluginVersions = lib.mapAttrs (_: drv: drv.version) plugins;
  };

  meta = {
    description = "Plugins for OMP, resolved and pinned rather than installed at run time";
    platforms = lib.platforms.all;
  };
}
