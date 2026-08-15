{
  config,
  pkgs,
  lib,
  inputs,
  mkPyApp,
  ...
}:
with lib;
let
  patched-umu = pkgs.umu-launcher-unwrapped.overrideAttrs (oldAttrs: {
    postPatch = (oldAttrs.postPatch or "") + ''
      substituteInPlace umu/umu_run.py --replace-fail 'env["SteamGameId"] = env["SteamAppId"]' 'env["SteamGameId"] = os.environ.get("SteamGameId", env["SteamAppId"])'
    '';
  });

  umu = pkgs.steam.buildRuntimeEnv {
    pname = "umu-launcher";
    inherit (patched-umu) version meta;

    extraPkgs = pkgs: [ patched-umu ];
    executableName = patched-umu.meta.mainProgram;
    runScript = lib.getExe patched-umu;

    privateTmp = false;
    dieWithParent = false;

    extraInstallCommands = ''
      ln -s ${patched-umu}/lib $out/lib
      ln -s ${patched-umu}/share $out/share
    '';
  };

  protonVersions = [
    {
      name = "Proton GE (Latest)";
      path = "$HOME/.local/share/umu/proton/proton-ge-latest";
    }
    {
      name = "Proton GE 10";
      path = "$HOME/.local/share/umu/proton/proton-ge-10";
    }
    {
      name = "Proton UMU 10";
      path = "$HOME/.local/share/umu/proton/proton-umu-10";
      default = true;
    }
    {
      name = "Proton UMU 9";
      path = "$HOME/.local/share/umu/proton/proton-umu-9";
    }
    {
      name = "Proton UMU 8";
      path = "$HOME/.local/share/umu/proton/proton-umu-8";
    }
  ];

  defaultProton = findFirst (v: v.default or false) (builtins.head protonVersions) protonVersions;

  protonCaseBranches = concatStringsSep "\n" (
    map (v: ''"${v.name}") export PROTONPATH="${v.path}" ;;'') protonVersions
  );

  openal =
    (pkgs.pkgsCross.mingw32.openal.override {
      alsaSupport = false;
      pulseSupport = false;
      dbusSupport = false;
    }).overrideAttrs
      (old: {
        buildInputs = [ ];
        nativeBuildInputs = old.nativeBuildInputs ++ [
          pkgs.cmake
          pkgs.ninja
        ];
        meta = old.meta // {
          platforms = [ "i686-windows" ];
        };
        preConfigure = (old.preConfigure or "") + ''
          export LDFLAGS="$LDFLAGS -static -static-libgcc -static-libstdc++"
        '';
        cmakeFlags = (old.cmakeFlags or [ ]) ++ [
          "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
          "-DALSOFT_REQUIRE_WINMM=ON"
          "-DALSOFT_REQUIRE_DSOUND=ON"
          "-DALSOFT_BACKEND_ALSA=OFF"
          "-DALSOFT_BACKEND_OSS=OFF"
          "-DALSOFT_BACKEND_PULSEAUDIO=OFF"
          "-DALSOFT_BACKEND_JACK=OFF"
          "-DALSOFT_EXAMPLES=OFF"
          "-DALSOFT_UTILS=OFF"
        ];
      });

  cfg = config.umu;

  mkUmuApp =
    {
      name,
      src,
      pathDeps ? [ ],
    }:
    (mkPyApp { inherit name src pathDeps; }).overrideAttrs {
      preFixup = ''
        gappsWrapperArgs+=(
          --prefix PATH : "${lib.makeBinPath pathDeps}"
          --set STEAM_APP_ID_LIST_PATH "${inputs.steam-app-id-list}/data/games_appid.json"
          --set UMU_PROTON_VERSIONS_JSON ${
            lib.escapeShellArg (
              builtins.toJSON (
                map (v: {
                  inherit (v) name;
                  default = v.default or false;
                }) protonVersions
              )
            )
          }
        )
      '';
    };
