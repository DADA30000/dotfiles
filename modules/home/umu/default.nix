{
  config,
  pkgs,
  lib,
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
      path = "${config.xdg.dataHome}/umu/proton/proton-ge-latest";
    }
    {
      name = "Proton UMU 10";
      path = "${config.xdg.dataHome}/umu/proton/proton-umu-10";
      default = true;
    }
    {
      name = "Proton UMU 9";
      path = "${config.xdg.dataHome}/umu/proton/proton-umu-9";
    }
    {
      name = "Proton UMU 8";
      path = "${config.xdg.dataHome}/umu/proton/proton-umu-8";
    }
  ];

  # Locates the default choice, falling back to the first defined entry if default = true is omitted
  defaultProton = findFirst (v: v.default or false) (builtins.head protonVersions) protonVersions;

  # Generates the case statement choices for umu-run-wrapper using the version name as the key
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

  # Declarative PyGObject application wrapper leveraging Nixpkgs setup hooks
  mkPyApp =
    {
      name,
      src,
      pathDeps ? [ ],
    }:
    pkgs.stdenv.mkDerivation {
      pname = name;
      version = "1.0";
      inherit src;
      dontUnpack = true;

      # Automates the generation of GI_TYPELIB_PATH, XDG_DATA_DIRS, and GDK_PIXBUF_MODULE_FILE
      nativeBuildInputs = [
        pkgs.wrapGAppsHook3
        pkgs.gobject-introspection
      ];
      buildInputs = [
        pkgs.gtk3
        pkgs.gsettings-desktop-schemas
        pkgs.adwaita-icon-theme
      ];

      pythonEnv = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);

      installPhase = ''
        mkdir -p $out/bin
        echo "#!$pythonEnv/bin/python" > $out/bin/${name}
        cat $src >> $out/bin/${name}
        chmod +x $out/bin/${name}
      '';

      # Appends runtime command dependencies onto the wrapped PATH and injects the JSON list of Proton versions
      preFixup = ''
        gappsWrapperArgs+=(
          --prefix PATH : "${lib.makeBinPath pathDeps}"
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
      pkgs.yad

      # 1. run-exe
      (mkPyApp {
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
      (mkPyApp {
        name = "manage-umu-shortcuts";
        src = ../../../stuff/modules/home/umu/manage_shortcuts.py;
        pathDeps = [ pkgs.pciutils ];
      })

      # 3. manage-umu-prefixes
      (mkPyApp {
        name = "manage-umu-prefixes";
        src = ../../../stuff/modules/home/umu/manage_prefixes.py;
        pathDeps = [
          pkgs.libnotify
          pkgs.winetricks
          pkgs.protontricks
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
              export PROTONPATH="${defaultProton.path}"
              ;;
          esac
        fi

        mkdir -p "$WINEPREFIX/drive_c/Program Files (x86)/Steam"
        cp --no-preserve=mode "$PROTONPATH/files/lib/wine/x86_64-windows/lsteamclient.dll" "$WINEPREFIX/drive_c/Program Files (x86)/Steam/steamclient64.dll"
        cp --no-preserve=mode "$PROTONPATH/files/lib/wine/i386-windows/lsteamclient.dll" "$WINEPREFIX/drive_c/Program Files (x86)/Steam/steamclient.dll"

        if [[ "$USE_STEAM_INTEGRATION" == "1" ]]; then
          export WINEDLLOVERRIDES="steamclient64,voices38,dxgi,winhttp,winmm,SteamFix64,steam_api64,OnlineFix64,SteamOverlay64,version=n,b"
        else
          export WINEDLLOVERRIDES="voices38,dxgi,winhttp,winmm,version=n,b"
        fi

        if [[ "$USE_STEAM_OVERLAY" == "1" ]]; then
          export SteamGameId=480
          export ENABLE_VK_LAYER_VALVE_steam_overlay_1=1
          export LD_PRELOAD="$LD_PRELOAD:$HOME/.steam/bin32/gameoverlayrenderer.so:$HOME/.steam/bin64/gameoverlayrenderer.so"
          export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${pkgs.libGL}/lib:${pkgs.pkgsi686Linux.libGL}/lib"
        fi

        MOUNT_DIR="${config.xdg.dataHome}/umu"
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

        unset ALSOFT_DRIVERS
        export UMU_RUNTIME_UPDATE=0
        export PROTON_ENABLE_WAYLAND=''${PROTON_ENABLE_WAYLAND:-1}
        cd "$(dirname "$1")" &> /dev/null || true

        AMD_PCI_ID=$(${pkgs.pciutils}/bin/lspci -nn | grep -E "VGA compatible controller|3D controller|Display controller" | grep -i -E "AMD|Advanced Micro Devices" | grep -o -E "\[[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\]" | head -n 1 | tr -d '[]')
        NVIDIA_PCI_ID=$(${pkgs.pciutils}/bin/lspci -nn | grep -E "VGA compatible controller|3D controller|Display controller" | grep -i "NVIDIA" | grep -o -E "\[[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\]" | head -n 1 | tr -d '[]')
        INTEL_PCI_ID=$(${pkgs.pciutils}/bin/lspci -nn | grep -E "VGA compatible controller|3D controller|Display controller" | grep -i "Intel" | grep -o -E "\[[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\]" | head -n 1 | tr -d '[]')

        case "$UMU_GPU_SELECT" in
          "AMD")
            if [[ -n "$AMD_PCI_ID" ]]; then
              export DRI_PRIME="$AMD_PCI_ID!"
              export MESA_VK_DEVICE_SELECT="$AMD_PCI_ID!"
            fi
          ;;
          "Intel")
            if [[ -n "$INTEL_PCI_ID" ]]; then
              export DRI_PRIME="$INTEL_PCI_ID!"
              export MESA_VK_DEVICE_SELECT="$INTEL_PCI_ID!"
            fi
          ;;
          "Nvidia")
            export __NV_PRIME_RENDER_OFFLOAD=1
            export __GLX_VENDOR_LIBRARY_NAME=nvidia
            export __VK_LAYER_NV_optimus=NVIDIA_only
            if [[ -n "$NVIDIA_PCI_ID" ]]; then
              export DRI_PRIME="$NVIDIA_PCI_ID!"
              export MESA_VK_DEVICE_SELECT="$NVIDIA_PCI_ID!"
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

        "''${CMD[@]}"
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

        while IFS= read -r -d "" USER_PROFILE; do
          while IFS= read -r -d "" lnk; do
            
            if grep -Fq "X-UMU-Lnk-Path=$lnk" "${config.xdg.dataHome}/applications"/umu-*.desktop 2>/dev/null; then
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

              rel_path=$(echo "$win_path" | sed 's/^[A-Z]://; s/\\/\//g')
              actual_exe="$WINEPREFIX/drive_c$rel_path"

              create-desktop-with-umu "$actual_exe" "$lnk" "$args"
            ) &
            pids+=("$!")

          done < <(find "$USER_PROFILE/Desktop" "$USER_PROFILE/AppData/Roaming/Microsoft/Windows/Start Menu/Programs" "$WINEPREFIX/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs" -type f -name "*.lnk" -print0 2>/dev/null)
        done < <(find "$WINEPREFIX/drive_c/users" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

        wait
      '')
      (pkgs.writeShellScriptBin "cleanup-desktop-with-umu" ''
        PATH="${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:$PATH"
        ICON_DIR="${config.xdg.dataHome}/icons/umu"
        DESKTOP_DIR="${config.xdg.dataHome}/applications"
        CACHE_ICON_DIR="$HOME/.cache/umu/icons"

        if [[ -d "$CACHE_ICON_DIR" ]]; then
          rm -rf "$CACHE_ICON_DIR"/* 2>/dev/null || true
        fi

        for d_file in "$DESKTOP_DIR"/umu-*.desktop; do
          if [[ -f "$d_file" ]]; then
            exe_path=$(grep '^Exec=' "$d_file" | sed -n 's/^.*umu-run-wrapper "\([^"]*\)".*/\1/p')
            if [[ -n "$exe_path" && ! -f "$exe_path" ]]; then
              game_name=$(grep '^Name=' "$d_file" | head -n 1 | cut -d= -f2-)
              icon_path=$(grep '^Icon=' "$d_file" | head -n 1 | cut -d= -f2)
              ${pkgs.libnotify}/bin/notify-send -u normal -i "$icon_path" "Cleanup" "Removing shortcut for: $game_name"
              rm "$d_file"
              if [[ "$icon_path" == "$ICON_DIR"* && -f "$icon_path" ]]; then
                rm -f "$icon_path"
              fi
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
        ICON_DIR="${config.xdg.dataHome}/icons/umu"
        DESKTOP_DIR="${config.xdg.dataHome}/applications"
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

        export WINEPREFIX=$HOME/.umu/$env_prefix_name

        if [[ -f "$actual_exe" ]]; then
          PATH_HASH=$(echo "$actual_exe$args" | md5sum | cut -c1-8)
          DESKTOP_FILE="$DESKTOP_DIR/umu-$PATH_HASH.desktop"
          ICON_FILE="umu-$PATH_HASH.png"

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
                REL_ICON_PATH=$(echo "$ICON_SRC_WIN" | sed 's/^[A-Z]://; s/\\/\//g')
                ICON_SOURCE="$WINEPREFIX/drive_c$REL_ICON_PATH"
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

          AMD_PCI_ID=$(${pkgs.pciutils}/bin/lspci -nn | grep -E "VGA compatible controller|3D controller|Display controller" | grep -i -E "AMD|Advanced Micro Devices" | grep -o -E "\[[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\]" | head -n 1 | tr -d '[]')
          NVIDIA_PCI_ID=$(${pkgs.pciutils}/bin/lspci -nn | grep -E "VGA compatible controller|3D controller|Display controller" | grep -i "NVIDIA" | grep -o -E "\[[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\]" | head -n 1 | tr -d '[]')
          INTEL_PCI_ID=$(${pkgs.pciutils}/bin/lspci -nn | grep -E "VGA compatible controller|3D controller|Display controller" | grep -i "Intel" | grep -o -E "\[[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\]" | head -n 1 | tr -d '[]')

          GPU_ENV=""
          case "$env_gpu_select" in
            "AMD")
              if [[ -n "$AMD_PCI_ID" ]]; then
                GPU_ENV="DRI_PRIME=$AMD_PCI_ID! MESA_VK_DEVICE_SELECT=$AMD_PCI_ID!"
              fi
            ;;
            "Intel")
              if [[ -n "$INTEL_PCI_ID" ]]; then
                GPU_ENV="DRI_PRIME=$INTEL_PCI_ID! MESA_VK_DEVICE_SELECT=$INTEL_PCI_ID!"
              fi
            ;;
            "Nvidia")
              GPU_ENV="__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only"
              if [[ -n "$NVIDIA_PCI_ID" ]]; then
                GPU_ENV="$GPU_ENV DRI_PRIME=$NVIDIA_PCI_ID! MESA_VK_DEVICE_SELECT=$NVIDIA_PCI_ID!"
              fi
            ;;
          esac

          EXEC_BASE="env USE_GAMEMODE=$env_gamemode USE_MANGOHUD=$env_mangohud PROTON_ENABLE_WAYLAND=$env_wayland UMU_PREFIX_NAME=$env_prefix_name UMU_PROTON_TYPE=\"$env_proton_type\" USE_STEAM_INTEGRATION=$env_steam USE_STEAM_OVERLAY=$env_overlay $GPU_ENV umu-run-wrapper \"$actual_exe\""

          if [[ "$args" == *"%command%"* ]]; then
            EXEC_CMD=$(echo "$args" | sed "s|%command%|$EXEC_BASE|g")
          else
            EXEC_CMD="$EXEC_BASE $args"
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
        EOF

          chmod +x "$DESKTOP_FILE"

          ${pkgs.libnotify}/bin/notify-send -i "$ICON_SPEC" "New game added" "Shortcut created for $LNK_DISPLAY_NAME"
        fi
      '')
    ];
  };
}
