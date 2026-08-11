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
    "1password" # the desktop app; the `op` CLI is in home/darwin.nix
    "ente-auth"
    "ghostty" # nixpkgs builds it for Linux only; config is in home/roles/
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

  # A global keybind is registered by the running application, so with Ghostty
  # closed there is no process to receive F12 or ⌘⌥T and nothing happens at
  # all. macOS has no built-in way to bind a key to launching an app — the
  # keyboard settings only reach menu items of apps already running — so the
  # app has to be up. This starts it at login; `quit-after-last-window-closed`
  # in home/roles/darwin-laptop.nix keeps it up after the last window closes.
  #
  # `-g` keeps it from taking focus at login, and `--initial-window=false`
  # applies only to this launch, so opening Ghostty by hand still gives a
  # window.
  launchd.user.agents.ghostty = {
    serviceConfig = {
      ProgramArguments = [
        "/usr/bin/open"
        "-g"
        "-a"
        "Ghostty"
        "--args"
        "--initial-window=false"
      ];
      RunAtLoad = true;
    };
  };

  # KakaoTalk and WireGuard are missing on purpose: both are Mac App Store
  # exclusives and there is no route to either from here.
  #
  # KakaoTalk has no cask anywhere in Homebrew, nothing in nixpkgs, and no
  # direct download — every Kakao CDN path answers 403, browser headers
  # included. WireGuard's official client is App Store only too; the casks
  # that mention WireGuard (defguard-client, firezone, passepartout,
  # tailscale-app) are other vendors' clients, not the same application.
  # nixpkgs has wireguard-tools and wireguard-go, but those are the CLI, not
  # the app that was asked for.
  #
  # `homebrew.masApps` is not the answer either: brew bundle runs under sudo
  # during activation, while the App Store's installd only answers inside the
  # logged-in user's session, so mas never reaches it (mas-cli issue #1221).
  # It does not fail quietly — the two entries took `brew bundle` down with
  # them, and set -e took the rest of activation, leaving /run/current-system
  # a generation behind.
  #
  # So both are installed by hand from the App Store, once per machine.
}
