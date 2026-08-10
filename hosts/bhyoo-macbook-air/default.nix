# MacBook Air. Everything shared with the Mac mini is in modules/darwin.nix;
# only what is genuinely specific to this machine belongs here.
{ ... }:

{
  nixpkgs.hostPlatform = "aarch64-darwin";
}
