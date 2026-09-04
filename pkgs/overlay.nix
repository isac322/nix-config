# Packages this configuration needs that nixpkgs does not have, and the three
# it has in a form this configuration cannot use.
#
# They are added through an overlay rather than referenced as bare paths so
# that `pkgs.posthog-cli` works everywhere `pkgs` does — including inside
# home-manager modules, which never see this directory.
argsOrFinal:
let
  impl =
    {
      beardriveChecksums ? null,
      bun2nix ? null,
      gajaeCodeManifest ? null,
      releaseManifests ? { },
      sourceInputs ? { },
    }:
    final: prev:
    let
      release = import ./release-manifest.nix { inherit (final) lib; };
      bunAsset =
        system:
        let
          names = {
            "aarch64-darwin" = version: "bun-darwin-aarch64.zip";
            "aarch64-linux" = version: "bun-linux-aarch64.zip";
            "x86_64-linux" = version: "bun-linux-x64.zip";
          };
        in
        release.github {
          manifestFile = releaseManifests.bun;
          tagPrefix = "bun-v";
          assetName = names.${system};
        };
    in
    {
      posthog-cli = final.callPackage ./posthog-cli/package.nix {
        manifestFile = releaseManifests.posthog;
      };
      axiom-cli = final.callPackage ./axiom-cli/package.nix {
        manifestFile = releaseManifests.axiom;
      };
      langfuse-cli = final.callPackage ./langfuse-cli/package.nix {
        manifestFile = releaseManifests.langfuse;
      };
      vercel-cli = final.callPackage ./vercel-cli/package.nix {
        manifestFiles = {
          "aarch64-darwin" = releaseManifests.vercelDarwinArm64;
          "aarch64-linux" = releaseManifests.vercelLinuxArm64;
          "x86_64-linux" = releaseManifests.vercelLinuxX64;
        };
      };
      beardrive = final.callPackage ./beardrive/package.nix {
        checksumsFile = beardriveChecksums;
      };
      gajae-code = final.callPackage ./gajae-code/package.nix {
        manifestFile = gajaeCodeManifest;
      };
      sentry = final.callPackage ./sentry/package.nix {
        manifestFile = releaseManifests.sentry;
      };

      # Native Apple Silicon browser and remote-console components. Camofox uses
      # the immutable Camoufox browser; DeskPad supplies the virtual display,
      # macVNC exports its framebuffer, and displayplacer fixes its layout.
      camoufox = final.callPackage ./camoufox/package.nix {
        manifestFile = releaseManifests.camoufox;
      };
      camofox-browser = final.callPackage ./camofox-browser/package.nix {
        source = sourceInputs.camofoxBrowser;
      };
      camofox-mcp-session = final.callPackage ./camofox-mcp-session/package.nix { };
      camofox-url-handler = final.callPackage ./camofox-url-handler/package.nix { };
      deskpad = final.callPackage ./deskpad/package.nix {
        manifestFile = releaseManifests.deskpad;
      };
      displayplacer = final.callPackage ./displayplacer/package.nix {
        manifestFile = releaseManifests.displayplacer;
      };
      macvnc = final.callPackage ./macvnc/package.nix {
        source = sourceInputs.macvnc;
      };

      # macOS only in practice — it shells out to /usr/bin/security. Declared here
      # rather than in a role file because it is a program, and this is where this
      # repository's programs live.
      pinentry-keychain = final.callPackage ./pinentry-keychain/package.nix { };

      # omp's plugins as one node_modules tree, pinned here rather than fetched at
      # run time by `omp plugin install`.
      omp-bin = final.callPackage ./omp-bin/package.nix {
        manifestFile = releaseManifests.omp;
      };
      omp-plugins = final.callPackage ./omp-plugins {
        inherit sourceInputs;
        bun2nix = bun2nix.packages.${final.stdenv.hostPlatform.system}.default;
      };

      # This one replaces an existing attribute rather than adding one: nixpkgs'
      # `slack-cli` is a different project that took the name first. The reasoning
      # is in the package, since that is where it would be read.
      slack-cli = final.callPackage ./slack-cli/package.nix {
        manifestFile = releaseManifests.slack;
      };

      # Bun follows its official release metadata rather than the pinned nixpkgs
      # snapshot. `nix flake update` therefore moves the version and all three
      # platform artifacts together.
      #
      # Overriding is cheap here in a way it would not be for, say, nodejs:
      # nixpkgs does not build Bun, it unpacks an upstream binary. The package
      # reads `passthru.sources`, not `src`, so replacing that set is the actual
      # source override; finalAttrs then updates meta fields from the new version.
      #
      # All three platforms are replaced although only the Macs currently install
      # Bun. This overlay is also applied on NixOS, and a partial source set could
      # combine one release version with another platform's artifact.
      bun = prev.bun.overrideAttrs (
        finalAttrs: prevAttrs:
        let
          darwinArm64 = bunAsset "aarch64-darwin";
          linuxArm64 = bunAsset "aarch64-linux";
          linuxX64 = bunAsset "x86_64-linux";
        in
        {
          version = darwinArm64.version;
          __intentionallyOverridingVersion = true;

          passthru = prevAttrs.passthru // {
            sources = {
              "aarch64-darwin" = final.fetchurl {
                inherit (darwinArm64) url hash;
              };
              "aarch64-linux" = final.fetchurl {
                inherit (linuxArm64) url hash;
              };
              "x86_64-linux" = final.fetchurl {
                inherit (linuxX64) url hash;
              };
            };
          };
        }
      );

      # nixpkgs builds all four of Tempo's commands, three of which are the
      # server side of a trace store nothing here runs. Building only the CLI
      # takes the closure from 237 MiB to about 70 and keeps a binary called
      # `tempo` — which would read as the server — off PATH.
      tempo-cli = final.tempo.overrideAttrs (old: {
        pname = "tempo-cli";
        subPackages = [ "cmd/tempo-cli" ];
        meta = old.meta // {
          description = "Command line tool for Grafana Tempo";
          mainProgram = "tempo-cli";
        };
      });
    };
in
if argsOrFinal ? callPackage then impl { } argsOrFinal else impl argsOrFinal
