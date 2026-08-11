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
  home.packages = [ pkgs.nerd-fonts.jetbrains-mono ];

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
      font-family = "JetBrainsMono Nerd Font";
      font-size = 14;

      # The quake-style drop-down. `global:` makes the binding work while
      # another app is focused, which on macOS needs Ghostty to be granted
      # Accessibility permission — a one-time GUI approval that cannot be
      # declared away.
      keybind = [ "global:ctrl+grave_accent=toggle_quick_terminal" ];
      quick-terminal-position = "top";
      quick-terminal-screen = "mouse";
      quick-terminal-animation-duration = 0.1;
    };
  };
}
