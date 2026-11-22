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

  # Keep T3 Code's state, SQLite DB, provider profiles, caches, scratch dirs,
  # and worktrees on the external APFS SSD mounted at /data so they stay off
  # the internal drive and share one APFS volume with fastWorktreeCheckout.
  local.t3code.baseDir = "/data/data/t3code";
}
