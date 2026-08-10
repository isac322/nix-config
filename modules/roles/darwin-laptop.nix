# A Mac someone sits in front of.
#
# Dock, trackpad, keyboard, Finder and the rest are the same on every Mac and
# live in modules/darwin.nix; what makes a laptop different is only that it
# runs desktop applications. The user-level half is
# home/roles/darwin-laptop.nix.
{ inputs, pkgs, ... }:

{
  # Only the machines that actually run Firefox need this overlay, and it is
  # not harmless elsewhere: besides firefox-bin it defines librewolf,
  # floorp-bin and zen-browser-bin, shadowing the nixpkgs packages of those
  # names for anything else that might want them.
  nixpkgs.overlays = [ inputs.nixpkgs-firefox-darwin.overlay ];

  # GUI applications come from Homebrew rather than nixpkgs. Most of these have
  # no darwin build in nixpkgs at all, and the ones that do are unmaintained
  # app-bundle copies that miss the privileged pieces — the same reason WARP
  # and Karabiner are casks. Homebrew is also what keeps them current, since
  # `onActivation.upgrade` is on.
  # Stably's Orca ships from its own tap rather than homebrew-cask, so the tap
  # has to be declared alongside it. nix-homebrew leaves taps mutable by
  # default, which is what lets this work without pinning the tap as a flake
  # input.
  homebrew.taps = [ "stablyai/orca" ];

  homebrew.casks = [
    "ente-auth"
    "google-chrome"
    "intellij-idea" # Ultimate; the community edition is intellij-idea-ce
    "kde-connect"
    "linear"
    "notion"
    "orbstack"
    "slack"
    "stablyai/orca/orca"
    "telegram" # the native macOS client, not telegram-desktop
    "vorta"
    "zoom"
  ];

  # WireGuard from nixpkgs rather than the App Store. The App Store app is a
  # menu-bar front end; these are the actual implementation, and unlike a cask
  # they are pinned by flake.lock. macOS has no kernel module, so wg-quick runs
  # the tunnel through the userspace wireguard-go, which wireguard-tools does
  # not pull in by itself. They go in systemPackages rather than home.packages
  # because `wg-quick` is run under sudo and root has to find both on PATH.
  #
  #   sudo wg-quick up /path/to/tunnel.conf
  environment.systemPackages = [
    pkgs.wireguard-tools
    pkgs.wireguard-go
  ];

  # KakaoTalk is missing on purpose. It is a Mac App Store exclusive: no cask
  # anywhere in Homebrew, nothing in nixpkgs, and no direct download — every
  # Kakao CDN path answers 403. `homebrew.masApps` cannot install it here
  # either: brew bundle runs under sudo during activation, while the App
  # Store's installd only answers inside the logged-in user's session, so mas
  # never reaches it (mas-cli issue #1221). It does not fail quietly — the
  # entry took `brew bundle` down with it, and set -e took the rest of
  # activation, leaving /run/current-system a generation behind.
  #
  # So it is installed by hand from the App Store, once per machine.
}
