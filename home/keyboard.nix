# Keyboard behaviour on the Macs: the Karabiner-Elements profile, and the Cocoa
# key binding that fixes ₩ on the key below Esc.
#
# Karabiner itself is installed as a Homebrew cask from modules/darwin.nix
# rather than from nixpkgs: it ships a DriverKit system extension and
# privileged daemons that need Input Monitoring permission, and nix-darwin's
# services.karabiner-elements runs those out of /nix/store, where the path
# changes on every version bump and the permission has to be granted again.
# The cask also tracks upstream (16.1.0) while nixpkgs sits on 15.7.0.
{ lib, pkgs, ... }:

let
  # The fn key has two spellings and they are different keys. Karabiner 16's own
  # simple_modifications.json lists `apple_vendor_top_case_key_code:
  # keyboard_fn` as "fn (globe)" among the modifiers, which is the fn on Apple's
  # built-in keyboards; a plain `key_code: fn` appears separately much further
  # down as the generic HID one. Both are mapped from, so the rotation holds on
  # the built-in keyboard and on external keyboards alike, and the Apple
  # spelling is what gets sent back out so the media keys keep working.
  fnApple.apple_vendor_top_case_key_code = "keyboard_fn";
  fnGeneric.key_code = "fn";

  # A four-way rotation, plus the right command key as the Korean/English
  # toggle. Written as one list because these are simultaneous, not sequential:
  # Karabiner reads the original key on each side, so a cycle is well defined.
  #
  #   fn -> left command -> left option -> left control -> fn
  #
  # Consequence worth knowing: with fn now acting as command, the media
  # functions of F1-F12 move to the physical left control key, which is what
  # sends fn after the rotation.
  #
  # `lang1` is HID usage 0x90, the code Apple's Korean keyboards send for 한/영;
  # Karabiner 16 still lists it as a plain key_code.
  modifierMap = [
    {
      from = fnApple;
      to = { key_code = "left_command"; };
    }
    {
      from = fnGeneric;
      to = { key_code = "left_command"; };
    }
    {
      from = { key_code = "left_command"; };
      to = { key_code = "left_option"; };
    }
    {
      from = { key_code = "left_option"; };
      to = { key_code = "left_control"; };
    }
    {
      from = { key_code = "left_control"; };
      to = fnApple;
    }
    {
      from = { key_code = "right_command"; };
      to = { key_code = "lang1"; };
    }
  ];

  profile = {
    name = "nix-darwin";
    selected = true;

    # No per-device entries. Profile-level modifications apply to every
    # keyboard Karabiner grabs, the built-in one included, which is what
    # "all keyboards" requires. Karabiner repopulates this array itself as it
    # discovers devices; those additions are overwritten on the next activation.
    devices = [ ];

    simple_modifications = map (m: {
      inherit (m) from;
      to = [ m.to ];
    }) modifierMap;

    complex_modifications.rules = [ ];
  };

  karabinerJson = pkgs.writeText "karabiner.json" (
    builtins.toJSON {
      global = {
        # The cask pins the version; let it come through Homebrew like every
        # other package here rather than updating itself behind our back.
        check_for_updates_on_startup = false;
        show_in_menu_bar = true;
      };
      profiles = [ profile ];
    }
  );

  # The key below Esc emits ₩ because the 2-Set Korean layout says so, which is
  # downstream of Karabiner: remapping the key cannot help, since the layout
  # still decides what it produces. Karabiner could leave and re-enter the input
  # source around the keystroke, but upstream warns against exactly that —
  # "switching to input sources which have input_mode_id (Chinese, Japanese,
  # Korean, Vietnamese) may be failed due to an macOS issue".
  #
  # So this is fixed where the character actually appears instead: Cocoa's text
  # system reads ~/Library/KeyBindings/DefaultKeyBinding.dict and will insert a
  # backtick wherever it was about to insert ₩, in either input mode.
  #
  # Limitation: this is a Cocoa mechanism, so it holds in native apps and not in
  # ones that draw their own text stack (Electron, JetBrains, some terminals).
  # Applications read it at launch, so restart them after the first activation.
  defaultKeyBinding = pkgs.writeText "DefaultKeyBinding.dict" ''
    {
        "₩" = ("insertText:", "`");
    }
  '';
in
{
  home.file."Library/KeyBindings/DefaultKeyBinding.dict".source = defaultKeyBinding;

  # Copied rather than symlinked. Karabiner-Elements rewrites karabiner.json
  # (normalising it on launch, and whenever anything is changed in the UI), and
  # it cannot write through a symlink into the read-only store. The trade is
  # that changes made in the Karabiner UI survive only until the next
  # activation, which is the correct direction for a declarative setup.
  home.activation.karabiner = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$HOME/.config/karabiner"
    run install -m 0644 ${karabinerJson} "$HOME/.config/karabiner/karabiner.json"
  '';
}
