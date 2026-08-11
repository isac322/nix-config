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

  # This machine is reached from Ghostty, which sets TERM=xterm-ghostty. That
  # name is not in ncurses — 6.6 ships the entry as plain `ghostty`, a
  # different name that does not answer for it — so without this every TUI over
  # ssh dies with `Error opening terminal: xterm-ghostty`.
  #
  # The laptop's Ghostty can push the entry over on first connect
  # (`shell-integration-features = ssh-terminfo`, home/roles/darwin-laptop.nix),
  # but that is a shell function wrapping `ssh`, so it misses anything not
  # typed at a prompt. This is a machine we own, so it carries the entry itself
  # and the answer stops depending on how the connection was opened. 2 kB from
  # cache.nixos.org, built from the same 1.3.1 the laptop runs.
  environment.systemPackages = [ pkgs.ghostty.terminfo ];

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
