#!/usr/bin/env bash
set -euo pipefail

# 1. Capture click coordinate; exit silently if cancelled (Escape / right-click)
if ! POINT=$(slurp -p -b '#00000000' -f "%x %y" 2>/dev/null); then
  exit 0
fi

read -r X Y <<< "$POINT"
if [[ -z "${X:-}" || -z "${Y:-}" ]]; then
  exit 0
fi

# 2. Get monitors and clients from Hyprland
MONS=$(hyprctl monitors -j)
CLIENTS=$(hyprctl clients -j)

# 3. Hit-test top-most visible window under (X, Y)
TARGET=$(jq -n --argjson x "$X" --argjson y "$Y" --argjson mons "$MONS" --argjson clients "$CLIENTS" '
  ([ $mons[] | .specialWorkspace | select(.id != 0) | .id ] + [ $mons[] | .activeWorkspace.id ]) as $vis_ws |
  [
    $clients[] |
    select(.workspace.id as $w | $vis_ws | index($w)) |
    select(.at[0] <= $x and $x <= (.at[0] + .size[0]) and .at[1] <= $y and $y <= (.at[1] + .size[1])) |
    {
      pid: .pid,
      class: .class,
      title: .title,
      floating: .floating,
      special: (.workspace.id < 0),
      focus: .focusHistoryID
    }
  ] |
  sort_by([ (if .special then 0 else 1 end), (if .floating then 0 else 1 end), .focus ]) |
  first // empty
')

if [[ -z "$TARGET" ]]; then
  notify-send -u low "Cgroup Killer" "Окно не найдено"
  exit 1
fi

PID=$(echo "$TARGET" | jq -r '.pid // empty')
CLASS=$(echo "$TARGET" | jq -r '.class // "Window"')

if [[ -z "$PID" || "$PID" == "0" ]]; then
  notify-send -u low "Cgroup Killer" "Не удалось определить PID окна ($CLASS)"
  exit 1
fi

# 4. Resolve user systemd unit by walking /proc/$PID/cgroup backwards
CGROUP=$(cut -d: -f3 < "/proc/$PID/cgroup" 2>/dev/null || true)
UNIT=""

if [[ -n "$CGROUP" ]]; then
  IFS='/' read -ra PARTS <<< "$CGROUP"
  for (( i=${#PARTS[@]}-1; i>=0; i-- )); do
    PART="${PARTS[i]}"
    if [[ "$PART" =~ \.(service|scope)$ ]] && ! [[ "$PART" =~ ^(user@[0-9]+|init|systemd-.*|wayland-wm.*|hyprland.*|noctalia.*|dbus.*|pipewire.*|wireplumber.*|xdg-desktop-portal.*)\. ]]; then
      UNIT="$PART"
      break
    fi
  done
fi

# 5. Stop user unit
if [[ -n "$UNIT" ]] && systemctl --user is-active --quiet "$UNIT" 2>/dev/null; then
  systemctl --user stop "$UNIT"
  notify-send -u normal "Cgroup Killer" "Остановлен юнит:\n$UNIT ($CLASS)"
else
  notify-send -u critical "Cgroup Killer" "Пользовательский systemd-юнит не найден ($CLASS)"
  exit 1
fi
