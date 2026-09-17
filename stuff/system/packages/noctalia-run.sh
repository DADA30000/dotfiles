#!/usr/bin/env bash
# Noctalia Run Mode (1:1 drop-in replacement for `rofi -show run`).
# Scans $PATH for executables and launches the chosen command/binary via app2unit.
# Supports custom freeform command input with arguments as well.

cmd=$(
  IFS=:
  for dir in $PATH; do
    [ -d "$dir" ] && ls -1 "$dir" 2>/dev/null
  done | sort -u | grep -E "^[a-zA-Z0-9]" | noctalia dmenu -p "Run:"
)

if [ -n "$cmd" ]; then
  if command -v app2unit-wrapped >/dev/null 2>&1; then
    eval "app2unit-wrapped $cmd"
  else
    eval "app2unit -- $cmd"
  fi
fi
