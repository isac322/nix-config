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
  camofoxUrlHandler = pkgs.camofox-url-handler.override {
    apiPort = camofoxCfg.apiPort;
  };
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

  # Both Macs follow Orca's Homebrew cask. The server calls the CLI symlink
  # installed by the cask rather than carrying a separately pinned Nix package.
  orca = "/opt/homebrew/bin/orca";

  # Homebrew installs OrbStack's app and this stable shim. It may not exist yet
  # when the LaunchAgent first runs: nix-darwin does not promise an ordering
  # between its Homebrew activation and home-manager's user activation.
  orb = "/opt/homebrew/bin/orb";
  timeout = lib.getExe' pkgs.coreutils "timeout";
  orbstackDockerConfig = pkgs.writeText "orbstack-docker.json" (
    builtins.toJSON {
      "log-driver" = "local";
      builder.gc = {
        enabled = true;
        policy = [
          {
            all = true;
            reservedSpace = "50GB";
          }
        ];
      };
    }
  );

  orbstackStart = pkgs.writeShellScript "orbstack-start" ''
    set -u

    # launchd supplies almost no PATH. Include OrbStack's Homebrew shim first,
    # then the same declarative profiles used by the other server agents.
    export PATH=/opt/homebrew/bin:/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin

    # The cask and home-manager activations have no ordering contract. Missing
    # prerequisites are therefore a clean one-shot deferral, never a retry loop
    # that can keep an unattended login session busy forever.
    if ! command -v orb >/dev/null 2>&1; then
      if [ ! -d /Applications/OrbStack.app ]; then
        echo "orbstack-start: OrbStack is not installed yet; deferred." >&2
        exit 0
      fi

      /usr/bin/open -gj -a OrbStack

      waited=0
      while [ "$waited" -lt 60 ] && ! command -v orb >/dev/null 2>&1; do
        /bin/sleep 1
        waited=$((waited + 1))
      done
    fi

    if ! command -v orb >/dev/null 2>&1; then
      echo "orbstack-start: orb CLI unavailable after 60s; deferred." >&2
      exit 0
    fi

    # Home Manager installs the daemon configuration before it loads user
    # agents. Referencing the generated store file here also changes this
    # script's path when the JSON changes, which makes launchd reload the agent.
    if ! /usr/bin/cmp -s ${orbstackDockerConfig} \
      ${config.home.homeDirectory}/.orbstack/config/docker.json; then
      echo "orbstack-start: Docker engine config is not installed; deferred." >&2
      exit 0
    fi
    # Do not add another spawn attempt behind a helper already stuck in
    # macOS's exit state. `kill -9`, even as root, cannot advance that state.
    if /bin/ps -axo state=,command= |
      /usr/bin/awk '$1 ~ /E/ && index($0, "(OrbStack Helper)") { found = 1 } END { exit !found }'; then
      echo "orbstack-start: stale exiting OrbStack Helper found; deferred until reboot." >&2
      exit 0
    fi

    # OrbStack enables Rosetta by default and otherwise opens a GUI installer
    # that blocks forever on this headless session. softwareupdate is
    # non-interactive with --agree-to-license, and the store-pinned timeout
    # kills its whole command group if Apple’s updater stops making progress.
    if ! /usr/sbin/pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; then
      if ! ${timeout} -k 5 180 /usr/sbin/softwareupdate \
        --install-rosetta --agree-to-license; then
        echo "orbstack-start: Rosetta installation failed or timed out; deferred." >&2
        exit 0
      fi
    fi

    run_orb() {
      ${timeout} -k 5 30 ${orb} "$@"
    }

    # Leave one CPU and 8 GiB to macOS, Orca and Camofox. Every command is
    # bounded separately; a failed setting leaves a diagnostic and stops this
    # one-shot agent rather than spawning another invisible retry.
    configure_orbstack() {
      run_orb config set setup.use_admin false &&
        run_orb config set cpu 10 &&
        run_orb config set memory_mib 28672 &&
        run_orb config set rosetta true &&
        run_orb config set k8s.enable false &&
        run_orb config set docker.set_context true
    }

    if ! configure_orbstack; then
      echo "orbstack-start: configuration failed or timed out; deferred." >&2
      exit 0
    fi

    # Never stop a running VM from activation. OrbStack can leave its helper in
    # an unkillable macOS exit state when shutdown is interrupted; that blocks
    # every later start until reboot. A running instance keeps serving
    # containers and picks up changed engine settings on its next ordinary
    # reboot.
    if run_orb status >/dev/null 2>&1; then
      echo "orbstack-start: already running; settings apply on the next restart." >&2
      exit 0
    fi


    if ! ${timeout} -k 5 60 ${orb} start; then
      # OrbStack's spawn helper double-forks out of timeout's process group.
      # Remove only that failed start helper so it cannot accumulate behind a
      # later attempt; the VM manager and running containers do not match.
      /usr/bin/pkill -9 -f \
        "/Applications/OrbStack.app/Contents/Frameworks/OrbStack Helper.app/Contents/MacOS/OrbStack Helper spawn-daemon" \
        >/dev/null 2>&1 || true
      echo "orbstack-start: startup failed or timed out." >&2
    fi
  '';

  orcaServe = pkgs.writeShellScript "orca-serve" ''
    set -u

    # A launchd agent inherits almost no PATH, and `orca serve` shells out to
    # everything the agents need — git, claude, codex — from the server's own
    # environment rather than the client's. These are, in order: home-manager's
    # profile, nix-darwin's system profile, Homebrew, and the base system.
    export PATH=/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin

    if [ ! -x ${orca} ]; then
      # Homebrew activation and home-manager activation have no promised
      # ordering. Fail so KeepAlive retries after the cask installs its CLI.
      echo "orca-serve: ${orca} is missing — retrying later." >&2
      exit 1
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

  hideApplicationSource = pkgs.writeText "hide-application.m" ''
    #import <AppKit/AppKit.h>
    #include <stdlib.h>

    int main(int argc, char **argv) {
      @autoreleasepool {
        if (argc != 2) {
          return 2;
        }
        pid_t pid = (pid_t)strtol(argv[1], NULL, 10);
        NSRunningApplication *application =
          [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        if (application == nil) {
          return 1;
        }
        [application hide];
        return 0;
      }
    }
  '';
  hideApplication = pkgs.runCommandCC "hide-application" { } ''
    mkdir -p "$out/bin"
    "$CC" -fobjc-arc -framework AppKit \
      ${hideApplicationSource} -o "$out/bin/hide-application"
  '';

  camofox = pkgs.writeShellScript "camofox-browser" ''
    set -u

    # OMP reaches the browser API through loopback. Remote observation remains
    # HTTPS noVNC over WireGuard; neither the control API nor the VNC backend
    # needs a network-facing listener.
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

    # Headful selection belongs to the service. The packaged server wrapper
    # owns its immutable executable, runtime-download, and telemetry policy.
    export CAMOFOX_HEADLESS=false

    deskpadApp=${lib.escapeShellArg "${pkgs.deskpad}/Applications/DeskPad.app/Contents/MacOS/DeskPad"}
    beforeDisplaySpecs=""
    deskpadDisplayId=""
    deskpadPersistentId=""
    restoreDisplayX=0
    layoutConfigured=0
    deskpadPid=0
    vncPid=0
    browserPid=0
    displayAwakePid=0
    restoreDisplayLayout() {
      [ "$layoutConfigured" -eq 1 ] || return 0

      restoreArgs=()
      while IFS=$'\t' read -r \
        displayId displayResolution displayHertz displayColorDepth \
        displayScaling displayRotation displayEnabled displayOrigin; do
        [ -n "$displayId" ] || continue
        if [ -z "$displayResolution" ] ||
          [ -z "$displayHertz" ] ||
          [ -z "$displayColorDepth" ] ||
          [ -z "$displayScaling" ] ||
          [ -z "$displayRotation" ] ||
          [ -z "$displayEnabled" ] ||
          [ -z "$displayOrigin" ]; then
          echo "camofox-browser: could not restore incomplete display $displayId." >&2
          return 1
        fi
        restoreArgs+=(
          "id:$displayId res:$displayResolution hz:$displayHertz color_depth:$displayColorDepth enabled:$displayEnabled scaling:$displayScaling origin:$displayOrigin degree:$displayRotation"
        )
      done <<< "$beforeDisplaySpecs"
      if ! currentDisplayState=$(${pkgs.displayplacer}/bin/displayplacer list 2>/dev/null); then
        echo "camofox-browser: could not read displays while restoring the physical layout." >&2
        return 1
      fi
      if printf '%s\n' "$currentDisplayState" |
        /usr/bin/awk -v id="$deskpadDisplayId" '
          $1 == "Contextual" && $2 == "screen" && $3 == "id:" && $4 == id {
            found = 1
          }
          END { exit !found }
        '; then
        restoreArgs+=(
          "id:$deskpadDisplayId res:${toString camofoxCfg.displayWidth}x${toString camofoxCfg.displayHeight} hz:60 color_depth:4 enabled:true scaling:off origin:($restoreDisplayX,0) degree:0"
        )
      fi

      if ! ${pkgs.displayplacer}/bin/displayplacer "''${restoreArgs[@]}"; then
        echo "camofox-browser: could not restore the physical display layout." >&2
        return 1
      fi
      layoutConfigured=0
    }
    configureDeskPadLayout() {
      # displayplacer does not make a screen main merely because its origin is
      # (0,0). Configure the whole arrangement in one transaction instead.
      displayArgs=(
        "id:$deskpadDisplayId res:${toString camofoxCfg.displayWidth}x${toString camofoxCfg.displayHeight} hz:60 color_depth:4 enabled:true scaling:off origin:(0,0) degree:0"
      )
      if ! availableDisplayState=$(${pkgs.displayplacer}/bin/displayplacer list 2>/dev/null); then
        echo "camofox-browser: could not read displays while configuring DeskPad." >&2
        return 1
      fi
      displayX=${toString camofoxCfg.displayWidth}
      while IFS=$'\t' read -r \
        displayId displayResolution displayHertz displayColorDepth \
        displayScaling displayRotation displayEnabled displayOrigin; do
        [ -n "$displayId" ] || continue
        if [ -z "$displayResolution" ] ||
          [ -z "$displayHertz" ] ||
          [ -z "$displayColorDepth" ] ||
          [ -z "$displayScaling" ] ||
          [ -z "$displayRotation" ] ||
          [ -z "$displayEnabled" ] ||
          [ -z "$displayOrigin" ]; then
          echo "camofox-browser: could not preserve display $displayId while making DeskPad main." >&2
          return 1
        fi
        if ! printf '%s\n' "$availableDisplayState" |
          /usr/bin/awk -v id="$displayId" '
            $1 == "Contextual" && $2 == "screen" && $3 == "id:" {
              matches = ($4 == id)
              found = found || matches
              next
            }
            matches && $1 == "Enabled:" && $2 == "true" { enabled = 1 }
            END { exit !(found && enabled) }
          '; then
          continue
        fi
        displayArgs+=(
          "id:$displayId res:$displayResolution hz:$displayHertz color_depth:$displayColorDepth enabled:$displayEnabled scaling:$displayScaling origin:($displayX,0) degree:$displayRotation"
        )
        displayPixelWidth=''${displayResolution%%x*}
        displayX=$((displayX + displayPixelWidth))
      done <<< "$beforeDisplaySpecs"

      layoutConfigured=1
      if ! ${pkgs.displayplacer}/bin/displayplacer "''${displayArgs[@]}"; then
        echo "camofox-browser: could not configure DeskPad display $deskpadDisplayId." >&2
        return 1
      fi

      if ! configuredDisplayState=$(${pkgs.displayplacer}/bin/displayplacer list 2>/dev/null) ||
        ! printf '%s\n' "$configuredDisplayState" |
          /usr/bin/awk \
            -v id="$deskpadDisplayId" \
            -v expectedResolution="${toString camofoxCfg.displayWidth}x${toString camofoxCfg.displayHeight}" '
              $1 == "Persistent" && found { exit }
              $1 == "Contextual" && $2 == "screen" && $3 == "id:" && $4 == id {
                found = 1
                next
              }
              found && $1 == "Resolution:" && $2 == expectedResolution { resolution = 1 }
              found && $1 == "Enabled:" && $2 == "true" { enabled = 1 }
              found && index($0, "Origin: (0,0) - main display") { main = 1 }
              END { exit !(found && resolution && enabled && main) }
            '; then
        echo "camofox-browser: DeskPad display $deskpadDisplayId did not become the configured main display." >&2
        return 1
      fi
    }
    waitForProcessExit() {
      targetPid=$1
      maxChecks=$2
      checks=0
      while /bin/kill -0 "$targetPid" 2>/dev/null; do
        processState=$(/bin/ps -o state= -p "$targetPid" 2>/dev/null |
          /usr/bin/tr -d '[:space:]')
        case "$processState" in
          "" | Z*) break ;;
        esac
        [ "$checks" -ge "$maxChecks" ] && return 1
        /bin/sleep 1
        checks=$((checks + 1))
      done
      # Reap an original child after observing its exit. For an adopted process
      # this returns immediately because the shell is not its parent.
      wait "$targetPid" 2>/dev/null || true
      return 0
    }
    stopChildren() {
      trap - TERM INT
      if [ "$browserPid" -gt 0 ]; then
        /bin/kill "$browserPid" 2>/dev/null || true
      fi
      if [ "$vncPid" -gt 0 ]; then
        /bin/kill "$vncPid" 2>/dev/null || true
      fi
      if [ "$deskpadPid" -gt 0 ]; then
        restoreDisplayLayout || true
        /bin/kill "$deskpadPid" 2>/dev/null || true
      fi
      if [ "$displayAwakePid" -gt 0 ]; then
        /bin/kill "$displayAwakePid" 2>/dev/null || true
      fi
      if [ "$browserPid" -gt 0 ]; then
        wait "$browserPid" 2>/dev/null || true
      fi
      if [ "$vncPid" -gt 0 ]; then
        wait "$vncPid" 2>/dev/null || true
      fi
      if [ "$deskpadPid" -gt 0 ] &&
        ! waitForProcessExit "$deskpadPid" 10; then
        echo "camofox-browser: DeskPad $deskpadPid did not exit after 10s; killing it." >&2
        /bin/kill -KILL "$deskpadPid" 2>/dev/null || true
        waitForProcessExit "$deskpadPid" 5 || true
      fi
      if [ "$displayAwakePid" -gt 0 ]; then
        wait "$displayAwakePid" 2>/dev/null || true
      fi
    }
    terminate() {
      stopChildren
      exit 143
    }
    trap terminate TERM INT

    if ! beforeDisplayState=$(${pkgs.displayplacer}/bin/displayplacer list 2>/dev/null); then
      echo "camofox-browser: could not read displays before starting DeskPad." >&2
      exit 1
    fi
    beforeEnabledDisplayIds=$(printf '%s\n' "$beforeDisplayState" |
      /usr/bin/awk '
        $1 == "Contextual" && $2 == "screen" && $3 == "id:" {
          id = $4
          next
        }
        $1 == "Enabled:" && $2 == "true" && id != "" { print id }
      ' |
      /usr/bin/tr '\n' ' ')
    beforeDisplaySpecs=$(printf '%s\n' "$beforeDisplayState" |
      /usr/bin/awk '
        function emit() {
          if (id != "" && enabled == "true") {
            print id "\t" resolution "\t" hertz "\t" colorDepth "\t" scaling "\t" rotation "\t" enabled "\t" origin
          }
        }
        $1 == "Contextual" && $2 == "screen" && $3 == "id:" {
          emit()
          id = $4
          resolution = hertz = colorDepth = scaling = rotation = enabled = origin = ""
          next
        }
        $1 == "Resolution:" { resolution = $2 }
        $1 == "Hertz:" { hertz = $2 }
        $1 == "Color" && $2 == "Depth:" { colorDepth = $3 }
        $1 == "Scaling:" { scaling = $2 }
        $1 == "Rotation:" { rotation = $2 }
        $1 == "Enabled:" { enabled = $2 }
        $1 == "Origin:" { origin = $2 }
        END { emit() }
      ')
    restoreDisplayX=$(printf '%s\n' "$beforeDisplayState" |
      /usr/bin/awk '
        function emit() {
          if (enabled != "true" || width == "" || origin == "") {
            return
          }
          gsub(/[()]/, "", origin)
          split(origin, coordinates, ",")
          right = coordinates[1] + width
          if (right > maxRight) {
            maxRight = right
          }
        }
        $1 == "Contextual" && $2 == "screen" && $3 == "id:" {
          emit()
          width = origin = enabled = ""
          next
        }
        $1 == "Resolution:" {
          split($2, resolution, "x")
          width = resolution[1]
        }
        $1 == "Origin:" { origin = $2 }
        $1 == "Enabled:" { enabled = $2 }
        END {
          emit()
          print maxRight + 0
        }
      ')

    # ScreenCaptureKit stops when macOS powers the virtual display down. Keep
    # display idle sleep inhibited for exactly the lifetime of this stack.
    /usr/bin/caffeinate -d &
    displayAwakePid=$!

    "$deskpadApp" &
    deskpadPid=$!

    waited=0
    while ! ${hideApplication}/bin/hide-application "$deskpadPid"; do
      if ! /bin/kill -0 "$deskpadPid" 2>/dev/null; then
        wait "$deskpadPid"
        status=$?
        [ "$status" -eq 0 ] && status=1
        echo "camofox-browser: DeskPad exited before it could be hidden." >&2
        exit "$status"
      fi
      if [ "$waited" -ge 10 ]; then
        echo "camofox-browser: could not hide DeskPad after 10s." >&2
        stopChildren
        exit 1
      fi
      /bin/sleep 1
      waited=$((waited + 1))
    done

    # A closed lid can leave the new virtual display powered off even though
    # DeskPad is running. Wake it once; the lifetime assertion above keeps it
    # available to ScreenCaptureKit afterward.
    /usr/bin/caffeinate -u -t 5

    deskpadDisplayId=""
    waited=0
    while [ "$waited" -lt 30 ]; do
      if ! /bin/kill -0 "$deskpadPid" 2>/dev/null; then
        wait "$deskpadPid"
        status=$?
        [ "$status" -eq 0 ] && status=1
        echo "camofox-browser: DeskPad exited before creating its display." >&2
        exit "$status"
      fi

      if afterDisplayState=$(${pkgs.displayplacer}/bin/displayplacer list 2>/dev/null); then
        afterEnabledDisplayIds=$(printf '%s\n' "$afterDisplayState" |
          /usr/bin/awk '
            $1 == "Contextual" && $2 == "screen" && $3 == "id:" {
              id = $4
              next
            }
            $1 == "Enabled:" && $2 == "true" && id != "" { print id }
          ' |
          /usr/bin/tr '\n' ' ')
        candidateDisplayId=""
        candidateDisplayCount=0
        for displayId in $afterEnabledDisplayIds; do
          case " $beforeEnabledDisplayIds " in
            *" $displayId "*) ;;
            *)
              candidateDisplayId=$displayId
              candidateDisplayCount=$((candidateDisplayCount + 1))
              ;;
          esac
        done
        if [ "$candidateDisplayCount" -eq 1 ]; then
          deskpadDisplayId=$candidateDisplayId
          break
        fi
        if [ "$candidateDisplayCount" -gt 1 ]; then
          echo "camofox-browser: DeskPad enabled multiple candidate displays; refusing an ambiguous selection." >&2
          stopChildren
          exit 1
        fi
      fi

      /bin/sleep 1
      waited=$((waited + 1))
    done
    if [ -z "$deskpadDisplayId" ]; then
      echo "camofox-browser: DeskPad display was not ready after 30s." >&2
      stopChildren
      exit 1
    fi

    deskpadPersistentId=$(printf '%s\n' "$afterDisplayState" |
      /usr/bin/awk -v id="$deskpadDisplayId" '
        $1 == "Persistent" && $2 == "screen" && $3 == "id:" {
          persistentId = $4
          next
        }
        $1 == "Contextual" && $2 == "screen" && $3 == "id:" && $4 == id {
          print persistentId
          exit
        }
      ')
    if [ -z "$deskpadPersistentId" ]; then
      echo "camofox-browser: could not identify DeskPad display $deskpadDisplayId persistently." >&2
      stopChildren
      exit 1
    fi

    if ! configureDeskPadLayout; then
      stopChildren
      exit 1
    fi

    ${pkgs.camofox-browser}/bin/camofox-browser &
    browserPid=$!

    export MACVNC_EXCLUDE_BUNDLE_ID=com.stengo.DeskPad
    macvnc=${lib.escapeShellArg "${config.home.homeDirectory}/Applications/Home Manager Apps/macVNC.app/Contents/MacOS/macVNC"}
    set -- \
      -rfbport ${lib.escapeShellArg (toString camofoxCfg.vncPort)} \
      -rfbportv6 0 \
      -listen localhost \
      -rfbauth ${lib.escapeShellArg camofoxCfg.rfbAuthFile} \
      -alwaysshared \
      -dontdisconnect
    permissionArgs=()
    ${lib.optionalString camofoxCfg.vncViewOnly ''
      set -- -viewonly "$@"
      permissionArgs=(-viewonly)
    ''}

    vncAttempts=0
    vncMaxAttempts=3
    vncDisabled=0
    vncPermissionUnavailable=0
    vncReadyLogged=0
    vncReadinessChecks=0
    while true; do
      if ! /bin/kill -0 "$displayAwakePid" 2>/dev/null; then
        status=0
        wait "$displayAwakePid" || status=$?
        [ "$status" -eq 0 ] && status=1
        echo "camofox-browser: display sleep assertion exited with status $status; stopping the stack." >&2
        stopChildren
        exit "$status"
      fi

      if ! /bin/kill -0 "$deskpadPid" 2>/dev/null; then
        deadDeskpadPid=$deskpadPid
        status=1
        waitForProcessExit "$deadDeskpadPid" 1 || true

        # DeskPad can replace its process while preserving the same virtual
        # display. Adopt that singleton instead of taking down a healthy VNC
        # stack because the originally launched PID disappeared.
        replacementPid=""
        replacementAttempts=0
        while [ "$replacementAttempts" -lt 5 ]; do
          replacementCount=0
          for candidatePid in $(/bin/ps -axo pid=,command= |
            /usr/bin/awk -v executable="$deskpadApp" '
              $2 == executable && NF == 2 { print $1 }
            '); do
            if /bin/kill -0 "$candidatePid" 2>/dev/null; then
              replacementPid=$candidatePid
              replacementCount=$((replacementCount + 1))
            fi
          done

          replacementDisplayId=""
          if [ "$replacementCount" -eq 1 ] &&
            replacementDisplayState=$(${pkgs.displayplacer}/bin/displayplacer list 2>/dev/null); then
            replacementDisplayId=$(printf '%s\n' "$replacementDisplayState" |
              /usr/bin/awk -v persistentId="$deskpadPersistentId" '
                $1 == "Persistent" && $2 == "screen" && $3 == "id:" {
                  matches = ($4 == persistentId)
                  next
                }
                matches && $1 == "Contextual" && $2 == "screen" && $3 == "id:" {
                  print $4
                  exit
                }
              ')
            [ -n "$replacementDisplayId" ] && break
          fi
          replacementPid=""
          [ "$replacementCount" -gt 1 ] && break
          /bin/sleep 1
          replacementAttempts=$((replacementAttempts + 1))
        done

        if [ -n "$replacementPid" ]; then
          deskpadPid=$replacementPid
          deskpadDisplayId=$replacementDisplayId
          if ! configureDeskPadLayout; then
            replacementPid=""
          else
            hideAttempts=0
            while ! ${hideApplication}/bin/hide-application "$deskpadPid"; do
              if ! /bin/kill -0 "$deskpadPid" 2>/dev/null; then
                replacementPid=""
                break
              fi
              if [ "$hideAttempts" -ge 5 ]; then
                echo "camofox-browser: replacement DeskPad $deskpadPid could not be hidden; capture exclusion remains active." >&2
                break
              fi
              /bin/sleep 1
              hideAttempts=$((hideAttempts + 1))
            done
          fi
        fi

        if [ -n "$replacementPid" ] && /bin/kill -0 "$deskpadPid" 2>/dev/null; then
          echo "camofox-browser: DeskPad replaced PID $deadDeskpadPid with $deskpadPid; continuing the stack." >&2
          continue
        fi

        echo "camofox-browser: DeskPad exited with status $status; stopping the stack." >&2
        stopChildren
        exit "$status"
      fi

      if ! /bin/kill -0 "$browserPid" 2>/dev/null; then
        status=0
        wait "$browserPid" || status=$?
        [ "$status" -eq 0 ] && status=1
        echo "camofox-browser: browser service exited with status $status; stopping the stack." >&2
        stopChildren
        exit "$status"
      fi

      if [ "$vncPid" -gt 0 ] && ! /bin/kill -0 "$vncPid" 2>/dev/null; then
        status=0
        wait "$vncPid" || status=$?
        echo "camofox-browser: macVNC exited with status $status; Camofox and DeskPad remain active." >&2
        vncPid=0
        vncReadyLogged=0
        vncReadinessChecks=0
      fi

      if [ "$vncPid" -eq 0 ] && [ "$vncDisabled" -eq 0 ]; then
        permissionError=""
        if ! permissionError=$("$macvnc" "''${permissionArgs[@]}" -checkpermissions 2>&1); then
          if [ "$vncPermissionUnavailable" -eq 0 ]; then
            echo "camofox-browser: macVNC unavailable: $permissionError" >&2
            echo "camofox-browser: waiting for Screen Recording approval; checking again every 10s." >&2
          fi
          vncPermissionUnavailable=1
          vncAttempts=0
        else
          if [ "$vncPermissionUnavailable" -eq 1 ]; then
            echo "camofox-browser: macVNC permissions are available; resuming VNC startup." >&2
          fi
          vncPermissionUnavailable=0
          if [ "$vncAttempts" -ge "$vncMaxAttempts" ]; then
            echo "camofox-browser: macVNC failed $vncAttempts consecutive starts; continuing without VNC." >&2
            vncDisabled=1
          else
            vncAttempts=$((vncAttempts + 1))
            "$macvnc" "$@" &
            vncPid=$!
            vncReadinessChecks=0
          fi
        fi
      fi

      if [ "$vncPid" -gt 0 ] && [ "$vncReadyLogged" -eq 0 ]; then
        if /usr/bin/nc -z 127.0.0.1 ${lib.escapeShellArg (toString camofoxCfg.vncPort)}; then
          echo "camofox-browser: macVNC ready on 127.0.0.1:${toString camofoxCfg.vncPort}." >&2
          vncReadyLogged=1
          vncAttempts=0
        else
          vncReadinessChecks=$((vncReadinessChecks + 1))
          if [ "$vncReadinessChecks" -ge 3 ]; then
            echo "camofox-browser: macVNC did not become ready after 30s; retrying it alone." >&2
            /bin/kill "$vncPid" 2>/dev/null || true
          fi
        fi
      fi

      /bin/sleep 10
    done
  '';

in
{
  # The server Mac runs the single evolve worker. Storage is the user's
  # existing external S3 backend; this role does not deploy an object store.
  local.skillclaw.evolve.enable = true;

  # OrbStack is a user application, not a root daemon. The server already
  # creates an Aqua session automatically for Orca and Camofox, so a LaunchAgent
  # is the reliable reboot path here as well. It is deliberately one-shot:
  # every external operation in the wrapper is bounded, and a prerequisite
  # failure waits for the next login or switch instead of retrying forever.
  launchd.agents.orbstack = {
    enable = true;
    config = {
      ProgramArguments = [ "${orbstackStart}" ];
      RunAtLoad = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/orbstack.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/orbstack.log";
    };
  };

  # OrbStack reads standard dockerd configuration from this path. The local
  # logging driver rotates compact container logs by default, and the BuildKit
  # GC reserve keeps 50 GB of reusable build cache while still allowing the
  # daemon to reclaim everything above it under pressure. `force` replaces the
  # mutable empty file created by OrbStack.
  home.file.".orbstack/config/docker.json" = {
    source = orbstackDockerConfig;
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

      # The wrapper retries only macVNC, without touching DeskPad or Camofox.
      # A core failure stays stopped so launchd never recreates the virtual
      # display in a loop.
      KeepAlive = false;

      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/camofox-browser.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/camofox-browser.log";
    };
  };

  # macOS must not launch Camoufox.app directly for ordinary links. Doing so
  # would create a second, unmanaged Firefox process outside the Camofox
  # daemon's BrowserContext, session isolation, and persistent cookie store.
  # Camofox.app is a small LaunchServices bridge instead: it receives HTTP and
  # HTTPS URLs and creates tabs in the daemon's fixed `default-browser`
  # namespace under the shared `omp` user.
  #
  # Register the copied app, but leave the default-browser choice to System
  # Settings. duti maps URL schemes to dynamic UTIs on current macOS and
  # LSSetDefaultRoleHandlerForContentType rejects those writes with error -50;
  # making that user preference an activation prerequisite prevents an
  # otherwise valid remote switch.
  home.activation.camofoxUrlHandlerRegistration = lib.mkIf camofoxCfg.enable (
    lib.hm.dag.entryAfter [ "copyApps" ] ''
      appPath=${lib.escapeShellArg "${config.home.homeDirectory}/Applications/Home Manager Apps/Camofox.app"}
      lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

      if [ -d "$appPath" ]; then
        $DRY_RUN_CMD "$lsregister" -f "$appPath"
      elif [ -n "$DRY_RUN_CMD" ]; then
        echo "camofox-url-handler: would register $appPath." >&2
      else
        echo "camofox-url-handler: $appPath is missing after copyApps." >&2
        exit 1
      fi
    ''
  );

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
  # `cargo fmt` is an external Cargo subcommand, not part of the cargo
  # derivation. nixpkgs supplies its `cargo-fmt` executable through the
  # separate rustfmt package, so it must be listed explicitly too.
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
    # OMP references this package directly. PATH exposure remains for the
    # documented Claude Code and Codex MCP registration commands.
    pkgs.camofox-mcp-session
    # LaunchServices registers this bridge during activation. Selecting it as
    # the default web browser remains a one-time System Settings choice.
    camofoxUrlHandler

    # The LaunchAgent deliberately uses this stable app path so macOS privacy
    # grants survive store-path changes. DeskPad needs no equivalent grant and
    # runs directly from its Nix store path.
    pkgs.macvnc

    pkgs.cargo
    pkgs.rust-analyzer
    pkgs.rustc
    pkgs.rustfmt
    pkgs.terraform-ls
  ];
}
