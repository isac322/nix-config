# Camofox browser automation and optional dedicated virtual display.
#
# The browser API and display lifecycle belong to the logged-in Aqua session
# and are declared in Home Manager. This module only defines the system options
# and the unattended-session requirement.
{
  config,
  lib,
  ...
}:

let
  cfg = config.local.camofox;
in
{
  options.local.camofox = {
    enable = lib.mkEnableOption "the loopback Camofox browser API and local desktop integration";

    virtualDisplay = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Run Camofox on a dedicated DeskPad virtual display. This mode is for
        unattended Macs; local desktop use needs only local.camofox.enable.
      '';
    };

    apiPort = lib.mkOption {
      type = lib.types.port;
      default = 9377;
      description = "Loopback TCP port for the Camofox browser API.";
    };

    displayWidth = lib.mkOption {
      type = lib.types.ints.between 640 7680;
      default = 1920;
      description = "Pixel width of the Camofox virtual display.";
    };

    displayHeight = lib.mkOption {
      type = lib.types.ints.between 480 4320;
      default = 1080;
      description = "Pixel height of the Camofox virtual display.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.optionals cfg.virtualDisplay [
      {
        assertion = config.local.autoLogin.enable;
        message = ''
          local.camofox.virtualDisplay requires local.autoLogin.enable: the
          dedicated display is headful and must run in an automatically-created
          Aqua session after an unattended reboot.
        '';
      }
    ];
  };
}
