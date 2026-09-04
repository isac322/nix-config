{
  description = "Isac's systems";

  inputs = {
    nixpkgs.url = "git+https://github.com/NixOS/nixpkgs.git?ref=nixpkgs-unstable&shallow=1";

    nix-darwin.url = "git+https://github.com/nix-darwin/nix-darwin.git?ref=master&shallow=1";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "git+https://github.com/nix-community/home-manager.git?ref=master&shallow=1";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "git+https://github.com/zhaofengli/nix-homebrew.git?shallow=1";
    nix-homebrew.inputs.brew-src = {
      url = "git+https://github.com/Homebrew/brew.git?rev=3ecc9eff23feebf1bc73846d74e14a122c93b66f&shallow=1";
      flake = false;
    };

    nixpkgs-firefox-darwin.url = "git+https://github.com/bandithedoge/nixpkgs-firefox-darwin.git?shallow=1";
    nixpkgs-firefox-darwin.inputs.nixpkgs.follows = "nixpkgs";

    # Deliberately NOT `inputs.nixpkgs.follows = "nixpkgs"`. We take
    # `packages.<system>` from this flake rather than its overlay precisely
    # because those are built against the nixpkgs it pinned, which is what makes
    # the store paths match what cache.numtide.com holds. A `follows` would
    # change every one of them and put us back to compiling Rust from source,
    # which is what the overlay was doing. See home/common.nix.
    llm-agents.url = "git+https://github.com/numtide/llm-agents.nix.git?shallow=1";
    # Upstream still declares these through Nix's GitHub fetcher. Each override
    # stays pinned to the revision in llm-agents' own lock file: allowing one to
    # float independently would change the package graph and miss
    # cache.numtide.com. When llm-agents updates, review its new lock and update
    # these revisions in the same change.
    llm-agents.inputs = {
      bun2nix.url = "git+https://github.com/nix-community/bun2nix.git?rev=5765b0614591f75ee8ba5596e81ae85c167d1071&shallow=1";
      bun2nix.inputs = {
        flake-parts.url = "git+https://github.com/hercules-ci/flake-parts.git?rev=17c9d6cdfc60c64f4ee8d306f9bc0b4ccb51481e&shallow=1";
        flake-parts.inputs.nixpkgs-lib.url = "git+https://github.com/nix-community/nixpkgs.lib.git?rev=db3f255737b94216eb71cce308e2912cf6bc2d7c&shallow=1";
        nixpkgs.url = "git+https://github.com/NixOS/nixpkgs.git?rev=241313f4e8e508cb9b13278c2b0fa25b9ca27163&shallow=1";
        systems.url = "git+https://github.com/nix-systems/triplet.git?rev=6de7bc09397911ce03636afbcf6118745ab2cda0&shallow=1";
        treefmt-nix.url = "git+https://github.com/numtide/treefmt-nix.git?rev=df3c0640565d04a0261253cdd89fce78ec50168a&shallow=1";
        treefmt-nix.inputs.nixpkgs.url = "git+https://github.com/NixOS/nixpkgs.git?rev=4533d9293756b63904b7238acb84ac8fe4c8c2c4&shallow=1";
      };
      flake-parts.url = "git+https://github.com/hercules-ci/flake-parts.git?rev=f16b25b8c3d2809b87925d0b76652d7821a75c68&shallow=1";
      flake-parts.inputs.nixpkgs-lib.url = "git+https://github.com/nix-community/nixpkgs.lib.git?rev=596e2e3940e09b2abbeb03f75fa1828c57fcd72c&shallow=1";
      nixpkgs.url = "git+https://github.com/NixOS/nixpkgs.git?rev=e8be7818e19ada32105a8af937a6a473b38167ca&shallow=1";
      systems.url = "git+https://github.com/nix-systems/default.git?rev=da67096a3b9bf56a91d16901293e51ba5b49a27e&shallow=1";
      treefmt-nix.url = "git+https://github.com/numtide/treefmt-nix.git?rev=27b3b12a8e6375f28ebe122f07d230ca5459bbfa&shallow=1";
    };

    # SkillClaw is not a flake. Pin its source here so the Python package and
    # every node's client/server processes use one reviewed revision.
    skillclaw = {
      url = "git+https://github.com/AMAP-ML/SkillClaw.git?shallow=1";
      flake = false;
    };

    # Public Agent Skills are source trees, not flakes. flake.lock pins the
    # exact revisions installed by home/agent-skills.nix on every node.
    gentle-ai = {
      url = "git+https://github.com/Gentleman-Programming/gentle-ai.git?shallow=1";
      flake = false;
    };
    humanizer = {
      url = "git+https://github.com/blader/humanizer.git?shallow=1";
      flake = false;
    };
    agent-toolkit = {
      url = "git+https://github.com/softaworks/agent-toolkit.git?shallow=1";
      flake = false;
    };

    pi-codegraph-source = {
      url = "git+https://github.com/isac322/pi-codegraph.git?ref=main&shallow=1";
      flake = false;
    };

    # Sources whose upstream does not publish a release manifest with a
    # complete dependency graph. Their own lock files are consumed directly.
    camofox-browser-source = {
      url = "git+https://github.com/jo-inc/camofox-browser.git?ref=master&shallow=1";
      flake = false;
    };
    context-mode-source = {
      url = "git+https://github.com/mksglu/context-mode.git?ref=main&shallow=1";
      flake = false;
    };
    macvnc-source = {
      url = "git+https://github.com/LibVNC/macVNC.git?ref=main&shallow=1";
      flake = false;
    };
    zsh-auto-notify-source = {
      url = "git+https://github.com/MichaelAquilina/zsh-auto-notify.git?ref=master&shallow=1";
      flake = false;
    };
    pi-anthropic-web-fetch-source = {
      url = "git+https://github.com/code-yeongyu/pi-anthropic-web-fetch.git?ref=main&shallow=1";
      flake = false;
    };
    pi-google-url-context-source = {
      url = "git+https://github.com/code-yeongyu/pi-google-url-context.git?ref=main&shallow=1";
      flake = false;
    };
    pi-anthropic-web-search-source = {
      url = "git+https://github.com/code-yeongyu/pi-anthropic-web-search.git?ref=main&shallow=1";
      flake = false;
    };
    pi-openai-web-search-source = {
      url = "git+https://github.com/code-yeongyu/pi-openai-web-search.git?ref=main&shallow=1";
      flake = false;
    };
    pi-google-google-search-source = {
      url = "git+https://github.com/code-yeongyu/pi-google-google-search.git?ref=main&shallow=1";
      flake = false;
    };

    # Lets nix-darwin manage /etc/nix/nix.custom.conf declaratively. It forces
    # `nix.enable = false`, leaving /etc/nix/nix.conf to Determinate Nix.
    # No `follows` here either: upstream advises against it (FlakeHub cache).
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";

    # Determinate itself comes from FlakeHub, but its Nix input still contains
    # three GitHub-fetcher sources. Pin every override to Determinate's own lock
    # revisions; update them only when the corresponding upstream lock changes.
    determinate.inputs.nix.inputs.nixpkgs-23-11.url =
      "git+https://github.com/NixOS/nixpkgs.git?rev=a62e6edd6d5e1fa0329b8653c801147986f8d446&shallow=1";
    determinate.inputs.nix.inputs.nixpkgs-regression.url =
      "git+https://github.com/NixOS/nixpkgs.git?rev=215d4d0fd80ca5163643b03a33fde804a29cc1e2&shallow=1";
    determinate.inputs.nix.inputs.git-hooks-nix.inputs.flake-compat = {
      url = "git+https://github.com/edolstra/flake-compat.git?rev=0f9255e01c2351cc7d116c072cb317785dd33b33&shallow=1";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nix-darwin,
      nixpkgs,
      home-manager,
      nix-homebrew,
      ...
    }:
    let
      user = "bhyoo";
      releaseSnapshots = builtins.fromJSON (builtins.readFile ./pkgs/release-snapshots.json);
      snapshotFile = name: value: builtins.toFile "release-snapshot-${name}.json" (builtins.toJSON value);
      releaseManifests = nixpkgs.lib.mapAttrs snapshotFile releaseSnapshots.releaseManifests;
      beardriveChecksums = builtins.toFile "beardrive-checksums.txt" releaseSnapshots.beardriveChecksums;
      gajaeCodeManifest = snapshotFile "gajae-code" releaseSnapshots.gajaeCodeManifest;
      sourceInputs = {
        camofoxBrowser = inputs.camofox-browser-source;
        contextMode = inputs.context-mode-source;
        piCodegraph = inputs.pi-codegraph-source;
        macvnc = inputs.macvnc-source;
        piAnthropicWebFetch = inputs.pi-anthropic-web-fetch-source;
        piGoogleUrlContext = inputs.pi-google-url-context-source;
        piAnthropicWebSearch = inputs.pi-anthropic-web-search-source;
        piOpenaiWebSearch = inputs.pi-openai-web-search-source;
        piGoogleGoogleSearch = inputs.pi-google-google-search-source;
      };
      packageOverlay = import ./pkgs/overlay.nix {
        inherit
          beardriveChecksums
          gajaeCodeManifest
          releaseManifests
          sourceInputs
          ;
        bun2nix = inputs.llm-agents.inputs.bun2nix;
      };

      # Systems the locally packaged cross-platform tools are offered for. Two
      # of these are machines that exist here; x86_64-linux is included because
      # it costs nothing to evaluate and is what anyone else consuming this
      # flake is most likely to be on. The native browser packages are added to
      # aarch64-darwin only below.
      forAllSystems = nixpkgs.lib.genAttrs [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      # Three axes, composed rather than inherited: every configuration is
      # `common + platform + role + host`. A Mac is the same Mac in either role
      # — same keyboard, Finder, Dock and trackpad — so the role files carry
      # only what genuinely differs: desktop applications on a laptop, staying
      # awake on a server. `extraModules` / `extraHomeModules` remain for
      # anything that fits none of the three, such as one machine also serving
      # media.
      mkDarwin =
        {
          hostname,
          role,
          extraModules ? [ ],
          extraHomeModules ? [ ],
        }:
        nix-darwin.lib.darwinSystem {
          specialArgs = { inherit inputs hostname packageOverlay; };
          modules = [
            ./modules/common.nix
            ./modules/darwin.nix
            ./modules/roles/darwin-${role}.nix
            ./hosts/${hostname}

            inputs.determinate.darwinModules.default

            nix-homebrew.darwinModules.nix-homebrew
            {
              nix-homebrew = {
                enable = true;
                enableRosetta = false;
                inherit user;
              };
            }

            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit inputs; };

              # home-manager refuses to overwrite a file it did not create and
              # aborts the whole activation, which is how ~/.ssh/config — left
              # behind by OrbStack — took down a switch. Moving the stray file
              # aside turns that into a rename instead of a dead end.
              home-manager.backupFileExtension = "hm-backup";
              home-manager.users.${user}.imports = [
                ./home/common.nix
                ./home/darwin.nix
                ./home/roles/darwin-${role}.nix
              ]
              ++ extraHomeModules;
            }
          ]
          ++ extraModules;
        };

      mkNixos =
        {
          hostname,
          extraModules ? [ ],
          extraHomeModules ? [ ],
        }:
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs packageOverlay; };
          modules = [
            ./modules/common.nix
            ./modules/nixos.nix
            ./hosts/${hostname}

            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit inputs; };

              # home-manager refuses to overwrite a file it did not create and
              # aborts the whole activation, which is how ~/.ssh/config — left
              # behind by OrbStack — took down a switch. Moving the stray file
              # aside turns that into a rename instead of a dead end.
              home-manager.backupFileExtension = "hm-backup";
              home-manager.users.${user}.imports = [
                ./home/common.nix
                ./home/linux.nix
              ]
              ++ extraHomeModules;
            }
          ]
          ++ extraModules;
        };
    in
    {
      # pkgs/ is exposed as flake outputs, not just consumed internally, so
      # that another machine — or another person — can take these packages as
      # an input instead of copying the directory. pkgs/overlay.nix remains the
      # single definition: the configurations below import the same file, so
      # there is no second copy to drift.
      overlays.default = packageOverlay;

      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ packageOverlay ];
            config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "sentry" ];
          };
        in
        {
          inherit (pkgs)
            posthog-cli
            axiom-cli
            langfuse-cli
            vercel-cli
            beardrive
            gajae-code
            sentry
            slack-cli
            omp-bin
            tempo-cli
            ;
        }
        // nixpkgs.lib.optionalAttrs (system == "aarch64-darwin") {
          inherit (pkgs)
            camoufox
            camofox-browser
            camofox-url-handler
            deskpad
            displayplacer
            macvnc
            ;
        }
      );

      # `nix run .#cache-push -- <cache>` builds and uploads the custom CLI
      # packages above plus source-built macVNC on Darwin. Fixed upstream
      # artifact repacks are still exposed as package outputs, but pushing them
      # saves only an unpack and consumes cache bandwidth, so they are excluded
      # explicitly below. A newly added package remains included by default.
      #
      # The store paths are baked in rather than resolved from `.#` at run
      # time: building this app builds precisely what it will push, and it
      # keeps the script correct when run from another directory.
      apps = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system}.extend packageOverlay;
          inherit (nixpkgs) lib;
          targets = builtins.attrValues (
            builtins.removeAttrs self.packages.${system} [
              "camoufox"
              "camofox-browser"
              "deskpad"
              "displayplacer"
            ]
          );
        in
        {
          cache-push = {
            type = "app";
            meta.description = "Push selected locally packaged outputs to a Cachix cache";
            program = lib.getExe (
              pkgs.writeShellApplication {
                name = "cache-push";
                runtimeInputs = [ pkgs.cachix ];
                text = ''
                  cache=''${1:-}
                  if [ -z "$cache" ]; then
                    echo "usage: nix run <flake>#cache-push -- <cachix-cache-name>" >&2
                    exit 2
                  fi
                  exec cachix push "$cache" ${lib.concatStringsSep " " (map toString targets)}
                '';
              }
            );
          };
          update-packages = {
            type = "app";
            meta.description = "Refresh packaged upstream releases and flake inputs atomically";
            program = lib.getExe (
              pkgs.writeShellApplication {
                name = "update-packages";
                runtimeInputs = [
                  pkgs.nix
                  pkgs.python3
                ];
                text = ''
                  exec python3 ${./pkgs/release-snapshots/update.py} --repo "$PWD" "$@"
                '';
              }
            );
          };
        }
      );

      # Attribute names match each machine's host name, so a bare
      # `darwin-rebuild switch --flake <path>` resolves. With more than one host
      # there is no sensible `default`; name the target explicitly when the
      # machine is called something else.
      darwinConfigurations = {
        "bhyoo-macbook-air" = mkDarwin {
          hostname = "bhyoo-macbook-air";
          role = "laptop";
        };
        "bhyoo-macbook-pro" = mkDarwin {
          hostname = "bhyoo-macbook-pro";
          role = "server";
          extraModules = [ (import ./modules/borg-backup.nix { platform = "darwin"; }) ];
        };
      };

      nixosConfigurations = {
        server = mkNixos {
          hostname = "server";
          extraModules = [ (import ./modules/borg-backup.nix { platform = "linux"; }) ];
        };
      };
    };
}
