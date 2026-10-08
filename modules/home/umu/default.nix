{
  config,
  pkgs,
  lib,
  inputs,
  evalAndSubstitute,
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
      default = true;
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
    inherit (steamrt3_data) version;
    phases = [ "installPhase" ];
    src = pkgs.fetchurl {
      url = "https://repo.steampowered.com/steamrt3/images/${steamrt3_data.version}/SteamLinuxRuntime_sniper.tar.xz";
      inherit (steamrt3_data) hash;
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
    inherit (steamrt4_data) version;
    phases = [ "installPhase" ];
    src = pkgs.fetchurl {
      url = "https://repo.steampowered.com/steamrt4/images/${steamrt4_data.version}/SteamLinuxRuntime_4.tar.xz";
      inherit (steamrt4_data) hash;
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

  patch-proton = pkgs.writers.writePython3 "patch-proton" { doCheck = false; } (
    builtins.readFile ../../../stuff/home/umu/patch-proton.py
  );

  # ---------------------------------------------------------------------------
  # UMU Runtime EROFS Image (Base Prefixes + Runtimes + Protons)
  # ---------------------------------------------------------------------------
  runtime = pkgs.stdenv.mkDerivation {
    name = "umu-runtime.img";
    inherit (steamrt4_data) version;
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

    extraPkgs = _: [ patched-umu ];
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
  create-desktop-with-umu = pkgs.writeShellScriptBin "create-desktop-with-umu" (evalAndSubstitute {
    string = builtins.readFile ../../../stuff/home/umu/create-desktop-with-umu.sh;
    scope = { inherit defaultProton; };
  });

  umu-run-wrapper = pkgs.writeShellScriptBin "umu-run-wrapper" (evalAndSubstitute {
    string = builtins.readFile ../../../stuff/home/umu/umu-run-wrapper.sh;
    scope = {
      inherit
        protonCaseBranches
        defaultProtonCode
        umu
        ;
    };
  });

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
