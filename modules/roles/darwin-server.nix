# A Mac that runs unattended.
#
# The difference from a laptop is not what it looks like — the desktop settings
# in modules/darwin.nix apply here too, and the hardware is a MacBook Pro just
# like the other one — but that nobody is present. It has to stay awake with
# the lid shut while it is on the adapter, sleep like a laptop when it is not,
# and come back on its own.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  # The part `services.openssh.enable = true` turns out not to guarantee.
  #
  # nix-darwin bootstraps the launchd job only when
  # `systemsetup -getremotelogin` reads exactly "Off". On this machine it read
  # "On" while nothing held port 22: the job was registered in the system domain
  # but disabled, so its socket was never bound. That combination is invisible
  # to the guard — it is not "Off", so no switch ever ran the bootstrap, and
  # every switch quietly did nothing while Remote Login looked on.
  #
  # `launchctl enable` alone was what fixed it. `bootstrap` answered "Bootstrap
  # failed: 5: Input/output error", which is launchd for "already loaded".
  #
  # So ask the port rather than asking systemsetup. Nothing listening on 22 is
  # the actual symptom, it is what a person would check, and it is true exactly
  # when there is something to repair — which keeps this silent and idempotent
  # on a machine that is already fine. Testing for a running sshd would not
  # work: the daemon is socket-activated, launchd holds 22 on its behalf, and
  # `state = not running` is its normal resting state.
  sshdEnsureListening = ''
    if ! /usr/sbin/lsof -nP -iTCP:22 -sTCP:LISTEN >/dev/null 2>&1; then
      /bin/launchctl enable system/com.openssh.sshd

      # Already-loaded is the expected answer whenever `enable` was the missing
      # half, and it is not a failure. Anything else is, and says so rather than
      # aborting a switch that has otherwise finished.
      if ! bootstrapOut=$(/bin/launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist 2>&1); then
        case "$bootstrapOut" in
          *"Input/output error"* | *already*) ;;
          *)
            echo "" >&2
            echo "  sshd is not listening on 22 and could not be started:" >&2
            echo "    $bootstrapOut" >&2
            echo "" >&2
            echo "  This machine is reached over SSH, so that is worth looking at" >&2
            echo "  from its own console before the session you are in ends." >&2
            echo "" >&2
            ;;
        esac
      fi
    fi
  '';

in

