# Applications that can only come from the Mac App Store, and the switch-time
# check that says when one is missing.
#
# Why they are not declared like everything else is
# [0016](../docs/decisions/0016-mas-only-apps-installed-by-hand.md): there is no
# cask, no nixpkgs package and no direct download for either, and
# `homebrew.masApps` cannot work here because `brew bundle` runs under sudo
# during activation while the App Store's installd only answers inside a
# logged-in user session.
#
# So the install stays manual. What does not have to stay manual is *noticing* —
# a machine missing one of these looks exactly like a machine that has it until
# something reaches for it. That is precisely the case
# [0025](../docs/decisions/0025-activation-speaks-only-when-needed.md) describes:
# a human has to act, so the switch says so, every time, until they do.
#
# `local.` for the same reason as modules/orca.nix — options this repository
# invents live under one prefix so they cannot collide with nix-darwin's.
{ config, lib, ... }:

let
  cfg = config.local.masApps;

  missingCheck = lib.concatMapStrings (app: ''
    if [ ! -d ${lib.escapeShellArg app.path} ]; then
      echo "" >&2
      echo "  ${app.name} is not installed. ${app.reason}" >&2
      echo "" >&2
      echo "  It is App Store only — no cask, no nixpkgs package, no direct" >&2
      echo "  download — so this is the one step a switch cannot take:" >&2
      echo "" >&2
      echo "    open 'macappstore://apps.apple.com/app/id${toString app.appStoreId}'" >&2
      echo "" >&2
    fi
  '') (lib.attrValues cfg);
in
{
  options.local.masApps = lib.mkOption {
    default = { };
    description = ''
      Mac App Store applications this machine is expected to have. Nothing here
      installs anything — each entry only makes activation report the
      application when it is absent.
    '';
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "Display name, as it appears in the report.";
            };

            path = lib.mkOption {
              type = lib.types.str;
              example = "/Applications/WireGuard.app";
              description = ''
                Bundle path whose absence means the application is missing.

                A path rather than a bundle identifier because this runs during
                activation, where `mdfind` may be answering from an index that
                has not caught up and `mas list` needs a user session the
                activation does not have.
              '';
            };

            appStoreId = lib.mkOption {
              type = lib.types.int;
              example = 1451685025;
              description = ''
                App Store item id, used to build the `macappstore://` link that
                opens the page directly.

                Read it off a machine that already has the application:
                `mdls -name kMDItemAppStoreAdamID -raw /Applications/<name>.app`.
              '';
            };

            reason = lib.mkOption {
              type = lib.types.str;
              example = "The Orca runtime is only reachable through the tunnel.";
              description = ''
                One sentence on what stops working without it. The report is
                worth reading only if it says why the machine wants this.
              '';
            };
          };
        }
      )
    );
  };

  # postActivation, so this is the last thing said rather than the first — a
  # switch that also has something to say about GPG or host keys should not bury
  # them under this. The text type merges across modules, so this coexists with
  # the other postActivation blocks rather than replacing them.
  config.system.activationScripts.postActivation.text = lib.mkIf (cfg != { }) missingCheck;
}
