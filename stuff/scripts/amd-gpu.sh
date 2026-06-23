trap - SIGPIPE

GPU_PATH=""
for dev in /sys/bus/pci/devices/*; do
  if [ -e "$dev/driver" ] && [[ "$(readlink "$dev/driver")" =~ "amdgpu" ]]; then
    GPU_PATH="$dev"
    break
  fi
done

if [ -z "$GPU_PATH" ]; then
  echo "{\"text\":\"error\",\"tooltip\":\"No AMD GPU found\"}" 2>/dev/null
  exit 1
fi

HWMON_PATH=""
for d in "$GPU_PATH"/hwmon/hwmon*; do
  if [ -d "$d" ]; then
    HWMON_PATH="$d"
    break
  fi
done

if [ -d "$HWMON_PATH" ]; then
  usage=$(cat "$HWMON_PATH/device/gpu_busy_percent" 2>/dev/null || echo "0")
  temp=$(($(cat "$HWMON_PATH/temp1_input" 2>/dev/null || echo "0") / 1000))
  power=$(($(cat "$HWMON_PATH/power1_average" 2>/dev/null || echo "0") / 1000000))

  pci_addr=$(basename "$GPU_PATH")

  CACHE_FILE="/tmp/gpu_name_$pci_addr"
  if [ -f "$CACHE_FILE" ]; then
    name=$(cat "$CACHE_FILE")
  else
    name=$(lspci -s "$pci_addr" 2>/dev/null | cut -d ':' -f3- | sed 's/^ //')
    name=${name:-"AMD GPU"}
    echo "$name" >"$CACHE_FILE" 2>/dev/null
  fi

  text="<span color='#990000'>  ${usage}%  󰢮 </span>"
  tooltip="$name\rUsage: ${usage}%\rTemp: ${temp}°C\rPower: ${power}W"

  echo "{\"text\":\"$text\",\"tooltip\":\"$tooltip\"}" 2>/dev/null
else
  echo "{\"text\":\"error\",\"tooltip\":\"No hwmon found\"}" 2>/dev/null
fi
