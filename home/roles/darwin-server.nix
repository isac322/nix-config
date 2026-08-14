# home-manager configuration for the Macs that run unattended.
#
# A server Mac runs the same shell, editor and CLI tools as any other — those
# are in home/common.nix and home/darwin.nix — and the only thing it does not
# want is the desktop applications, which it gets by not importing the laptop
# role. What lands here is tooling this machine alone has a use for.
{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:

let
  # Declared in modules/orca.nix. `osConfig` is the system configuration of the
  # host this home-manager generation belongs to — home-manager's nix-darwin
  # module passes it in under that name.
  cfg = osConfig.local.orca;

  # Homebrew's, because the cask is where Orca comes from (see
  # docs/decisions/0015-gui-apps-come-from-homebrew.md). This is a symlink brew
  # maintains into /Applications/Orca.app; naming the shim rather than the path
  # inside the bundle keeps this working if the bundle is rearranged.
  orca = "/opt/homebrew/bin/orca";

  orcaServe = pkgs.writeShellScript "orca-serve" ''
    set -u

    # A launchd agent inherits almost no PATH, and `orca serve` shells out to
    # everything the agents need — git, claude, codex — from the server's own
    # environment rather than the client's. These are, in order: home-manager's
    # profile, nix-darwin's system profile, Homebrew, and the base system.
    export PATH=/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin

    if [ ! -x ${orca} ]; then
      # First boot after the cask is declared but before `brew bundle` has run.
      # Exit 0 so KeepAlive leaves it alone instead of spinning; the next
      # switch, or the next login, starts it for real.
      echo "orca-serve: ${orca} is not installed yet — nothing to start." >&2
      exit 0
    fi

    ${
      if cfg.pairingAddress != null then
        "addr=${lib.escapeShellArg cfg.pairingAddress}"
      else
        ''
          # The address to advertise, read off the tunnel rather than written
          # down twice. The WireGuard daemon publishes it to a readable file
          # after bringing the interfaces up (modules/wireguard.nix) — nothing
          # wg-quick leaves behind is readable without root, so going to the
          # source directly is not an option for an agent that runs as the user.
          #
          # Waiting rather than failing: this agent starts when the session is
          # created and the tunnel comes up at boot, so the order is usually
          # right — but "usually" is not a thing to depend on, and a runtime that
          # advertised the wrong address would look like it worked.
          addr=""
          waited=0
          while [ "$waited" -lt 60 ]; do
            if [ -s /var/run/wireguard-addresses ]; then
              addr=$(/usr/bin/head -n 1 /var/run/wireguard-addresses)
              [ -n "$addr" ] && break
            fi
            sleep 2
            waited=$((waited + 2))
          done

          if [ -z "$addr" ]; then
            # Non-zero on purpose: KeepAlive brings this back, which is the
            # right behaviour for a tunnel that has not come up yet. A runtime
            # advertising nothing would be worse than one that keeps trying.
            echo "orca-serve: no WireGuard address after ''${waited}s, so there is" >&2
            echo "orca-serve: nothing to advertise. See /var/log/wireguard.log." >&2
            exit 1
          fi
        ''
    }

    ${orca} serve --port ${toString cfg.port} --pairing-address "$addr" --json
    status=$?

    # Exit 3 means another process already owns the Orca profile — the desktop
    # app, or a serve started by hand. Restarting cannot help, and upstream's
    # own systemd unit says so with RestartPreventExitStatus=3. launchd has no
    # equivalent, so the wrapper reports it as a clean exit and KeepAlive
    # (SuccessfulExit = false) stops there.
    if [ "$status" -eq 3 ]; then
      echo "orca-serve: exit 3 — another process already owns the Orca profile. Not restarting." >&2
      exit 0
    fi

    exit "$status"
  '';
in
{
  # The Orca runtime, headless, for the whole time the machine is up.
  #
  # `orca serve` is upstream's answer for a host that should run without a
  # desktop window. The client is only the UI: this side owns the projects,
  # worktrees, terminals and agent processes, and uses this machine's PATH,
  # home directory and credentials rather than the client's.
  #
  # It is an Electron application, so it needs an Aqua session — and a
  # LaunchAgent gets one only at console login. That is the whole reason
  # automatic login is turned on for this role
  # (modules/roles/darwin-server.nix); everything else this machine runs is a
  # root daemon precisely so it does not need any of that.
  #
  # It binds 0.0.0.0. There is no flag to narrow that — --pairing-address only
  # changes the address handed to clients — so what keeps this off other
  # networks is the network, not the runtime. Upstream is explicit that the port
  # must not be forwarded to the public internet.
  launchd.agents.orca-serve = lib.mkIf cfg.enable {
    enable = true;

    # The `gui` domain, which is home-manager's default and so is not written
    # here — this comment is.
    #
    # `domain = "user"` with `LimitLoadToSessionType = "Background"` was the
    # first attempt, on the reasoning that the user domain is not tied to the
    # window server. It loads at switch time and does not survive a reboot:
    # ~/Library/LaunchAgents is read when a session is created, and with nobody
    # logged in there is no session to read it. Verified on the machine — after
    # an unattended reboot the plist was in place and `launchctl print
    # user/<uid>/…orca-serve` found no such service.
    #
    # So the Aqua session has to exist, which is what automatic login is for
    # (modules/roles/darwin-server.nix). Given that it does exist, the default
    # domain is the known-good path: it is where home-manager's own gpg-agent-ssh
    # agent lives and demonstrably works.
    config = {
      # No /bin/wait4path here. home-manager wraps ProgramArguments in exactly
      # that guard already (`waitForNixStore`, on by default), and writing it
      # again nests one inside the other — visible in the gpg-agent-ssh plist
      # this repository generates today, which is double-wrapped for that
      # reason.
      ProgramArguments = [ "${orcaServe}" ];
      RunAtLoad = true;

      # Restart on failure, not on a clean stop. The wrapper turns the one
      # failure worth not retrying into a clean stop.
      KeepAlive.SuccessfulExit = false;
      ThrottleInterval = 10;

      # Where the readiness line lands: `orca_server_ready` carries the bound
      # endpoint, the advertised endpoint and the pairing URL, and there is
      # nowhere else to read it on a machine with no window.
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/orca-serve.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/orca-serve.log";
    };
  };

  # No authorized_keys handling here, of either kind. The file is not declared
  # (`users.users.<name>.openssh.authorizedKeys`) because this repository is
  # public and one key is the SSH identity of every machine — see
  # docs/decisions/0026-sshd-on-the-server-mac.md — and there is no activation
  # notice about it either, because installing your own key on your own machine
  # is not something this configuration has a stake in. sshd is declared here;
  # who is allowed through it is not.

  # Rust straight from nixpkgs, not through rustup.
  #
  # rustup earns its place when a project pins a toolchain in
  # rust-toolchain.toml, or when several versions have to coexist and switch
  # per directory. Neither applies here — one current toolchain is the whole
  # requirement — and what it costs is the property this repository exists for:
  # rustup downloads its toolchains into ~/.rustup at run time, so the compiler
  # on this machine would be whatever it last fetched rather than what
  # flake.lock pins, and a rebuild from this flake would not reproduce it.
  # rust-overlay or fenix is the declarative answer if per-project pinning ever
  # does become the requirement; rustup is not.
  #
  # wasm needs no extra step. nixpkgs configures rustc with
  # `--target=wasm32-unknown-unknown,wasm32v1-none,…` next to the host target,
  # so the standard library for both is built into the package already and
  # `cargo build --target wasm32-unknown-unknown` works as it stands. There is
  # nothing here corresponding to `rustup target add`. What is genuinely
  # separate is the tooling that wraps the output — wasm-bindgen-cli,
  # wasm-pack, binaryen — and none of it is listed because nothing has asked
  # for it yet.
  #
  # Both packages are needed: rustc is the compiler alone, and cargo is a
  # separate derivation in nixpkgs rather than something it brings along.
  #
  # The two language servers are here rather than in home/darwin.nix because
  # this is the machine an editor or a coding agent actually runs on. Neither
  # is configured: an LSP client starts the binary and speaks to it over stdio,
  # so being on PATH under the name the client looks for is the whole
  # integration.
  #
  # `rust-analyzer`, not `rust-analyzer-unwrapped`. The plain attribute is a
  # wrapper whose only job is to set RUST_SRC_PATH to rustPlatform.rustLibSrc,
  # and without it the server runs perfectly well while knowing nothing about
  # the standard library — no completion or go-to-definition on anything from
  # std. That fails as missing features rather than as an error, which is the
  # kind of wrong that goes unnoticed.
  #
  # terraform-ls is HashiCorp's own and, unlike terraform itself, is still
  # MPL-2.0 — so it needs no allowUnfreePredicate entry. It shells out to
  # `terraform` for validation, and finds the one from home/darwin.nix.
  home.packages = [
    pkgs.cargo
    pkgs.rust-analyzer
    pkgs.rustc
    pkgs.terraform-ls
  ];
}
