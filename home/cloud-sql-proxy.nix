# Runbear Cloud SQL proxies shared by every managed host.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  proxy = lib.getExe pkgs.google-cloud-sql-proxy;
  instances = {
    prod = {
      connectionName = "runbear:us-east4:runbear-prod-pg";
      port = 15432;
    };
    staging = {
      connectionName = "runbear:us-east4:runbear-staging-pg";
      port = 15433;
    };
  };
  programArguments = instance: [
    proxy
    "--psc"
    "--auto-iam-authn"
    "--address=127.0.0.1"
    "--port=${toString instance.port}"
    instance.connectionName
  ];
  launchdAgent =
    environment: instance:
    lib.nameValuePair "cloud-sql-proxy-${environment}" {
      enable = true;
      config = {
        ProgramArguments = programArguments instance;
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 10;
        ProcessType = "Background";
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/cloud-sql-proxy-${environment}.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/cloud-sql-proxy-${environment}.log";
      };
    };
  systemdService =
    environment: instance:
    lib.nameValuePair "cloud-sql-proxy-${environment}" {
      Unit.Description = "Runbear ${environment} Cloud SQL proxy";
      Service = {
        ExecStart = lib.escapeShellArgs (programArguments instance);
        Restart = "always";
        RestartSec = 10;
      };
      Install.WantedBy = [ "default.target" ];
    };
in
{
  home.packages = [
    pkgs.google-cloud-sql-proxy
    pkgs.postgresql_15
  ];

  launchd.agents = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (lib.mapAttrs' launchdAgent instances);
  systemd.user.services = lib.mkIf pkgs.stdenv.hostPlatform.isLinux (
    lib.mapAttrs' systemdService instances
  );
}
