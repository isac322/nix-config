# A Mac someone sits in front of.
#
# How the Dock behaves, and trackpad, keyboard, Finder and the rest, are the
# same on every Mac and live in modules/darwin.nix; what makes a laptop
# different is only that it runs desktop applications — including which of them
# the Dock holds, since that list is mostly the casks below. The user-level half
# is home/roles/darwin-laptop.nix.
{
  config,
  hostname,
  inputs,
  lib,
  ...
}:

let
  inherit (config.system) primaryUser;

  # Where a nixpkgs .app lands on darwin under home-manager. A stable path that
  # points into the store, which is the reason to name it rather than a store
  # path: this one survives a rebuild, and a store path in the Dock would not.
  homeApps = "${config.users.users.${primaryUser}.home}/Applications/Home Manager Apps";
in
{
  # Only the machines that actually run Firefox need this overlay, and it is
  # not harmless elsewhere: besides firefox-bin it defines librewolf,
  # floorp-bin and zen-browser-bin, shadowing the nixpkgs packages of those
  # names for anything else that might want them.
  nixpkgs.overlays = [ inputs.nixpkgs-firefox-darwin.overlay ];

  # Run Camofox on the desktop session already in front of the user. The local
  # API needs neither the unattended remote console nor its WireGuard tunnel.
  local.camofox = {
    enable = true;
    remoteConsole = false;
  };

  # The two App Store only applications (0016). Both are role-level rather than
  # shared, for different reasons: KakaoTalk is a window and the server Mac has
  # nobody to look at it, and WireGuard is the *app*, which the server Mac
  # deliberately does not use — it runs the tunnel as a root daemon instead,
  # because the app cannot come up without a console login. See
  # modules/wireguard.nix.
  local.masApps.kakaotalk = {
    name = "KakaoTalk";
    path = "/Applications/KakaoTalk.app";
    appStoreId = 869223134;
    reason = "Nothing else installed here replaces it.";
  };

  local.masApps.wireguard = {
    name = "WireGuard";
    path = "/Applications/WireGuard.app";
    appStoreId = 1451685025;
    reason = "The tunnel is how this machine reaches the others, including the server Mac's Orca runtime.";
  };

  # Interactive GUI applications come from Homebrew. Most have no maintained
  # Darwin package in nixpkgs, and Homebrew keeps their app bundles current.
  # Both Macs share the stablyai/orca cask in modules/darwin.nix.
  #
  # Vorta's archive mount needs both macFUSE and the Borg build linked against
  # it. The macFUSE cask installs a signed pkg and kernel extension, so its
  # first installation still needs interactive approval and a reboot; keeping
  # it here makes subsequent upgrades declarative.
  homebrew.taps = [
    "borgbackup/tap"
  ];

  homebrew.brews = [ "borgbackup-fuse" ];

  homebrew.casks = [
    "1password" # the desktop app; the `op` CLI is in home/darwin.nix
    "ente-auth"
    "ghostty" # nixpkgs builds it for Linux only; config is in home/roles/
    "intellij-idea" # Ultimate; the community edition is intellij-idea-ce
    "kde-connect"
    "linear"
    "macfuse"
    "notion"
    "slack"
    # `auto_updates true` in the cask, so Spotify replaces itself in place and
    # onActivation.upgrade rarely has anything to do — which is fine, and the
    # reason the version here is never what is running.
    "spotify"
    "telegram" # the native macOS client, not telegram-desktop
    "vorta"
    "zoom"
  ];

  # The generated Brewfile installs formulae before casks, but
  # borgbackup-fuse cannot be built until the macFUSE pkg has installed its
  # headers. Run this fragment immediately before nix-darwin's Homebrew bundle:
  # it verifies the Apple silicon boot policy, bootstraps the declared cask
  # when needed, and refuses to continue until macOS has loaded the VFS kext.
  # Nothing changes the boot policy automatically; that requires the owner in
  # Recovery and should never be scripted from a normal boot.
  system.activationScripts.homebrew.text = lib.mkOrder 750 ''
    macfuseSwitchCommand='sudo darwin-rebuild switch --flake /etc/nix-darwin#${hostname}'

    printMacfuseRecoveryInstructions() {
      cat >&2 <<EOF

      macFUSE VFS cannot be enabled while third-party kernel extensions are
      disabled in this Mac's boot policy.

      1. Shut down the Mac.
      2. Hold the power button until "Loading startup options" appears.
      3. Open Options, then choose Utilities > Startup Security Utility.
      4. Select this macOS installation and open Security Policy.
      5. Select Reduced Security.
      6. Enable "Allow user management of kernel extensions from identified developers."
      7. Restart macOS and run:

         $macfuseSwitchCommand

    EOF
    }

    printMacfuseApprovalInstructions() {
      cat >&2 <<EOF

      macFUSE is installed, but its VFS kernel extension is not loaded.

      1. Open System Settings > Privacy & Security.
      2. Allow the blocked system software from macFUSE.
      3. Restart the Mac.
      4. Run:

         $macfuseSwitchCommand

    EOF
    }

    if [ "$(/usr/bin/uname -m)" = arm64 ]; then
      if ! volumeGroupID=$(
        /usr/sbin/diskutil info -plist / |
          /usr/bin/plutil -extract APFSVolumeGroupID raw -o - -
      ); then
        echo "error: could not determine the current APFS volume group for the macFUSE boot-policy check" >&2
        exit 1
      fi

      if [ -z "$volumeGroupID" ]; then
        echo "error: the current APFS volume group is empty; refusing to skip the macFUSE boot-policy check" >&2
        exit 1
      fi

      if ! bootPolicy=$(/usr/bin/bputil -v "$volumeGroupID" -d 2>&1); then
        echo "error: could not read the Apple silicon boot policy with bputil" >&2
        echo "$bootPolicy" >&2
        exit 1
      fi

      if ! printf '%s\n' "$bootPolicy" |
        /usr/bin/grep -Eq '\(smb2\):[[:space:]]+1[[:space:]]*$'; then
        printMacfuseRecoveryInstructions
        exit 1
      fi
    fi

    brewPath=${lib.escapeShellArg "${config.homebrew.prefix}/bin"}
    runBrewAsUser() {
      PATH="$brewPath:$PATH" /usr/bin/sudo \
        --preserve-env=PATH \
        --user=${lib.escapeShellArg config.system.primaryUser} \
        --set-home \
        /usr/bin/env brew "$@"
    }

    if ! runBrewAsUser list --cask macfuse > /dev/null 2>&1; then
      echo "installing the declaratively configured macFUSE cask before borgbackup-fuse..." >&2
      runBrewAsUser install --cask macfuse
    fi

    macfuseKextLoaded() {
      /usr/bin/kmutil showloaded --list-only 2>/dev/null |
        /usr/bin/grep 'io\.macfuse\.filesystems\.macfuse' > /dev/null
    }

    if ! macfuseKextLoaded; then
      macosMajor=$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f1)
      macfuseKext="/Library/Filesystems/macfuse.fs/Contents/Extensions/$macosMajor/macfuse.kext"

      if [ ! -d "$macfuseKext" ]; then
        echo "error: macFUSE does not provide a kernel extension for macOS $macosMajor at:" >&2
        echo "  $macfuseKext" >&2
        echo "Upgrade the declared macFUSE cask, then rerun:" >&2
        echo "  $macfuseSwitchCommand" >&2
        exit 1
      fi

      # This also makes macOS present the Allow button after a first install.
      # It requests a load only; policy and user approval stay under macOS
      # control.
      /usr/bin/kmutil load -p "$macfuseKext" > /dev/null 2>&1 || true

      if ! macfuseKextLoaded; then
        printMacfuseApprovalInstructions
        exit 1
      fi
    fi
  '';

  # The Dock, left to right. Setting this makes the list declarative in both
  # directions: an app dragged in by hand is gone at the next activation, and
  # an app removed from here leaves the Dock. It says nothing about recents,
  # which are on — they occupy their own section to the right and do not
  # disturb these positions.
  #
  # A tile is a path and only a path — nix-darwin writes it verbatim into
  # com.apple.dock. A path that no longer resolves is not a build error; it is
  # a question mark in the Dock, which is why the /Applications entries are
  # worth reading against the cask list above when either changes.
  #
  # Three sources, and which one a tile comes from decides what breaks it:
  #   /System/Applications  Apple's own, present on every Mac.
  #   /Applications         The casks above, put there by Homebrew.
  #   homeApps              home-manager's per-user link farm — see the let
  #                         binding at the top of this file.
  #
  # Note zoom.us.app: the cask is `zoom`, the bundle is not.
  system.defaults.dock.persistent-apps = [
    { app = "/System/Applications/Apps.app"; }
    { app = "/System/Applications/Calendar.app"; }
    { app = "${homeApps}/Firefox.app"; }
    { app = "/Applications/Orca.app"; }
    { app = "/Applications/Ghostty.app"; }
    { app = "/Applications/Slack.app"; }
    { app = "/Applications/zoom.us.app"; }
    { app = "/System/Applications/System Settings.app"; }
  ];

  # Laptop-only in the role sense, not the hardware sense — the server Mac is a
  # MacBook Pro and has the same sensor. It is run headless with the lid shut
  # and reached over SSH, where pam_tid has nothing to prompt on. This does not
  # replace the sudo timestamp in modules/darwin.nix — it decides what happens
  # when a prompt does appear, and that one decides how often one appears.
  #
  # nix-darwin renders /etc/pam.d/sudo_local, the file Apple added in macOS 14
  # precisely so local changes survive a system update; /etc/pam.d/sudo itself
  # is on the sealed volume and includes it.
  #
  # `reattach` (pam_reattach) comes along because pam_tid can only draw its
  # prompt from inside the user's bootstrap session. A shell under tmux is
  # outside it, and so is the brew step, which activation reaches through
  # `sudo --user=bhyoo` from a root process. It is an `auth optional` line, so
  # it costs nothing where it is not needed.
  security.pam.services.sudo_local = {
    touchIdAuth = true;
    reattach = true;
  };

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
