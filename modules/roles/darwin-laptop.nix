# A Mac someone sits in front of.
#
# Dock, trackpad, keyboard, Finder and the rest are the same on every Mac and
# live in modules/darwin.nix; what makes a laptop different is only that it
# runs desktop applications. The user-level half is
# home/roles/darwin-laptop.nix.
{ inputs, ... }:

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

  # Not on Homebrew: both are Mac App Store exclusives, so they go through mas.
  # This needs the App Store to be signed in on the machine — mas cannot log in
  # for you, and an unpurchased or unsigned-in app is simply skipped.
  homebrew.masApps = {
    KakaoTalk = 869223134;
    WireGuard = 1451685025;
  };
}
