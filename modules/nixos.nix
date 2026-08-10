# Shared by every NixOS host. Host-specific bits live in hosts/<name>/.
{ pkgs, ... }:

let
  caches = import ../lib/caches.nix;
in
{
  # No Determinate module here: on NixOS, Nix is part of the system closure and
  # nix.settings writes /etc/nix/nix.conf directly. This is the same
  # configuration the Macs express through `determinateNix.customSettings`.
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    extra-substituters = caches.substituters;
    extra-trusted-public-keys = caches.trustedPublicKeys;
    trusted-users = [
      "root"
      "bhyoo"
    ];
  };

  # Collect garbage on a server that nobody logs into to do it by hand.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  nix.optimise.automatic = true;

  users.users.bhyoo = {
    isNormalUser = true;
    description = "Byeonghoon Yoo";
    home = "/home/bhyoo";
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
  };

  # Required for `users.users.bhyoo.shell = pkgs.zsh` to be a valid login shell.
  programs.zsh.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  time.timeZone = "Asia/Seoul";
  i18n.defaultLocale = "en_US.UTF-8";

  # NixOS types this as a string; nix-darwin uses an integer. Hence per-platform.
  system.stateVersion = "26.05";
}
