# A Mac that runs unattended.
#
# The difference from a laptop is not what it looks like — the desktop settings
# in modules/darwin.nix apply here too, and the hardware is a MacBook Pro just
# like the other one — but that nobody is present. It has to stay awake with
# the lid shut while it is on the adapter, sleep like a laptop when it is not,
# and come back on its own.
{ lib, pkgs, ... }:

{
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
  environment.systemPackages = [ pkgs.google-chrome ];
  environment.variables.AGENT_BROWSER_EXECUTABLE_PATH = lib.getExe pkgs.google-chrome;

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
  power.restartAfterFreeze = true;

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
  system.activationScripts.postActivation.text = ''
    /usr/bin/pmset -c sleep 0 disksleep 0 displaysleep 10
    /usr/bin/pmset -b sleep 10 disksleep 10 displaysleep 2
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
