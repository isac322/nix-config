# Shared by every Mac. Host-specific bits live in hosts/<name>/default.nix.
{ config, lib, ... }:

let
  caches = import ../lib/caches.nix;
  sshAudit = import ../lib/ssh-audit.nix;

  # sshd_config takes one directive per line, values comma-joined. Integers pass
  # through as themselves. NixOS renders this for us; macOS does not, because
  # nothing here goes through a NixOS-style `settings` option — see below.
  sshdConfigText = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: value:
      "${name} ${if lib.isList value then lib.concatStringsSep "," value else toString value}"
    ) sshAudit.sshdSettings
  );
in
{
  imports = [
    ./keyboard.nix
    ./finder.nix
    ./appearance.nix
    ./warp.nix

    # Options only, no configuration. Every Mac can declare where its Orca
    # runtime is reached; only the server role acts on it.
    ./orca.nix
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

  # There is deliberately no `environment.etc."nix/nix.custom.conf"
  # .knownSha256Hashes` here. The determinate module wants to replace the file
  # the installer wrote, and nix-darwin refuses to overwrite an /etc file whose
  # contents it does not recognise — so a whitelist would have to name every
  # installer variant, and be extended for each new one. The bootstrap moves the
  # file aside instead (README, 맥 5번), which leaves nothing to recognise and
  # nothing to maintain. Nothing is lost either way: the old file is renamed,
  # not deleted, and this module declares its contents anyway.

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

    # Stably's Orca ships from its own tap rather than homebrew-cask, so the tap
    # has to be declared alongside it. nix-homebrew leaves taps mutable by
    # default, which is what lets this work without pinning the tap as a flake
    # input.
    taps = [ "stablyai/orca" ];

    casks = [
      # Karabiner-Elements deliberately absent: it cannot be brought up without
      # a console session approving its driver extension and Input Monitoring.
      # The remapping it would have done is in modules/keyboard.nix via hidutil.

      # The one GUI application both Macs get. Orca drives coding agents in
      # parallel, each in its own git worktree, and the `orca` CLI that comes
      # in the bundle is the half that matters on a headless machine — the
      # laptop additionally keeps it in the Dock, in the laptop role.
      #
      # The tap prefix is not optional. Plain `orca` in homebrew-cask is
      # plotly's chart renderer, an unrelated package that is deprecated for
      # failing Gatekeeper.
      "stablyai/orca/orca"
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

  # The crypto half of the sshd configuration, on every Mac. Whether sshd
  # actually answers is a separate question decided per role — the laptop leaves
  # `services.openssh.enable` at null, which hands the daemon back to macOS.
  # These two settings are about what it does when it is on, no matter who
  # turned it on, and a laptop whose Remote Login someone flips in System
  # Settings should not be weaker than the server for it.
  #
  # Dropping ECDSA from the default rsa/ecdsa/ed25519 triple is what stops it
  # being offered. nix-darwin writes one `HostKey` line per entry into
  # 099-host-keys.conf and generates any key that is missing — but only missing
  # ones, never a replacement for a key already there, which is why the RSA size
  # below is a message rather than a regeneration.
  services.openssh.hostKeys = lib.attrValues sshAudit.hostKeys;

  # And this is why the algorithm lists are not in `services.openssh.extraConfig`
  # where they visibly belong.
  #
  # sshd_config's first line is `Include /etc/ssh/sshd_config.d/*`, the glob
  # expands in lexical order, and sshd keeps the **first** value it sees for a
  # keyword. Apple ships 100-macos.conf, which includes /etc/ssh/crypto.conf,
  # which sets Ciphers, KexAlgorithms and MACs with a leading `^` — prepend to
  # the defaults. nix-darwin writes `extraConfig` to 100-nix-darwin.conf, and
  # "100-macos" sorts before "100-nix-darwin".
  #
  # So the obvious placement loses, silently and only for the directives that
  # matter. Written as extraConfig, `sshd -T` reports kexalgorithms starting
  # with ecdh-sha2-nistp256 and running through curve25519 and two more NIST
  # curves — the exact opposite of the intent, with the file looking correct.
  # The identical text under this name yields `kexalgorithms
  # mlkem768x25519-sha256` and nothing else.
  #
  # 010- rather than 000- leaves room to wedge something in front, and sits
  # clear of 099-host-keys.conf, which nix-darwin owns.
  environment.etc."ssh/sshd_config.d/010-ssh-audit-hardening.conf".text = sshdConfigText + "\n";

  # nix-darwin generates a missing host key but never regenerates an existing
  # one, which is the right call — replacing a host key breaks every client's
  # known_hosts and no switch should do that on its own. The consequence is that
  # a machine that made its RSA key before this profile existed keeps whatever
  # ssh-keygen defaulted to at the time, and macOS's default is 3072. That
  # passes RequiredRSASize and fails the ssh-audit policy, which checks the size
  # of the key actually presented.
  #
  # Only said where sshd is actually on: on the laptop this is nobody's problem
  # until they turn Remote Login on, and at that point the switch after it says
  # so. `enable` is `nullOr bool`, so the comparison has to be against true
  # rather than a truth test.
  system.activationScripts.postActivation.text =
    lib.optionalString (config.services.openssh.enable == true)
      ''
        if [ -f /etc/ssh/ssh_host_rsa_key.pub ]; then
          rsaBits=$(/usr/bin/ssh-keygen -l -f /etc/ssh/ssh_host_rsa_key.pub 2>/dev/null | /usr/bin/awk '{print $1}')
          if [ -n "$rsaBits" ] && [ "$rsaBits" -lt 4096 ]; then
            echo "" >&2
            echo "  The RSA host key is $rsaBits bits, and the hardening profile wants" >&2
            echo "  4096. It predates the profile, and a switch will not replace a host" >&2
            echo "  key that already exists — that is a decision with consequences for" >&2
            echo "  every client that has ever connected." >&2
            echo "" >&2
            echo "  Deleting it and switching again regenerates it at 4096:" >&2
            echo "" >&2
            echo "    sudo rm /etc/ssh/ssh_host_rsa_key /etc/ssh/ssh_host_rsa_key.pub" >&2
            echo "    sudo darwin-rebuild switch --flake /etc/nix-darwin" >&2
            echo "" >&2
            echo "  Every client that trusted the old key will refuse to connect until" >&2
            echo "  the stale line is out of its known_hosts. Do it from the console, or" >&2
            echo "  from a session you can afford to lose." >&2
            echo "" >&2
            echo "  The ED25519 key is preferred over RSA and is unaffected, so an" >&2
            echo "  ordinary OpenSSH client will not notice either way. This is about" >&2
            echo "  what the machine still offers, not what it uses." >&2
            echo "" >&2
          fi
        fi
      '';

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
