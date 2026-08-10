# A Mac that runs unattended.
#
# The difference from a laptop is not what it looks like — the desktop settings
# in modules/darwin.nix apply here too — but that nobody is present. It has to
# stay awake, and it has to come back on its own.
{ ... }:

{
  # A machine reached over the network cannot be asleep. The display may as
  # well idle off; nothing is attached to it.
  power.sleep.computer = "never";
  power.sleep.harddisk = "never";
  power.sleep.display = 10;

  # Come back without someone pressing the button.
  power.restartAfterPowerFailure = true;
  power.restartAfterFreeze = true;
}
