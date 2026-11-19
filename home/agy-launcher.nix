# The `agy` on PATH: runs the real binary with the current working directory
# (and any `--add-dir` paths) merged into a session-only `--settings` overlay so
# `agy` never stops on the workspace trust prompt in new directories or
# worktrees, without mutating ~/.gemini/antigravity-cli/settings.json.
#
# The script runs under /bin/sh and execs the real binary directly so on macOS
# no non-platform executable sits in front of `agy` and TCC still charges
# `agy`'s own grant (`jq` runs only as a sibling helper). Setting
# `AGY_NO_AUTO_TRUST=1` disables this behavior.
{
  writeTextFile,
  jq,
}:
target:
writeTextFile {
  name = "agy-launcher";
  destination = "/bin/agy";
  executable = true;
  text = ''
    #!/bin/sh
    if [ "''${AGY_NO_AUTO_TRUST:-}" = 1 ]; then
      exec "${target}" "$@"
    fi

    if [ $# -gt 0 ]; then
      case "$1" in
        -*) ;;
        *) exec "${target}" "$@" ;;
      esac
    fi

    _pwd_logical="''${PWD:-$(pwd -L 2>/dev/null || pwd)}"
    _pwd_physical="$(pwd -P 2>/dev/null || printf '%s' "$_pwd_logical")"

    _expect_val=""
    _after_dd=0
    _skip_inject=0
    _user_settings_set=0
    _user_settings_raw=""
    _extra_dirs_json="[]"

    add_dir_norm() {
      _ad_in="$1"
      [ -n "$_ad_in" ] || return 0
      case "$_ad_in" in
        /*) _ad_log="$_ad_in" ;;
        *) _ad_log="$_pwd_logical/$_ad_in" ;;
      esac
      _ad_phys=$(CDPATH= cd -- "$_ad_log" 2>/dev/null && pwd -P) || _ad_phys="$_ad_log"
      _extra_dirs_json=$("${jq}" -cn \
        --argjson cur "$_extra_dirs_json" \
        --arg a "$_ad_log" \
        --arg b "$_ad_phys" \
        '$cur + [$a, $b]' 2>/dev/null) || _extra_dirs_json="[]"
    }

    for _arg in "$@"; do
      if [ "$_after_dd" = 1 ]; then
        break
      fi
      if [ -n "$_expect_val" ]; then
        case "$_expect_val" in
          add-dir) add_dir_norm "$_arg" ;;
          settings)
            _user_settings_set=1
            _user_settings_raw="$_arg"
            ;;
        esac
        _expect_val=""
        continue
      fi

      case "$_arg" in
        --)
          _after_dd=1
          ;;
        --add-dir|-add-dir)
          _expect_val="add-dir"
          ;;
        --add-dir=*|-add-dir=*)
          add_dir_norm "''${_arg#*=}"
          ;;
        --settings|-settings)
          _expect_val="settings"
          ;;
        --settings=*|-settings=*)
          _user_settings_set=1
          _user_settings_raw="''${_arg#*=}"
          ;;
        --agent|-agent|--conversation|-conversation|--effort|-effort|--input-format|-input-format|--json-schema|-json-schema|--log-file|-log-file|--mode|-mode|--model|-model|--output-format|-output-format|-p|--print|-print|--prompt|-prompt|--print-timeout|-print-timeout|--project|-project|-i|--prompt-interactive|-prompt-interactive)
          _expect_val="other"
          ;;
        -h|--help|-help|-v|--version|-version)
          _skip_inject=1
          ;;
        -*)
          ;;
        *)
          _skip_inject=1
          ;;
      esac
    done

    if [ -n "$_expect_val" ]; then
      _skip_inject=1
    fi

    if [ "$_skip_inject" = 1 ]; then
      exec "${target}" "$@"
    fi

    _settings_file="''${HOME:-}/.gemini/antigravity-cli/settings.json"
    _existing_trusted="[]"
    if [ -n "''${HOME:-}" ] && [ -r "$_settings_file" ]; then
      _existing_trusted=$("${jq}" -c 'if type == "object" then (.trustedWorkspaces // []) else [] end | if type == "array" then . else [] end' "$_settings_file" 2>/dev/null) || _existing_trusted="[]"
    fi

    if [ "$_user_settings_set" = 0 ]; then
      _session_settings=$("${jq}" -cn \
        --argjson base "$_existing_trusted" \
        --arg d1 "$_pwd_logical" \
        --arg d2 "$_pwd_physical" \
        --argjson extra "$_extra_dirs_json" '
        ($base + [$d1, $d2] + $extra)
        | map(select(type == "string" and length > 0) | sub("/+$"; "") | if . == "" then "/" else . end)
        | unique
        | {trustedWorkspaces: .}
      ' 2>/dev/null) || _session_settings=""
      if [ -z "$_session_settings" ]; then
        exec "${target}" "$@"
      fi
      exec "${target}" --settings "$_session_settings" "$@"
    fi

    _trimmed_raw="''${_user_settings_raw#"''${_user_settings_raw%%[![:space:]]*}"}"
    _user_obj=""
    case "$_trimmed_raw" in
      "{"*)
        _user_obj=$(printf '%s' "$_user_settings_raw" | "${jq}" -ce 'if type == "object" then . else halt_error(1) end' 2>/dev/null) || _user_obj=""
        ;;
      *)
        if [ -n "$_user_settings_raw" ] && [ -r "$_user_settings_raw" ]; then
          _user_obj=$("${jq}" -ce 'if type == "object" then . else halt_error(1) end' "$_user_settings_raw" 2>/dev/null) || _user_obj=""
        fi
        ;;
    esac

    if [ -z "$_user_obj" ]; then
      exec "${target}" "$@"
    fi

    _session_settings=$("${jq}" -cn \
      --argjson user "$_user_obj" \
      --argjson base "$_existing_trusted" \
      --arg d1 "$_pwd_logical" \
      --arg d2 "$_pwd_physical" \
      --argjson extra "$_extra_dirs_json" '
      (($user.trustedWorkspaces // $base) | if type == "array" then . else [] end) + [$d1, $d2] + $extra
      | map(select(type == "string" and length > 0) | sub("/+$"; "") | if . == "" then "/" else . end)
      | unique
      | $user + {trustedWorkspaces: .}
    ' 2>/dev/null) || _session_settings=""

    if [ -z "$_session_settings" ]; then
      exec "${target}" "$@"
    fi

    _count=$#
    _i=0
    _past_dd=0
    _expect_other=0
    _skip_next=0
    while [ "$_i" -lt "$_count" ]; do
      _arg="$1"
      shift
      _i=$((_i + 1))
      if [ "$_past_dd" = 1 ]; then
        set -- "$@" "$_arg"
        continue
      fi
      if [ "$_skip_next" = 1 ]; then
        _skip_next=0
        continue
      fi
      if [ "$_expect_other" = 1 ]; then
        _expect_other=0
        set -- "$@" "$_arg"
        continue
      fi
      case "$_arg" in
        --)
          _past_dd=1
          set -- "$@" "$_arg"
          ;;
        --settings|-settings)
          _skip_next=1
          ;;
        --settings=*|-settings=*)
          ;;
        --add-dir|-add-dir|--agent|-agent|--conversation|-conversation|--effort|-effort|--input-format|-input-format|--json-schema|-json-schema|--log-file|-log-file|--mode|-mode|--model|-model|--output-format|-output-format|-p|--print|-print|--prompt|-prompt|--print-timeout|-print-timeout|--project|-project|-i|--prompt-interactive|-prompt-interactive)
          _expect_other=1
          set -- "$@" "$_arg"
          ;;
        *)
          set -- "$@" "$_arg"
          ;;
      esac
    done

    exec "${target}" --settings "$_session_settings" "$@"
  '';
  checkPhase = ''
    /bin/sh -n "$target"
  '';
  meta.mainProgram = "agy";
}
