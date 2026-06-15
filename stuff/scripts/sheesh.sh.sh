THE_MOUNT_POINT="$HOME/.local/state/nixos-config"
USER_ID="$(id -u)"
GROUP_ID="$(id -g)"
USER_NAME="$(id -un)"
USER_HOME="$HOME"
WAYLAND_DISPLAY_VAR="$WAYLAND_DISPLAY"
DISPLAY_VAR="$DISPLAY"
XAUTHORITY_VAR="$XAUTHORITY"
XDG_RUNTIME_DIR_VAR="$XDG_RUNTIME_DIR"

pkexec unshare -m --propagation slave -- bash -c '
  MOUNT_POINT="$9"

  cleanup() {
    if findmnt -M "$MOUNT_POINT" > /dev/null; then
      umount "$MOUNT_POINT"
    fi
    if [ -d "$MOUNT_POINT" ]; then
      rmdir "$MOUNT_POINT"
    fi
  }

  trap cleanup EXIT

  mkdir -p "$MOUNT_POINT"
  chown "$1:$2" "$MOUNT_POINT"
  bindfs --force-user=$1 --force-group=$2 /etc/nixos "$MOUNT_POINT"

  runuser -u "$3" -- \
    env \
      HOME="$4" \
      WAYLAND_DISPLAY="$5" \
      DISPLAY="$6" \
      XAUTHORITY="$7" \
      XDG_RUNTIME_DIR="$8" \
      NEOVIDE_MOUNT_POINT="$MOUNT_POINT" \
      neovide "$MOUNT_POINT"

' bash "$USER_ID" "$GROUP_ID" "$USER_NAME" "$USER_HOME" "$WAYLAND_DISPLAY_VAR" "$DISPLAY_VAR" "$XAUTHORITY_VAR" "$XDG_RUNTIME_DIR_VAR" "$THE_MOUNT_POINT"
