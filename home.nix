{ pkgs, config, ... }:

{
  home.stateVersion = "26.05";

  home.packages = [
    pkgs.ripgrep
    pkgs.htop
    pkgs.fzf
    # From llm-agents rather than nixpkgs: it tracks upstream daily, while the
    # nixpkgs-unstable channel lags master by several days.
    pkgs.llm-agents.claude-code
    pkgs.llm-agents.omp
  ];

  programs.git = {
    enable = true;
    settings.user = {
      name = "Byeonghoon Yoo";
      email = "bhyoo@bhyoo.com";
    };
  };

  programs.zsh.enable = true;

  programs.firefox =
    let
      policies = {
        DisableAppUpdate = true;
        BackgroundAppUpdate = false;
      };
    in
    {
      enable = true;

      # firefox-bin comes from the nixpkgs-firefox-darwin overlay. It is a plain
      # .app bundle, so home-manager cannot wrap it; policies are delivered twice
      # instead: baked into the bundle here, and via macOS defaults below.
      package = pkgs.firefox-bin.override {
        extraFiles."distribution/policies.json".source =
          pkgs.writeText "policies.json" (builtins.toJSON { inherit policies; });
      };

      # Written to ~/Library/Preferences/org.mozilla.firefox.plist along with
      # EnterprisePoliciesEnabled.
      inherit policies;
    };
}
