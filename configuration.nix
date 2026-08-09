{ pkgs, lib, inputs, ... }:

{
  # Determinate Nix owns the Nix install, the nix-daemon and /etc/nix/nix.conf,
  # so nix-darwin must not manage them; this module sets `nix.enable = false`
  # for us and renders /etc/nix/nix.custom.conf from `customSettings`.
  determinateNix = {
    enable = true;

    customSettings = {
      # Prebuilt llm-agents packages (omp is a ~237 MiB source build otherwise).
      extra-substituters = [ "https://cache.numtide.com" ];
      extra-trusted-public-keys = [
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      ];
    };
  };

  # The Determinate installer writes its own /etc/nix/nix.custom.conf, which the
  # determinate module then wants to replace. Without whitelisting that file's
  # hash, the first activation on a fresh machine aborts with
  # "Unexpected files in /etc". Add a hash here if an install writes a variant.
  environment.etc."nix/nix.custom.conf".knownSha256Hashes = [
    "3bd68ef979a42070a44f8d82c205cfd8e8cca425d91253ec2c10a88179bb34aa"
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.overlays = [
    inputs.nixpkgs-firefox-darwin.overlay
    inputs.llm-agents.overlays.shared-nixpkgs
  ];
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "claude-code" ];

  system.primaryUser = "bhyoo";

  users.users.bhyoo = {
    name = "bhyoo";
    home = "/Users/bhyoo";
  };

  environment.systemPackages = [
    pkgs.git
  ];

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

  system.defaults = {
    dock.autohide = true;
    finder.AppleShowAllExtensions = true;
    NSGlobalDomain.InitialKeyRepeat = 15;
    NSGlobalDomain.KeyRepeat = 2;
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

  system.stateVersion = 7;
}
