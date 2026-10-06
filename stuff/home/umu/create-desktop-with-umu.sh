PATH="%{{{pkgs.coreutils}}}/bin:%{{{pkgs.gnugrep}}}/bin:%{{{pkgs.gnused}}}/bin:$PATH"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/umu"
DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "$ICON_DIR" "$DESKTOP_DIR"
actual_exe="$1"
lnk="$2"
args="$3"
name="$4"
custom_icon="$5"

env_gamemode=${USE_GAMEMODE:-1}
env_mangohud=${USE_MANGOHUD:-1}
env_wayland=${PROTON_ENABLE_WAYLAND:-1}
env_prefix_name=${UMU_PREFIX_NAME:-default}
env_proton_type=${UMU_PROTON_TYPE:-"%{{{defaultProton.displayName}}}"}
env_gpu_select=${UMU_GPU_SELECT:-Автоматически}
env_steam=${USE_STEAM_INTEGRATION:-0}
env_overlay=${USE_STEAM_OVERLAY:-0}
env_vpn=${USE_VPN:-0}
env_gameid=${GAMEID:-""}
env_sandbox=${USE_SANDBOX:-1}
env_gamepad=${USE_GAMEPAD:-1}
env_extra_paths=${UMU_EXTRA_PATHS:-""}

PREFIX_DIR=$HOME/.umu/$env_prefix_name

