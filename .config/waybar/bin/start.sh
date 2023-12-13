#!/usr/bin/env bash

# This script will start or restart waybar and also make sure that waybar is only visible on the primary monitor.

# Terminate already running bar instances
killall -q waybar

check() {
  command -v "$1" >/dev/null 2>&1
}

notify() {
  check notify-send && notify-send "$@" || echo "$@"
}

check hyprctl || {
  notify "hyprctl is not present"
  exit 1
}

data="$(hyprctl monitors -j)"
readarray -t monitors <<< "$(echo "$data" | jq -r '.[].name')"
laptop="${monitors[0]}"
monitor="${monitors[-1]}"

if [ "$laptop" == "$monitor" ]; then
  cat << EOF > "$HOME"/.config/waybar/config
[
  {
  "output": [ "$laptop" ],
    "include": [
      "~/.config/waybar/bars/top.json",
    ],
  }
]
EOF
else
cat << EOF > "$HOME"/.config/waybar/config
[
  {
  "output": [ "$monitor" ],
    "include": [
      "~/.config/waybar/bars/top.json",
    ],
  }
]
EOF
fi
setsid waybar &>/dev/null &
