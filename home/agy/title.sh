#!/usr/bin/env bash
set -euo pipefail

# Antigravity CLI terminal window title (plain single-line text)

title=$(
  jq -r '
    if type == "object" then
      def clean: gsub("[[:cntrl:]]+"; " ");
      def s(v):
        if (v | type) == "string" then (v | clean)
        else ""
        end;
      s(.workspace.current_dir) as $ws_dir |
      (if $ws_dir != "" then $ws_dir else s(.cwd) end) as $dir |
      (
        if $dir == "" then "agy"
        elif ($dir | test("^/+$")) then "/"
        else ($dir | sub("/+$"; "") | split("/") | last | if . == "" then "agy" else . end)
        end
      ) as $label |
      (
        if .tool_confirmation_pending == true or .agent_state == "reviewing" then "⏸"
        elif .agent_state == "working" or .agent_state == "tool_use" then "⚙"
        elif .agent_state == "idle" then "✓"
        elif .agent_state == "error" then "✗"
        else "…"
        end
      ) as $icon |
      (
        s(.conversation_title)
        | gsub(" +"; " ")
        | sub("^ +"; "")
        | sub(" +$"; "")
        | if length > 60 then .[0:59] + "…" else . end
      ) as $conv |
      if $conv != "" then "\($icon) \($label) — \($conv)" else "\($icon) \($label)" end
    else
      empty
    end
  ' 2>/dev/null || true
)

if [ -n "$title" ]; then
  printf '%s\n' "$title"
fi
