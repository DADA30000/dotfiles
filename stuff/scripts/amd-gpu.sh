GPU_PATH=""
for dev in /sys/bus/pci/devices/*; do
  if [ -e "$dev/driver" ] && [[ "$(readlink "$dev/driver")" =~ "amdgpu" ]]; then
    GPU_PATH="$dev"
    break
  fi
done

if [ -z "$GPU_PATH" ]; then
  exit 1
fi

HWMON_DIR=$(find "$GPU_PATH/hwmon" 2>/dev/null | head -n 1)
HWMON_PATH="$GPU_PATH/hwmon/$HWMON_DIR"

if [ -d "$HWMON_PATH" ]; then
  usage=$(cat "$HWMON_PATH/device/gpu_busy_percent" 2>/dev/null || echo "0")
  temp=$(($(cat "$HWMON_PATH/temp1_input" 2>/dev/null || echo "0") / 1000))
  power=$(($(cat "$HWMON_PATH/power1_average" 2>/dev/null || echo "0") / 1000000))

  pci_addr=$(basename "$GPU_PATH")
  name=$(lspci -s "$pci_addr" | cut -d ':' -f3- | sed 's/^ //')

  text="<span color='#990000'>  ${usage}%  󰢮 </span>"
  tooltip="$name\rUsage: ${usage}%\rTemp: ${temp}°C\rPower: ${power}W"

  echo "{\"text\":\"$text\",\"tooltip\":\"$tooltip\"}"
else
  echo "{\"text\":\"error\",\"tooltip\":\"No hwmon found\"}"
fi
