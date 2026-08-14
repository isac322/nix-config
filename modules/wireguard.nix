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
  confDir = "/etc/wireguard";

  up = pkgs.writeShellScript "wireguard-up" ''
    set -u

    # wg-quick shells out constantly — wireguard-go, networksetup, ifconfig,
    # route, sed. The nixpkgs wrapper puts wireguard-go on PATH by itself; the
    # rest are Apple's and a daemon starts with almost no PATH at all.
    export PATH=${pkgs.wireguard-tools}/bin:/usr/bin:/bin:/usr/sbin:/sbin

    # Every tunnel this machine has been given, rather than a name from the
    # repository. The interface name is the basename of its own configuration,
    # so the file already carries it — asking for it twice would only create
    # somewhere for the two to disagree, and the configuration is placed by hand
    # anyway because it holds a private key.
    started=0
    for conf in ${confDir}/*.conf; do
      [ -f "$conf" ] || continue

      iface=''${conf##*/}
      iface=''${iface%.conf}

      # Idempotent on purpose. A switch reloads this daemon while the previous
      # tunnel may still be up, and wg-quick refuses to raise an interface that
      # already exists. Tearing down first makes reload mean reload.
      wg-quick down "$iface" >/dev/null 2>&1 || true
      wg-quick up "$iface" || echo "wireguard: $iface failed to come up." >&2
      started=$((started + 1))
    done

    if [ "$started" -eq 0 ]; then
      echo "wireguard: no ${confDir}/*.conf, so no tunnel is started." >&2
      echo "wireguard: a configuration holds this machine's private key and is" >&2
      echo "wireguard: placed by hand; see docs/operations.md." >&2
    fi
  '';
in
{
  options.local.wireguard.enable =
    lib.mkEnableOption ''
      bringing up every tunnel in ${confDir} at boot, as a root daemon.

      Which tunnels those are is not declared here. The interface name is the
      basename of its own configuration file, and that file is placed by hand
      because it holds a private key — so naming it in the repository as well
      would add a second source of truth and nothing else.

      Off by default, which is right for a Mac someone sits at: there the App
      Store client is nicer and, having a login session, able to work at all''
    // {
      example = true;
    };

  config = lib.mkIf cfg.enable {
    # `wg` for looking at a tunnel that is misbehaving. wg-quick itself is
    # reached through the store path above rather than PATH, so this is for the
    # person, not for the daemon.
    environment.systemPackages = [ pkgs.wireguard-tools ];

    launchd.daemons.wireguard = {
      # `command` rather than `serviceConfig.ProgramArguments`, and the
      # difference is not cosmetic. nix-darwin turns `command` into
      # `/bin/sh -c '/bin/wait4path /nix/store && exec …'`; a ProgramArguments
      # written by hand gets no such guard.
      #
      # Which matters at exactly the moment this daemon exists for. /nix/store
      # is on a volume that is not mounted yet when daemons start, so a bare
      # store path fails to exec — silently, because the failure happens before
      # the process that would have written to StandardErrorPath. With
      # KeepAlive off nothing retries, and the machine comes up with no tunnel
      # and an empty log. Seen exactly that way: the log's last line predated
      # the boot by two hours.
      command = "${up}";

      serviceConfig = {
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
