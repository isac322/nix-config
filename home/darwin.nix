# home-manager configuration for every Mac.
#
# Desktop applications are not here — they belong to the laptop role, in
# home/roles/darwin-laptop.nix.
{ ... }:

{
  imports = [ ./keyboard.nix ];
}
