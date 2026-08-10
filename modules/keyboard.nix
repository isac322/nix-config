# Keyboard remapping and shortcuts for the Macs, imported from modules/darwin.nix.
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
{ config, lib, ... }:

let
  inherit (config.system) primaryUser;

  # UserKeyMapping values are 64-bit: the high 32 bits are the HID usage page,
  # the low 32 bits the usage. Keyboard/keypad is page 0x07; the fn key lives on
  # Apple's vendor-defined top case page 0xFF instead.
  keyboardPage = usage: 30064771072 + usage; # 0x700000000 + usage

  keys = {
    leftControl = keyboardPage 224; # 0xE0
    leftOption = keyboardPage 226; # 0xE2
    leftCommand = keyboardPage 227; # 0xE3
    rightCommand = keyboardPage 231; # 0xE7
    f18 = keyboardPage 109; # 0x6D
    fn = 1095216660483; # 0xFF00000003
  };

  remap = src: dst: {
    HIDKeyboardModifierMappingSrc = src;
    HIDKeyboardModifierMappingDst = dst;
  };

  # Cocoa modifier masks, as stored in com.apple.symbolichotkeys.
  shift = 131072;
  control = 262144;
  option = 524288;
  command = 1048576;

  # Apple virtual key codes, which are not the HID usages above.
  vkSpace = 49;
  vkF18 = 79;

  # Symbolic hotkey ids. `defaults read com.apple.symbolichotkeys` lists them.
  hotkeyIds = {
    previousInputSource = 60; # 이전 입력 소스 선택
    spotlight = 64;
  };

  # `-dict-add` rather than a plain write, and therefore an activation script
  # rather than `system.defaults.CustomUserPreferences`: nix-darwin writes a
  # whole key at once, and AppleSymbolicHotKeys is one dictionary holding every
  # shortcut on the system. Writing it wholesale would drop the twenty-odd
  # entries not mentioned here.
  #
  # parameters is (ASCII character, virtual key code, modifier mask), where
  # 65535 means the key has no ASCII equivalent.
  setHotkey = id: params: ''
    asUser /usr/bin/defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add ${toString id} "
      <dict>
        <key>enabled</key><true/>
        <key>value</key>
        <dict>
          <key>type</key><string>standard</string>
          <key>parameters</key>
          <array>${lib.concatMapStrings (p: "<integer>${toString p}</integer>") params}</array>
        </dict>
      </dict>"
  '';
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
  #
  # Right command becomes F18 rather than lang1. lang1 is the usage Apple's own
  # Korean keyboards send for 한/영, and hidutil accepts it, but macOS does not
  # act on it from a remapped key. The recipe that does work is to send an
  # otherwise unused key and bind it to the input-source shortcut below.
  system.keyboard.userKeyMapping = [
    (remap keys.fn keys.leftCommand)
    (remap keys.leftCommand keys.leftOption)
    (remap keys.leftOption keys.leftControl)
    (remap keys.leftControl keys.fn)
    (remap keys.rightCommand keys.f18)
  ];

  system.activationScripts.postActivation.text = ''
    asUser() {
      launchctl asuser "$(id -u -- ${primaryUser})" sudo --user=${primaryUser} -- "$@"
    }

    echo "configuring keyboard shortcuts..." >&2

    # 한/영. Right command sends F18 (see userKeyMapping), and F18 selects the
    # previous input source, which with one Latin and one Korean source is a
    # straight toggle.
    ${setHotkey hotkeyIds.previousInputSource [
      65535
      vkF18
      0
    ]}

    ${setHotkey hotkeyIds.spotlight [
      65535
      vkSpace
      option
    ]}

    # nix-darwin writes the `system.defaults` plists but never asks macOS to
    # re-read them, so keyboard and trackpad changes would sit in the preference
    # files until the next login. This is the same refresh System Settings
    # itself performs, run as the user because the defaults are in the user
    # domain. Shortcut changes are read by the WindowServer and may still want
    # a log out.
    echo "reloading system settings..." >&2
    asUser /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
  '';
}
