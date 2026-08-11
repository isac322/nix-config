# System-level settings that apply to every host, macOS and NixOS alike.
#
# Anything whose option type or meaning differs between the two platforms must
# NOT live here. `system.stateVersion` is the trap: nix-darwin types it as an
# integer and NixOS as a string, so it is set in modules/darwin.nix and
# modules/nixos.nix separately.
{
  lib,
  pkgs,
  inputs,
  ...
}:

{
  nixpkgs.overlays = [
    # Cross-platform: llm-agents builds for aarch64-darwin, x86_64-linux and
    # aarch64-linux. The Firefox overlay is deliberately not here — see
    # modules/darwin.nix for why it must stay off Linux.
    inputs.llm-agents.overlays.shared-nixpkgs

    # Locally packaged CLIs — see pkgs/overlay.nix.
    (import ../pkgs/overlay.nix)
  ];

  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "1password-cli"
      "claude-code"
      # Only the server Mac takes this from nixpkgs — see
      # modules/roles/darwin-server.nix. The laptop's Chrome is a cask, which
      # Homebrew installs without consulting this predicate at all.
      "google-chrome"
    ];

  environment.systemPackages = [
    pkgs.git
  ];
}
