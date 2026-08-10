# Shared by every Mac. Host-specific bits live in hosts/<name>/default.nix.
{ lib, inputs, ... }:

let
  caches = import ../lib/caches.nix;
in
{
  # Determinate Nix owns the Nix install, the nix-daemon and /etc/nix/nix.conf,
  # so nix-darwin must not manage them; this module sets `nix.enable = false`
  # for us and renders /etc/nix/nix.custom.conf from `customSettings`.
  # NixOS needs none of this — it manages Nix itself, see modules/nixos.nix.
  determinateNix = {
    enable = true;

    customSettings = {
      extra-substituters = caches.substituters;
      extra-trusted-public-keys = caches.trustedPublicKeys;
    };
  };

  # The Determinate installer writes its own /etc/nix/nix.custom.conf, which the
  # determinate module then wants to replace. Without whitelisting that file's
  # hash, the first activation on a fresh machine aborts with
  # "Unexpected files in /etc". Add a hash here if an install writes a variant.
  environment.etc."nix/nix.custom.conf".knownSha256Hashes = [
    "3bd68ef979a42070a44f8d82c205cfd8e8cca425d91253ec2c10a88179bb34aa"
  ];

  # Darwin only, and it has to stay that way: besides firefox-bin, this overlay
  # defines `librewolf`, `floorp-bin` and `zen-browser-bin`, which on Linux
  # would shadow the perfectly good nixpkgs packages of the same names.
  nixpkgs.overlays = [ inputs.nixpkgs-firefox-darwin.overlay ];

  system.primaryUser = "bhyoo";

  users.users.bhyoo = {
    name = "bhyoo";
    home = "/Users/bhyoo";
  };

  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";
    onActivation.upgrade = true;
    # Without this, `brew bundle` runs with HOMEBREW_NO_AUTO_UPDATE=1 and
    # `upgrade` only sees the formula index as of the last manual `brew update`.
    onActivation.autoUpdate = true;
    casks = [
      # "discord"
    ];
  };

  # mkDefault throughout: these are a baseline every Mac starts from, and a host
  # that wants something else says so in hosts/<name>/default.nix. Without it
  # the two definitions collide at equal priority and evaluation fails.
  system.defaults = {
    dock.autohide = lib.mkDefault true;
    finder.AppleShowAllExtensions = lib.mkDefault true;
    NSGlobalDomain.InitialKeyRepeat = lib.mkDefault 15;
    NSGlobalDomain.KeyRepeat = lib.mkDefault 2;
  };

  system.activationScripts.extraActivation.text = ''
    if ! /usr/bin/xcode-select -p &>/dev/null; then
      echo "Installing Xcode Command Line Tools..." >&2
      touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
      PROD=$(softwareupdate -l 2>/dev/null | grep "\*.*Command Line" | tail -n 1 | sed 's/^[^C]* //')
      softwareupdate -i "$PROD" --verbose
      rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    fi
  '';

  # nix-darwin types this as an integer; NixOS uses a string. Hence per-platform.
  system.stateVersion = 7;
}