in
{
  options.umu = {
    enable = mkEnableOption "umu - universal windows apps launcher";
  };

  config = mkIf cfg.enable {
    xdg = {
      mimeApps.defaultApplications = {
        "application/vnd.microsoft.portable-executable" = "run-exe.desktop";
        "application/x-msi" = "run-exe.desktop";
        "application/x-msdownload" = "run-exe.desktop";
        "application/x-ms-shortcut" = "run-exe.desktop";
        "application/x-mswinurl" = "run-exe.desktop";
        "application/x-ms-dos-executable" = "run-exe.desktop";
        "application/x-bat" = "run-exe.desktop";
      };
      desktopEntries = {
        run-exe = {
          exec = "run-exe %f";
          mimeType = [
            "application/vnd.microsoft.portable-executable"
            "application/x-msi"
            "application/x-msdownload"
            "application/x-ms-shortcut"
            "application/x-bat"
            "application/x-ms-dos-executable"
            "application/x-mswinurl"
          ];
          name = "Execute Windows file";
          type = "Application";
          icon = "wine";
          settings.StartupWMClass = "run-exe";
        };
        manage-umu-shortcuts = {
          exec = "manage-umu-shortcuts";
          name = "Manage UMU Shortcuts";
          type = "Application";
          icon = "system-run";
          categories = [
            "Settings"
            "Utility"
          ];
          settings.StartupWMClass = "manage-umu-shortcuts";
        };
        manage-umu-prefixes = {
          exec = "manage-umu-prefixes";
          name = "Manage UMU Prefixes";
          type = "Application";
          icon = "folder-wine";
          categories = [
            "Settings"
            "Utility"
          ];
          settings.StartupWMClass = "manage-umu-prefixes";
        };
      };
    };
    home.packages = [
      # 1. run-exe
      (mkUmuApp {
        name = "run-exe";
        src = ../../../stuff/modules/home/umu/run_exe.py;
        pathDeps = [
          pkgs.pciutils
          pkgs.exiftool
          pkgs.icoutils
          pkgs.imagemagick
        ];
      })

      # 2. manage-umu-shortcuts
      (mkUmuApp {
        name = "manage-umu-shortcuts";
        src = ../../../stuff/modules/home/umu/manage_shortcuts.py;
        pathDeps = [
          pkgs.pciutils
          pkgs.imagemagick
        ];
      })

      # 3. manage-umu-prefixes
      (mkUmuApp {
        name = "manage-umu-prefixes";
        src = ../../../stuff/modules/home/umu/manage_prefixes.py;
        pathDeps = [
          pkgs.libnotify
          pkgs.winetricks
          pkgs.protontricks
          pkgs.xdg-utils
        ];
      })

      # 4. fix-umu-path
      (mkUmuApp {
        name = "fix-umu-path";
        src = ../../../stuff/modules/home/umu/fix_path.py;
        pathDeps = [
          pkgs.libnotify
          pkgs.xdg-utils
        ];
      })

      (pkgs.writeShellScriptBin "umu-run-wrapper" ''
        if [[ -z "$WINEPREFIX" ]]; then
          prefix_name=''${UMU_PREFIX_NAME:-default}
          export WINEPREFIX=$HOME/.umu/$prefix_name
        fi
        if [[ ! -f "$WINEPREFIX/check-do_not_delete_this" ]]; then
          mkdir -p "$WINEPREFIX/drive_c/windows/syswow64"
          cp --no-preserve=mode "${openal}/bin/OpenAL32.dll" "$WINEPREFIX/drive_c/windows/syswow64/OpenAL32.dll"
          touch "$WINEPREFIX/check-do_not_delete_this"
        fi
        ${pkgs.libnotify}/bin/notify-send "Starting UMU"

        if [[ -z "$(printenv PROTONPATH)" ]]; then
          case "$UMU_PROTON_TYPE" in
            ${protonCaseBranches}
            *)
              export PROTONPATH="$HOME/.local/share/umu/proton/proton-umu-10"
              ;;
          esac
        fi

        MOUNT_DIR="''${XDG_DATA_HOME:-$HOME/.local/share}/umu"
        if [[ -x "/run/wrappers/bin/prepare-umu" ]]; then
          /run/wrappers/bin/prepare-umu
          t=10
          while ! mountpoint -q "$MOUNT_DIR" || [ $(find "$MOUNT_DIR" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l) -lt 2 ]; do
            sleep 0.1
            if ((--t <= 0)); then
              ${pkgs.libnotify}/bin/notify-send "Closed" "Timeout. Mount failed."
              exit 1
            fi
          done
        else
          ${pkgs.libnotify}/bin/notify-send "Closed" "prepare-umu not found"
          exit 1
        fi

        mkdir -p "$WINEPREFIX/drive_c/Program Files (x86)/Steam"
        cp --no-preserve=mode "$PROTONPATH/files/lib/wine/x86_64-windows/lsteamclient.dll" "$WINEPREFIX/drive_c/Program Files (x86)/Steam/steamclient64.dll"
        cp --no-preserve=mode "$PROTONPATH/files/lib/wine/i386-windows/lsteamclient.dll" "$WINEPREFIX/drive_c/Program Files (x86)/Steam/steamclient.dll"

        if [[ "$USE_STEAM_INTEGRATION" == "1" ]]; then
          export WINEDLLOVERRIDES="steamclient64,SteamFix64,steam_api64,OnlineFix64,SteamOverlay64=n,b;$WINEDLLOVERRIDES"
        fi

        unset ALSOFT_DRIVERS
        export WINEDLLOVERRIDES="voices38,dxgi,winhttp,winmm,version=n,b;$WINEDLLOVERRIDES"
        export UMU_RUNTIME_UPDATE=0
        export PROTON_ENABLE_WAYLAND=''${PROTON_ENABLE_WAYLAND:-1}
        cd "$(dirname "$1")" &> /dev/null || true

        get_pci_id() {
          ${pkgs.pciutils}/bin/lspci -nn | grep -E "VGA compatible controller|3D controller|Display controller" | grep -i -E "$1" | grep -o -E "\[[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\]" | head -n 1 | tr -d '[]'
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
          CMD+=(${pkgs.gamemode}/bin/gamemoderun)
        fi
        if [[ "$USE_MANGOHUD" != "0" ]]; then
          CMD+=(${pkgs.mangohud}/bin/mangohud)
        fi
        CMD+=(${umu}/bin/umu-run "$@")

        if [[ "$USE_STEAM_OVERLAY" == "1" ]]; then
          export SteamGameId=480
          export ENABLE_VK_LAYER_VALVE_steam_overlay_1=1
          export LD_PRELOAD="$LD_PRELOAD:$HOME/.steam/bin32/gameoverlayrenderer.so:$HOME/.steam/bin64/gameoverlayrenderer.so"
          export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${pkgs.libGL}/lib:${pkgs.pkgsi686Linux.libGL}/lib"
        fi

        if [[ "$USE_VPN" == "1" ]]; then
           export SOCKET_DIR=$(mktemp -d /tmp/umu-vpn-XXXXXX)
           export SOCKET_PATH="$SOCKET_DIR/steam_pass"

           rust-bridge -r pass --address "127.0.0.1:[57343,27060]" -s "$SOCKET_PATH" &

           cleanup_vpn() {
             pkill -f "rust-bridge.*$SOCKET_PATH" 2>/dev/null || true
             rm -rf "$SOCKET_DIR"
           }
           trap cleanup_vpn EXIT INT TERM

           export _VPN_LD_PRELOAD="$LD_PRELOAD"
           export _VPN_LD_LIBRARY_PATH="$LD_LIBRARY_PATH"

           vpnify sh -c '
             rust-bridge -r listen --address "127.0.0.1:[57343,27060]" -s "$SOCKET_PATH" -d
             
             export LD_PRELOAD="$_VPN_LD_PRELOAD"
             export LD_LIBRARY_PATH="$_VPN_LD_LIBRARY_PATH"
             
             "$0" "$@"
             
             pkill -15 -f "rust-bridge.*listen.*$SOCKET_PATH" 2>/dev/null || true
           ' "''${CMD[@]}"

        else
          "''${CMD[@]}"
        fi

        ${pkgs.libnotify}/bin/notify-send "Closed" "UMU exited (if you didn't close the app, app might've crashed)"
      '')
      (pkgs.writeShellScriptBin "scan-umu-for-lnk" ''
        if [[ -z "$WINEPREFIX" ]]; then
          prefix_name=''${UMU_PREFIX_NAME:-default}
          export WINEPREFIX=$HOME/.umu/$prefix_name
        fi

        cleanup-desktop-with-umu

        pids=()
        MAX_JOBS=16

        throttle_jobs() {
          local temp_pids=()
          for pid in "''${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
              temp_pids+=("$pid")
            fi
          done
          pids=("''${temp_pids[@]}")
          while [[ ''${#pids[@]} -ge $MAX_JOBS ]]; do
            sleep 0.05
            temp_pids=()
            for pid in "''${pids[@]}"; do
              if kill -0 "$pid" 2>/dev/null; then
                temp_pids+=("$pid")
              fi
            done
            pids=("''${temp_pids[@]}")
          done
        }

        SEARCH_DIRS=()
        if [[ -d "$WINEPREFIX/drive_c/users" ]]; then
          while IFS= read -r -d "" d; do
            [[ -d "$d/Desktop" ]] && SEARCH_DIRS+=("$d/Desktop")
            [[ -d "$d/AppData/Roaming/Microsoft/Windows/Start Menu/Programs" ]] && SEARCH_DIRS+=("$d/AppData/Roaming/Microsoft/Windows/Start Menu/Programs")
          done < <(find "$WINEPREFIX/drive_c/users" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
        fi

        if [[ -d "$WINEPREFIX/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs" ]]; then
          SEARCH_DIRS+=("$WINEPREFIX/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs")
        fi

        if [[ ''${#SEARCH_DIRS[@]} -eq 0 ]]; then
          exit 0
        fi

        DESKTOP_DIR="''${XDG_DATA_HOME:-$HOME/.local/share}/applications"

        while IFS= read -r -d "" lnk; do
          if grep -Fq "X-UMU-Lnk-Path=$lnk" "$DESKTOP_DIR"/umu-*.desktop 2>/dev/null; then
            continue
          fi

          throttle_jobs

          (
            metadata=$(${pkgs.exiftool}/bin/exiftool -f -p '$LocalBasePath|$CommandLineArguments' "$lnk" 2>/dev/null)
            IFS='|' read -r win_path args <<< "$metadata"

            win_path=$(echo "$win_path" | tr -d '\r')
            args=$(echo "$args" | tr -d '\r')

            if [[ "$win_path" == "-" || -z "$win_path" ]]; then
              rm -f "$lnk"
              exit 0
            fi

            if [[ "$args" == "-" ]]; then
              args=""
            fi

            norm_p=$(echo "$win_path" | tr '\\' '/')
            drive=""
            path_no_drive=""

            if [[ "$norm_p" =~ ^[a-zA-Z]: ]]; then
              drive=$(echo "$norm_p" | cut -d: -f1 | tr '[:upper:]' '[:lower:]')
              path_no_drive=$(echo "$norm_p" | sed 's/^[a-zA-Z]://')
            else
              path_no_drive="$norm_p"
            fi

            if [[ -n "$path_no_drive" && "$path_no_drive" != /* ]]; then
              path_no_drive="/$path_no_drive"
            fi

            actual_exe=""

            if [[ -n "$drive" && -d "$WINEPREFIX/dosdevices/$drive:" ]]; then
              cand=$(realpath -m "$WINEPREFIX/dosdevices/$drive:$path_no_drive" 2>/dev/null)
              if [[ -f "$cand" ]]; then
                actual_exe="$cand"
              fi
            fi

            if [[ -z "$actual_exe" && -n "$path_no_drive" && -f "$path_no_drive" ]]; then
              actual_exe="$path_no_drive"
            fi

            if [[ -z "$actual_exe" && -n "$path_no_drive" ]]; then
              cand="$WINEPREFIX/drive_c$path_no_drive"
              if [[ -f "$cand" ]]; then
                actual_exe="$cand"
              fi
            fi

            if [[ -n "$actual_exe" && -f "$actual_exe" ]]; then
              create-desktop-with-umu "$actual_exe" "$lnk" "$args"
            fi
          ) &
          pids+=("$!")
        done < <(find "''${SEARCH_DIRS[@]}" -type f \( -name "*.lnk" -o -name "*.LNK" \) -print0 2>/dev/null)

        wait
      '')
      (pkgs.writeShellScriptBin "cleanup-desktop-with-umu" ''
        PATH="${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:$PATH"
        ICON_DIR="''${XDG_DATA_HOME:-$HOME/.local/share}/icons/umu"
        DESKTOP_DIR="''${XDG_DATA_HOME:-$HOME/.local/share}/applications"
        CACHE_ICON_DIR="$HOME/.cache/umu/icons"

        if [[ -d "$CACHE_ICON_DIR" ]]; then
          rm -rf "$CACHE_ICON_DIR"/* 2>/dev/null || true
        fi

        for d_file in "$DESKTOP_DIR"/umu-*.desktop; do
          [[ -f "$d_file" ]] || continue

          actual_exe=$(grep '^X-UMU-Actual-Exe=' "$d_file" | head -n 1 | cut -d= -f2-)
          if [[ -z "$actual_exe" ]]; then
            actual_exe=$(grep '^Exec=' "$d_file" | sed -n 's/^.*umu-run-wrapper "\([^"]*\)".*/\1/p')
          fi

          game_name=$(grep '^Name=' "$d_file" | head -n 1 | cut -d= -f2-)
          icon_path=$(grep '^Icon=' "$d_file" | head -n 1 | cut -d= -f2)

          if [[ -n "$actual_exe" && ! -f "$actual_exe" ]]; then
            if [[ "$game_name" != *" (Inactive)"* ]]; then
              clean_name="$game_name"
              inactive_name="$game_name (Inactive)"
              sed -i "s/^Name=.*/Name=$inactive_name/" "$d_file"
              sed -i "s|^Exec=.*|Exec=fix-umu-path \"$d_file\"|" "$d_file"
              ${pkgs.libnotify}/bin/notify-send -u normal -i "$icon_path" "Shortcut Inactive" "Executable missing for $clean_name. Double-click shortcut to set new path."
            fi
          elif [[ -n "$actual_exe" && -f "$actual_exe" ]]; then
            if [[ "$game_name" == *" (Inactive)"* ]]; then
              clean_name="''${game_name% (Inactive)}"
              sed -i "s/^Name=.*/Name=$clean_name/" "$d_file"

              args=$(grep '^X-UMU-Raw-Args=' "$d_file" | head -n 1 | cut -d= -f2-)
              prefix=$(grep '^X-UMU-Prefix-Name=' "$d_file" | head -n 1 | cut -d= -f2-)
              gpu=$(grep '^X-UMU-GPU-Select=' "$d_file" | head -n 1 | cut -d= -f2-)
              steam=$(grep '^X-UMU-Steam-Integration=' "$d_file" | head -n 1 | cut -d= -f2-)
              overlay=$(grep '^X-UMU-Steam-Overlay=' "$d_file" | head -n 1 | cut -d= -f2-)
              proton=$(grep '^X-UMU-Proton-Type=' "$d_file" | head -n 1 | cut -d= -f2-)
              vpn=$(grep '^X-UMU-VPN=' "$d_file" | head -n 1 | cut -d= -f2-)
              gameid=$(grep '^X-UMU-Game-ID=' "$d_file" | head -n 1 | cut -d= -f2-)

              ENV_BASE="env GAMEID=$gameid USE_GAMEMODE=1 USE_MANGOHUD=1 PROTON_ENABLE_WAYLAND=1 UMU_PREFIX_NAME=$prefix UMU_PROTON_TYPE=\"$proton\" USE_STEAM_INTEGRATION=$steam USE_STEAM_OVERLAY=$overlay USE_VPN=$vpn UMU_GPU_SELECT=\"$gpu\""

              if [[ "$args" == *"%command%"* ]]; then
                prefix_args="''${args%%\%command\%*}"
                suffix_args="''${args#*\%command\%}"
                EXEC_CMD="$ENV_BASE $prefix_args umu-run-wrapper \"$actual_exe\" $suffix_args"
              else
                EXEC_CMD="$ENV_BASE umu-run-wrapper \"$actual_exe\" $args"
              fi

              sed -i "s|^Exec=.*|Exec=$EXEC_CMD|" "$d_file"
              ${pkgs.libnotify}/bin/notify-send -u normal -i "$icon_path" "Shortcut Reactivated" "Restored executable for $clean_name"
            fi
          fi
        done

        for i_file in "$ICON_DIR"/*; do
          [[ -e "$i_file" ]] || continue
          base=$(basename "$i_file" .png)
          
          if [[ ! -f "$DESKTOP_DIR/$base.desktop" && ! -f "$DESKTOP_DIR/$base-umu.desktop" ]]; then
            ${pkgs.libnotify}/bin/notify-send -u normal -i "$i_file" "Cleanup" "Removing stale icon $(basename "$i_file")"
            rm "$i_file"
          fi
        done
      '')
      (pkgs.writeShellScriptBin "create-desktop-with-umu" ''
        PATH="${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:$PATH"
        ICON_DIR="''${XDG_DATA_HOME:-$HOME/.local/share}/icons/umu"
        DESKTOP_DIR="''${XDG_DATA_HOME:-$HOME/.local/share}/applications"
        mkdir -p "$ICON_DIR" "$DESKTOP_DIR"
        actual_exe="$1"
        lnk="$2"
        args="$3"
        name="$4"
        custom_icon="$5"

        env_gamemode=''${USE_GAMEMODE:-1}
        env_mangohud=''${USE_MANGOHUD:-1}
        env_wayland=''${PROTON_ENABLE_WAYLAND:-1}
        env_prefix_name=''${UMU_PREFIX_NAME:-default}
        env_proton_type=''${UMU_PROTON_TYPE:-"${defaultProton.name}"}
        env_gpu_select=''${UMU_GPU_SELECT:-Автоматически}
        env_steam=''${USE_STEAM_INTEGRATION:-0}
        env_overlay=''${USE_STEAM_OVERLAY:-0}
        env_vpn=''${USE_VPN:-0}
        env_gameid=''${GAMEID:-""}

        export WINEPREFIX=$HOME/.umu/$env_prefix_name

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
            if [[ "$custom_icon" == *"/umu/icons/"* || "$custom_icon" == *"/cache/umu/"* ]]; then
              cp "$custom_icon" "$ICON_DIR/$ICON_FILE" 2>/dev/null
              ICON_SPEC="$ICON_DIR/$ICON_FILE"
            else
              ICON_SPEC="$custom_icon"
            fi
          else
            ICON_SPEC="$ICON_DIR/$ICON_FILE"
            if [[ ! -f "$ICON_SPEC" ]]; then
              WORK_DIR=$(mktemp -d)

              if [[ -n "$lnk" && -f "$lnk" ]]; then
                ICON_SRC_WIN=$(${pkgs.exiftool}/bin/exiftool -s3 -IconFileName "$lnk" | tr -d '\r')
              else
                ICON_SRC_WIN=""
              fi            

              if [[ -n "$ICON_SRC_WIN" ]]; then
                norm_icon=$(echo "$ICON_SRC_WIN" | tr '\\' '/')
                icon_drive=""
                icon_path_no_drive=""
                if [[ "$norm_icon" =~ ^[a-zA-Z]: ]]; then
                  icon_drive=$(echo "$norm_icon" | cut -d: -f1 | tr '[:upper:]' '[:lower:]')
                  icon_path_no_drive=$(echo "$norm_icon" | sed 's/^[a-zA-Z]://')
                else
                  icon_path_no_drive="$norm_icon"
                fi
                if [[ -n "$icon_path_no_drive" && "$icon_path_no_drive" != /* ]]; then
                  icon_path_no_drive="/$icon_path_no_drive"
                fi

                ICON_SOURCE=""
                if [[ -n "$icon_drive" && -d "$WINEPREFIX/dosdevices/$icon_drive:" ]]; then
                  cand=$(realpath -m "$WINEPREFIX/dosdevices/$icon_drive:$icon_path_no_drive" 2>/dev/null)
                  [[ -f "$cand" ]] && ICON_SOURCE="$cand"
                fi
                if [[ -z "$ICON_SOURCE" && -n "$icon_path_no_drive" && -f "$icon_path_no_drive" ]]; then
                  ICON_SOURCE="$icon_path_no_drive"
                fi
                if [[ -z "$ICON_SOURCE" && -n "$icon_path_no_drive" && -f "$WINEPREFIX/drive_c$icon_path_no_drive" ]]; then
                  ICON_SOURCE="$WINEPREFIX/drive_c$icon_path_no_drive"
                fi
                if [[ -z "$ICON_SOURCE" ]]; then
                  ICON_SOURCE="$actual_exe"
                fi
              else
                ICON_SOURCE="$actual_exe"
              fi
              
              if [[ "$ICON_SOURCE" == *.ico || "$ICON_SOURCE" == *.ICO ]]; then
                cp "$ICON_SOURCE" "$WORK_DIR/icon.ico" 2>/dev/null
              else
                ${pkgs.icoutils}/bin/wrestool -x -t 14 "$ICON_SOURCE" > "$WORK_DIR/icon.ico" 2>/dev/null
                
                if [[ ! -s "$WORK_DIR/icon.ico" ]]; then
                    ${pkgs.icoutils}/bin/wrestool -x -t 14 "$actual_exe" > "$WORK_DIR/icon.ico" 2>/dev/null
                fi
              fi
              
              if [[ -s "$WORK_DIR/icon.ico" ]]; then
                ${pkgs.imagemagick}/bin/magick "$WORK_DIR/icon.ico" "$WORK_DIR/icon.png"
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

          ENV_BASE="env GAMEID=$env_gameid USE_GAMEMODE=$env_gamemode USE_MANGOHUD=$env_mangohud PROTON_ENABLE_WAYLAND=$env_wayland UMU_PREFIX_NAME=$env_prefix_name UMU_PROTON_TYPE=\"$env_proton_type\" USE_STEAM_INTEGRATION=$env_steam USE_STEAM_OVERLAY=$env_overlay USE_VPN=$env_vpn UMU_GPU_SELECT=\"$env_gpu_select\""

          if [[ "$args" == *"%command%"* ]]; then
            prefix_args="''${args%%\%command\%*}"
            suffix_args="''${args#*\%command\%}"
            EXEC_CMD="$ENV_BASE $prefix_args umu-run-wrapper \"$actual_exe\" $suffix_args"
          else
            EXEC_CMD="$ENV_BASE umu-run-wrapper \"$actual_exe\" $args"
          fi

          cat <<EOF > "$DESKTOP_FILE"
        [Desktop Entry]
        Name=$LNK_DISPLAY_NAME
        Exec=$EXEC_CMD
        Icon=$ICON_SPEC
        Type=Application
        Categories=Game;
        Path=$(dirname "$actual_exe")
        Terminal=false
        X-UMU-Lnk-Path=$lnk
        X-UMU-Raw-Args=$args
        X-UMU-Actual-Exe=$actual_exe
        X-UMU-Prefix-Name=$env_prefix_name
        X-UMU-GPU-Select=$env_gpu_select
        X-UMU-Steam-Integration=$env_steam
        X-UMU-Steam-Overlay=$env_overlay
        X-UMU-Proton-Type=$env_proton_type
        X-UMU-VPN=$env_vpn
        X-UMU-Game-ID=$env_gameid
        EOF

          chmod +x "$DESKTOP_FILE"

          ${pkgs.libnotify}/bin/notify-send -i "$ICON_SPEC" "New game added" "Shortcut created for $LNK_DISPLAY_NAME"
        fi
      '')
    ];
  };
}