if [[ -f "$actual_exe" ]]; then
  PATH_HASH=$(echo "$actual_exe$args" | md5sum | cut -c1-8)
  DESKTOP_FILE="$DESKTOP_DIR/umu-$PATH_HASH.desktop"
  ICON_FILE="umu-$PATH_HASH.png"

  if [[ -f "$DESKTOP_FILE" ]]; then
    exit 0
  fi

  LOCK_DIR="$DESKTOP_DIR/.lock-$PATH_HASH"
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    exit 0
  fi
  trap 'rm -rf "$LOCK_DIR"' EXIT

  if [[ -f "$DESKTOP_FILE" ]]; then
    exit 0
  fi

  if [[ -n "$name" ]]; then
    LNK_DISPLAY_NAME="$name"
  elif [[ -n "$lnk" ]]; then
    LNK_DISPLAY_NAME=$(basename "$lnk" | sed 's/\.[lL][nN][kK]$//')
  else
    LNK_DISPLAY_NAME=$(basename "$actual_exe" | sed 's/\.[eE][xX][eE]$//')
  fi

  if [[ -n "$custom_icon" && "$custom_icon" != "wine" ]]; then
    if [[ "$custom_icon" == *"/cache/umu/"* ]]; then
      cp "$custom_icon" "$ICON_DIR/$ICON_FILE" 2>/dev/null
      ICON_SPEC="$ICON_DIR/$ICON_FILE"
    else
      ICON_SPEC="$custom_icon"
    fi
  else
    ICON_SPEC="$ICON_DIR/$ICON_FILE"
    if [[ ! -f "$ICON_SPEC" ]]; then
      WORK_DIR=$(mktemp -d)

      ICON_SRC_WIN=""

      if [[ -n "$ICON_SRC_WIN" ]]; then
        norm_icon=$(echo "$ICON_SRC_WIN" | tr '\\' '/')
        icon_drive=""
        icon_path_no_drive=""
        if [[ "$norm_icon" =~ ^[a-zA-Z]: ]]; then
          icon_drive=$(echo "$norm_icon" | cut -d: -f1 | tr '[:upper:]' '[:lower:]')
          path_no_drive=$(echo "$norm_icon" | sed 's/^[a-zA-Z]://')
        else
          path_no_drive="$norm_icon"
        fi
        if [[ -n "$icon_path_no_drive" && "$icon_path_no_drive" != /* ]]; then
          path_no_drive="/$path_no_drive"
        fi

        ICON_SOURCE=""
        for pfx_root in "$PREFIX_DIR/upper" "$PREFIX_DIR"; do
          if [[ -n "$icon_drive" && -d "$pfx_root/dosdevices/$icon_drive:" ]]; then
            cand=$(realpath -m "$pfx_root/dosdevices/$icon_drive:$icon_path_no_drive" 2>/dev/null)
            [[ -f "$cand" ]] && ICON_SOURCE="$cand" && break
          fi
          if [[ -z "$ICON_SOURCE" && -n "$icon_path_no_drive" && -f "$pfx_root/drive_c$icon_path_no_drive" ]]; then
            ICON_SOURCE="$pfx_root/drive_c$icon_path_no_drive" && break
          fi
        done
        if [[ -z "$ICON_SOURCE" ]]; then
          ICON_SOURCE="$actual_exe"
        fi
      else
        ICON_SOURCE="$actual_exe"
      fi

      if [[ "$ICON_SOURCE" == *.ico || "$ICON_SOURCE" == *.ICO ]]; then
        cp "$ICON_SOURCE" "$WORK_DIR/icon.ico" 2>/dev/null
      else
        %{{{pkgs.icoutils}}}/bin/wrestool -x -t 14 "$ICON_SOURCE" >"$WORK_DIR/icon.ico" 2>/dev/null

        if [[ ! -s "$WORK_DIR/icon.ico" ]]; then
          %{{{pkgs.icoutils}}}/bin/wrestool -x -t 14 "$actual_exe" >"$WORK_DIR/icon.ico" 2>/dev/null
        fi
      fi

      if [[ -s "$WORK_DIR/icon.ico" ]]; then
        %{{{pkgs.imagemagick}}}/bin/magick "$WORK_DIR/icon.ico" "$WORK_DIR/icon.png"
        BIGGEST_PNG=$(ls -S "$WORK_DIR"/*.png 2>/dev/null | head -n 1)

        if [[ -n "$BIGGEST_PNG" ]]; then
          cp "$BIGGEST_PNG" "$ICON_DIR/$ICON_FILE"
          ICON_SPEC="$ICON_DIR/$ICON_FILE"
        else
          ICON_SPEC="wine"
        fi
      else
        ICON_SPEC="wine"
      fi

      rm -rf "$WORK_DIR"
    fi
  fi

  ENV_BASE="env GAMEID=$env_gameid USE_GAMEMODE=$env_gamemode USE_MANGOHUD=$env_mangohud PROTON_ENABLE_WAYLAND=$env_wayland UMU_PREFIX_NAME=$env_prefix_name UMU_PROTON_TYPE=\"$env_proton_type\" USE_STEAM_INTEGRATION=$env_steam USE_STEAM_OVERLAY=$env_overlay USE_VPN=$env_vpn UMU_GPU_SELECT=\"$env_gpu_select\" USE_SANDBOX=$env_sandbox USE_GAMEPAD=$env_gamepad USE_NETWORK=${env_network:-1} USE_STEAM_PORTS=${env_steam_ports:-$env_steam}"
  if [[ -n "$env_extra_paths" ]]; then
    ENV_BASE="$ENV_BASE UMU_EXTRA_PATHS=\"$env_extra_paths\""
  fi

  cat <<EOF >"$DESKTOP_FILE"
[Desktop Entry]
Type=Application
Name=$LNK_DISPLAY_NAME
Exec=umu-run-wrapper %k
Icon=$ICON_SPEC
Path=$(dirname "$actual_exe")
Terminal=false
Categories=Game;

# UMU Configuration
X-UMU-Actual-Exe=$actual_exe
X-UMU-Raw-Args=$args
X-UMU-Prefix-Name=$env_prefix_name
X-UMU-GPU-Select=$env_gpu_select
X-UMU-Gamemode=$env_gamemode
X-UMU-Mangohud=$env_mangohud
X-UMU-Wayland=$env_wayland
X-UMU-Steam-Integration=$env_steam
X-UMU-Steam-Overlay=$env_overlay
X-UMU-Steam-Ports=${env_steam_ports:-$env_steam}
X-UMU-Proton-Type=$env_proton_type
X-UMU-VPN=$env_vpn
X-UMU-Game-ID=$env_gameid
X-UMU-Sandbox=$env_sandbox
X-UMU-Gamepad=$env_gamepad
X-UMU-Network=${env_network:-1}
X-UMU-Extra-Paths=$env_extra_paths
X-UMU-Lnk-Path=$lnk
EOF

  chmod +x "$DESKTOP_FILE"

  %{{{pkgs.libnotify}}}/bin/notify-send -i "$ICON_SPEC" "New game added" "Shortcut created for $LNK_DISPLAY_NAME"
fi
