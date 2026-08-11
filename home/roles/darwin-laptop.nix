# home-manager configuration for the Macs someone sits in front of.
#
# The desktop applications, and nothing else. Everything shared by every Mac
# is in home/darwin.nix; everything shared by every machine is in
# home/common.nix.
{ pkgs, ... }:

{
  # Firefox is the clearest case of "same option, different implementation".
  # On macOS the package is a plain .app bundle from the nixpkgs-firefox-darwin
  # overlay, which home-manager cannot wrap, so the policies have to be
  # delivered through two channels instead. A Linux host would just use
  # `pkgs.firefox` and let home-manager wrap it with the same `policies`.
  programs.firefox =
    let
      policies = {
        DisableAppUpdate = true;
        BackgroundAppUpdate = false;
      };
    in
    {
      enable = true;

      # Baked into the bundle.
      package = pkgs.firefox-bin.override {
        extraFiles."distribution/policies.json".source =
          pkgs.writeText "policies.json" (builtins.toJSON { inherit policies; });
      };

      # Written to ~/Library/Preferences/org.mozilla.firefox.plist along with
      # EnterprisePoliciesEnabled.
      inherit policies;
    };

  # JetBrains Mono Nerd Font. home-manager links fonts into ~/Library/Fonts on
  # darwin, so a package in home.packages is all it takes. The family name is
  # "JetBrainsMono Nerd Font" — the files are JetBrainsMonoNerdFont-*.ttf, and
  # the NL and Mono variants in the same package are separate families.
  home.packages = [
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.nerd-fonts.d2coding
  ];

  programs.ghostty = {
    # Ghostty itself is a cask, declared in modules/roles/darwin-laptop.nix.
    # nixpkgs builds it for Linux only — `meta.platforms` has no darwin — and
    # the module documents exactly this case: set package to null where ghostty
    # is unavailable and let something else install it.
    enable = true;
    package = null;

    # Written to ~/.config/ghostty/config. Ghostty is the one terminal here
    # whose settings are a plain text file rather than a GUI preference store,
    # which is why it was chosen over Warp and iTerm2 — the quake window is
    # built in to all three, but only this one is configurable from the repo.
    settings = {
      # Repeating font-family builds a fallback chain: Ghostty moves down the
      # list when a codepoint is missing from the font above. JetBrains Mono has
      # no Hangul, so without a second entry macOS picks something arbitrary.
      #
      # D2Coding is the pairing that keeps the grid intact — its Hangul is
      # exactly twice the ASCII advance, which a proportional Korean face is
      # not, and a terminal notices.
      font-family = [
        "JetBrainsMono Nerd Font"
        "D2CodingLigature Nerd Font"
      ];
      font-size = 14;

      # The quake-style drop-down. `global:` makes the binding work while
      # another app is focused, which on macOS needs Ghostty to be granted
      # Accessibility permission — a one-time GUI approval that cannot be
      # declared away.
      #
      # F12 is free: nothing in macOS's own shortcut table binds key code 111,
      # and no symbolic hotkey on this machine uses it.
      #
      # cmd+opt+t opens an ordinary window. `new_window` brings Ghostty to the
      # front when it is not focused, so the binding doubles as "launch it".
      # Splits and movement between them. No `global:` — these only make sense
      # while the terminal is focused.
      #
      # ⌘⌥D needed macOS's Dock-hiding shortcut turned off first; it is a
      # system binding, and those win over an application's. That is handled in
      # modules/keyboard.nix. ⌘⌥R was unclaimed, and macOS uses no ⇧⌥
      # combination at all, so the WASD movement keys were all free.
      #
      # Note the overlap: ⌘⌥D splits downwards while ⇧⌥D moves right, because
      # movement follows WASD and splitting follows the direction's initial.
      keybind = [
        "global:f12=toggle_quick_terminal"
        "global:cmd+opt+t=new_window"
        "cmd+opt+d=new_split:down"
        "cmd+opt+r=new_split:right"
        "shift+opt+w=goto_split:up"
        "shift+opt+a=goto_split:left"
        "shift+opt+s=goto_split:down"
        "shift+opt+d=goto_split:right"
      ];
      quick-terminal-position = "top";
      quick-terminal-screen = "mouse";
      quick-terminal-animation-duration = 0.1;
    };
  };
}
