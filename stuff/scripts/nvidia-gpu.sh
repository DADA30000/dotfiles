NVIDIA_PATH=""
for dev in /sys/bus/pci/devices/*; do
  vendor=$(cat "$dev/vendor" 2>/dev/null)
  if [ "$vendor" == "0x10de" ]; then
    NVIDIA_PATH="$dev"
    break
  fi
done

if [ -z "$NVIDIA_PATH" ]; then
  exit 1
fi

status=$(cat "$NVIDIA_PATH/power/runtime_status")

if [ "$status" != "active" ]; then
  # Fluent-style suspended tooltip
  tooltip="<b>NVIDIA GeForce GPU</b>\n"
  tooltip="${tooltip}<span foreground='#888888'>●</span> Status: <span foreground='#888888'>Suspended (D3cold)</span>\n"
  tooltip="${tooltip}────────────────────────────\n"
  tooltip="${tooltip}The graphics adapter has entered sleep mode to preserve power."

  echo "{\"text\":\"<span color='#555555'> 󰢮 0W </span>\",\"tooltip\":\"${tooltip}\",\"class\":\"sleep\"}"
else
  # Safely run nvidia-smi capturing stdout and stderr
  stats_output=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,power.draw --format=csv,noheader,nounits 2>&1)
  exit_code=$?

  # Catch blocked or failed driver communication states gracefully
  if [ $exit_code -ne 0 ] || echo "$stats_output" | grep -iq "fail"; then
    tooltip="<b>NVIDIA GeForce GPU</b>\n"
    tooltip="${tooltip}<span foreground='#fa8c16'>●</span> Status: <span foreground='#fa8c16'>Blocked / Transitioning</span>\n"
    tooltip="${tooltip}────────────────────────────\n"
    tooltip="${tooltip}The driver is currently locked or preparing for hibernation."

    echo "{\"text\":\"<span color='#fa8c16'> Blocked  󰢮 </span>\",\"tooltip\":\"${tooltip}\",\"class\":\"blocked\"}"
  else
    usage=$(echo "$stats_output" | cut -d',' -f1 | tr -d ' ')
    temp=$(echo "$stats_output" | cut -d',' -f2 | tr -d ' ')
    power=$(echo "$stats_output" | cut -d',' -f3 | tr -d ' ')

    # Fluent-style active layout
    tooltip="<b>NVIDIA GeForce GPU</b>\n"
    tooltip="${tooltip}<span foreground='#357a38'>●</span> Status: <span foreground='#357a38'>Active</span>\n"
    tooltip="${tooltip}────────────────────────────\n"
    tooltip="${tooltip}<b>Usage:</b>   ${usage}%\n"
    tooltip="${tooltip}<b>Temp:</b>    ${temp}°C\n"
    tooltip="${tooltip}<b>Power:</b>   ${power}W"

    echo "{\"text\":\"<span color='#357a38'>  ${usage}%  󰢮 </span>\",\"tooltip\":\"${tooltip}\",\"class\":\"active\"}"
  fi
fi
