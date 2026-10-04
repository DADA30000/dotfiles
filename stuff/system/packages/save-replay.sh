#!/usr/bin/env bash
MON_NAME=$(hyprctl activeworkspace -j | jq -r '.monitor')
pkill -SIGUSR1 -f "gpu-screen-recorder.*-w $MON_NAME.*" &&
  notify-send 'GPU-Screen-Recorder' "Повтор с $MON_NAME успешно сохранён"
