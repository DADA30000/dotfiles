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
  echo '{"text":"<span color=\"#555555\"> 󰢮 0W </span>","tooltip":"GPU is suspended","class":"sleep"}'
else
  stats=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,power.draw --format=csv,noheader,nounits 2>/dev/null)
  if [ -n "$stats" ]; then
    usage=$(echo "$stats" | cut -d',' -f1 | tr -d ' ')
    temp=$(echo "$stats" | cut -d',' -f2 | tr -d ' ')
    power=$(echo "$stats" | cut -d',' -f3 | tr -d ' ')
    echo "{\"text\":\"<span color='#00ff00'>  ${usage}%  󰢮 </span>\",\"tooltip\":\"NVIDIA GPU\rUsage: ${usage}%\rTemp: ${temp}°C\rPower: ${power}W\",\"class\":\"active\"}"
  fi
fi
