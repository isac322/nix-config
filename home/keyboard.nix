# The Cocoa key binding that fixes ₩ on the key below Esc.
#
# The modifier remapping is not here — it is system-wide and lives in
# modules/keyboard.nix, applied with hidutil.
{ pkgs, ... }:

let
  # The key below Esc emits ₩ because the 2-Set Korean layout says so, and the
  # layout sits downstream of any key remapping: hidutil or Karabiner can change
  # which key arrives, but the layout still decides what it produces. Karabiner
  # could leave and re-enter the input source around the keystroke, but upstream
  # warns against exactly that — "switching to input sources which have
  # input_mode_id (Chinese, Japanese, Korean, Vietnamese) may be failed due to
  # an macOS issue".
  #
  # So this is fixed where the character is actually inserted instead. Cocoa's
  # text system reads ~/Library/KeyBindings/DefaultKeyBinding.dict and puts a
  # backtick wherever it was about to put ₩, in either input mode. It is a plain
  # file with no permission attached, so it works headlessly.
  #
  # Limitation: being a Cocoa mechanism, it holds in native apps and not in ones
  # that draw their own text stack (Electron, JetBrains, some terminals).
  # Applications read it at launch, so restart them after the first activation.
  defaultKeyBinding = pkgs.writeText "DefaultKeyBinding.dict" ''
    {
        "₩" = ("insertText:", "`");
    }
  '';
in
{
  home.file."Library/KeyBindings/DefaultKeyBinding.dict".source = defaultKeyBinding;
}
