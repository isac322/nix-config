# The `codex` on PATH: runs the real binary, injecting private proxy provider
# definitions via runtime `-c` flags when proxy origin environment variables
# are configured.
#
# Codex does not interpolate environment variables in ~/.codex/config.toml,
# ignores OPENAI_BASE_URL, and has no env-var setting for `base_url` or
# `experimental_realtime_ws_base_url`. Injecting them at launch keeps private
# proxy origins out of this repository, the world-readable Nix store, and
# ~/.codex/config.toml while still covering interactive shells, headless
# callers, launchd agents (`~/.config/agents/env.sh` fallback), and `exec`/`app-server`.
#
# Setting `CODEX_NO_CUSTOM_PROVIDER=1` disables this wrapper and runs the
# underlying `codex` binary unchanged.
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
    if [ "''${CODEX_NO_CUSTOM_PROVIDER:-}" = 1 ]; then
      exec "${target}" "$@"
    fi

    if [ $# -gt 0 ]; then
      case "$1" in
        -h|--help|-V|--version|help|completion)
          exec "${target}" "$@"
          ;;
      esac
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
      case "$_raw" in
        *" "*|*"$_tab"*|*"$_nl"*|*"$_cr"*|*"$_bs"*|*"$_dq"*)
          return 0
          ;;
      esac
      printf '%s' "$_raw"
    }

    _custom_origin=$(normalize_origin "''${CODEX_CUSTOM_ORIGIN:-}")
    _cpa_origin=$(normalize_origin "''${CLIPROXYAPI_ORIGIN:-}")

    if [ -z "$_custom_origin" ] && [ -z "$_cpa_origin" ]; then
      exec "${target}" "$@"
    fi

    _user_provider=""
    _user_realtime_set=0

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
              _user_provider="$_v"
              ;;
            experimental_realtime_ws_base_url)
              _user_realtime_set=1
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

    if [ -n "$_custom_origin" ]; then
      _default_provider="custom"
    else
      _default_provider="cliproxyapi"
    fi

    if [ -n "$_user_provider" ]; then
      _effective_provider="$_user_provider"
    else
      _effective_provider="$_default_provider"
    fi

    _orig_n=$#

    if [ "$_effective_provider" = "custom" ] || [ "$_effective_provider" = "cliproxyapi" ]; then
      if [ -z "$_user_provider" ]; then
        set -- "$@" -c "model_provider=\"''${_default_provider}\""
      fi
      set -- "$@" \
        -c 'service_tier="fast"' \
        -c 'web_search="live"' \
        -c 'features.standalone_web_search=true'
      if [ "$_user_realtime_set" -eq 0 ]; then
        if [ "$_effective_provider" = "custom" ] && [ -n "$_custom_origin" ]; then
          set -- "$@" -c "experimental_realtime_ws_base_url=\"''${_custom_origin}/openai/backend-api/codex/realtime\""
        elif [ "$_effective_provider" = "cliproxyapi" ] && [ -n "$_cpa_origin" ]; then
          set -- "$@" -c "experimental_realtime_ws_base_url=\"''${_cpa_origin}/v1/realtime\""
        fi
      fi
    fi

    for _p in custom cliproxyapi; do
      case "$_p" in
        custom)
          _p_origin="$_custom_origin"
          _p_path="/openai/backend-api/codex"
          _p_env="CODEX_CUSTOM_API_KEY"
          ;;
        cliproxyapi)
          _p_origin="$_cpa_origin"
          _p_path="/v1"
          _p_env="CLIPROXYAPI_API_KEY"
          ;;
      esac
      [ -n "$_p_origin" ] || continue
      set -- "$@" \
        -c "model_providers.''${_p}.name=\"OpenAI\"" \
        -c "model_providers.''${_p}.base_url=\"''${_p_origin}''${_p_path}\"" \
        -c "model_providers.''${_p}.env_key=\"''${_p_env}\"" \
        -c "model_providers.''${_p}.wire_api=\"responses\"" \
        -c "model_providers.''${_p}.supports_websockets=true" \
        -c "model_providers.''${_p}.supports_standalone_web_search=true" \
        -c "model_providers.''${_p}.http_headers.x-openai-actor-authorization=\"''${_p}\"" \
        -c "model_providers.''${_p}.capabilities.remote_compaction=\"v2\"" \
        -c "model_providers.''${_p}.capabilities.external_web_access=true"
    done

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
