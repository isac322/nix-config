#!/usr/bin/env bash
set -euo pipefail

# Antigravity CLI statusLine — Powerlevel10k Rainbow style

parsed=$(
  jq -r '
    if type == "object" then
      def clean: gsub("[[:cntrl:]]+"; " ");
      def s(v):
        if (v | type) == "string" then (v | clean)
        elif (v | type) == "number" then (v | tostring)
        else ""
        end;
      def pos_int(v):
        if (v | type) == "number" and v > 0 then (v | floor | tostring) else "0" end;
      s(.workspace.current_dir) as $ws_cwd |
      (if $ws_cwd != "" then $ws_cwd else s(.cwd) end) as $cwd |
      s(.agent.name) as $agent |
      s(.version) as $version |
      (
        if (.cost.total_usd | type) == "number" and .cost.total_usd >= 0.005 then
          (.cost.total_usd | tostring)
        else
          ""
        end
      ) as $cost |
      (if .cost.estimated == true then "1" else "" end) as $cost_estimated |
      pos_int(.context_window.total_input_tokens) as $in_tokens |
      pos_int(.context_window.total_output_tokens) as $out_tokens |
      (
        if (.context_window.used_percentage | type) == "number" and (.context_window.current_usage != null or .context_window.used_percentage > 0) then
          (.context_window.used_percentage | tostring)
        else
          ""
        end
      ) as $used |
      ([.subagents // [] | if type == "array" then .[] else empty end | select(type == "object" and .status == "running")] | length | tostring) as $running_subagents |
      pos_int(.task_count) as $task_count |
      pos_int(.pending_input_count) as $pending_input |
      (if .tool_confirmation_pending == true then "1" else "" end) as $confirm_pending |
      s(.agent_state) as $agent_state |
      (if .sandbox.enabled == true then "1" else "" end) as $sandbox_on |
      s(.vim.mode) as $vim_mode |
      [
        $cwd,
        $agent,
        $version,
        $cost,
        $cost_estimated,
        $in_tokens,
        $out_tokens,
        $used,
        $running_subagents,
        $task_count,
        $pending_input,
        $confirm_pending,
        $agent_state,
        $sandbox_on,
        $vim_mode,
        "_"
      ] | join("\u0001")
    else
      empty
    end
  ' 2>/dev/null || true
)

[ -n "$parsed" ] || exit 0

sentinel=""
IFS=$'\x01' read -r \
  cwd agent version cost cost_estimated \
  in_tokens out_tokens used running_subagents task_count \
  pending_input confirm_pending agent_state sandbox_on vim_mode \
  sentinel <<< "$parsed"
[ "$sentinel" = "_" ] || exit 0

# Shorten only exact $HOME or $HOME/... prefix so /Users/bhyoo2 is never corrupted.
home_dir="${HOME:-}"
home_dir="${home_dir%/}"
tilde="~"
if [ -n "$cwd" ]; then
  if [ -n "$home_dir" ] && [ "$cwd" = "$home_dir" ]; then
    short_cwd="$tilde"
  elif [ -n "$home_dir" ] && [[ "$cwd" == "$home_dir/"* ]]; then
    short_cwd="${tilde}/${cwd#"$home_dir"/}"
  else
    short_cwd="$cwd"
  fi
else
  short_cwd=""
fi

reset=$'\033[0m'
# Literal UTF-8 bytes remain locale-independent even if LANG/LC_CTYPE is C or unset.
sep=""
out=""
prev_bg=""

append_segment() {
  local bg_c=$1 fg_c=$2 content=$3
  local transition seg
  if [ -n "$prev_bg" ]; then
    printf -v transition '\033[48;5;%sm\033[38;5;%sm%s' "$bg_c" "$prev_bg" "$sep"
    out+="$transition"
  fi
  printf -v seg '\033[48;5;%sm\033[38;5;%sm %s ' "$bg_c" "$fg_c" "$content"
  out+="$seg"
  prev_bg=$bg_c
}

fmt_tokens() {
  local n=$1
  if (( n >= 999950 )); then
    local tenths=$(( (n + 50000) / 100000 ))
    printf '%d.%dM' $(( tenths / 10 )) $(( tenths % 10 ))
  elif (( n >= 1000 )); then
    local tenths=$(( (n + 50) / 100 ))
    printf '%d.%dK' $(( tenths / 10 )) $(( tenths % 10 ))
  else
    printf '%d' "$n"
  fi
}

# 1. dir (blue)
if [ -n "$short_cwd" ]; then
  append_segment 4 254 "$short_cwd"
fi

# 2. agent (purple) — conditional
if [ -n "$agent" ]; then
  append_segment 55 254 "󰚩 $agent"
fi

# 3. version (gray) — conditional
if [ -n "$version" ]; then
  append_segment 244 0 "v${version#v}"
fi

# 6. cost (orange) — conditional (>= $0.005)
if [ -n "$cost" ]; then
  LC_ALL=C printf -v formatted_cost '$%.2f' "$cost"
  if [ "$cost_estimated" = "1" ]; then
    formatted_cost="~${formatted_cost}"
  fi
  append_segment 208 0 "$formatted_cost"
fi

# 7. tokens (magenta) — conditional
if (( in_tokens > 0 || out_tokens > 0 )); then
  append_segment 5 254 "$(fmt_tokens "$in_tokens")/$(fmt_tokens "$out_tokens")"
fi

# 8. context (red >= 90%, else yellow) — conditional
if [ -n "$used" ]; then
  LC_ALL=C printf -v used_int '%.0f' "$used"
  if (( used_int >= 90 )); then
    append_segment 1 254 "󰾅 ${used_int}%"
  else
    append_segment 3 0 "󰾅 ${used_int}%"
  fi
fi

# 9. vim mode (dark gray) — conditional
if [ -n "$vim_mode" ]; then
  append_segment 240 254 "$vim_mode"
fi

# 10. sandbox (darker gray) — conditional when enabled
if [ "$sandbox_on" = "1" ]; then
  append_segment 238 254 "sandbox"
fi

# 11. activity / confirmation / error
activity_parts=()
if (( running_subagents > 0 )); then
  activity_parts+=("${running_subagents} sub")
fi
if (( task_count > 0 )); then
  activity_parts+=("${task_count} task")
fi
if (( pending_input > 0 )); then
  activity_parts+=("${pending_input} queued")
fi
if [ "$confirm_pending" = "1" ]; then
  activity_parts+=("confirm")
fi

if (( ${#activity_parts[@]} > 0 )); then
  joined=${activity_parts[0]}
  for part in "${activity_parts[@]:1}"; do
    joined+=" · ${part}"
  done
  if [ "$confirm_pending" = "1" ]; then
    append_segment 1 254 "⏸ ${joined}"
  else
    append_segment 55 254 "󰚩 ${joined}"
  fi
elif [ "$agent_state" = "error" ]; then
  append_segment 1 254 "✗ error"
fi

# End arrow over default terminal background
if [ -n "$prev_bg" ]; then
  printf -v end_cap '%s\033[38;5;%sm%s%s' "$reset" "$prev_bg" "$sep" "$reset"
  out+="$end_cap"
fi

printf '%s' "$out"
