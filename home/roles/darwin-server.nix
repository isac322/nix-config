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
  # Declared by system modules. `osConfig` is the system configuration of the
  # host this home-manager generation belongs to — home-manager's nix-darwin
  # module passes it in under that name.
  cfg = osConfig.local.orca;
  camofoxCfg = osConfig.local.camofox;
  autoLogin = osConfig.local.autoLogin;

  # The bill for automatic login, and the thing that pays it.
  #
  # When a person types their password at the login window, that keystroke does
  # two jobs: it logs them in and it unlocks their login keychain. An automatic
  # login through /etc/kcpassword does only the first. The keychain stays
  # locked, and everything that needs a secret out of it stops — for this
  # machine that means gpg-agent, whose pinentry-mac holds the GPG passphrase
  # there.
  #
  # The failure is invisible in the worst way. `ssh-add -L` still answers,
  # because listing keys needs no secret; the *signing* step is what blocks. So
  # `ssh -T git@github.com` gets as far as "Server accepts key" and then stops
  # forever, and so does every commit signature. Seen on this machine with a
  # pinentry-mac process 49 minutes old, waiting on a dialog drawn on a console
  # nobody is sitting at.
  #
  # `security -i` takes its command on standard input, so the password is never
  # an argument and never appears in `ps`.
  unlockKeychain = pkgs.writeShellScript "unlock-login-keychain" ''
    set -u

    pwFile=${lib.escapeShellArg autoLogin.passwordFile}
    keychain="$HOME/Library/Keychains/login.keychain-db"

    if [ ! -r "$pwFile" ]; then
      echo "unlock-login-keychain: cannot read $pwFile; keychain left as it is." >&2
      exit 0
    fi
    [ -f "$keychain" ] || exit 0

    # `security -i` splits its input the way a shell would, so a password
    # holding a quote or a backslash has to survive that. Built in perl rather
    # than with shell expansions — the same reason the rest of this repository's
    # secret handling is in perl: it is one place and it is readable.
    /usr/bin/perl -e '
      my $kc = $ARGV[0];
      my $pw = <STDIN>;
      $pw = "" unless defined $pw;
      $pw =~ s/\r?\n\z//;
      for ($pw, $kc) { s/(["\\])/\\$1/g }
      print qq{unlock-keychain -p "$pw" "$kc"\n};
    ' "$keychain" < "$pwFile" |
      /usr/bin/security -i >/dev/null 2>&1

    # Say something only when it did not work, which is the only case a person
    # can do anything about.
    if ! /usr/bin/security show-keychain-info "$keychain" >/dev/null 2>&1; then
      echo "unlock-login-keychain: the login keychain is still locked." >&2
      echo "unlock-login-keychain: gpg-agent will hang on its first signature," >&2
      echo "unlock-login-keychain: which stops commit signing and SSH. Does the" >&2
      echo "unlock-login-keychain: password in $pwFile still match the account?" >&2
    fi
  '';

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

    # Exit 3 means another process already owns the Orca profile. Upstream's own
    # systemd unit refuses to retry that (RestartPreventExitStatus=3) and for the
    # case it means — the desktop app is sharing this machine — refusing is
    # right.
    #
    # But it also happens for a few seconds during our own restart. `launchctl
    # kickstart -k` kills this script; Electron takes longer to let go of the
    # profile lock, so the replacement starts into a profile that is still held.
    # Treating that as terminal leaves the machine with no runtime at all, which
    # is how a restart-on-upgrade turned into an outage.
    #
    # So retry a few times before believing it. A restart clears in seconds; a
    # desktop app that genuinely owns the profile is still there a minute later,
    # and then we stop and say so.
    attempt=0
    while :; do
      ${orca} serve --port ${toString cfg.port} --pairing-address "$addr" --json
      status=$?

      [ "$status" -ne 3 ] && break

      attempt=$((attempt + 1))
      if [ "$attempt" -ge 6 ]; then
        echo "orca-serve: exit 3 after $attempt tries — another process owns the" >&2
        echo "orca-serve: Orca profile and is not letting go. Not restarting." >&2
        exit 0
      fi
      sleep 10
    done

    exit "$status"
  '';

  camofox = pkgs.writeShellScript "camofox-browser" ''
    set -u

    # OMP runs on this Mac and reaches the API through loopback.  Remote
    # observation remains noVNC over WireGuard; the browser control API has no
    # reason to cross a network interface at all.  Setting the host explicitly
    # is mandatory because Camofox's unset default is every interface.

    # Session persistence and cookie import both live under ~/.camofox. Make
    # the complete private shape before the server starts rather than allowing
    # one request to race another while lazily creating it.
    stateRoot=${lib.escapeShellArg "${config.home.homeDirectory}/.camofox"}
    /usr/bin/install -d -m 0700 \
      "$stateRoot" \
      "$stateRoot/cookies" \
      "$stateRoot/profiles" \
      "$stateRoot/traces"

    export CAMOFOX_BIND_HOST=127.0.0.1
    export CAMOFOX_PORT=${lib.escapeShellArg (toString camofoxCfg.apiPort)}
    export CAMOFOX_COOKIES_DIR="$stateRoot/cookies"
    export CAMOFOX_PROFILE_DIR="$stateRoot/profiles"
    export CAMOFOX_TRACES_DIR="$stateRoot/traces"

    # v1.13.1 is patched at package time so false means an ordinary headed
    # Camoufox process in this Aqua session. The upstream ENABLE_VNC plugin is
    # Linux/Xvfb machinery and stays explicitly off; Apple Screen Sharing and
    # the root noVNC daemon in modules/camofox.nix provide the view instead.
    export CAMOFOX_HEADLESS=false
    export ENABLE_VNC=0

    # The packaged browser executable is fixed in the generation, and Camoufox
    # must not replace it with a runtime download. Default addons retain their
    # upstream behavior.
    export CAMOUFOX_EXECUTABLE=${lib.escapeShellArg "${pkgs.camoufox}/Applications/Camoufox.app/Contents/MacOS/camoufox"}
    export CAMOUFOX_SKIP_DOWNLOAD=1

    # Upstream sends anonymized crash and hang reports by default. This machine
    # is unattended, but that is not consent to send its failures elsewhere.
    export CAMOFOX_CRASH_REPORT_ENABLED=false
    export SENTRY_DSN=""

    exec ${pkgs.camofox-browser}/bin/camofox-browser
  '';

  # OMP's native MCP loader starts this stdio adapter per agent session. The
  # session wrapper derives OMP's durable UUID from its per-terminal transcript
  # breadcrumb, keeps CAMOFOX_USER_ID fixed for shared login state, and gives
  # each OMP conversation a distinct sessionKey/tab namespace. The underlying
  # adapter remains only an HTTP client: it forwards its eleven Camofox tools
  # to the launchd-owned singleton above and never launches another browser.
  #
  # Keep context-mode in the same declarative file. It created the original
  # mutable mcp.json; `force` performs the one-time migration to a Home Manager
  # symlink and means future MCP additions belong in this configuration.
  ompMcpConfig = {
    "$schema" =
      "https://raw.githubusercontent.com/can1357/oh-my-pi/main/packages/coding-agent/src/config/mcp-schema.json";
    mcpServers = {
      "context-mode" = {
        type = "stdio";
        command = lib.getExe pkgs.nodejs;
        args = [ "${pkgs.omp-plugins}/node_modules/context-mode/server.bundle.mjs" ];
      };

      camofox = {
        type = "stdio";
        command = lib.getExe pkgs.camofox-mcp-session;
        args = [ "omp" ];
        timeout = 120000;
        env = {
          CAMOFOX_BASE_URL = "http://127.0.0.1:${toString camofoxCfg.apiPort}";
          CAMOFOX_USER_ID = "omp";
        };
      };
    };
  };
in
{
  home.file.".omp/agent/mcp.json" = lib.mkIf camofoxCfg.enable {
    text = builtins.toJSON ompMcpConfig;
    force = true;
  };

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

  # Camofox must be in the same automatically-created Aqua session as the
  # browser window it launches. This is the same known-good default `gui`
  # LaunchAgent domain as Orca above, not a Background user-domain agent that
  # disappears across an unattended reboot.
  launchd.agents.camofox-browser = lib.mkIf camofoxCfg.enable {
    enable = true;
    config = {
      # home-manager supplies the /nix/store readiness wrapper itself.
      ProgramArguments = [ "${camofox}" ];
      RunAtLoad = true;

      # An unexpected server exit is retryable. Throttling prevents a bad
      # package from spinning.
      KeepAlive.SuccessfulExit = false;
      ThrottleInterval = 10;

      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/camofox-browser.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/camofox-browser.log";
    };
  };

  # A pinentry that can both remember and ask.
  #
  # pinentry-mac is right on a laptop and wrong here. It draws its dialog on the
  # console, so over SSH the prompt is invisible and the request waits forever —
  # `ssh -T git@github.com` stops at "Server accepts key" and a commit stops at
  # nothing at all. Its "Save in Keychain" is its own feature, implemented
  # against Keychain Services; the upstream pinentries have no such code. Losing
  # it is the point of the preset below.
  #
  # pkgs/pinentry-keychain: keychain first, and pinentry-tty behind it. tty
  # rather than curses for that fallback — this machine is only ever a remote
  # shell, and a plain prompt beats a full-screen one there. When there is no
  # terminal at all it fails immediately instead of hanging, which is the
  # failure worth having.
  #
  # `program` is named because `writeScriptBin` sets no `meta.mainProgram`, and
  # home-manager would otherwise look for a binary called `pinentry`.
  services.gpg-agent.pinentry.package = lib.mkForce pkgs.pinentry-keychain;
  services.gpg-agent.pinentry.program = lib.mkForce "pinentry-keychain";

  # Restart the runtime when Homebrew has replaced it underneath.
  #
  # Orca comes from a cask and `onActivation.upgrade` is on, so a switch is also
  # when it gets a new version — `brew bundle` runs before home-manager's part
  # of activation. But the LaunchAgent's plist does not change when the
  # application does, so home-manager sees nothing to reload and the old binary
  # keeps running. The machine then reports a version it is not running, which
  # is the kind of wrong that is only noticed much later.
  #
  # The bundle's own version string is the signal, compared against a stamp from
  # last time. No stamp means this is the first switch since this existed:
  # record it and leave the agent alone, because restarting something that was
  # just bootstrapped is noise.
  #
  # `kickstart -k` rather than bootout and bootstrap: it is one call, it works on
  # a job that is already running, and the -k asks for the current instance to be
  # killed first. Sessions are on disk, so the clients reconnect.
  home.activation.orcaRestartOnUpgrade = lib.mkIf cfg.enable (
    lib.hm.dag.entryAfter [ "setupLaunchAgents" ] ''
      orcaPlist=/Applications/Orca.app/Contents/Info.plist
      stamp=${config.home.homeDirectory}/.local/state/nix-darwin/orca-version

      if [ -f "$orcaPlist" ]; then
        version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$orcaPlist" 2>/dev/null || true)

        if [ -n "$version" ]; then
          previous=""
          [ -f "$stamp" ] && previous=$(/usr/bin/head -n 1 "$stamp")

          if [ -n "$previous" ] && [ "$previous" != "$version" ]; then
            $DRY_RUN_CMD /bin/launchctl kickstart -k \
              "gui/$(/usr/bin/id -u)/org.nix-community.home.orca-serve" || true
            echo "  Orca $previous -> $version; the runtime was restarted." >&2
          fi

          $DRY_RUN_CMD /usr/bin/install -d -m 0700 "$(dirname "$stamp")"
          $DRY_RUN_CMD printf '%s\n' "$version" > "$stamp"
        fi
      fi
    ''
  );

  # Unlock the login keychain that automatic login leaves locked. See the
  # script above for why this is needed at all.
  #
  # An agent rather than a daemon, and in the default `gui` domain: a keychain
  # is unlocked for a session, and the session this has to reach is the Aqua one
  # that automatic login just created. RunAtLoad and nothing else — it is one
  # command, and there is no process to keep alive.
  #
  # Not covered: the keychain locks again on sleep if that setting is on. The
  # machine this runs on is configured never to sleep on power, so that has not
  # come up.
  launchd.agents.unlock-login-keychain = lib.mkIf autoLogin.enable {
    enable = true;
    config = {
      ProgramArguments = [ "${unlockKeychain}" ];
      RunAtLoad = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/unlock-login-keychain.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/unlock-login-keychain.log";
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
    pkgs.camofox-mcp-session
    pkgs.cargo
    pkgs.rust-analyzer
    pkgs.rustc
    pkgs.terraform-ls
  ];
}
