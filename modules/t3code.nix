# Per-machine settings for the T3 Code headless server. Declaration only — what
# consumes them is the LaunchAgent in home/roles/darwin-server.nix.
{ lib, ... }:

{
  options.local.t3code = {
    enable = lib.mkEnableOption "running the T3 Code headless server on this machine";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3773;
      description = ''
        HTTP/WebSocket port for the T3 Code headless server. 3773 is upstream's
        default port; naming it explicitly avoids dynamic fallback ports so
        clients and SSH launches stay predictable.
      '';
    };

    lan = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Pass `--lan` to `t3 serve` so clients on the local network and VPN/tailnet
        (such as WireGuard) can reach the server directly with a pairing code.
        T3 Code binds `0.0.0.0` while closing non-private connections at the
        socket layer and keeping `origin` on loopback in `server-runtime.json`.
      '';
    };

    baseDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/Users/bhyoo/.t3";
      description = ''
        Explicit T3 Code state directory (`--base-dir`). When `null`, uses
        `$HOME/.t3`.
      '';
    };
  };
}
