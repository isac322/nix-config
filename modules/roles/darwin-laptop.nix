# A Mac someone sits in front of.
#
# Almost nothing is here on purpose. Dock, trackpad, keyboard, Finder and the
# rest are the same on every Mac and live in modules/darwin.nix; what makes a
# laptop different is only that it runs desktop applications. The user-level
# half of that is home/roles/darwin-laptop.nix.
{ inputs, ... }:

{
  # Only the machines that actually run Firefox need this overlay, and it is
  # not harmless elsewhere: besides firefox-bin it defines librewolf,
  # floorp-bin and zen-browser-bin, shadowing the nixpkgs packages of those
  # names for anything else that might want them.
  nixpkgs.overlays = [ inputs.nixpkgs-firefox-darwin.overlay ];
}
