# Per-machine settings for the Orca runtime. Declaration only — what consumes
# them is the LaunchAgent in home/roles/darwin-server.nix, and the decision is
# docs/decisions/0028-orca-runtime-on-the-server-mac.md.
#
# The split exists because the two halves belong to different layers. *Whether*
# a Mac runs the runtime is a role question and the answer is the same on every
# machine in that role; *where clients dial it* is a fact about one machine and
# nothing else. Roles live in modules/roles/, machines live in hosts/, and this
# is what lets the address live in hosts/ where it belongs — a second server Mac
# sets its own without touching anything shared.
#
# `local.` rather than a bare `orca.` or an entry under `services.`: options
# this repository declares itself go under one prefix, so a name we invent can
# never collide with one nix-darwin adds later. This is the first of them.
#
# The agent that reads these is a home-manager module, which sees this through
# `osConfig` — home-manager's nix-darwin module imports nixos/common.nix, which
# passes the system config in under that name.
{ lib, ... }:

{
  options.local.orca = {
    pairingAddress = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "10.99.0.2";
      description = ''
        Address clients should dial to reach this machine's Orca runtime,
        passed to `orca serve --pairing-address`. Normally this machine's
        WireGuard address.

        This changes only what the runtime advertises in its pairing URL. It is
        not a bind address, and there is no flag that is: the runtime listens on
        0.0.0.0, so what keeps it off other networks is the network.

        `null` — the default — means no runtime is started on this machine.
        That is deliberate rather than a fallback: a pairing URL built from a
        guessed address resolves to nothing, and upstream refuses to advertise a
        wildcard for the same reason.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 6768;
      description = ''
        Port for the Orca runtime. 6768 is the number every upstream example
        uses.

        Named rather than left unset because the runtime falls back to some
        other port when this one is taken, and a service whose endpoint has to
        stay predictable cannot have that happen quietly.
      '';
    };
  };
}
