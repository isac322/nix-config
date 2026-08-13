# WireGuard on a Mac that nobody logs into.
#
# The App Store client is the right answer on a laptop and cannot be the answer
# here. Checked on a Mac that has it installed: the bundle holds one executable
# and no command-line tool, its tunnel is a
# `com.apple.networkextension.packet-tunnel` app extension hosted by the app,
# there is no launchd plist anywhere inside it, its configuration lives only
# under `~/Library/Group Containers/…group.com.wireguard.macos` with nothing in
# `/Library`, and `launchctl print system` lists zero WireGuard jobs — the app
# and its login-item helper are in `gui/<uid>`. Nothing exists that could raise
# the tunnel before someone logs in at the console.
#
# nixpkgs' `wireguard-tools` builds for aarch64-darwin and ships the macOS
# `wg-quick`, not a Linux one pretending: it brings the interface up through
# `wireguard-go utun` and sets DNS with `networksetup`. So the tunnel becomes an
# ordinary root daemon, which is what a headless machine wanted from it.
#
# [0016](../docs/decisions/0016-mas-only-apps-installed-by-hand.md) is not
# contradicted. It says the App Store app cannot be installed declaratively and
# that `wireguard-tools` is the CLI rather than that app, and both remain true.
# What changed is the question: a machine with no screen does not want the app.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.local.wireguard;
  conf = "/etc/wireguard/${toString cfg.interface}.conf";

  up = pkgs.writeShellScript "wireguard-up" ''
    set -u

    # wg-quick shells out constantly — wireguard-go, networksetup, ifconfig,
    # route, sed. The nixpkgs wrapper puts wireguard-go on PATH by itself; the
    # rest are Apple's and a daemon starts with almost no PATH at all.
    export PATH=${pkgs.wireguard-tools}/bin:/usr/bin:/bin:/usr/sbin:/sbin

    if [ ! -f ${conf} ]; then
      echo "wireguard: ${conf} is missing, so no tunnel is started." >&2
      echo "wireguard: it holds this machine's private key and is placed by hand;" >&2
      echo "wireguard: see docs/operations.md." >&2
      exit 0
    fi

    # Idempotent on purpose. A switch reloads this daemon while the previous
    # tunnel may still be up, and wg-quick refuses to raise an interface that
    # already exists. Tearing down first makes reload mean reload.
    wg-quick down ${lib.escapeShellArg (toString cfg.interface)} >/dev/null 2>&1 || true
    exec wg-quick up ${lib.escapeShellArg (toString cfg.interface)}
  '';
in
{
  options.local.wireguard.interface = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    example = "wg0";
    description = ''
      Name of the WireGuard interface to bring up at boot, which is also the
      basename of its configuration: `/etc/wireguard/<name>.conf`.

      `null` — the default — means this machine runs no tunnel of its own. That
      is the right answer for a Mac someone sits at, where the App Store client
      is both nicer and able to work, since it has the login session it needs.

      The configuration file is never in this repository. It carries the private
      key, and it is installed once per machine the same way the WARP service
      token is.
    '';
  };

  config = lib.mkIf (cfg.interface != null) {
    # `wg` for looking at a tunnel that is misbehaving. wg-quick itself is
    # reached through the store path above rather than PATH, so this is for the
    # person, not for the daemon.
    environment.systemPackages = [ pkgs.wireguard-tools ];

    launchd.daemons.wireguard = {
      serviceConfig = {
        ProgramArguments = [ "${up}" ];
        RunAtLoad = true;

        # `wg-quick up` exits as soon as the interface is up — there is no
        # process to supervise, and KeepAlive would raise the tunnel in a loop.
        # What keeps it alive afterwards is wireguard-go, which wg-quick starts
        # detached. Nothing here restarts that if it dies; if that turns out to
        # matter, the answer is a watchdog rather than KeepAlive on this.
        KeepAlive = false;

        # A tunnel that failed to come up on a machine reached only through that
        # tunnel is the failure that has to be readable afterwards.
        StandardOutPath = "/var/log/wireguard.log";
        StandardErrorPath = "/var/log/wireguard.log";
      };
    };
  };
}
