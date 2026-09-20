# Applications that can only come from the Mac App Store, and the switch-time
# step that installs and updates them.
#
# Why they are not declared like everything else is
# [0016](../docs/decisions/0016-mas-only-apps-installed-by-hand.md): there is
# no cask, no nixpkgs package and no direct download for either, and
# `homebrew.masApps` cannot work here because `brew bundle` drops to the
# primary user during activation while mas 7 re-execs itself through sudo for
# installs and updates — a password prompt with no one to answer it.
#
# What mas 7 actually needs is the reverse: run as root, with SUDO_UID and
# SUDO_GID naming the user whose App Store account should act, inside that
# user's Mach bootstrap so storeuid and installd answer. `launchctl asuser`
# supplies the session; the environment variables supply the account. The
# switch fails when that cannot happen — the primary user not on the
# console, no signed-in account, an app the account has never acquired, or a
# bundle Spotlight cannot attribute to the declared id — because a switch
# that cannot reach the App Store has not done what the configuration says,
# and [0025](../docs/decisions/0025-activation-speaks-only-when-needed.md)
# is about telling the human, not pretending.
#
# `local.` for the same reason as modules/orca.nix — options this repository
# invents live under one prefix so they cannot collide with nix-darwin's.
{
  config,
  hostname,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.local.masApps;

  mas = "${pkgs.mas}/bin/mas";
  timeout = "${pkgs.coreutils}/bin/timeout";

  # One bounded mas invocation inside the console user's session. mas drops
  # its effective uid to SUDO_UID for the StoreKit calls, so the purchase or
  # update runs as the logged-in user while the real uid stays root — which
  # is what keeps mas from re-execing itself through sudo and prompting.
  # timeout bounds the known StoreKit hang; 124 means it fired.
  masRun = ''
    masRun() {
      /bin/launchctl asuser "$consoleUid" \
        /usr/bin/env SUDO_UID="$consoleUid" SUDO_GID="$consoleGid" \
        ${timeout} --kill-after=30 600 ${mas} "$@"
    }
  '';
  appStep = app: ''
    if [ -d ${lib.escapeShellArg app.path} ]; then
      # mas decides what to update from Spotlight's kMDItemAppStoreAdamID. A
      # bundle that exists but is not indexed — or is indexed under a
      # different id — would make `mas update` a silent no-op, so verify the
      # id first and give the indexer one explicit nudge before failing.
      adamId=$(/usr/bin/mdls -name kMDItemAppStoreAdamID -raw ${lib.escapeShellArg app.path} 2>/dev/null || true)
      if [ "$adamId" != "${toString app.appStoreId}" ]; then
        /usr/bin/mdimport ${lib.escapeShellArg app.path} 2>/dev/null || true
        adamId=$(/usr/bin/mdls -name kMDItemAppStoreAdamID -raw ${lib.escapeShellArg app.path} 2>/dev/null || true)
      fi
      if [ "$adamId" != "${toString app.appStoreId}" ]; then
        masFailed=1
        echo "" >&2
        echo "  ${app.name} is at ${app.path} but Spotlight reports App Store" >&2
        echo "  id ''${adamId:-none}, not ${toString app.appStoreId}, so mas cannot see or" >&2
        echo "  update it. Check that Spotlight is allowed to index the app" >&2
        echo "  (System Settings > Spotlight) and that it was installed from the" >&2
        echo "  App Store account ${config.system.primaryUser} is signed into, then" >&2
        echo "  re-run:" >&2
        echo "    sudo darwin-rebuild switch --flake /etc/nix-darwin#${hostname}" >&2
        echo "" >&2
      elif masRun update --accurate --no-check-min-os ${toString app.appStoreId}; then
        :
      else
        masStatus=$?
        masFailed=1
        echo "" >&2
        echo "  ${app.name} is installed but could not be updated (mas exit $masStatus)." >&2
        echo "  ${app.reason}" >&2
        echo "" >&2
        echo "  Sign ${config.system.primaryUser} into the App Store and re-run:" >&2
        echo "    sudo darwin-rebuild switch --flake /etc/nix-darwin#${hostname}" >&2
        echo "" >&2
      fi
    else
      if masRun install ${toString app.appStoreId}; then
        if [ ! -d ${lib.escapeShellArg app.path} ]; then
          masFailed=1
          echo "  mas finished installing ${app.name}, but ${app.path} is still missing." >&2
          echo "  Locate the App Store installation and correct local.masApps before retrying." >&2
        fi
      else
        masStatus=$?
        masFailed=1
        echo "" >&2
        echo "  ${app.name} is not installed and mas could not install it" >&2
        echo "  (exit $masStatus). ${app.reason}" >&2
        echo "" >&2
        echo "  mas install only re-downloads apps the signed-in account has" >&2
        echo "  already acquired — it never purchases one. If this account has" >&2
        echo "  not, open the App Store page once and get it there:" >&2
        echo "" >&2
        echo "    open 'macappstore://apps.apple.com/app/id${toString app.appStoreId}'" >&2
        echo "" >&2
        echo "  Then re-run:" >&2
        echo "    sudo darwin-rebuild switch --flake /etc/nix-darwin#${hostname}" >&2
        echo "" >&2
      fi
    fi
  '';

  masActivation = ''
    # Mac App Store apps. Everything below needs the primary user logged in
    # on the console: storeuid and installd only answer inside a GUI session,
    # and the App Store account that owns these apps belongs to that user —
    # running mas under anyone else's session would act on the wrong account.
    # The uid is read once and the name resolved from it, so a console
    # logout/login between the two reads cannot pair a stale name with a
    # fresh uid.
    consoleUid=$(/usr/bin/stat -f '%u' /dev/console 2>/dev/null || true)

    if ! consoleUser=$(/usr/bin/id -nu "$consoleUid" 2>/dev/null) ||
      [ "$consoleUser" != ${lib.escapeShellArg config.system.primaryUser} ]; then
      echo "" >&2
      echo "  Mac App Store apps are declared for ${config.system.primaryUser}, but" >&2
      echo "  the console session belongs to ''${consoleUser:-nobody}. mas can only" >&2
      echo "  reach the App Store inside ${config.system.primaryUser}'s logged-in" >&2
      echo "  session. Log in as ${config.system.primaryUser} on the console, then" >&2
      echo "  re-run:" >&2
      echo "    sudo darwin-rebuild switch --flake /etc/nix-darwin#${hostname}" >&2
      echo "" >&2
      exit 1
    fi

    if ! consoleGid=$(/usr/bin/id -g "$consoleUid" 2>/dev/null); then
      echo "  could not resolve the primary group of console uid $consoleUid" >&2
      exit 1
    fi

    ${masRun}

    masFailed=0
    ${lib.concatMapStrings appStep (lib.attrValues cfg)}

    if [ "$masFailed" -ne 0 ]; then
      exit 1
    fi
  '';
in
{
  options.local.masApps = lib.mkOption {
    default = { };
    description = ''
      Mac App Store applications this machine is expected to have. Each entry
      is installed when missing and updated when present, during activation,
      inside the console user's session — a switch fails when that cannot be
      done.
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
                Bundle path whose presence decides whether activation updates
                the application or installs it.

                A path rather than a bundle identifier because this runs during
                activation, where `mdfind` may be answering from an index that
                has not caught up.
              '';
            };

            appStoreId = lib.mkOption {
              type = lib.types.int;
              example = 1451685025;
              description = ''
                App Store item id — the argument mas install and mas update
                take, and the id in the `macappstore://` link the report
                prints when the account has not acquired the app.

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
  # the other postActivation blocks rather than replacing them. A nonzero exit
  # aborts activation before /run/current-system is repointed, so a failed App
  # Store step leaves the switch unclaimed rather than half-reported.
  config.system.activationScripts.postActivation.text = lib.mkIf (cfg != { }) masActivation;
}
