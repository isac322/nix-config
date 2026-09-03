{
  lib,
  stdenv,
  writeShellApplication,
  camofox-browser,
  coreutils,
  gnused,
  procps,
  util-linux,
}:

let
  ps = if stdenv.hostPlatform.isDarwin then "/bin/ps" else "${procps}/bin/ps";
  uuidgen = if stdenv.hostPlatform.isDarwin then "/usr/bin/uuidgen" else "${util-linux}/bin/uuidgen";
in
writeShellApplication {
  name = "camofox-browser-mcp-session";

  text = ''
    client="''${1-}"
    case "$client" in
      omp | claude | codex) ;;
      *)
        echo "usage: camofox-browser-mcp-session {omp|claude|codex}" >&2
        exit 64
        ;;
    esac

    session_id="''${CAMOFOX_SESSION_ID-}"

    if [ -z "$session_id" ]; then
      case "$client" in
        claude)
          # Claude Code passes this to stdio MCP subprocesses and preserves it
          # when a conversation is resumed.
          session_id="''${CLAUDE_CODE_SESSION_ID-}"
          ;;
        codex)
          # Use a stable thread identifier when Codex exposes one to MCP
          # subprocesses. Releases that do not expose either variable fall
          # back to a process-local namespace below.
          session_id="''${CODEX_THREAD_ID-''${CODEX_SESSION_ID-}}"
          ;;
        omp)
          session_id="''${OMP_SESSION_ID-}"

          # OMP does not export its session UUID to MCP subprocesses. It does
          # maintain a per-terminal breadcrumb whose second line is the active
          # transcript path. Derive the same UUID from that path so /resume
          # keeps the same Camofox tab namespace.
          if [ -z "$session_id" ]; then
            config_dir_name="''${PI_CONFIG_DIR:-.omp}"
            if [ "''${OMP_PROFILE+x}" = x ]; then
              profile="''${OMP_PROFILE-}"
            else
              profile="''${PI_PROFILE-}"
            fi
            case "$profile" in
              "" | default) profile="" ;;
            esac

            if [ -n "$profile" ]; then
              agent_dir="''${PI_CODING_AGENT_DIR:-$HOME/$config_dir_name/profiles/$profile/agent}"
              xdg_state="''${XDG_STATE_HOME-}/omp/profiles/$profile"
              if [ -n "''${XDG_STATE_HOME-}" ] && [ -d "$xdg_state" ]; then
                breadcrumb_dir="$xdg_state/terminal-sessions"
              else
                breadcrumb_dir="$agent_dir/terminal-sessions"
              fi
            else
              default_agent_dir="$HOME/$config_dir_name/agent"
              agent_dir="''${PI_CODING_AGENT_DIR:-$default_agent_dir}"
              xdg_state="''${XDG_STATE_HOME-}/omp"
              if [ "$agent_dir" = "$default_agent_dir" ] && [ -n "''${XDG_STATE_HOME-}" ] && [ -d "$xdg_state" ]; then
                breadcrumb_dir="$xdg_state/terminal-sessions"
              else
                breadcrumb_dir="$agent_dir/terminal-sessions"
              fi
            fi

            parent_tty=$(${ps} -o tty= -p "$PPID" 2>/dev/null | ${coreutils}/bin/tr -d '[:space:]' || true)
            case "$parent_tty" in
              "" | "?" | "??") ;;
              *)
                terminal_id=$(printf '%s' "$parent_tty" | ${coreutils}/bin/tr '/' '-')
                breadcrumb="$breadcrumb_dir/$terminal_id"
                if [ -f "$breadcrumb" ]; then
                  transcript=$(${gnused}/bin/sed -n '2p' "$breadcrumb")
                  transcript_name="''${transcript##*/}"
                  transcript_name="''${transcript_name%.jsonl}"
                  session_id="''${transcript_name##*_}"
                fi
                ;;
            esac
          fi
          ;;
      esac
    fi

    # A client that exposes no stable logical-session identifier still gets a
    # distinct namespace for this MCP adapter process. It is intentionally not
    # persisted: claiming resume stability without a client ID would merge or
    # misattribute sessions.
    if [ -z "$session_id" ]; then
      session_id=$(${uuidgen} | ${coreutils}/bin/tr '[:upper:]' '[:lower:]')
    fi

    case "$session_id" in
      *[!A-Za-z0-9._-]* | "")
        echo "camofox-browser-mcp-session: invalid session identifier" >&2
        exit 65
        ;;
    esac

    export CAMOFOX_USER_ID="''${CAMOFOX_USER_ID-omp}"
    export CAMOFOX_SESSION_KEY="$client-$session_id"

    exec ${camofox-browser}/bin/camofox-browser-mcp
  '';

  meta = {
    description = "Session-aware Camofox MCP adapter launcher";
    license = lib.licenses.mit;
    mainProgram = "camofox-browser-mcp-session";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
    ];
  };
}
