# A Mac that runs unattended.
#
# The difference from a laptop is not what it looks like — the desktop settings
# in modules/darwin.nix apply here too, and the hardware is a MacBook Pro just
# like the other one — but that nobody is present. It has to stay awake with
# the lid shut, and it has to come back on its own.
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

  # A machine reached over the network cannot be asleep. The display may as
  # well idle off; nothing is attached to it.
  power.sleep.computer = "never";
  power.sleep.harddisk = "never";
  power.sleep.display = 10;

  # Come back without someone pressing the button.
  power.restartAfterPowerFailure = true;
  power.restartAfterFreeze = true;

  # Clamshell: keep running with the lid shut.
  #
  # The three settings above are idle timers and do not cover this. Closing the
  # lid is a separate path into sleep — the lid switch asks IOPMrootDomain to
  # sleep directly, so a machine with `sleep 0` still goes down the moment the
  # lid meets the case. `caffeinate` does not help either: it takes a power
  # assertion, and assertions are what the idle timer consults, not the lid.
  #
  # Apple's own answer is clamshell mode proper, which is gated on an external
  # display plus power plus an input device. This machine has none of the three
  # and is reached over SSH, so that route is closed.
  #
  # What is left is SleepDisabled, a kernel flag that IOPMrootDomain treats as a
  # veto on sleep from any source, lid included. `pmset -a disablesleep 1` is
  # the only way to set it; there is no nix-darwin option, and `systemsetup`,
  # which is what the power module drives, does not expose it.
  #
  # It is deliberately global rather than conditioned on the power source, and
  # this is macOS's shape rather than a shortcut. Ordinary pmset settings live
  # in per-source dictionaries — `pmset -g cap` lists what each source accepts,
  # and disablesleep is in neither list — while SleepDisabled is a single key
  # under SystemPowerSettings in
  # /Library/Preferences/com.apple.PowerManagement.plist. `pmset -c disablesleep
  # 1` is accepted and writes exactly the same global key; the -c is cosmetic.
  # So "while on power" cannot be expressed here: on battery this machine will
  # not sleep either, and a long enough outage ends in a flat battery rather
  # than a suspend. Given that it lives on the adapter, and that
  # restartAfterPowerFailure above brings it back afterwards, that is the trade
  # this takes.
  #
  # The guard is not an optimisation — pmset would happily rewrite the same
  # value — but the rule that activation says nothing when there is nothing for
  # a person to do. `pmset -g` omits the line entirely while the flag is off, so
  # the empty case falls through to the write on its own.
  system.activationScripts.postActivation.text = ''
    if [ "$(/usr/bin/pmset -g | /usr/bin/awk '$1 == "SleepDisabled" { print $2 }')" != "1" ]; then
      /usr/bin/pmset -a disablesleep 1
    fi
  '';
}
