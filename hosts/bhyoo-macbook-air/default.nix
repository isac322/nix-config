# MacBook Air. Everything shared with the MacBook Pro is in modules/darwin.nix;
# only what is genuinely specific to this machine belongs here.
{ ... }:

{
  nixpkgs.hostPlatform = "aarch64-darwin";
}
