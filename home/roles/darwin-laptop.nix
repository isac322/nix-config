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
}
