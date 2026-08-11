# A Mac that runs unattended.
#
# The difference from a laptop is not what it looks like — the desktop settings
# in modules/darwin.nix apply here too — but that nobody is present. It has to
# stay awake, and it has to come back on its own.
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
  # which `ssh mini agent-browser …` is neither.
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
}
