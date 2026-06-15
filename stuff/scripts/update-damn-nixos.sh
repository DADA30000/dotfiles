LOG_FILE="$HOME/.cache/nixos-rebuild.log"
rm -f "$LOG_FILE"
NOTIFY_ID=$(notify-send -p "Обновление" "Ожидание ввода пароля...")

if [ -z "$NOTIFY_ID" ]; then
  echo "Could not create notification. Aborting." >&2
  exit 1
fi

pkexec nixos-rebuild switch -v &>"$LOG_FILE" &
REBUILD_PID=$!

while [[ ! -s "$LOG_FILE" ]]; do
  if [[ -d "/proc/$REBUILD_PID" ]]; then
    sleep 0.1
  else
    break
  fi
done

START_TIME=$(date +%s)
while [[ -d "/proc/$REBUILD_PID" ]]; do
  mapfile -t LOG_LINES < <(tail -n 3 "$LOG_FILE" | sed 's/^\s*//')
  if [ ''${#LOG_LINES[@]} -gt 0 ]; then
    TRUNCATED_LINES=$(notify_trunc 300 "Noto Sans 12" "''${LOG_LINES[*]}")
  else
    TRUNCATED_LINES="..."
  fi
  CURR_TIME=$(date +%s)
  notify-send -r "$NOTIFY_ID" "Обновление" "Прошло $((CURR_TIME - START_TIME)) секунд \n\n$TRUNCATED_LINES"
  sleep 0.1
done

wait "$REBUILD_PID"
EXIT_CODE=$?

kek() {
  if [[ $(notify-send -u critical -A "openlog=Открыть логи" "$1" "$2") == "openlog" ]]; then
    neovide -- -c "normal! G" "$LOG_FILE"
  fi
}

if [ $EXIT_CODE -eq 0 ]; then
  notify-send "Успех" "Система успешно обновлена."
elif [ $EXIT_CODE -eq 1 ]; then
  kek "Ошибка сборки" "Произошла ошибка во время сборки. Лог: $LOG_FILE"
elif [ $EXIT_CODE -eq 2 ]; then
  kek "Ошибка активации" "Сборка прошла успешно, но активация не удалась. Лог: $LOG_FILE"
else
  kek "Неизвестная ошибка" "Произошла ошибка с кодом $EXIT_CODE. Лог: $LOG_FILE"
fi
