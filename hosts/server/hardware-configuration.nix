# PLACEHOLDER — replace wholesale before the first build.
#
# Run `nixos-generate-config --show-hardware-config` on the actual machine and
# write the output over this file. The values below exist only so the flake
# still evaluates from a Mac; they describe no real disk and will not boot.
{ lib, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  swapDevices = lib.mkDefault [ ];
}
