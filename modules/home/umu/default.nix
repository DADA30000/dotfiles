{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  # ---------------------------------------------------------------------------
  # Declarative Proton Versions Registry
  # To add a new Proton, simply add an attribute here.
  # ---------------------------------------------------------------------------
  protons = {
    proton-cachyos-11 = {
      displayName = "Proton CachyOS 11";
      pkg = pkgs.stdenv.mkDerivation (finalAttrs: {
        name = "proton-cachyos";
        version = "11.0-20260703";
        phases = [ "installPhase" ];
        src = pkgs.fetchurl {
          url = "https://github.com/CachyOS/${finalAttrs.name}/releases/download/cachyos-${finalAttrs.version}-slr/${finalAttrs.name}-${finalAttrs.version}-slr-x86_64.tar.xz";
          hash = "sha512-cT/gCNZ+NJGu87Wx2a4sES18K1iz8j/COH0RIvwTH/fn8OonxnvyeXPZBr3OYjXDQJhTDsTHhgWUOLFTxuFhhw==";
        };
        installPhase = ''
          mkdir -p "$out"
          tar -C "$out" --strip-components=1 -xf "$src"
        '';
      });
    };

    proton-ge-10 = {
      displayName = "Proton GE 10";
      pkg = pkgs.stdenv.mkDerivation (finalAttrs: {
        name = "GE-Proton";
        version = "10-34";
        phases = [ "installPhase" ];
        src = pkgs.fetchurl {
          url = "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${finalAttrs.name}${finalAttrs.version}/${finalAttrs.name}${finalAttrs.version}.tar.gz";
          hash = "sha256-UcWAtmqDPHOZj+APBxfurFcZdlQECi8u1RiePuaNdz0=";
        };
        installPhase = ''
          mkdir -p "$out"
          tar -C "$out" --strip-components=1 -xf "$src"
        '';
      });
    };

    proton-umu-10 = {
      displayName = "Proton UMU 10";
      default = true;
      pkg = pkgs.stdenv.mkDerivation (finalAttrs: {
        name = "UMU-Proton";
        version = "10.0-4";
        phases = [ "installPhase" ];
        src = pkgs.fetchurl {
          url = "https://github.com/Open-Wine-Components/umu-proton/releases/download/${finalAttrs.name}-${finalAttrs.version}/${finalAttrs.name}-${finalAttrs.version}.tar.gz";
          hash = "sha256-YumeApoY+jE+b6Y9QjkJGBAXMKlA40kcVNnVjKuIfGk=";
        };
        installPhase = ''
          mkdir -p "$out"
          tar -C "$out" --strip-components=1 -xf "$src"
        '';
      });
    };

    proton-umu-9 = {
      displayName = "Proton UMU 9";
      pkg = pkgs.stdenv.mkDerivation (finalAttrs: {
        name = "UMU-Proton";
        version = "9.0-4e";
        phases = [ "installPhase" ];
        src = pkgs.fetchurl {
          url = "https://github.com/Open-Wine-Components/umu-proton/releases/download/${finalAttrs.name}-${finalAttrs.version}/${finalAttrs.name}-${finalAttrs.version}.tar.gz";
          hash = "sha256-1TYX073YlPTVyP1D6Cf/+7zbtJv0c9f7O+JhjdRx6/M=";
        };
        installPhase = ''
          mkdir -p "$out"
          tar -C "$out" --strip-components=1 -xf "$src"
        '';
      });
    };

    proton-umu-8 = {
      displayName = "Proton UMU 8";
      pkg = pkgs.stdenv.mkDerivation (finalAttrs: {
        name = "ULWGL-Proton";
        version = "8.0-5-3";
        phases = [ "installPhase" ];
        src = pkgs.fetchurl {
          url = "https://github.com/Open-Wine-Components/umu-proton/releases/download/${finalAttrs.name}-${finalAttrs.version}/${finalAttrs.name}-${finalAttrs.version}.tar.gz";
          hash = "sha256-JmBo/hk5pBnzi3JrRkv9WlEoCPYpe9AWs7Mcns7j0bA=";
        };
        installPhase = ''
          mkdir -p "$out"
          tar -C "$out" --strip-components=1 -xf "$src"
        '';
      });
    };

    proton-ge-latest = {
      displayName = "Proton GE (Latest)";
      pkg = pkgs.proton-ge-bin.steamcompattool;
    };
  };

  # Automatically resolve default proton
  defaultProtonCode = lib.findFirst (name: protons.${name}.default or false) (builtins.head (
    builtins.attrNames protons
  )) (builtins.attrNames protons);

  defaultProton = protons.${defaultProtonCode};

  protonCaseBranches = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (codeName: p: ''
      "${p.displayName}" | "${codeName}")
        export PROTONPATH="$SECURE_MOUNT/proton/${codeName}"
        ;;
    '') protons
  );

  # ---------------------------------------------------------------------------
  # Steam Linux Runtimes
  # ---------------------------------------------------------------------------
  steamrt4_data = builtins.fromJSON (builtins.readFile ../../../stuff/home/umu/steamrt4.json);
  steamrt3_data = builtins.fromJSON (builtins.readFile ../../../stuff/home/umu/steamrt3.json);

  steamrt3 = pkgs.stdenv.mkDerivation {
    name = "steamrt3";
    version = steamrt3_data.version;
    phases = [ "installPhase" ];
    src = pkgs.fetchurl {
      url = "https://repo.steampowered.com/steamrt3/images/${steamrt3_data.version}/SteamLinuxRuntime_sniper.tar.xz";
      hash = steamrt3_data.hash;
    };
    installPhase = ''
      mkdir -p "$out"
      cd "$out"
      tar -C . --strip-components=1 -xf "$src"
      ln -s "_v2-entry-point" "umu"
      echo "ok" > ".installed.ok"
    '';
  };

  steamrt4 = pkgs.stdenv.mkDerivation {
    name = "steamrt4";
    version = steamrt4_data.version;
    phases = [ "installPhase" ];
    src = pkgs.fetchurl {
      url = "https://repo.steampowered.com/steamrt4/images/${steamrt4_data.version}/SteamLinuxRuntime_4.tar.xz";
      hash = steamrt4_data.hash;
    };
    installPhase = ''
      mkdir -p "$out"
      cd "$out"
      tar -C . --strip-components=1 -xf "$src"
      ln -s "_v2-entry-point" "umu"
      echo "ok" > ".installed.ok"
    '';
  };

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

  patch-proton = pkgs.writers.writePython3 "patch-proton" { doCheck = false; } ''
    import os
    import sys

    for path in sys.argv[1:]:
        if not os.path.exists(path):
            continue
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            s = f.read()

        if "import filecmp" not in s:
            s = s.replace("#!/usr/bin/env python3\n", "#!/usr/bin/env python3\nimport filecmp\n", 1)

        old_check = "        if file_exists(dst, follow_symlinks=False):\n            os.remove(dst)"
        new_check = (
            "        if file_exists(dst, follow_symlinks=False):\n"
            "            if os.path.isfile(dst) and os.path.isfile(src):\n"
            "                try:\n"
            "                    if os.path.samefile(src, dst) or (os.path.getsize(src) == os.path.getsize(dst) and filecmp.cmp(src, dst, shallow=False)):\n"
            "                        return\n"
            "                except OSError:\n"
            "                    pass\n"
            "            os.remove(dst)"
        )
        if old_check in s:
            s = s.replace(old_check, new_check, 1)

        old_file_check = "        if file_exists(dst, follow_symlinks=False):\n            os.remove(dst)\n        copyfile(src, dst)"
        new_file_check = (
            "        if file_exists(dst, follow_symlinks=False):\n"
            "            if os.path.isfile(dst) and os.path.isfile(src):\n"
            "                try:\n"
            "                    if os.path.samefile(src, dst) or (os.path.getsize(src) == os.path.getsize(dst) and filecmp.cmp(src, dst, shallow=False)):\n"
            "                        return\n"
            "                except OSError:\n"
            "                    pass\n"
            "            os.remove(dst)\n"
            "        copyfile(src, dst)"
        )
        if old_file_check in s:
            s = s.replace(old_file_check, new_file_check, 1)

        os.chmod(path, 0o755)
        with open(path, "w", encoding="utf-8") as f:
            f.write(s)
        print("Successfully processed proton script:", path)
  '';

  # ---------------------------------------------------------------------------
  # UMU Runtime EROFS Image (Base Prefixes + Runtimes + Protons)
  # ---------------------------------------------------------------------------
  runtime = pkgs.stdenv.mkDerivation {
    name = "umu-runtime.img";
    version = steamrt4_data.version;
    nativeBuildInputs = [
      pkgs.erofs-utils
      pkgs.bubblewrap
      pkgs.util-linux
      pkgs.umu-launcher
    ];
    phases = [ "installPhase" ];
    installPhase = ''
      # =========================================================================
      # STAGE 1: Generate clean base prefixes using wineboot inside bwrap
      # =========================================================================
      cat << "EOF" > run-wineboot-stage.sh
      #!/bin/sh
      set -e

      TMP_HOME="$TMPDIR/stage1_home"
      mkdir -p "$TMP_HOME/.local/share/umu/steamrt3"
      mkdir -p "$TMP_HOME/.local/share/umu/steamrt4"
      mkdir -p "$TMP_HOME/.local/share/umu/proton"

      echo "Setting up temporary runtimes for wineboot..."
      cp -rL --no-preserve=ownership "${steamrt3}/." "$TMP_HOME/.local/share/umu/steamrt3/"
      cp -rL --no-preserve=ownership "${steamrt4}/." "$TMP_HOME/.local/share/umu/steamrt4/"

      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (codeName: p: ''
          cp -rL --no-preserve=ownership "${p.pkg}/." "$TMP_HOME/.local/share/umu/proton/${codeName}/"
        '') protons
      )}

      chmod -R u+w "$TMP_HOME/.local/share/umu"

      # Patch proton scripts inside stage 1
      ${patch-proton} "$TMP_HOME"/.local/share/umu/proton/*/proton

      export HOME="$TMP_HOME"
      export XDG_DATA_HOME="$TMP_HOME/.local/share"
      export UMU_RUNTIME_UPDATE=0
      BASE_PFX_OUT="$TMPDIR/base_prefixes"
      mkdir -p "$BASE_PFX_OUT"

      run_wineboot_for_proton() {
        local name="$1"
        local pfx_path="$BASE_PFX_OUT/$name"
        local proton_path="$TMP_HOME/.local/share/umu/proton/$name"

        echo "Generating base prefix via wineboot for: $name"
        mkdir -p "$pfx_path"
        WINEPREFIX="$pfx_path" PROTONPATH="$proton_path" umu-run wineboot -u

        # Inject OpenAL32.dll into syswow64
        mkdir -p "$pfx_path/drive_c/windows/syswow64"
        cp --no-preserve=mode "${openal}/bin/OpenAL32.dll" "$pfx_path/drive_c/windows/syswow64/OpenAL32.dll"

        # Inject Steam client stubs dynamically
        local steam_dest="$pfx_path/drive_c/Program Files (x86)/Steam"
        mkdir -p "$steam_dest"

        local cand64
        cand64=$(find "$proton_path" -path "*/x86_64-windows/lsteamclient.dll" 2>/dev/null | head -n 1)
        if [ -n "$cand64" ]; then
          cp --no-preserve=mode "$cand64" "$steam_dest/steamclient64.dll"
        fi

        local cand32
        cand32=$(find "$proton_path" -path "*/i386-windows/lsteamclient.dll" 2>/dev/null | head -n 1)
        if [ -n "$cand32" ]; then
          cp --no-preserve=mode "$cand32" "$steam_dest/steamclient.dll"
        fi

        # Resolve all file symlinks into actual regular files
        echo "Resolving file symlinks in base prefix for: $name"
        find "$pfx_path" -type l | while read -r symlink; do
          target=$(readlink -f "$symlink" 2>/dev/null || true)
          if [ -n "$target" ] && [ -f "$target" ]; then
            rm -f "$symlink"
            cp "$target" "$symlink"
          fi
        done

        # Remove sandbox-specific paths
        rm -f "$pfx_path/dosdevices/x:"
        rm -f "$pfx_path/drive_c/users/nixbld"

        # Normalize config_info and .update-timestamp in base prefix
        if [ -f "$pfx_path/config_info" ]; then
          sed -i "s|$TMP_HOME|@UMU_USER_HOME@|g" "$pfx_path/config_info"
          sed -i 's|^[0-9]\+\.[0-9]\+$|1.0|' "$pfx_path/config_info"
        fi
        echo -n "1" > "$pfx_path/.update-timestamp"

        touch "$pfx_path/creation_sync_guard"
        touch "$pfx_path/check-do_not_delete_this"
        ln -sfn . "$pfx_path/pfx"
      }

      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (codeName: _: ''
          run_wineboot_for_proton "${codeName}"
        '') protons
      )}

      echo "Base prefixes generated successfully. Cleaning temporary runtimes..."
      rm -rf "$TMP_HOME"
      EOF

      chmod +x run-wineboot-stage.sh

      # Run stage 1 inside bwrap to provide /sys, /proc, /dev and FHS root
      bwrap \
        --tmpfs / \
        --dir /sys \
        --ro-bind /nix /nix \
        --ro-bind /bin /bin \
        --ro-bind /etc /etc \
        --dev /dev \
        --proc /proc \
        --bind /tmp /tmp \
        --bind /build /build \
        ./run-wineboot-stage.sh

      rm -f run-wineboot-stage.sh

      # =========================================================================
      # STAGE 2: Assemble clean EROFS filesystem with runtime & base prefixes
      # =========================================================================
      echo "Assembling final runtime image..."
      mkdir -p build/proton
      cp -aL "${steamrt3}" build/steamrt3
      cp -aL "${steamrt4}" build/steamrt4

      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (codeName: p: ''
          cp -aL "${p.pkg}" build/proton/${codeName}
        '') protons
      )}

      # Ensure permissions for patching and pressure-vessel
      chmod -R u+w build

      # Patch proton scripts in final image
      ${patch-proton} build/proton/*/proton

      # Copy generated clean base prefixes into image
      mv "$TMPDIR/base_prefixes" build/base_prefixes

      # Resolve any remaining file symlinks in build/ to actual file copies
      echo "Resolving all file symlinks in build image..."
      find build -type l | while read -r symlink; do
        target=$(readlink -f "$symlink" 2>/dev/null || true)
        if [ -n "$target" ] && [ -f "$target" ]; then
          rm -f "$symlink"
          cp "$target" "$symlink"
        fi
      done

      # Ensure permissions for pressure-vessel
      chmod -R u+w build

      # Create immutable EROFS with inode deduplication
      mkfs.erofs \
        --force-uid=0 \
        --force-gid=0 \
        --workers "$NIX_BUILD_CORES" \
        --ignore-mtime \
        --zD=1 \
        -z zstd,19 \
        -C 65536 \
        -m 65536:zstd,19 \
        -E 48bit,all-fragments,dot-omitted,fragdedupe=inode \
        -T 0 \
        -x -1 \
        "$out" \
        build
    '';
  };

  # ---------------------------------------------------------------------------
  # UMU Launcher Environment
  # ---------------------------------------------------------------------------
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

  # ---------------------------------------------------------------------------
  # Helper Tools & Scripts
  # ---------------------------------------------------------------------------
  create-desktop-with-umu = pkgs.writeShellScriptBin "create-desktop-with-umu" ''
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
        env_proton_type=''${UMU_PROTON_TYPE:-"${defaultProton.displayName}"}
        env_gpu_select=''${UMU_GPU_SELECT:-Автоматически}
        env_steam=''${USE_STEAM_INTEGRATION:-0}
        env_overlay=''${USE_STEAM_OVERLAY:-0}
        env_vpn=''${USE_VPN:-0}
        env_gameid=''${GAMEID:-""}

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
  '';

  umu-run-wrapper = pkgs.writeShellScriptBin "umu-run-wrapper" ''
    set -e

    # 1. Resolve Prefix Storage Directory
    prefix_name="''${UMU_PREFIX_NAME:-default}"
    PREFIX_DIR="$HOME/.umu/$prefix_name"
    ORIG_UID=$(id -u)
    RUNTIME_ROOT="''${XDG_RUNTIME_DIR:-/run/user/$ORIG_UID}"
    MERGED_PFX="$RUNTIME_ROOT/umu-pfx/$prefix_name"

    cleanup_all() {
      local exit_code=$?
      trap - EXIT INT TERM

      if [[ -n "''${SOCKET_PATH:-}" ]]; then
        pkill -f "rust-bridge.*$SOCKET_PATH" 2>/dev/null || true
        rm -rf "$SOCKET_DIR" 2>/dev/null || true
      fi

      if [[ -n "''${MERGED_PFX:-}" ]]; then
        unshare -r umount -l "$MERGED_PFX" 2>/dev/null || umount -l "$MERGED_PFX" 2>/dev/null || true
        rmdir "$MERGED_PFX" 2>/dev/null || true
      fi
      if [[ -n "''${PREFIX_DIR:-}" ]]; then
        unshare -r rm -rf "$PREFIX_DIR/.work" 2>/dev/null || rm -rf "$PREFIX_DIR/.work" 2>/dev/null || true
      fi

      if [[ $exit_code -eq 0 ]]; then
        ${pkgs.libnotify}/bin/notify-send "Closed" "UMU exited ($prefix_name)"
      else
        ${pkgs.libnotify}/bin/notify-send -u critical "Closed (Error $exit_code)" "UMU exited with error ($prefix_name)"
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
        ${pkgs.libnotify}/bin/notify-send -u critical "UMU Prefix Error" "Directory '$PREFIX_DIR' contains non-overlay files! Overlay prefix must only contain 'upper' and '.work'."
        echo "ERROR: Prefix '$PREFIX_DIR' is not a valid overlay prefix directory!" >&2
        echo "Found non-overlay files:" >&2
        echo "$unexpected_items" >&2
        echo "Please migrate or remove legacy prefix contents." >&2
        exit 1
      fi
    else
      mkdir -p "$PREFIX_DIR/upper" "$PREFIX_DIR/.work"
    fi

    ${pkgs.libnotify}/bin/notify-send "Starting UMU" "Launching $prefix_name"

    # 4. Resolve Proton version dynamically
    ORIG_UID=$(id -u)
    SECURE_MOUNT="/run/umu/$ORIG_UID"
    MOUNT_DIR="''${XDG_DATA_HOME:-$HOME/.local/share}/umu"

    if [[ -z "$(printenv PROTONPATH)" ]]; then
      case "$UMU_PROTON_TYPE" in
        ${protonCaseBranches}
        *)
          export PROTONPATH="$SECURE_MOUNT/proton/${defaultProtonCode}"
          ;;
      esac
    fi

    # 5. Ensure runtime EROFS is mounted via hardened systemd service
    if ! mountpoint -q "$SECURE_MOUNT"; then
      if ! systemctl start "umu-mount@$ORIG_UID.service" || ! mountpoint -q "$SECURE_MOUNT"; then
        ${pkgs.libnotify}/bin/notify-send "Closed" "UMU runtime mount failed."
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
    CURRENT_PROTON_VER=$(cat "$SECURE_MOUNT/proton/$PROTON_NAME/version" 2>/dev/null || echo "unknown")
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
    fi

    unset ALSOFT_DRIVERS
    export PROTON_DISCORD_BRIDGE=1
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
       ' run_overlay_app "''${CMD[@]}"
    else
      run_overlay_app "''${CMD[@]}"
    fi
  '';

  cfg = config.umu;
in
{
  options.umu = {
    enable = lib.mkEnableOption "umu - universal windows apps launcher (user environment & tools)";
  };

  config = lib.mkIf cfg.enable {
    xdg = {
      dataFile = {
        "umu-ui/games_appid.json".source = "${inputs.steam-app-id-list}/data/games_appid.json";
        "umu-ui/proton_versions.json".text = builtins.toJSON (
          lib.mapAttrsToList (codeName: p: {
            name = p.displayName;
            code = codeName;
            default = p.default or false;
          }) protons
        );
        # Link the EROFS runtime image to standard location
        "umu/runtime.img".source = "${runtime}";
      };
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
      pkgs.pciutils
      pkgs.icoutils
      pkgs.imagemagick
      pkgs.libnotify
      pkgs.winetricks
      pkgs.protontricks
      pkgs.xdg-utils
      create-desktop-with-umu
      umu-run-wrapper
    ];
  };
}
