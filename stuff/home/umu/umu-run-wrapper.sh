set -e

# 1. Resolve Prefix Storage Directory
prefix_name="${UMU_PREFIX_NAME:-default}"
PREFIX_DIR="$HOME/.umu/$prefix_name"
ORIG_UID=$(id -u)
RUNTIME_ROOT="${XDG_RUNTIME_DIR:-/run/user/$ORIG_UID}"
MERGED_PFX="$RUNTIME_ROOT/umu-pfx/$prefix_name"

cleanup_all() {
  local exit_code=$?
  trap - EXIT INT TERM

  if [[ -n "${SOCKET_PATH:-}" ]]; then
    pkill -f "rust-bridge.*$SOCKET_PATH" 2>/dev/null || true
    rm -rf "$SOCKET_DIR" 2>/dev/null || true
  fi

  if [[ -n "${MERGED_PFX:-}" ]]; then
    unshare -r umount -l "$MERGED_PFX" 2>/dev/null || umount -l "$MERGED_PFX" 2>/dev/null || true
    rmdir "$MERGED_PFX" 2>/dev/null || true
  fi
  if [[ -n "${PREFIX_DIR:-}" ]]; then
    unshare -r rm -rf "$PREFIX_DIR/.work" 2>/dev/null || rm -rf "$PREFIX_DIR/.work" 2>/dev/null || true
  fi

  if [[ $exit_code -eq 0 ]]; then
    %{{{pkgs.libnotify}}}/bin/notify-send "Closed" "UMU exited ($prefix_name)"
  else
    %{{{pkgs.libnotify}}}/bin/notify-send -u critical "Closed (Error $exit_code)" "UMU exited with error ($prefix_name)"
  fi
}
trap cleanup_all EXIT INT TERM

# 2. Check if Prefix is already running (GUI Dialog via rust-helpers)
if command -v manage-running-prefix >/dev/null 2>&1; then
  if ! manage-running-prefix "$prefix_name"; then
    echo "Launch canceled by user."
    exit 0
  fi
fi

# 3. Guard against legacy / polluted prefix folders (only upper and .work allowed)
if [[ -d "$PREFIX_DIR" ]]; then
  unexpected_items=$(find "$PREFIX_DIR" -mindepth 1 -maxdepth 1 ! -name "upper" ! -name ".work" ! -name ".*" 2>/dev/null)
  if [[ -n "$unexpected_items" ]]; then
    %{{{pkgs.libnotify}}}/bin/notify-send -u critical "UMU Prefix Error" "Directory '$PREFIX_DIR' contains non-overlay files! Overlay prefix must only contain 'upper' and '.work'."
    echo "ERROR: Prefix '$PREFIX_DIR' is not a valid overlay prefix directory!" >&2
    echo "Found non-overlay files:" >&2
    echo "$unexpected_items" >&2
    echo "Please migrate or remove legacy prefix contents." >&2
    exit 1
  fi
else
  mkdir -p "$PREFIX_DIR/upper" "$PREFIX_DIR/.work"
fi

%{{{pkgs.libnotify}}}/bin/notify-send "Starting UMU" "Launching $prefix_name"

# 4. Resolve Proton version dynamically
ORIG_UID=$(id -u)
SECURE_MOUNT="/run/umu/$ORIG_UID"
MOUNT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/umu"

if [[ -z "$(printenv PROTONPATH)" ]]; then
  case "$UMU_PROTON_TYPE" in
    %{{{protonCaseBranches}}}
    *)
      export PROTONPATH="$SECURE_MOUNT/proton/%{{{defaultProtonCode}}}"
      ;;
  esac
fi

# 5. Ensure runtime EROFS is mounted via hardened systemd service
if ! mountpoint -q "$SECURE_MOUNT"; then
  if ! systemctl start "umu-mount@$ORIG_UID.service" || ! mountpoint -q "$SECURE_MOUNT"; then
    %{{{pkgs.libnotify}}}/bin/notify-send "Closed" "UMU runtime mount failed."
    exit 1
  fi
fi

# Ensure mount target directory exists on host as a regular directory (NOT a symlink)
if [[ -L "$MOUNT_DIR" ]]; then
  rm -f "$MOUNT_DIR"
fi
mkdir -p "$MOUNT_DIR"

