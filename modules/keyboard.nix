# Keyboard remapping for the Macs, imported from modules/darwin.nix.
#
# This uses hidutil (nix-darwin's `system.keyboard`) rather than
# Karabiner-Elements, because Karabiner cannot be set up without a human at the
# console: its DriverKit extension has to be approved in System Settings and its
# grabber needs an Input Monitoring grant, and the TCC database that records
# that grant is SIP-protected — no CLI, no defaults key, nothing Nix can write.
# Only an MDM profile can pre-authorise it.
#
# hidutil needs none of that. It remaps inside IOKit as root, applies to every
# attached keyboard including the built-in one, and is re-applied on every boot
# by the org.nixos.activate-system LaunchDaemon, so it survives reboots without
# a login item. The cost is that it can only do 1:1 key remapping — no
# conditional or chorded rules. Nothing here needs more than that.
{ config, ... }:

let
  # UserKeyMapping values are 64-bit: the high 32 bits are the HID usage page,
  # the low 32 bits the usage. Keyboard/keypad is page 0x07; the fn key lives on
  # Apple's vendor-defined top case page 0xFF instead.
  keyboardPage = usage: 30064771072 + usage; # 0x700000000 + usage

  keys = {
    leftControl = keyboardPage 224; # 0xE0
    leftOption = keyboardPage 226; # 0xE2
    leftCommand = keyboardPage 227; # 0xE3
    rightCommand = keyboardPage 231; # 0xE7
    lang1 = keyboardPage 144; # 0x90 — 한/영, what Apple's Korean keyboards send
    fn = 1095216660483; # 0xFF00000003
  };

  remap = src: dst: {
    HIDKeyboardModifierMappingSrc = src;
    HIDKeyboardModifierMappingDst = dst;
  };
in
{
  system.keyboard.enableKeyMapping = true;

  # A four-way rotation, plus the right command key as the Korean toggle:
  #
  #   fn -> left command -> left option -> left control -> fn
  #
  # hidutil reads every Src against the original hardware key, so writing a
  # cycle is well defined; the entries are not applied in sequence.
  #
  # Consequence worth knowing: with fn now acting as command, the media
  # functions of F1-F12 move to the physical left control key, which is what
  # sends fn after the rotation. That pairs with the fnState default in
  # modules/darwin.nix, which makes F1-F12 function keys to begin with.
  system.keyboard.userKeyMapping = [
    (remap keys.fn keys.leftCommand)
    (remap keys.leftCommand keys.leftOption)
    (remap keys.leftOption keys.leftControl)
    (remap keys.leftControl keys.fn)
    (remap keys.rightCommand keys.lang1)
  ];

  # nix-darwin writes the `system.defaults` plists but never asks macOS to
  # re-read them, so keyboard and trackpad changes would sit in the preference
  # files until the next login. This is the same refresh System Settings itself
  # performs, run as the user because the defaults are in the user domain.
  system.activationScripts.postActivation.text = ''
    echo "reloading system settings..." >&2
    launchctl asuser "$(id -u -- ${config.system.primaryUser})" \
      sudo --user=${config.system.primaryUser} -- \
      /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
  '';
}
