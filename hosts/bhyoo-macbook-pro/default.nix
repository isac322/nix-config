# MacBook Pro, run headless as this configuration's `server` role.
#
# The attribute name must match `scutil --get LocalHostName` for a bare
# `darwin-rebuild switch --flake <path>` to pick it up; otherwise select it
# explicitly with `--flake <path>#bhyoo-macbook-pro`.
{ ... }:

{
  nixpkgs.hostPlatform = "aarch64-darwin";

  # This machine's WireGuard address, which is what an Orca client dials to
  # reach the runtime the server role keeps running here. The option is declared
  # in modules/orca.nix and the reasoning is in
  # docs/decisions/0028-orca-runtime-on-the-server-mac.md.
  #
  # It is here rather than in the role because it describes this machine and
  # nothing else — a second server Mac would set its own and share every other
  # line of the configuration.
  local.orca.pairingAddress = "10.222.0.134";
}
