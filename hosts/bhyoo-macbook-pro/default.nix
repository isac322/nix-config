# MacBook Pro, run headless as this configuration's `server` role.
#
# The attribute name must match `scutil --get LocalHostName` for a bare
# `darwin-rebuild switch --flake <path>` to pick it up; otherwise select it
# explicitly with `--flake <path>#bhyoo-macbook-pro`.
{ ... }:

{
  nixpkgs.hostPlatform = "aarch64-darwin";
}
