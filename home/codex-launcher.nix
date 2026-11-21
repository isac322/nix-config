# The `codex` on PATH: runs the real binary, injecting ONLY the runtime URL
# overrides (`model_providers.*.base_url`, `experimental_realtime_ws_base_url`)
# that Codex cannot read from environment variables.
#
# All static declarative settings (provider definitions, headers, capabilities,
# `service_tier`, `web_search`, `[features]`, and `[mcp_servers.*]`) live in
# `/etc/codex/config.toml` (modules/common.nix), leaving `~/.codex/config.toml`
# for Codex's mutable state and per-user overrides.
#
# Keeping private proxy origins in env / `~/.config/agents/env.sh` keeps them
# out of this repository and the world-readable Nix store while covering
# interactive shells, headless callers, launchd agents, and `exec`/`app-server`.
#
# Setting `CODEX_NO_CUSTOM_PROVIDER=1` selects `model_provider="openai"` before
# user arguments so the default system `custom` provider is bypassed.
#
# The script runs under /bin/sh and execs the real binary directly so on macOS
# no non-platform executable sits in front of `codex` and TCC still charges
# `codex`'s own grant.
{
  writeTextFile,
}:
target:
writeTextFile {
  name = "codex-launcher";
  destination = "/bin/codex";
  executable = true;
  text = ''
    #!/bin/sh
    if [ $# -gt 0 ]; then
      case "$1" in
        -h|--help|-V|--version|help|completion)
          exec "${target}" "$@"
          ;;
      esac
    fi

    if [ "''${CODEX_NO_CUSTOM_PROVIDER:-}" = 1 ]; then
      exec "${target}" -c 'model_provider="openai"' "$@"
    fi

    # Scrubbed non-interactive callers (such as launchd services) never run
    # `.zshenv`, so fall back to `~/.config/agents/env.sh` only when neither
    # origin variable is present in the process environment.
    if [ -z "''${CODEX_CUSTOM_ORIGIN+set}" ] && [ -z "''${CLIPROXYAPI_ORIGIN+set}" ] \
      && [ -n "''${HOME:-}" ] && [ -r "$HOME/.config/agents/env.sh" ]; then
      . "$HOME/.config/agents/env.sh"
    fi

    _nl=$(printf '\nX')
    _nl=''${_nl%X}
    _cr=$(printf '\r')
    _tab=$(printf '\t')
    _bs='\'
    _dq='"'
    _sq="'"

    trim_ws() {
      _tw="$1"
      while :; do
        case "$_tw" in
          " "*|"$_tab"*) _tw="''${_tw#?}" ;;
          *) break ;;
        esac
      done
      while :; do
        case "$_tw" in
          *" "|*"$_tab") _tw="''${_tw%?}" ;;
          *) break ;;
        esac
      done
      printf '%s' "$_tw"
    }

    normalize_origin() {
      _raw="$1"
      while :; do
        case "$_raw" in
          */) _raw="''${_raw%/}" ;;
          *) break ;;
        esac
      done
      case "$_raw" in
        ""|"http://"|"https://")
          return 0
          ;;
        http://*|https://*)
          ;;
        *)
          return 0
          ;;
      esac
      case "''${_raw#*://}" in
        ""|/*)
          return 0
          ;;
      esac
      case "$_raw" in
        *" "*|*"$_tab"*|*"$_nl"*|*"$_cr"*|*"$_bs"*|*"$_dq"*)
          return 0
          ;;
      esac
      printf '%s' "$_raw"
    }

    extract_toml_quoted() {
      _q="$1"
      case "$_q" in
        "$_dq"*)
          _q="''${_q#?}"
          case "$_q" in
            *"$_dq"*)
              printf '%s' "''${_q%%"$_dq"*}"
              ;;
          esac
          ;;
        "$_sq"*)
          _q="''${_q#?}"
          case "$_q" in
            *"$_sq"*)
              printf '%s' "''${_q%%"$_sq"*}"
              ;;
          esac
          ;;
      esac
    }

    _custom_origin=$(normalize_origin "''${CODEX_CUSTOM_ORIGIN:-}")
    _cpa_origin=$(normalize_origin "''${CLIPROXYAPI_ORIGIN:-}")

    _cli_provider=""
    _cli_realtime_set=0

    record_cfg_override() {
      _kv="$1"
      case "$_kv" in
        *=*)
          _k=$(trim_ws "''${_kv%%=*}")
          _v=$(trim_ws "''${_kv#*=}")
          case "$_k" in
            model_provider)
              case "$_v" in
                "$_dq"*"$_dq")
                  _v="''${_v#?}"
                  _v="''${_v%?}"
                  ;;
                "$_sq"*"$_sq")
                  _v="''${_v#?}"
                  _v="''${_v%?}"
                  ;;
              esac
              _cli_provider="$_v"
              ;;
            experimental_realtime_ws_base_url)
              _cli_realtime_set=1
              ;;
          esac
          ;;
      esac
    }

    _expect_cfg=0
    for _arg in "$@"; do
      if [ "$_expect_cfg" = 1 ]; then
        record_cfg_override "$_arg"
        _expect_cfg=0
        continue
      fi
      case "$_arg" in
        --)
          break
          ;;
        -c|--config)
          _expect_cfg=1
          ;;
        -c=*)
          record_cfg_override "''${_arg#-c=}"
          ;;
        --config=*)
          record_cfg_override "''${_arg#--config=}"
          ;;
        --*)
          ;;
        -c*=*)
          record_cfg_override "''${_arg#-c}"
          ;;
      esac
    done

    _file_provider=""
    _file_realtime_set=0
    _codex_home="''${CODEX_HOME:-}"
    if [ -z "$_codex_home" ] && [ -n "''${HOME:-}" ]; then
      _codex_home="$HOME/.codex"
    fi
    if [ -n "$_codex_home" ] && [ -r "$_codex_home/config.toml" ] && [ -s "$_codex_home/config.toml" ]; then
      while IFS= read -r _line || [ -n "$_line" ]; do
        _line="''${_line%$_cr}"
        _t=$(trim_ws "$_line")
        case "$_t" in
          ""|"#"*)
            continue
            ;;
          "["*)
            break
            ;;
          *=*)
            _k=$(trim_ws "''${_t%%=*}")
            _v=$(trim_ws "''${_t#*=}")
            case "$_k" in
              model_provider)
                _pv=$(extract_toml_quoted "$_v")
                if [ -n "$_pv" ]; then
                  _file_provider="$_pv"
                fi
                ;;
              experimental_realtime_ws_base_url)
                _rv=$(extract_toml_quoted "$_v")
                if [ -n "$_rv" ]; then
                  _file_realtime_set=1
                fi
                ;;
            esac
            ;;
        esac
      done < "$_codex_home/config.toml"
    fi

    _user_provider="''${_cli_provider:-$_file_provider}"
    _user_realtime_set=0
    if [ "$_cli_realtime_set" -eq 1 ] || [ "$_file_realtime_set" -eq 1 ]; then
      _user_realtime_set=1
    fi

    if [ -n "$_user_provider" ]; then
      _effective_provider="$_user_provider"
      _fallback_provider=""
    elif [ -n "$_custom_origin" ]; then
      _effective_provider="custom"
      _fallback_provider=""
    elif [ -n "$_cpa_origin" ]; then
      _effective_provider="cliproxyapi"
      _fallback_provider="cliproxyapi"
    else
      _effective_provider="openai"
      _fallback_provider="openai"
    fi

    _orig_n=$#

    if [ -n "$_fallback_provider" ]; then
      set -- "$@" -c "model_provider=\"''${_fallback_provider}\""
    fi
    if [ -n "$_custom_origin" ]; then
      set -- "$@" -c "model_providers.custom.base_url=\"''${_custom_origin}/openai/backend-api/codex\""
    fi
    if [ -n "$_cpa_origin" ]; then
      set -- "$@" -c "model_providers.cliproxyapi.base_url=\"''${_cpa_origin}/v1\""
    fi
    if [ "$_user_realtime_set" -eq 0 ]; then
      if [ "$_effective_provider" = "custom" ] && [ -n "$_custom_origin" ]; then
        set -- "$@" -c "experimental_realtime_ws_base_url=\"''${_custom_origin}/openai/backend-api/codex/realtime\""
      elif [ "$_effective_provider" = "cliproxyapi" ] && [ -n "$_cpa_origin" ]; then
        set -- "$@" -c "experimental_realtime_ws_base_url=\"''${_cpa_origin}/v1/realtime\""
      fi
    fi

    _i=0
    while [ "$_i" -lt "$_orig_n" ]; do
      _a="$1"
      shift
      set -- "$@" "$_a"
      _i=$((_i + 1))
    done

    exec "${target}" "$@"
  '';
  checkPhase = ''
    /bin/sh -n "$target"
  '';
  meta.mainProgram = "codex";
}
