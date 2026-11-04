set -euo pipefail

exec run0 \
  --background= \
  --property=PrivateMounts=yes \
  --setenv=PATH \
  --setenv=HOME \
  --setenv=USER \
  --setenv=WAYLAND_DISPLAY \
  --setenv=DISPLAY \
  --setenv=XAUTHORITY \
  --setenv=XDG_RUNTIME_DIR \
  --setenv=DBUS_SESSION_BUS_ADDRESS \
  --setenv=SSH_AUTH_SOCK \
  --setenv="MOUNT_POINT=$HOME/.local/state/nixos-config" \
  --setenv="TARGET_UID=$(id -u)" \
  --setenv="TARGET_GID=$(id -g)" \
  --setenv="TARGET_USER=$(id -un)" \
  bash -c '
    set -euo pipefail

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
    chown "$TARGET_UID:$TARGET_GID" "$MOUNT_POINT"

    bindfs --force-user="$TARGET_UID" --force-group="$TARGET_GID" \
           --create-for-user=root --create-for-group=root \
           --chown-ignore --chgrp-ignore --chmod-ignore \
           /etc/nixos "$MOUNT_POINT"

    runuser -m -u "$TARGET_USER" -- \
      env NEOVIDE_MOUNT_POINT="$MOUNT_POINT" \
      neovide "$MOUNT_POINT"
  '
