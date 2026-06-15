HYPRGAMEMODE=$(hyprctl getoption animations:enabled | awk 'NR==1{print $2}')
if [ "$HYPRGAMEMODE" = "true" ]; then
  hyprctl eval "hl.config {
    animations = { enabled = 0 },
    general = { border_size = 0 }
  }"
  hyprctl eval 'hl.monitor({ output = "eDP-1", mode = "2560x1600@60", position = "auto", scale = "auto", bitdepth = 10 })'
  systemctl --user stop replays
  exit
fi
hyprctl reload
systemctl --user start replays
exit
