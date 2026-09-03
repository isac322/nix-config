# Home Manager configuration for Camofox on every Mac.
{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:

let
  camofoxCfg = osConfig.local.camofox;
  camofoxUrlHandler = pkgs.camofox-url-handler.override {
    apiPort = camofoxCfg.apiPort;
  };

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

  camofoxRemoteConsole = pkgs.writeShellScript "camofox-browser" ''
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

  camofoxCore = pkgs.writeShellScript "camofox-browser" ''
    set -u

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
    export CAMOFOX_HEADLESS=false

    exec ${pkgs.camofox-browser}/bin/camofox-browser
  '';

  camofox = if camofoxCfg.remoteConsole then camofoxRemoteConsole else camofoxCore;
in
{
  config = lib.mkIf camofoxCfg.enable {
    # Camofox runs in the logged-in Aqua session so its headful browser can use
    # the interactive desktop or the server's dedicated remote console.
    launchd.agents.camofox-browser = {
      enable = true;
      config = {
        # home-manager supplies the /nix/store readiness wrapper itself.
        ProgramArguments = [ "${camofox}" ];
        RunAtLoad = true;

        # A core failure stays stopped rather than relaunching the browser or,
        # in remote-console mode, recreating the virtual display in a loop.
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
    # otherwise valid switch.
    home.activation.camofoxUrlHandlerRegistration = lib.hm.dag.entryAfter [ "copyApps" ] ''
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
    '';

    home.packages = [
      # OMP references this package directly. PATH exposure remains for the
      # documented Claude Code and Codex MCP registration commands.
      pkgs.camofox-mcp-session
      # LaunchServices registers this bridge during activation. Selecting it as
      # the default web browser remains a one-time System Settings choice.
      camofoxUrlHandler
    ]
    ++ lib.optionals camofoxCfg.remoteConsole [
      # Keep the stable app path so macOS privacy grants survive store changes.
      pkgs.macvnc
    ];
  };
}
