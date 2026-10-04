echo "export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}" > "$XDG_RUNTIME_DIR/sunshine.env"
echo "export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}" >> "$XDG_RUNTIME_DIR/sunshine.env"
if [ -n "${DISPLAY:-}" ]; then
  echo "export DISPLAY=$DISPLAY" >> "$XDG_RUNTIME_DIR/sunshine.env"
fi
