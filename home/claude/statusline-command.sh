#!/usr/bin/env bash
# Claude Code statusLine — Powerlevel10k Rainbow style

input=$(cat)

# Single jq call: extract all 11 fields with SOH delimiter (non-whitespace to preserve empty fields)
IFS=$'\x01' read -r cwd model used agent version cost duration_ms \
  lines_added lines_removed input_tokens output_tokens < <(
  echo "$input" | jq -r '[
    (.cwd // ""),
    (.model.display_name // ""),
    (.context_window.used_percentage // ""),
    (.agent.name // ""),
    (.version // ""),
    (.cost.total_cost_usd // ""),
    (.cost.total_duration_ms // ""),
    (.cost.total_lines_added // ""),
    (.cost.total_lines_removed // ""),
    (.context_window.total_input_tokens // ""),
    (.context_window.total_output_tokens // "")
  ] | join("\u0001")'
)

# Home dir → ~
short_cwd="${cwd/#$HOME/\~}"

# 256-color ANSI helpers
fg() { printf '\033[38;5;%sm' "$1"; }
bg() { printf '\033[48;5;%sm' "$1"; }
reset=$'\033[0m'

# Powerline separator
sep=$'\uE0B0'

# Format duration: ms → 42s / 5m32s / 1h23m
fmt_duration() {
  local ms=$1
  local total_s=$(( ms / 1000 ))
  if (( total_s < 60 )); then
    printf '%ds' "$total_s"
  elif (( total_s < 3600 )); then
    printf '%dm%ds' $(( total_s / 60 )) $(( total_s % 60 ))
  else
    printf '%dh%dm' $(( total_s / 3600 )) $(( (total_s % 3600) / 60 ))
  fi
}

# Format tokens: 15234 → 15.2K, 1234567 → 1.2M
fmt_tokens() {
  local n=$1
  if (( n >= 1000000 )); then
    local whole=$(( n / 1000000 ))
    local frac=$(( (n % 1000000) / 100000 ))
    printf '%d.%dM' "$whole" "$frac"
  elif (( n >= 1000 )); then
    local whole=$(( n / 1000 ))
    local frac=$(( (n % 1000) / 100 ))
    printf '%d.%dK' "$whole" "$frac"
  else
    printf '%d' "$n"
  fi
}

# Segment builder: tracks prev_bg for automatic transition
out=""
prev_bg=""

append_segment() {
  local bg_c=$1 fg_c=$2 content=$3
  if [ -n "$prev_bg" ]; then
    out+="$(bg "$bg_c")$(fg "$prev_bg")${sep}"
  fi
  out+="$(bg "$bg_c")$(fg "$fg_c") ${content} "
  prev_bg=$bg_c
}

# 1. dir (blue)
append_segment 4 254 " ${short_cwd}"

# 2. agent (purple) — conditional
if [ -n "$agent" ]; then
  append_segment 55 254 "󰚩 ${agent}"
fi

# 3. model (green)
append_segment 2 0 "${model}"

# 4. version (gray) — conditional
if [ -n "$version" ]; then
  append_segment 244 0 " ${version}"
fi

# 5. cost (orange) — conditional
if [ -n "$cost" ] && [ "$cost" != "0" ]; then
  formatted_cost=$(printf '$%.2f' "$cost")
  append_segment 208 0 " ${formatted_cost}"
fi

# 6. lines (cyan) — conditional: added+removed > 0
if [ -n "$lines_added" ] && [ -n "$lines_removed" ]; then
  total_lines=$(( lines_added + lines_removed ))
  if (( total_lines > 0 )); then
    append_segment 6 0 " +${lines_added}/-${lines_removed}"
  fi
fi

# 7. duration (red) — conditional
if [ -n "$duration_ms" ] && [ "$duration_ms" != "0" ]; then
  dur=$(fmt_duration "$duration_ms")
  append_segment 1 254 " ${dur}"
fi

# 8. tokens (magenta) — conditional: input or output > 0
in_t=${input_tokens:-0}
out_t=${output_tokens:-0}
if (( in_t > 0 || out_t > 0 )); then
  tok_str="$(fmt_tokens "$in_t")/$(fmt_tokens "$out_t")"
  append_segment 5 254 " ${tok_str}"
fi

# 9. context (yellow) — conditional
if [ -n "$used" ]; then
  used_int=$(printf "%.0f" "$used")
  append_segment 3 0 "󰾅 ${used_int}%"
fi

# End transition → reset
out+="$(bg 0)$(fg "$prev_bg")${sep}${reset}"

printf '%s' "$out"
