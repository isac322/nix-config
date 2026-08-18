# Cross-platform daily Borg backup for unattended server configurations.
{ platform }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.local.borgBackup;
  isDarwin = platform == "darwin";
  isLinux = platform == "linux";
  excludeFile = "/etc/borg-exclude";
  backupHome =
    if cfg.home != null then
      cfg.home
    else if isDarwin then
      "/Users/${cfg.user}"
    else
      "/home/${cfg.user}";

  scheduleParts = builtins.match "([01][0-9]|2[0-3]):([0-5][0-9])" cfg.scheduleTime;
  digitValues = {
    "0" = 0;
    "1" = 1;
    "2" = 2;
    "3" = 3;
    "4" = 4;
    "5" = 5;
    "6" = 6;
    "7" = 7;
    "8" = 8;
    "9" = 9;
  };
  twoDigitNumber =
    value:
    let
      digits = lib.stringToCharacters value;
    in
    digitValues.${builtins.elemAt digits 0} * 10 + digitValues.${builtins.elemAt digits 1};
  scheduleHour =
    if scheduleParts == null then 0 else twoDigitNumber (builtins.elemAt scheduleParts 0);
  scheduleMinute =
    if scheduleParts == null then 0 else twoDigitNumber (builtins.elemAt scheduleParts 1);

  backupCommand = pkgs.writeShellScript "borg-backup" ''
    set -eu

    export HOME=${lib.escapeShellArg backupHome}
    ${lib.optionalString (cfg.passphraseFile != null) ''
      export BORG_PASSCOMMAND=${lib.escapeShellArg "${pkgs.coreutils}/bin/cat ${lib.escapeShellArg cfg.passphraseFile}"}
    ''}
    ${lib.optionalString (cfg.sshIdentityFile != null) ''
      export BORG_RSH=${lib.escapeShellArg "${pkgs.openssh}/bin/ssh -i ${lib.escapeShellArg cfg.sshIdentityFile} -o IdentitiesOnly=yes"}
    ''}

    cd ${lib.escapeShellArg backupHome}
    ${lib.getExe pkgs.borgbackup} create \
      --stats \
      --show-rc \
      --compression zstd,6 \
      --exclude-from ${lib.escapeShellArg excludeFile} \
      --exclude-caches \
      --exclude-if-present .nobackup \
      -- \
      ${lib.escapeShellArg "${cfg.repository}::{hostname}-{now:%Y-%m-%dT%H:%M:%S}"} \
      .

    ${lib.getExe pkgs.borgbackup} prune \
      --stats \
      --show-rc \
      --glob-archives ${lib.escapeShellArg "{hostname}-*"} \
      --keep-daily ${toString cfg.keepDaily} \
      --keep-weekly ${toString cfg.keepWeekly} \
      --keep-monthly ${toString cfg.keepMonthly} \
      -- \
      ${lib.escapeShellArg cfg.repository}

    exec ${lib.getExe pkgs.borgbackup} compact ${lib.escapeShellArg cfg.repository}
  '';
in
{
  options.local.borgBackup = {
    repository = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "ssh://backup@example.invalid/./borg/server";
      description = ''
        Borg repository URL. No backup job is generated until this is set, and
        the module never initializes the repository.
      '';
    };

    scheduleTime = lib.mkOption {
      type = lib.types.str;
      default = "03:00";
      example = "01:30";
      description = "Local time for the daily backup, in 24-hour HH:MM format.";
    };

    passphraseFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/borg-passphrase";
      description = ''
        Runtime path containing the Borg repository passphrase. The path is
        passed to BORG_PASSCOMMAND; the secret itself is never copied to the
        Nix store.
      '';
    };

    sshIdentityFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home/bhyoo/.ssh/borg";
      description = ''
        Runtime path to the SSH private key used for a remote repository. The
        key is referenced by BORG_RSH and is never copied to the Nix store.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "bhyoo";
      description = "User account that owns the backup source and runs Borg.";
    };

    home = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/srv/home/bhyoo";
      description = ''
        Full home directory backed up by the daily Borg job. When null, this
        defaults to /Users/<user> on Darwin and /home/<user> on Linux.
      '';
    };
    keepDaily = lib.mkOption {
      type = lib.types.ints.positive;
      default = 7;
      description = "Number of daily archives to retain.";
    };

    keepWeekly = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = "Number of weekly archives to retain.";
    };

    keepMonthly = lib.mkOption {
      type = lib.types.ints.positive;
      default = 6;
      description = "Number of monthly archives to retain.";
    };
  };

  config = lib.mkMerge [
    {
      environment.systemPackages = [ pkgs.borgbackup ];
      environment.etc."borg-exclude" = {
        source = ../home/files/borg-exclude;
      };

      assertions = [
        {
          assertion = scheduleParts != null;
          message = "local.borgBackup.scheduleTime must be a 24-hour time in HH:MM format";
        }
      ];
    }

    (lib.optionalAttrs isLinux {
      systemd = lib.mkIf (cfg.repository != null) {
        services.borg-backup = {
          description = "Daily Borg home backup";
          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            WorkingDirectory = backupHome;
            ExecStart = backupCommand;
          };
        };

        timers.borg-backup = {
          description = "Daily Borg home backup";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*-*-* ${cfg.scheduleTime}:00";
            Persistent = true;
            Unit = "borg-backup.service";
          };
        };
      };
    })

    (lib.optionalAttrs isDarwin {
      launchd = lib.mkIf (cfg.repository != null) {
        daemons.borg-backup = {
          command = backupCommand;
          serviceConfig = {
            UserName = cfg.user;
            WorkingDirectory = backupHome;
            ProcessType = "Background";
            StartCalendarInterval = {
              Hour = scheduleHour;
              Minute = scheduleMinute;
            };
            StandardOutPath = "/var/log/borg-backup.log";
            StandardErrorPath = "/var/log/borg-backup.log";
          };
        };
      };
    })
  ];
}
