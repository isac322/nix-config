# omp's plugins, as one node_modules tree that Nix builds.
#
# omp finds plugins by scanning `~/.omp/plugins/node_modules`, and an entry
# there may be a symlink — verified on a machine: `omp plugin link` writes a
# symlink and `omp plugin list` reports the package. Nothing records the set
# anywhere else; `~/.omp/plugins/package.json` stayed `{"dependencies": {}}`
# with a plugin linked and listed. So a tree built here and symlinked into
# place is a complete answer, not a trick.
#
# `omp plugin install` fetches from npm at run time, which makes the plugins on
# a machine whatever it last downloaded rather than what this flake pins — the
# same objection this repository already makes to rustup
# (home/roles/darwin-server.nix). Doing it here means `flake.lock` and the
# hashes below decide, and three machines agree.
#
# The cost, stated plainly: `~/.omp/plugins/node_modules` becomes a read-only
# store path, so `omp plugin install` no longer works on these machines. Adding
# a plugin means adding a line here.
#
# Two shapes, because the plugins come in two shapes.
#
#   Six have no runtime dependencies at all — their manifests declare
#   `dependencies: {}` and only peer dependencies, which omp itself provides.
#   Those are just source trees, so they are fetched and placed.
#
#   `context-mode` does have dependencies, so it comes from `buildNpmPackage`
#   against a committed lockfile, and that `node_modules` is merged into the
#   same tree. One tree matters: Node resolves a dependency by walking up from
#   the *real* path of the importing file, so a package and the things it
#   imports have to share a directory.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchurl,
  buildNpmPackage,
}:

let
  # Extensions for the pi/omp agent by one author, all the same shape: no
  # dependencies, `type: module`, and a `pi.extensions` manifest key pointing at
  # `src/index.ts` — omp loads the TypeScript directly, so there is nothing to
  # build.
  fromGitHub =
    {
      repo,
      rev,
      hash,
    }:
    fetchFromGitHub {
      owner = "code-yeongyu";
      inherit repo rev hash;
    };

  # npm packages that happen to have no dependencies, so the published tarball
  # is the whole package. `buildNpmPackage` would only add a lockfile and a
  # build step to something that needs neither.
  fromNpm =
    {
      pname,
      version,
      url,
      hash,
    }:
    stdenvNoCC.mkDerivation {
      inherit pname version;
      src = fetchurl { inherit url hash; };
      dontBuild = true;
      installPhase = "mkdir -p $out && cp -R . $out/";
    };

  standalone = {
    "pi-anthropic-web-fetch" = fromGitHub {
      repo = "pi-anthropic-web-fetch";
      rev = "3e882310f4dd";
      hash = "sha256-bK2KwLQyt5zXlg1v9dTLCeBrPd9NGj6ZSiOi0/MKGms=";
    };

    "pi-google-url-context" = fromGitHub {
      repo = "pi-google-url-context";
      rev = "4deb3b5a0995";
      hash = "sha256-IEzCHJFCCwwy/BmjHhotqF/0uP7FzD1hBmF7G9WrKDw=";
    };

    "pi-anthropic-web-search" = fromGitHub {
      repo = "pi-anthropic-web-search";
      rev = "f85d35421cef";
      hash = "sha256-Qa6sAPRTYuYfasOdAsVeMHAYacecRXaAvgNu0Df155U=";
    };

    "pi-google-google-search" = fromGitHub {
      repo = "pi-google-google-search";
      rev = "476db958f413";
      hash = "sha256-YF1fnx+BjlWgeqePOXBiNhvqzwm6CnkqgcJ2x7ucsSs=";
    };

    "@isac322/pi-codegraph" = fromNpm {
      pname = "pi-codegraph";
      version = "0.3.1";
      url = "https://registry.npmjs.org/@isac322/pi-codegraph/-/pi-codegraph-0.3.1.tgz";
      hash = "sha256-kMetzmQqqYbLTX550FuRBto8JMtk9M+aehdcrOSSgqE=";
    };

    "pi-agent-browser-native" = fromNpm {
      pname = "pi-agent-browser-native";
      version = "0.3.0";
      url = "https://registry.npmjs.org/pi-agent-browser-native/-/pi-agent-browser-native-0.3.0.tgz";
      hash = "sha256-beS3DWbEOyNt6klfmJNYJtOOKUQG1YI6NNW4UJTgoRY=";
    };
  };

  # The one that brings dependencies. `npmDepsHash` is the hash of everything the
  # lockfile resolves to; regenerate it with `nix build` and the hash it prints
  # when the lockfile changes.
  withDeps = buildNpmPackage {
    pname = "omp-plugins-npm";
    version = "0";
    src = ./npm;
    npmDepsHash = "sha256-fsUC40omBVFjl9QmZ7qVrJx+gEMkKnsy5sorrl2CKDo=";

    # There is nothing to compile — this exists only to resolve and place
    # dependencies — and the package has no build script of its own.
    dontNpmBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -R node_modules $out/node_modules
      runHook postInstall
    '';
  };
in
stdenvNoCC.mkDerivation {
  pname = "omp-plugins";
  version = "0";

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/node_modules

    # The dependency tree first, then the standalone packages on top. They
    # cannot collide: nothing in the lockfile is one of the six.
    cp -R ${withDeps}/node_modules/. $out/node_modules/
    chmod -R u+w $out/node_modules

    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: drv: ''
        mkdir -p "$out/node_modules/$(dirname ${lib.escapeShellArg name})"
        cp -R ${drv} "$out/node_modules/${name}"
      '') standalone
    )}

    chmod -R u+w $out/node_modules

    runHook postInstall
  '';

  meta = {
    description = "Plugins for omp, resolved and pinned rather than installed at run time";
    platforms = lib.platforms.all;
  };
}