# 6. Resolve Base Prefix (lowerdir from umu-runtime)
PROTON_NAME=$(basename "$PROTONPATH")
BASE_PFX="$SECURE_MOUNT/base_prefixes/$PROTON_NAME"
if [[ ! -d "$BASE_PFX" ]]; then
  BASE_PFX="$SECURE_MOUNT/proton/$PROTON_NAME/files/share/default_pfx"
  [[ -d "$BASE_PFX" ]] || BASE_PFX="$SECURE_MOUNT/proton/$PROTON_NAME/dist/share/default_pfx"
fi

# 7. Migrate/Rebase Upper Layer if Proton Version Changed
CURRENT_PROTON_VER=$(cat "$BASE_PFX/version" 2>/dev/null || cat "$SECURE_MOUNT/proton/$PROTON_NAME/version" 2>/dev/null || echo "unknown")
LAST_PROTON_VER=$(cat "$PREFIX_DIR/upper/.last_proton" 2>/dev/null || echo "")
LAST_PROTON_PATH=$(cat "$PREFIX_DIR/upper/.last_proton_path" 2>/dev/null || echo "")

if [[ -n "$LAST_PROTON_VER" && "$LAST_PROTON_VER" != "$CURRENT_PROTON_VER" ]]; then
  echo "Proton version change detected ($LAST_PROTON_VER -> $CURRENT_PROTON_VER). Running delta rebase..."
  OLD_PROTON_NAME=$(basename "$LAST_PROTON_PATH")
  OLD_BASE="$SECURE_MOUNT/base_prefixes/$OLD_PROTON_NAME"
  [[ -d "$OLD_BASE" ]] || OLD_BASE="$SECURE_MOUNT/proton/$OLD_PROTON_NAME/files/share/default_pfx"
  [[ -d "$OLD_BASE" ]] || OLD_BASE="$SECURE_MOUNT/proton/$OLD_PROTON_NAME/dist/share/default_pfx"

  umu-rebase-pfx \
    --old-base "$OLD_BASE" \
    --new-base "$BASE_PFX" \
    --upper "$PREFIX_DIR/upper" \
    --home "$HOME"
elif [[ ! -f "$PREFIX_DIR/upper/config_info" || ! -f "$PREFIX_DIR/upper/.update-timestamp" ]]; then
  umu-rebase-pfx \
    --new-base "$BASE_PFX" \
    --upper "$PREFIX_DIR/upper" \
    --home "$HOME"
fi

# Ensure config_info matches runtime PROTONPATH so Proton never detects false version changes
if [[ -f "$PREFIX_DIR/upper/config_info" ]]; then
  sed -i "s|$HOME/.local/share/umu/proton|$SECURE_MOUNT/proton|g" "$PREFIX_DIR/upper/config_info"
  sed -i "s|@UMU_USER_HOME@/.local/share/umu/proton|$SECURE_MOUNT/proton|g" "$PREFIX_DIR/upper/config_info"
fi

echo "$CURRENT_PROTON_VER" > "$PREFIX_DIR/upper/.last_proton"
echo "$PROTONPATH" > "$PREFIX_DIR/upper/.last_proton_path"

# 8. Clean and recreate empty .work directory
unshare -r rm -rf "$PREFIX_DIR/.work" 2>/dev/null || rm -rf "$PREFIX_DIR/.work" 2>/dev/null || true
mkdir -p "$PREFIX_DIR/.work"

# 9. Setup runtime merged mountpoint in RAM
ORIG_GID=$(id -g)
mkdir -p "$MERGED_PFX"

# 10. Hardware and GPU settings
if [[ "$USE_STEAM_INTEGRATION" == "1" ]]; then
  export WINEDLLOVERRIDES="steamclient64,SteamFix64,steam_api64,OnlineFix64,SteamOverlay64=n,b;$WINEDLLOVERRIDES"
else
  export WINEDLLOVERRIDES="steamclient,steamclient64=d;$WINEDLLOVERRIDES"
fi

unset ALSOFT_DRIVERS
export PROTON_DISCORD_BRIDGE=1
export WINEDLLOVERRIDES="voices38,dxgi,winhttp,winmm,version=n,b;$WINEDLLOVERRIDES"
export UMU_RUNTIME_UPDATE=0
export PROTON_ENABLE_WAYLAND=${PROTON_ENABLE_WAYLAND:-1}
cd "$(dirname "$1")" &> /dev/null || true

