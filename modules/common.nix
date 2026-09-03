# System-level settings that apply to every host, macOS and NixOS alike.
#
# Anything whose option type or meaning differs between the two platforms must
# NOT live here. `system.stateVersion` is the trap: nix-darwin types it as an
# integer and NixOS as a string, so it is set in modules/darwin.nix and
# modules/nixos.nix separately.
{
  inputs,
  lib,
  pkgs,
  ...
}:

{
  # llm-agents' `overlays.shared-nixpkgs` used to be here and is deliberately
  # gone: it builds that whole set against our nixpkgs, and its binary cache
  # only answers for the revision they pinned. home/common.nix takes
  # `packages.<system>` instead, which is the build they actually uploaded.
  # The Firefox overlay is deliberately not here either — see modules/darwin.nix
  # for why it must stay off Linux.
  nixpkgs.overlays = [
    # Locally packaged CLIs — see pkgs/overlay.nix.
    (import ../pkgs/overlay.nix {
      gajaeCodeManifest = inputs.gajae-code-manifest or null;
    })
  ];

  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "1password-cli"
      "claude-code"
      # getsentry/cli uses FSL-1.1-Apache-2.0. It permits internal use and
      # converts to Apache-2.0 after two years, but nixpkgs correctly classifies
      # the current release as unfree until that conversion.
      "sentry"
      # HashiCorp relicensed Terraform from MPL-2.0 to the Business Source
      # License at 1.5.x, so nixpkgs has marked it unfree ever since. Nothing
      # about the binary changed and the BUSL permits this use; it only forbids
      # offering a competing Terraform service. opentofu is the MPL fork that
      # came out of the relicensing and needs no entry here, if the licence
      # rather than the tool is what matters later.
      "terraform"
    ];

  environment.systemPackages = [
    pkgs.git
  ];
}
