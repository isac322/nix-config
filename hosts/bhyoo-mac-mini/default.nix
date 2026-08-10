# Mac mini.
#
# The attribute name must match `scutil --get LocalHostName` for a bare
# `darwin-rebuild switch --flake <path>` to pick it up; otherwise select it
# explicitly with `--flake <path>#bhyoo-mac-mini`.
{ ... }:

{
  nixpkgs.hostPlatform = "aarch64-darwin";
}
