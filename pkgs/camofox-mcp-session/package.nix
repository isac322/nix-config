{
  lib,
  writeShellApplication,
  camofox-browser,
}:

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
          # Accepted for a future Codex release or an explicitly wrapped Codex
          # invocation. Codex 0.147.0 does not pass its thread ID to MCP
          # subprocesses, so the process-local fallback below is used today.
          session_id="''${CODEX_THREAD_ID-''${CODEX_SESSION_ID-}}"
          ;;
        omp)
          session_id="''${OMP_SESSION_ID-}"

          # OMP 17.3.4 does not export its session UUID to MCP subprocesses. It
          # does maintain a per-terminal breadcrumb whose second line is the
          # active transcript path. Derive the same UUID from that path so
          # /resume keeps the same Camofox tab namespace.
          if [ -z "$session_id" ]; then
            agent_dir="''${PI_CODING_AGENT_DIR-}"
            if [ -z "$agent_dir" ]; then
              profile="''${OMP_PROFILE-''${PI_PROFILE-}}"
              case "$profile" in
                "" | default) agent_dir="$HOME/.omp/agent" ;;
                *) agent_dir="$HOME/.omp/profiles/$profile/agent" ;;
              esac
            fi

            parent_tty=$(/bin/ps -o tty= -p "$PPID" | /usr/bin/tr -d '[:space:]')
            breadcrumb="$agent_dir/terminal-sessions/$parent_tty"
            if [ -n "$parent_tty" ] && [ "$parent_tty" != "??" ] && [ -f "$breadcrumb" ]; then
              transcript=$(/usr/bin/sed -n '2p' "$breadcrumb")
              transcript_name="''${transcript##*/}"
              transcript_name="''${transcript_name%.jsonl}"
              session_id="''${transcript_name##*_}"
            fi
          fi
          ;;
      esac
    fi

    # A client that exposes no stable logical-session identifier still gets a
    # distinct namespace for this MCP adapter process. It is intentionally not
    # persisted: claiming resume stability without a client ID would merge or
    # misattribute sessions.
    if [ -z "$session_id" ]; then
      session_id=$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')
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
    platforms = [ "aarch64-darwin" ];
  };
}
