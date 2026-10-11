# MacBook Pro, run headless as this configuration's `server` role.
#
# The attribute name must match `scutil --get LocalHostName` for a bare
# `darwin-rebuild switch --flake <path>` to pick it up; otherwise select it
# explicitly with `--flake <path>#bhyoo-macbook-pro`.
{ pkgs, ... }:

{
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Lets this machine produce the 2FA codes for its own logins: a chosen
  # subset of Ente Auth entries lives in its login keychain (`totp import`),
  # and `totp code NAME` turns one into the current code.
  environment.systemPackages = [ pkgs.keychain-totp ];
}