get_pci_id() {
  %{{{pkgs.pciutils}}}/bin/lspci -nn | grep -E "VGA compatible controller|3D controller|Display controller" | grep -i -E "$1" | grep -o -E "\[[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\]" | head -n 1 | tr -d '[]'
}

case "$UMU_GPU_SELECT" in
  "AMD")
    pci_id=$(get_pci_id "AMD|Advanced Micro Devices|ATI")
    if [[ -n "$pci_id" ]]; then
      export DRI_PRIME="$pci_id!"
      export MESA_VK_DEVICE_SELECT="$pci_id!"
    fi
  ;;
  "Intel")
    pci_id=$(get_pci_id "Intel")
    if [[ -n "$pci_id" ]]; then
      export DRI_PRIME="$pci_id!"
      export MESA_VK_DEVICE_SELECT="$pci_id!"
    fi
  ;;
  "Nvidia")
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export __VK_LAYER_NV_optimus=NVIDIA_only
    pci_id=$(get_pci_id "NVIDIA")
    if [[ -n "$pci_id" ]]; then
      export DRI_PRIME="$pci_id!"
      export MESA_VK_DEVICE_SELECT="$pci_id!"
    fi
  ;;
esac

CMD=()
if [[ "$USE_GAMEMODE" != "0" ]]; then
  CMD+=(%{{{pkgs.gamemode}}}/bin/gamemoderun)
fi
if [[ "$USE_MANGOHUD" != "0" ]]; then
  CMD+=(%{{{pkgs.mangohud}}}/bin/mangohud)
fi
CMD+=(%{{{umu}}}/bin/umu-run "$@")

if [[ "$USE_STEAM_OVERLAY" == "1" ]]; then
  export SteamGameId=480
  export ENABLE_VK_LAYER_VALVE_steam_overlay_1=1
  export LD_PRELOAD="$LD_PRELOAD:$HOME/.steam/bin32/gameoverlayrenderer.so:$HOME/.steam/bin64/gameoverlayrenderer.so"
  export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:%{{{pkgs.libGL}}}/lib:%{{{pkgs.pkgsi686Linux.libGL}}}/lib"
fi

# 11. Run via in-kernel OverlayFS + app2unit systemd scope
run_overlay_app() {
  unshare -r -m env \
    SECURE_MOUNT="$SECURE_MOUNT" \
    MOUNT_DIR="$MOUNT_DIR" \
    BASE_PFX="$BASE_PFX" \
    UPPER_DIR="$PREFIX_DIR/upper" \
    WORK_DIR="$PREFIX_DIR/.work" \
    MERGED_PFX="$MERGED_PFX" \
    ORIG_UID="$ORIG_UID" \
    ORIG_GID="$ORIG_GID" \
    UNIT_NAME="umu-pfx-$prefix_name.scope" \
    sh -c '
      mount --bind "$SECURE_MOUNT" "$MOUNT_DIR" || exit 1
      mount -t overlay overlay -o "lowerdir=$BASE_PFX,upperdir=$UPPER_DIR,workdir=$WORK_DIR" "$MERGED_PFX" || exit 1
      exec unshare --user --map-user="$ORIG_UID" --map-group="$ORIG_GID" env WINEPREFIX="$MERGED_PFX" app2unit -u "$UNIT_NAME" -- "$@"
    ' _ "$@"
}

if [[ "$USE_VPN" == "1" ]]; then
   export SOCKET_DIR=$(mktemp -d /tmp/umu-vpn-XXXXXX)
   export SOCKET_PATH="$SOCKET_DIR/steam_pass"

   # Start background bridge; cleanup_all handles shutdown on exit
   rust-bridge -r pass --address "127.0.0.1:[57343,27060]" -s "$SOCKET_PATH" &

   export _VPN_LD_PRELOAD="$LD_PRELOAD"
   export _VPN_LD_LIBRARY_PATH="$LD_LIBRARY_PATH"

   vpnify sh -c '
     rust-bridge -r listen --address "127.0.0.1:[57343,27060]" -s "$SOCKET_PATH" -d
     export LD_PRELOAD="$_VPN_LD_PRELOAD"
     export LD_LIBRARY_PATH="$_VPN_LD_LIBRARY_PATH"
     "$0" "$@"
     pkill -15 -f "rust-bridge.*listen.*$SOCKET_PATH" 2>/dev/null || true
   ' run_overlay_app "${CMD[@]}"
else
  run_overlay_app "${CMD[@]}"
fi
