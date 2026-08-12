# Shared by every Mac. Host-specific bits live in hosts/<name>/default.nix.
{ lib, ... }:

let
  caches = import ../lib/caches.nix;
in
{
  imports = [
    ./keyboard.nix
    ./finder.nix
    ./appearance.nix
    ./warp.nix
  ];

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
      # Karabiner-Elements deliberately absent: it cannot be brought up without
      # a console session approving its driver extension and Input Monitoring.
      # The remapping it would have done is in modules/keyboard.nix via hidutil.
    ];
  };

  # Why a switch asks for a password a second time, after the one that started
  # it. Homebrew refuses to run as root, so nix-darwin's activation — which is
  # root by then — drops back to the primary user for the brew step:
  #
  #   sudo --preserve-env=PATH --user=bhyoo --set-home env brew bundle …
  #
  # Casks whose artifact is a `pkg` rather than an `app` have to run
  # /usr/sbin/installer as root, so Homebrew, now unprivileged, calls sudo
  # again. Root's authority does not flow down into a de-escalated child, and
  # the timestamp from the first sudo has a five-minute life (sudoers(5),
  # `timestamp_timeout`, default 5), which a build outlasts. So the prompt
  # appears exactly when brew has work to do — which `onActivation.upgrade`
  # above makes often.
  #
  # Thirty minutes covers a rebuild without leaving the terminal authenticated
  # for the rest of the day. The record is per-terminal (`timestamp_type` is
  # `tty` by default), so this does not hand the window to another session.
  # The laptop layers Touch ID on top; see modules/roles/darwin-laptop.nix.
  security.sudo.extraConfig = ''
    Defaults timestamp_timeout=30
  '';

  # mkDefault throughout: these are a baseline every Mac starts from, and a host
  # that wants something else says so in hosts/<name>/default.nix. Without it
  # the two definitions collide at equal priority and evaluation fails.
  system.defaults = {
    dock.autohide = lib.mkDefault true;
    finder.AppleShowAllExtensions = lib.mkDefault true;
    NSGlobalDomain.InitialKeyRepeat = lib.mkDefault 15;
    NSGlobalDomain.KeyRepeat = lib.mkDefault 2;

    # F1-F12 act as function keys; the media functions move behind fn. After the
    # rotation in modules/keyboard.nix, fn is the physical left control key, so
    # that is what reaches brightness and volume.
    NSGlobalDomain."com.apple.keyboard.fnState" = lib.mkDefault true;

    # Three-finger drag, which is what moves a window by its title bar. It is an
    # Accessibility setting rather than a Trackpad one, and nix-darwin writes it
    # to both com.apple.AppleMultitouchTrackpad and the Bluetooth domain, so it
    # covers the built-in trackpad and a Magic Trackpad alike.
    trackpad.TrackpadThreeFingerDrag = lib.mkDefault true;

    # Three-finger swipes have to give up their gestures for the drag to be
    # unambiguous; macOS expects those to move to four fingers.
    trackpad.TrackpadThreeFingerHorizSwipeGesture = lib.mkDefault 0;
    trackpad.TrackpadThreeFingerVertSwipeGesture = lib.mkDefault 0;
    trackpad.TrackpadFourFingerHorizSwipeGesture = lib.mkDefault 2;
    trackpad.TrackpadFourFingerVertSwipeGesture = lib.mkDefault 2;

    # Spaces keep the order they were created in. The default is to reorder them
    # by most recent use, which moves a space out from under the shortcut that
    # was just used to reach it.
    dock.mru-spaces = lib.mkDefault false;

    # No hot corners. macOS assigns one out of the box — bottom right opens a
    # Quick Note — and leaves the other three unset, which is not the same as
    # off: an unset corner is one a later release is free to assign. `1` is the
    # value for "no action", so all four are named rather than left to a
    # default.
    #
    # nix-darwin has no wvous-*-modifier options and none are needed here: a
    # modifier only gates a corner that has an action to gate.
    dock.wvous-tl-corner = lib.mkDefault 1;
    dock.wvous-tr-corner = lib.mkDefault 1;
    dock.wvous-bl-corner = lib.mkDefault 1;
    dock.wvous-br-corner = lib.mkDefault 1;

    # Recents stay. They sit to the right of the pinned list in
    # modules/roles/darwin-laptop.nix and never reorder it, so the two are
    # independent: the pinned tiles keep their positions and recents fill in
    # beside them. This matches Apple's default and is declared anyway, so that
    # pinning the Dock does not read as a decision about recents too.
    dock.show-recents = lib.mkDefault true;

    # Nothing on the desktop. This takes two owners: Finder draws the icons,
    # while widgets belong to WindowManager, so hiding one leaves the other.
    #
    # CreateDesktop hides every Finder icon, files included; the four
    # Show*OnDesktop keys decide which volumes would appear and are set anyway
    # so the desktop stays empty if icons are ever turned back on.
    finder.CreateDesktop = lib.mkDefault false;
    finder.ShowHardDrivesOnDesktop = lib.mkDefault false;
    finder.ShowExternalHardDrivesOnDesktop = lib.mkDefault false;
    finder.ShowMountedServersOnDesktop = lib.mkDefault false;
    finder.ShowRemovableMediaOnDesktop = lib.mkDefault false;

    # The WindowManager half, once for the ordinary desktop and once for Stage
    # Manager, which keeps its own copy of both toggles.
    WindowManager.StandardHideWidgets = lib.mkDefault true;
    WindowManager.StageManagerHideWidgets = lib.mkDefault true;
    WindowManager.StandardHideDesktopIcons = lib.mkDefault true;
    WindowManager.HideDesktop = lib.mkDefault true;
  };

  system.activationScripts.extraActivation.text = ''
    if ! /usr/bin/xcode-select -p &>/dev/null; then
      # softwareupdate --verbose narrates the download itself, so nothing is
      # printed here beyond what it says.
      touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
      PROD=$(softwareupdate -l 2>/dev/null | grep "\*.*Command Line" | tail -n 1 | sed 's/^[^C]* //')
      softwareupdate -i "$PROD" --verbose
      rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    fi
  '';

  # nix-darwin types this as an integer; NixOS uses a string. Hence per-platform.
  system.stateVersion = 7;
}
