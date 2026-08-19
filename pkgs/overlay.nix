# Packages this configuration needs that nixpkgs does not have, and the three
# it has in a form this configuration cannot use.
#
# They are added through an overlay rather than referenced as bare paths so
# that `pkgs.posthog-cli` works everywhere `pkgs` does — including inside
# home-manager modules, which never see this directory.
final: prev: {
  posthog-cli = final.callPackage ./posthog-cli/package.nix { };
  axiom-cli = final.callPackage ./axiom-cli/package.nix { };
  langfuse-cli = final.callPackage ./langfuse-cli/package.nix { };
  vercel-cli = final.callPackage ./vercel-cli/package.nix { };
  beardrive = final.callPackage ./beardrive/package.nix { };
  sentry = final.callPackage ./sentry/package.nix { };

  # Native Apple Silicon browser and remote-console components. Camofox uses
  # the immutable Camoufox browser; DeskPad supplies the virtual display,
  # macVNC exports its framebuffer, and displayplacer fixes its layout.
  camoufox = final.callPackage ./camoufox/package.nix { };
  camofox-browser = final.callPackage ./camofox-browser/package.nix { };
  camofox-mcp-session = final.callPackage ./camofox-mcp-session/package.nix { };
  deskpad = final.callPackage ./deskpad/package.nix { };
  displayplacer = final.callPackage ./displayplacer/package.nix { };
  macvnc = final.callPackage ./macvnc/package.nix { };

  # macOS only in practice — it shells out to /usr/bin/security. Declared here
  # rather than in a role file because it is a program, and this is where this
  # repository's programs live.
  pinentry-keychain = final.callPackage ./pinentry-keychain/package.nix { };

  # omp's plugins as one node_modules tree, pinned here rather than fetched at
  # run time by `omp plugin install`.
  omp-plugins = final.callPackage ./omp-plugins { };

  # This one replaces an existing attribute rather than adding one: nixpkgs'
  # `slack-cli` is a different project that took the name first. The reasoning
  # is in the package, since that is where it would be read.
  slack-cli = final.callPackage ./slack-cli/package.nix { };

  # bun, one release ahead of the pinned nixpkgs, because 1.3.14 is the version
  # that was asked for. It has been upstream since 2026-05-13 and nixpkgs has
  # not taken it: the bump, PR #519796, was opened the same day and is still
  # open, with a duplicate (#537255) closed in between. Waiting for the channel
  # is not a plan when the channel is already three months behind.
  #
  # Overriding is cheap here in a way it would not be for, say, nodejs: nixpkgs
  # does not build bun, it unzips a binary upstream published, so this changes a
  # version string and three hashes and nothing else about the package.
  #
  # `passthru.sources` rather than `src`, because that is the attribute the
  # package actually reads — `src = finalAttrs.passthru.sources.${system}` —
  # and overrideAttrs re-evaluates finalAttrs, so replacing the set is what
  # moves src. meta.platforms and meta.changelog follow from the same two
  # attributes and come along on their own.
  #
  # All three platforms are replaced although only the Macs install bun. This
  # overlay is applied on NixOS too (modules/common.nix), and a set with one
  # entry updated would leave the others pointing 1.3.13 hashes at a 1.3.14
  # URL — a hash mismatch on a machine nobody was thinking about.
  #
  # Delete this binding when nixpkgs catches up; nothing else refers to it.
  bun = prev.bun.overrideAttrs (
    finalAttrs: prevAttrs: {
      version = "1.3.14";

      # Changing `version` in an overrideAttrs draws a warning from nixpkgs on
      # every evaluation, because the usual mistake is to move the version and
      # leave src pointing at the old release — a build that succeeds and
      # installs the wrong thing. src does move here, through the sources set
      # below, so the warning has nothing to catch and this says so.
      __intentionallyOverridingVersion = true;

      passthru = prevAttrs.passthru // {
        sources = {
          "aarch64-darwin" = final.fetchurl {
            url = "https://github.com/oven-sh/bun/releases/download/bun-v${finalAttrs.version}/bun-darwin-aarch64.zip";
            hash = "sha256-2LliIYKK1vl6x6wKt+lYcjQa92MAHogD6CZ2UsJlJiA=";
          };
          "aarch64-linux" = final.fetchurl {
            url = "https://github.com/oven-sh/bun/releases/download/bun-v${finalAttrs.version}/bun-linux-aarch64.zip";
            hash = "sha256-on/7Y6gxA3WDbg1vZorhf6jY0YuIw3yCHGUzGXOhmjs=";
          };
          "x86_64-linux" = final.fetchurl {
            url = "https://github.com/oven-sh/bun/releases/download/bun-v${finalAttrs.version}/bun-linux-x64.zip";
            hash = "sha256-lR7iruhV8IWVruxiJSJqKY0/6oOj3NZGXAnLzN9+hI8=";
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
}
