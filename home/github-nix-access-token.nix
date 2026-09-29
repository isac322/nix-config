# Hands the GitHub CLI login to Nix so `github:` fetches use the 5,000/hour
# authenticated API quota instead of the 60/hour per-IP anonymous one.
#
# Nix has no credential-helper hook: `access-tokens` only takes a literal
# string. So a user agent copies `gh auth token` into a 0600 file that the user
# nix.conf pulls in with `!include`. When gh has no token the file is removed,
# and because `!include` skips missing files, Nix falls back to anonymous
# access instead of failing. Nothing wraps or shadows the `nix` command.
#
# The agent reruns whenever gh rewrites hosts.yml (login, logout, account
# switch) and hourly as a backstop, so a replaced token does not linger long
# enough to turn anonymous 403s into authenticated 401s.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  nixConfigDir = "${config.xdg.configHome}/nix";
  tokenFile = "${nixConfigDir}/github-access-token.conf";
  ghHosts = "${config.xdg.configHome}/gh/hosts.yml";

  sync = pkgs.writeShellScript "github-nix-access-token" ''
    set -eu
    umask 077
    mkdir -p ${lib.escapeShellArg nixConfigDir}
    if token=$(${lib.getExe pkgs.gh} auth token --hostname github.com 2>/dev/null) && [ -n "$token" ]; then
      tmp=$(mktemp ${lib.escapeShellArg "${nixConfigDir}/.github-access-token.XXXXXX"})
      printf 'access-tokens = github.com=%s\n' "$token" >"$tmp"
      mv -f "$tmp" ${lib.escapeShellArg tokenFile}
    else
      rm -f ${lib.escapeShellArg tokenFile}
    fi
  '';
in
{
  xdg.configFile."nix/nix.conf".text = ''
    !include ${baseNameOf tokenFile}
  '';

  launchd.agents.github-nix-access-token = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    enable = true;
    config = {
      # wait4path: /nix/store may not be mounted yet when LaunchAgents start.
      ProgramArguments = [
        "/bin/sh"
        "-c"
        "/bin/wait4path /nix/store && exec ${sync}"
      ];
      RunAtLoad = true;
      StartInterval = 3600;
      WatchPaths = [ ghHosts ];
      ProcessType = "Background";
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/github-nix-access-token.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/github-nix-access-token.log";
    };
  };

  systemd.user = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    services.github-nix-access-token = {
      Unit.Description = "Copy the GitHub CLI token into Nix access-tokens";
      Service = {
        Type = "oneshot";
        ExecStart = "${sync}";
      };
      Install.WantedBy = [ "default.target" ];
    };
    timers.github-nix-access-token = {
      Unit.Description = "Refresh the Nix GitHub access token hourly";
      Timer.OnUnitActiveSec = "1h";
      Install.WantedBy = [ "timers.target" ];
    };
    paths.github-nix-access-token = {
      Unit.Description = "Refresh the Nix GitHub access token when gh login changes";
      Path.PathChanged = ghHosts;
      Install.WantedBy = [ "default.target" ];
    };
  };
}
