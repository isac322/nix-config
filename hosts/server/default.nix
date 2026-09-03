# Linux server (NixOS, aarch64).
{ ... }:

{
  imports = [ ./hardware-configuration.nix ];

  nixpkgs.hostPlatform = "aarch64-linux";

  networking.hostName = "server";
  local.camofox.enable = true;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };
}
