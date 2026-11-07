# home-manager configuration for NixOS hosts only.
#
# Deliberately thin. Almost everything lives in home/common.nix, and the Vim
# config there is already written to degrade gracefully on a headless box (the
# clipboard setting is guarded by `has('clipboard')`). This file is the seam for
# what genuinely cannot be shared — put Linux-only programs and any
# `pkgs.firefox` desktop configuration here rather than widening common.nix.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  herdrCore = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.herdr-core;
  herdrCoreBin = "${herdrCore}/bin/herdr-core";
  timeout = lib.getExe' pkgs.coreutils "timeout";
  jq = lib.getExe pkgs.jq;

  herdrCoreStart = pkgs.writeShellScript "herdr-core-start" ''
    set -u

    export PATH=${config.home.profileDirectory}/bin:/run/current-system/sw/bin:/usr/bin:/bin
    unset SSH_CONNECTION SSH_CLIENT SSH_TTY

    status_json=$(${timeout} -k 5 30 ${herdrCoreBin} server start --json) || exit 1
    running=$(printf '%s\n' "$status_json" | ${jq} -r '.version // empty')
    pid=$(printf '%s\n' "$status_json" | ${jq} -r '.pid // empty')
    exe=""
    if [ -n "$pid" ]; then
      exe=$(${pkgs.coreutils}/bin/readlink "/proc/$pid/exe" 2>/dev/null || true)
    fi

    if [ "$running" = ${lib.escapeShellArg herdrCore.version} ] && [ "$exe" = ${lib.escapeShellArg herdrCoreBin} ]; then
      exit 0
    fi

    echo "herdr-core-start: serving ''${running:-unknown} (''${exe:-unknown}), installed ${herdrCore.version} — restarting the core (terminals kept)." >&2
    ${timeout} -k 5 30 ${herdrCoreBin} server restart --json >/dev/null
  '';
in
{
  home.packages = [ pkgs.rustdesk-flutter ];

  systemd.user.services.herdr-core = {
    Unit.Description = "Ensure the Herdr core runtime is running on the current Nix store generation";
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${herdrCoreStart}";
    };
    Install.WantedBy = [ "default.target" ];
  };

  home.activation.herdrCoreRefresh = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
    if [ -e "/run/user/$(${pkgs.coreutils}/bin/id -u)/systemd/private" ]; then
      run ${herdrCoreStart} || warnEcho "herdr-core server was not moved to the installed version."
    fi
  '';
}
