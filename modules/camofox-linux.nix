# Headless Camofox service for NixOS hosts.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.local.camofox;
  stateRoot = "/var/lib/camofox";
in
{
  options.local.camofox = {
    enable = lib.mkEnableOption "the loopback Camofox browser API";

    apiPort = lib.mkOption {
      type = lib.types.port;
      default = 9377;
      description = "Loopback TCP port for the Camofox browser API.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.camofox-browser = {
      description = "Headless Camofox browser automation server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      # Browser code and camoufox-js compatibility resources stay immutable in
      # the store. Only session state lives below systemd's StateDirectory.
      environment = {
        CAMOFOX_BIND_HOST = "127.0.0.1";
        CAMOFOX_PORT = toString cfg.apiPort;
        CAMOFOX_COOKIES_DIR = "${stateRoot}/cookies";
        CAMOFOX_PROFILE_DIR = "${stateRoot}/profiles";
        CAMOFOX_TRACES_DIR = "${stateRoot}/traces";
        CAMOFOX_HEADLESS = "true";
        CAMOFOX_DISABLE_DEFAULT_ADDONS = "1";
        CAMOFOX_CRASH_REPORT_ENABLED = "false";
        SENTRY_DSN = "";
        HOME = stateRoot;
      };

      serviceConfig = {
        Type = "simple";
        User = "bhyoo";
        Group = "users";
        ExecStart = lib.getExe pkgs.camofox-browser;
        WorkingDirectory = stateRoot;

        StateDirectory = [
          "camofox"
          "camofox/cookies"
          "camofox/profiles"
          "camofox/traces"
        ];
        StateDirectoryMode = "0700";
        UMask = "0077";

        Restart = "on-failure";
        RestartSec = "5s";
        TimeoutStopSec = "30s";

        AmbientCapabilities = "";
        CapabilityBoundingSet = "";
        LockPersonality = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        RemoveIPC = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
          "AF_NETLINK"
        ];
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
      };
    };
  };
}