{
  # The way in. Everything else in this file assumes a machine nobody is sitting
  # at, and this is what makes that true rather than merely unattended.
  #
  # nix-darwin does not touch `systemsetup -setremotelogin`, which needs Full
  # Disk Access and so cannot be driven from a switch. It enables the launchd
  # job directly instead — `launchctl enable system/com.openssh.sshd` and
  # `launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist` — which
  # is the same daemon System Settings' Remote Login toggle starts. Apple's sshd
  # is the one that runs; this decides whether it is loaded and hands it a
  # fragment in /etc/ssh/sshd_config.d.
  #
  # Not in modules/darwin.nix. The laptop should not answer on 22 — it is on
  # networks this machine never sees — and leaving `enable` unset there is not
  # the same as setting it false: null means "leave it to macOS", which is what
  # a machine whose Remote Login is a personal decision wants.
  services.openssh = {
    enable = true;

    # The same posture as the NixOS server (modules/nixos.nix): keys only, and
    # not as root. `sudo` is how anything privileged happens here, which keeps
    # the audit trail attached to a person.
    #
    # All three matter, because macOS leaves all three at the upstream default —
    # /etc/ssh/sshd_config carries them commented out, so it is
    # `prohibit-password`, `yes` and `yes` that apply until something says
    # otherwise.
    #
    # KbdInteractiveAuthentication is the one that is easy to miss. macOS sets
    # `UsePAM yes`, and PAM offers password authentication a second time through
    # keyboard-interactive, so turning off PasswordAuthentication alone leaves a
    # password prompt reachable.
    #
    # These land in 100-nix-darwin.conf, which is read after Apple's
    # 100-macos.conf — and for these three that is harmless, because
    # 100-macos.conf sets only UsePAM, AcceptEnv and an include of crypto.conf.
    # It is not harmless for anything crypto.conf names, which is why the
    # algorithm lists are not here but in a 010- file written directly from
    # modules/darwin.nix. That file explains the ordering; this one only has to
    # stay clear of it.
    #
    # Only the authentication policy is role-specific. What the daemon would
    # speak if it were listening is not — that is the same answer on any Mac,
    # and applying it to a machine whose sshd is off costs nothing.
    extraConfig = ''
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      PermitRootLogin no
    '';
  };

  # A browser for agent-browser (home/common.nix) to drive. The laptop gets
  # this from the google-chrome cask, which is the right answer where someone
  # also browses with it; here nothing does, so it comes from nixpkgs — pinned
  # with the rest of the closure, and installed without a `pkg` artifact that
  # would want root during activation.
  #
  # nixpkgs unpacks Google's DMG into $out/Applications rather than
  # /Applications, and agent-browser's auto-detection is four hardcoded
  # absolute paths (Google Chrome, Chrome Canary, Chromium, Brave, all under
  # /Applications) plus the Playwright cache. None of them is a store path, so
  # the browser has to be named explicitly.
  #
  # This is environment.variables, not home.sessionVariables, because the
  # machine is driven over SSH: /etc/zshenv is read by every zsh, while the
  # home-manager session file is only sourced by login and interactive shells,
  # which `ssh bhyoo-macbook-pro agent-browser …` is neither.
  # Deliberately *not* in `environment.systemPackages`, which is the one thing
  # that would put a copy in /Applications/Nix Apps — and that directory is what
  # makes this machine unswitchable over SSH.
  #
  # nix-darwin's checks touch a file inside every bundle under /Applications/Nix
  # Apps to prove it may modify them, and an SSH session has no such permission
  # unless "Allow full disk access for remote users" is granted by hand in
  # System Settings. Upstream's own comment says even granting it "will still
  # fail sometimes". With no bundle there the loop has nothing to test and the
  # check passes, so a headless machine stays switchable from anywhere.
  #
  # Nothing is lost. agent-browser never looks on PATH or in /Applications — it
  # is handed the absolute store path below, which is the whole point of
  # docs/decisions/0024-chrome-for-agent-browser-on-the-server.md. And the
  # package stays in the closure because that path is written into /etc/zshenv,
  # which Nix scans for store references.
  environment.variables.AGENT_BROWSER_EXECUTABLE_PATH = lib.getExe pkgs.google-chrome;

  # Log in without someone being there to do it.
  #
  # For exactly one thing: the Orca runtime is an Electron application, so it
  # needs an Aqua session and nothing else will give it one (0028). Everything
  # else this machine runs is a root daemon on purpose — sshd, WireGuard, the
  # keyboard mapping — and a daemon needs none of this. That is the general
  # rule; this is the exception to it, not the pattern.
  #
  # What it costs, and the one file that has to exist for it to work, is in
  # modules/auto-login.nix.
  local.autoLogin.enable = true;

  # The tunnel this machine is reached through, as a root daemon rather than the
  # App Store client — see
  # docs/decisions/0029-wireguard-as-a-daemon-on-the-server-mac.md. Which
  # tunnels exist is decided by which configuration files are on the machine,
  # not by anything here.
  local.wireguard.enable = true;

  # The Orca runtime. The address it advertises is not written here — it is read
  # off the tunnel above at run time, because that is where the answer is
  # already decided (0028).
  local.orca.enable = true;

  # The headful browser API and the view of its automatic Aqua session. Both
  # endpoints learn their bind address from WireGuard at run time; there is no
  # ordinary-interface fallback written here or in modules/camofox.nix.
  #
  # Keep Screen Sharing as an independent migration console through the first
  # open-source VNC switch. Change this flag only after macVNC capture and input
  # have both been verified through noVNC.
  local.camofox = {
    enable = true;
    retireScreenSharing = false;
  };

  # Come back without someone pressing the button.
  #
  # `power.restartAfterPowerFailure` is deliberately absent. Apple Silicon
  # notebooks do not have the capability — `pmset -g cap` lists no
  # `autorestart`, and `systemsetup -getRestartPowerFailure` answers "Not
  # supported". nix-darwin checks for exactly that before activating and exits
  # 2, so setting it does not merely no-op: it aborts every switch on this
  # machine. Nothing is lost by dropping it. A notebook does not see a power
  # failure — the adapter going away is a source change, which the daemon below
  # handles, and the machine only powers off once the battery is flat. Attaching
  # the adapter to a flat Mac powers it on by itself.
  #
  # `restartAfterFreeze` stays. It is not the same case: `strings
  # /usr/sbin/systemsetup` carries a "Not supported on this machine" line for
  # wake-on-modem, wake-on-network, restart-after-power-failure and the power
  # button, and none for freeze — `-getRestartFreeze` can only answer On or Off.
  # It cannot abort a switch either. nix-darwin greps that string rather than
  # reading `$?` because systemsetup exits 0 even when it refuses, so an
  # unsupported setting can never trip the activation script's `set -e`.
  power.restartAfterFreeze = true;

  # Camofox renders on a dedicated virtual display, but its windows still
  # belong to the logged-in Aqua session. A screen saver or login-window lock
  # would replace those windows even though the browser and VNC processes stay
  # healthy. Keep the unattended session unlocked and its displays awake while
  # the machine is acting as a server.
  system.defaults.screensaver = {
    askForPassword = false;
    askForPasswordDelay = 0;
  };
  system.defaults.CustomUserPreferences = {
    "com.apple.screensaver".idleTime = 0;
    "com.apple.loginwindow".DisableScreenLockImmediate = true;
  };

  # Idle timers, written per power source.
  #
  # nix-darwin's `power.sleep.*` options are deliberately not used here. They
  # drive `systemsetup -setComputerSleep` and friends, which take one value and
  # have no power-source dimension at all — and the whole point below is that
  # the adapter and the battery have to differ. pmset is the interface that
  # does: `-c` is the adapter's dictionary, `-b` the battery's.
  #
  # On the adapter it is a server and never sleeps. On battery it behaves like
  # a laptop, because on battery that is what it is — see the daemon below.
  # `ttyskeepawake` is on by default and counts an active SSH session as
  # activity, so the battery timer does not cut a session short.
  # Two unrelated things share this block because `postActivation.text` can only
  # be assigned once per module, and both belong to this file.
  system.activationScripts.postActivation.text = ''
    /usr/bin/pmset -c sleep 0 disksleep 0 displaysleep 0
    /usr/bin/pmset -b sleep 10 disksleep 10 displaysleep 2

    ${sshdEnsureListening}
  '';

  # Clamshell — keep running with the lid shut, but only while on power.
  #
  # The timers above do not cover this. Closing the lid is a separate path into
  # sleep: the lid switch asks IOPMrootDomain to sleep directly, so a machine
  # with `sleep 0` still goes down the moment the lid meets the case.
  # `caffeinate` does not help either — it takes a power assertion, and
  # assertions are what the idle timer consults, not the lid.
  #
  # Apple's own clamshell mode is gated on an external display plus power plus
  # an input device. This machine has none of the three and is reached over
  # SSH, so that route is closed.
  #
  # What is left is SleepDisabled, a kernel flag IOPMrootDomain treats as a veto
  # on sleep from any source, lid included. `pmset -a disablesleep 1` is the
  # only way to set it, and there is no nix-darwin option for it.
  #
  # It is also the one power setting with no per-source form. The others live in
  # the adapter and battery dictionaries — `pmset -g cap` lists what each source
  # accepts, and disablesleep is in neither, nor in pmset's own man page —
  # while SleepDisabled is a single key under SystemPowerSettings in
  # /Library/Preferences/com.apple.PowerManagement.plist. `pmset -c disablesleep
  # 1` is accepted and writes exactly that global key; the -c is cosmetic.
  #
  # So the condition cannot be declared, and is watched for instead. This is a
  # daemon rather than an activation script because the power source changes
  # long after activation has finished, and it is what the third-party tools
  # for this do too.
  #
  # `pmset -g pslog` is an event stream — it prints the current source at
  # startup and then one line per change, and it line-buffers through a pipe, so
  # a read loop reacts within a second and there is nothing to poll. The other
  # `Now drawing from` case is the initial one, which sets the flag and stops
  # there: sleeping a machine the moment this daemon starts would be wrong, and
  # would land in the middle of the switch that installed it.
  #
  # The sleepnow is what makes losing power act on a lid that is already shut.
  # Clearing SleepDisabled only removes the veto; it does not re-deliver the lid
  # event that the veto swallowed, so without this the machine would sit awake
  # on battery until an idle timer got to it. AppleClamshellState is
  # IOPMrootDomain's own view of the lid.
  #
  # One thing this cannot do: once the machine is asleep, the daemon is asleep
  # with it, so it is macOS that decides whether reconnecting power wakes it.
  # `acwake` is the setting that used to govern that and it is inert on Apple
  # Silicon — absent from `pmset -g cap`, and writing it changes nothing.
  # Behaviour is wired into the hardware and differs by model. If this machine
  # turns out not to wake on the adapter, an outage that outlasts the battery
  # timer needs someone to open the lid.
  launchd.daemons.clamshell-on-power = {
    serviceConfig = {
      RunAtLoad = true;
      KeepAlive = true;
      # Empty in the normal case. A daemon that fails silently and leaves the
      # machine asleep behind a shut lid is the failure worth being able to see.
      StandardErrorPath = "/var/log/clamshell-on-power.err.log";
    };
    script = ''
      set -u

      # Off for the startup call, on for every change after it.
      sleep_if_lid_shut=0

      apply() {
        case "$1" in
          *"'AC Power'"*) want=1 ;;
          *) want=0 ;;
        esac

        # `pmset -g` omits the line entirely while the flag is off, so the empty
        # case has to read as 0 rather than as "unknown".
        have=$(/usr/bin/pmset -g | /usr/bin/awk '$1 == "SleepDisabled" { print $2 }')
        [ -n "$have" ] || have=0
        [ "$have" = "$want" ] || /usr/bin/pmset -a disablesleep "$want"

        [ "$sleep_if_lid_shut" = 1 ] || return 0
        [ "$want" = 0 ] || return 0
        /usr/sbin/ioreg -r -k AppleClamshellState -d 4 |
          /usr/bin/grep -q '"AppleClamshellState" = Yes' || return 0
        /usr/bin/pmset sleepnow
      }

      apply "$(/usr/bin/pmset -g ps | /usr/bin/head -n 1)"
      sleep_if_lid_shut=1

      /usr/bin/pmset -g pslog | while IFS= read -r line; do
        case "$line" in
          "Now drawing from "*) apply "$line" ;;
        esac
      done
    '';
  };
}
