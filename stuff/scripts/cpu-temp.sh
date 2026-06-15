CPU_HWMON=""
for d in /sys/class/hwmon/hwmon*; do
  if [ -f "$d/name" ] && [ "$(cat "$d/name")" == "k10temp" ]; then
    CPU_HWMON="$d"
    break
  fi
done

if [ -z "$CPU_HWMON" ]; then
  echo '{"text":"N/A","tooltip":"k10temp driver not found"}'
  exit 0
fi

TEMP_FILE=""
for f in "$CPU_HWMON"/temp*_label; do
  label=$(cat "$f")
  if [ "$label" == "Tdie" ]; then
    TEMP_FILE="${f%_label}_input"
    break
  fi
done

if [ -z "$TEMP_FILE" ]; then
  TEMP_FILE="$CPU_HWMON/temp1_input"
fi

temp_raw=$(cat "$TEMP_FILE" 2>/dev/null || echo "0")
temp=$((temp_raw / 1000))

icon=""
if [ "$temp" -gt 65 ]; then icon=""; fi
if [ "$temp" -gt 85 ]; then icon=""; fi

echo "{\"text\":\"$temp°C $icon\",\"tooltip\":\"Sensor: $TEMP_FILE\",\"class\":\"temp-$temp\"}"
