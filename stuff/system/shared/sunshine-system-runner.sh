USER_NAME="$1"
USER_UID="$(id -u "$USER_NAME")"
export XDG_RUNTIME_DIR="/run/user/$USER_UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
if [ -f "$XDG_RUNTIME_DIR/sunshine.env" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$XDG_RUNTIME_DIR/sunshine.env"
  set +a
fi
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
exec %{{{pkgs.sunshine}}}/bin/sunshine
