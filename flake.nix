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

      # The two axes are machine and purpose, and they are composed rather than
      # inherited: every configuration is `common + platform + host + roles`.
      # `extraModules` / `extraHomeModules` are where a role plugs in — e.g. a
      # Mac mini doing double duty would pass a shared ./modules/media-server.nix
      # without any of the other hosts noticing.

      mkDarwin =
        {
          hostname,
          extraModules ? [ ],
          extraHomeModules ? [ ],
        }:
        nix-darwin.lib.darwinSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./modules/common.nix
            ./modules/darwin.nix
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
              home-manager.users.${user}.imports = [
                ./home/common.nix
                ./home/darwin.nix
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
      # Attribute names match each machine's host name, so a bare
      # `darwin-rebuild switch --flake <path>` resolves. With more than one host
      # there is no sensible `default`; name the target explicitly when the
      # machine is called something else.
      darwinConfigurations = {
        "bhyoo-macbook-air" = mkDarwin { hostname = "bhyoo-macbook-air"; };
        "bhyoo-mac-mini" = mkDarwin { hostname = "bhyoo-mac-mini"; };
      };

      nixosConfigurations = {
        server = mkNixos { hostname = "server"; };
      };
    };
}
