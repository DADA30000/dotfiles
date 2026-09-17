#!/usr/bin/env bash
# Drop-in replacement wrapper for `rofi -dmenu` or generic `dmenu`.
# Since `noctalia dmenu` strictly accepts only `-p` / `--prompt <text>`,
# this wrapper filters out rofi-specific flags (-i, -l, -mesg, -theme, etc.)
# and forwards the prompt and stdin to `noctalia dmenu`.

prompt=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  -p | --prompt)
    prompt="$2"
    shift 2
    ;;
  -p=* | --prompt=*)
    prompt="${1#*=}"
    shift 1
    ;;
  -dmenu)
    shift 1
    ;;
  -mesg | -theme | -font | -selected-row | -filter | -format)
    shift 2 2>/dev/null || shift 1
    ;;
  -i | -no-custom | -password | -case-sensitive | -markup-rows | -async)
    shift 1
    ;;
  *)
    # Ignore unknown rofi flags
    if [[ "$1" == -* ]]; then
      shift 1
    else
      shift 1
    fi
    ;;
  esac
done

if [[ -n "$prompt" ]]; then
  exec noctalia dmenu -p "$prompt"
else
  exec noctalia dmenu
fi
