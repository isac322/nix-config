{
  description = "Isac's darwin system";

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

  outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager, nix-homebrew, ... }:
    let
      system = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit inputs; };
        modules = [
          ./configuration.nix

          inputs.determinate.darwinModules.default

          nix-homebrew.darwinModules.nix-homebrew
          {
            nix-homebrew = {
              enable = true;
              enableRosetta = false;
              user = "bhyoo";
            };
          }

          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.bhyoo = import ./home.nix;
          }
        ];
      };
    in
    {
      # `darwin-rebuild` with no attribute selects
      # `darwinConfigurations.$(scutil --get LocalHostName)`, so a machine with a
      # different host name needs an attribute that does not depend on it. Both
      # names below are the same configuration; on a fresh machine use
      # `darwin-rebuild switch --flake /etc/nix-darwin#default`.
      darwinConfigurations = {
        default = system;
        "bhyoo-macbook-air" = system;
      };
    };
}

