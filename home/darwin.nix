# home-manager configuration for every Mac.
#
# Desktop applications are not here — they belong to the laptop role, in
# home/roles/darwin-laptop.nix.
{ pkgs, ... }:

{
  imports = [ ./keyboard.nix ];

  # The 1Password CLI, on every Mac including the headless one. `op` is a
  # single binary with no system integration, so unlike the desktop app it can
  # come from nixpkgs and be pinned by flake.lock. It does not need the app to
  # work: a service account token authenticates it non-interactively, which is
  # what a machine with nobody at it has to use.
  home.packages = [ pkgs._1password-cli ];
}
