{
  description = "Isac's systems";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    nixpkgs-firefox-darwin.url = "github:bandithedoge/nixpkgs-firefox-darwin";
    nixpkgs-firefox-darwin.inputs.nixpkgs.follows = "nixpkgs";

    # Deliberately NOT `inputs.nixpkgs.follows = "nixpkgs"`: the shared-nixpkgs
    # overlay builds against our pkgs but pins `bun` from its own nixpkgs, and
    # following would change every store path in the set, missing the cache.
    llm-agents.url = "github:numtide/llm-agents.nix";

    # Lets nix-darwin manage /etc/nix/nix.custom.conf declaratively. It forces
    # `nix.enable = false`, leaving /etc/nix/nix.conf to Determinate Nix.
    # No `follows` here either: upstream advises against it (FlakeHub cache).
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";
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

      # Systems the locally packaged CLIs are offered for. Two of these are
      # machines that exist here; x86_64-linux is included because it costs
      # nothing to evaluate and is what anyone else consuming this flake is
      # most likely to be on.
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
          specialArgs = { inherit inputs; };
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
          specialArgs = { inherit inputs; };
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
      overlays.default = import ./pkgs/overlay.nix;

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system}.extend (import ./pkgs/overlay.nix);
        in
        {
          inherit (pkgs)
            posthog-cli
            axiom-cli
            langfuse-cli
            tempo-cli
            ;
        }
      );

      # `nix run .#cache-push -- <cache>` builds the four packages above and
      # uploads them. They are exactly the set no public cache can have:
      # posthog-cli, axiom-cli and langfuse-cli exist nowhere else, and
      # tempo-cli is an override, so its derivation differs from the tempo that
      # cache.nixos.org built. Everything else in a system closure still comes
      # from upstream caches, so there is nothing else worth pushing.
      #
      # The store paths are baked in rather than resolved from `.#` at run
      # time: building this app builds precisely what it will push, and it
      # keeps the script correct when run from another directory.
      apps = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system}.extend (import ./pkgs/overlay.nix);
          inherit (nixpkgs) lib;
          targets = [
            pkgs.posthog-cli
            pkgs.axiom-cli
            pkgs.langfuse-cli
            pkgs.tempo-cli
          ];
        in
        {
          cache-push = {
            type = "app";
            meta.description = "Push the locally packaged CLIs to a Cachix cache";
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
        "bhyoo-mac-mini" = mkDarwin {
          hostname = "bhyoo-mac-mini";
          role = "server";
        };
      };

      nixosConfigurations = {
        server = mkNixos { hostname = "server"; };
      };
    };
}
