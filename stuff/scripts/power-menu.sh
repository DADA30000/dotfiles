TLP='%{{{pkgs.tlp}}}'
TLP_PD='%{{{pkgs.tlp-pd}}}'
ROFI='%{{{pkgs.rofi}}}'

if [ "$1" == "getdata" ]; then
  current=$("$TLP/bin/tlp-stat" -s | grep "Power profile" | awk '{print $4}')

  case "$current" in
  power-saver*)
    echo '{"text":"󰌪","class":"powersave","tooltip":"Mode: Power Saver"}'
    ;;
  performance*)
    echo '{"text":"󰓅","class":"performance","tooltip":"Mode: Performance"}'
    ;;
  balanced | *)
    echo '{"text":"󰗑","class":"default","tooltip":"Mode: Balanced"}'
    ;;
  esac
elif [ "$1" == "menu" ]; then
  options="󰌪 Power Saver\n󰗑 Balanced\n󰓅 Performance\n󱜝 Fan: Auto\n󱑯 Fan: Max"

  chosen=$(echo -e "$options" | "$ROFI/bin/rofi" -dmenu -i -p "Power Profile:" -theme-str 'window {width: 15%;}')

  case "$chosen" in
  *Power*) "$TLP_PD/bin/tlpctl" set power-saver ;;
  *Balanced*) "$TLP_PD/bin/tlpctl" set balanced ;;
  *Performance*) "$TLP_PD/bin/tlpctl" set performance ;;
  *Max*) echo '5' | pkexec tee /sys/devices/platform/aorus_laptop/fan_mode ;;
  *Auto*) echo '0' | pkexec tee /sys/devices/platform/aorus_laptop/fan_mode ;;
  *) exit 0 ;;
  esac

  pkill -RTMIN+5 waybar
fi
