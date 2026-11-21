#!/usr/bin/env bash
set -euo pipefail
MON_NAME=$(hyprctl activeworkspace -j | jq -r '.monitor')
if [[ -z "$MON_NAME" || "$MON_NAME" == "null" ]]; then
  exit 1
fi
printf '%s\n' "$MON_NAME" > "${XDG_RUNTIME_DIR}/replays-save.mon"
exec systemctl start "replays-save@$(id -u).service"
