{
  config,
  pkgs,
  lib,
  inputs,
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

  umu-rebase-pfx = pkgs.writeScriptBin "umu-rebase-pfx" ''
    #!${pkgs.python3}/bin/python3
    import os
    import sys
    import re
    import argparse

    def parse_reg(path):
        sections = {}
        current_sec = None
        header = []
        if not path or not os.path.exists(path):
            return header, sections

        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()

        i = 0
        n = len(lines)
        while i < n:
            line = lines[i]
            stripped = line.strip()
            if stripped.startswith("[") and "]" in stripped:
                sec_name = stripped[:stripped.find("]")+1]
                current_sec = sec_name
                sections[current_sec] = {
                    "raw_header": line.rstrip("\r\n"),
                    "values": {}
                }
                i += 1
            elif current_sec is not None:
                if not stripped or stripped.startswith("#time=") or stripped.startswith(";"):
                    i += 1
                    continue
                full_val_lines = [line.rstrip("\r\n")]
                while full_val_lines[-1].endswith("\\") and i + 1 < n:
                    i += 1
                    full_val_lines.append(lines[i].rstrip("\r\n"))

                first_line = full_val_lines[0]
                eq = first_line.find("=")
                if eq != -1:
                    k = first_line[:eq].strip()
                    sections[current_sec]["values"][k] = full_val_lines
                i += 1
            else:
                header.append(line.rstrip("\r\n"))
                i += 1

        return header, sections

    def rebase_reg(old_base_p, new_base_p, upper_p):
        _, old_base = parse_reg(old_base_p)
        new_header, new_base = parse_reg(new_base_p)
        _, upper = parse_reg(upper_p)

        added_sections = {}
        modified_keys = {}

        for sec, data in upper.items():
            if sec not in old_base:
                added_sections[sec] = data
            else:
                old_vals = old_base[sec]["values"]
                for k, val_lines in data["values"].items():
                    if k not in old_vals or old_vals[k] != val_lines:
                        modified_keys.setdefault(sec, {})[k] = val_lines

        for sec, keys in modified_keys.items():
            if sec in new_base:
                new_base[sec]["values"].update(keys)
            else:
                added_sections[sec] = {"raw_header": sec, "values": keys}

        new_base.update(added_sections)

        with open(upper_p, "w", encoding="utf-8") as f:
            f.write("\n".join(new_header) + "\n")
            for sec, data in new_base.items():
                f.write("\n" + data["raw_header"] + "\n")
                for val_lines in data["values"].values():
                    f.write("\n".join(val_lines) + "\n")

    def parse_ini(path):
        sections = {}
        current_sec = "DEFAULT"
        sections[current_sec] = {"raw_header": "", "lines": []}
        if not path or not os.path.exists(path):
            return sections

        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                stripped = line.strip()
                if stripped.startswith("[") and stripped.endswith("]"):
                    current_sec = stripped
                    sections[current_sec] = {"raw_header": line.rstrip("\r\n"), "lines": []}
                else:
                    sections[current_sec]["lines"].append(line.rstrip("\r\n"))
        return sections

    def rebase_ini(old_base_p, new_base_p, upper_p):
        old_base = parse_ini(old_base_p)
        new_base = parse_ini(new_base_p)
        upper = parse_ini(upper_p)

        for sec, data in upper.items():
            if sec not in new_base:
                new_base[sec] = data
            else:
                old_sec_lines = set(l.strip() for l in old_base.get(sec, {}).get("lines", []))
                new_sec_lines = set(l.strip() for l in new_base[sec]["lines"])

                for line in data["lines"]:
                    s_line = line.strip()
                    if not s_line or s_line.startswith(";"):
                        continue
                    if s_line not in old_sec_lines and s_line not in new_sec_lines:
                        new_base[sec]["lines"].append(line)

        with open(upper_p, "w", encoding="utf-8") as f:
            for sec, data in new_base.items():
                if data["raw_header"]:
                    f.write(data["raw_header"] + "\n")
                for l in data["lines"]:
                    f.write(l + "\n")

    def main():
        parser = argparse.ArgumentParser(description="Rebase Wine prefix upper layer against new Proton default prefix")
        parser.add_argument("--old-base", default="", help="Path to old Proton base prefix")
        parser.add_argument("--new-base", required=True, help="Path to new Proton base prefix")
        parser.add_argument("--upper", required=True, help="Path to upper directory")
        parser.add_argument("--home", default=os.environ.get("HOME", ""), help="User home directory")
        args = parser.parse_args()

        upper_dir = os.path.abspath(args.upper)
        new_base_dir = os.path.abspath(args.new_base)
        old_base_dir = os.path.abspath(args.old_base) if args.old_base else ""
        home_dir = args.home

        if not os.path.exists(upper_dir):
            return

        # 1. 3-way merge on config files found in new_base
        for root, dirs, files in os.walk(new_base_dir):
            for f in files:
                full_new = os.path.join(root, f)
                rel = os.path.relpath(full_new, new_base_dir)
                full_upper = os.path.join(upper_dir, rel)

                if not os.path.exists(full_upper) or os.path.islink(full_upper):
                    continue

                full_old = os.path.join(old_base_dir, rel) if old_base_dir else ""
                ext = os.path.splitext(f)[1].lower()

                if ext == ".reg":
                    rebase_reg(full_old, full_new, full_upper)
                elif ext in (".ini", ".cfg", ".conf"):
                    rebase_ini(full_old, full_new, full_upper)

        # 2. Remove duplicate/obsolete Proton runtime binaries from upper/drive_c/windows
        # so they resolve cleanly from lowerdir (new_base) without shadowing or bloat
        upper_win = os.path.join(upper_dir, "drive_c", "windows")
        if os.path.exists(upper_win):
            for root, dirs, files in os.walk(upper_win):
                for f in files:
                    full_upper = os.path.join(root, f)
                    rel = os.path.relpath(full_upper, upper_dir)
                    full_old = os.path.join(old_base_dir, rel) if old_base_dir else ""
                    full_new = os.path.join(new_base_dir, rel)
                    if (full_old and os.path.exists(full_old)) or os.path.exists(full_new):
                        try:
                            os.remove(full_upper)
                        except OSError:
                            pass
            for root, dirs, files in os.walk(upper_win, topdown=False):
                if not os.listdir(root):
                    try:
                        os.rmdir(root)
                    except OSError:
                        pass

        # 3. Synchronize config_info with host paths
        new_config_info = os.path.join(new_base_dir, "config_info")
        if os.path.exists(new_config_info):
            with open(new_config_info, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
            if home_dir:
                content = content.replace("@UMU_USER_HOME@", home_dir)
                content = re.sub(r"/build/[^/]+_home", home_dir, content)
            lines = content.split("\n")
            if len(lines) >= 9:
                lines[8] = "1.0"
            content = "\n".join(lines)
            with open(os.path.join(upper_dir, "config_info"), "w", encoding="utf-8") as f:
                f.write(content)

        # 4. Set .update-timestamp to 1 matching EROFS normalized timestamps
        with open(os.path.join(upper_dir, ".update-timestamp"), "w") as f:
            f.write("1")

        # 5. Set version
        new_ver_file = os.path.join(new_base_dir, "version")
        if os.path.exists(new_ver_file):
            with open(new_ver_file, "r") as f:
                ver = f.read().strip()
            with open(os.path.join(upper_dir, "version"), "w") as f:
                f.write(ver + "\n")

        # 6. Remove transient Proton state files
        for meta in ("tracked_files", "pfx.lock"):
            p = os.path.join(upper_dir, meta)
            if os.path.exists(p):
                try:
                    os.remove(p)
                except OSError:
                    pass

    if __name__ == "__main__":
        main()
  '';

  cfg = config.umu;
in
{
  options.umu = {
    enable = mkEnableOption "umu - universal windows apps launcher";
  };

  config = mkIf cfg.enable {
    xdg = {
      dataFile = {
        "umu-ui/games_appid.json".source = "${inputs.steam-app-id-list}/data/games_appid.json";
        "umu-ui/proton_versions.json".text = builtins.toJSON (
          map (v: {
            inherit (v) name;
            default = v.default or false;
          }) protonVersions
        );
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
      pkgs.exiftool
      pkgs.icoutils
      pkgs.imagemagick
      pkgs.libnotify
      pkgs.winetricks
      pkgs.protontricks
      pkgs.xdg-utils
      umu-rebase-pfx

      (pkgs.writeShellScriptBin "umu-run-wrapper" ''
        set -e

        # 1. Resolve Prefix Storage Directory
        prefix_name="''${UMU_PREFIX_NAME:-default}"
        PREFIX_DIR="$HOME/.umu/$prefix_name"

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

        # 4. Resolve Proton version
        if [[ -z "$(printenv PROTONPATH)" ]]; then
          case "$UMU_PROTON_TYPE" in
            ${protonCaseBranches}
            *)
              export PROTONPATH="$HOME/.local/share/umu/proton/proton-umu-10"
              ;;
          esac
        fi

        # 5. Ensure runtime EROFS is mounted
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

        # 6. Resolve Base Prefix (lowerdir from umu-runtime)
        PROTON_NAME=$(basename "$PROTONPATH")
        BASE_PFX="$MOUNT_DIR/base_prefixes/$PROTON_NAME"
        if [[ ! -d "$BASE_PFX" ]]; then
          # Fallback if base_prefixes is not in runtime
          BASE_PFX="$PROTONPATH/files/share/default_pfx"
          [[ -d "$BASE_PFX" ]] || BASE_PFX="$PROTONPATH/dist/share/default_pfx"
        fi

        # 7. Migrate/Rebase Upper Layer if Proton Version Changed
        CURRENT_PROTON_VER=$(cat "$PROTONPATH/version" 2>/dev/null || echo "unknown")
        LAST_PROTON_VER=$(cat "$PREFIX_DIR/upper/.last_proton" 2>/dev/null || echo "")
        LAST_PROTON_PATH=$(cat "$PREFIX_DIR/upper/.last_proton_path" 2>/dev/null || echo "")

        if [[ -n "$LAST_PROTON_VER" && "$LAST_PROTON_VER" != "$CURRENT_PROTON_VER" ]]; then
          echo "Proton version change detected ($LAST_PROTON_VER -> $CURRENT_PROTON_VER). Running delta rebase..."
          OLD_PROTON_NAME=$(basename "$LAST_PROTON_PATH")
          OLD_BASE="$MOUNT_DIR/base_prefixes/$OLD_PROTON_NAME"
          [[ -d "$OLD_BASE" ]] || OLD_BASE="$LAST_PROTON_PATH/files/share/default_pfx"
          [[ -d "$OLD_BASE" ]] || OLD_BASE="$LAST_PROTON_PATH/dist/share/default_pfx"

          ${umu-rebase-pfx}/bin/umu-rebase-pfx \
            --old-base "$OLD_BASE" \
            --new-base "$BASE_PFX" \
            --upper "$PREFIX_DIR/upper" \
            --home "$HOME"
        elif [[ ! -f "$PREFIX_DIR/upper/config_info" || ! -f "$PREFIX_DIR/upper/.update-timestamp" ]]; then
          ${umu-rebase-pfx}/bin/umu-rebase-pfx \
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
        ORIG_UID=$(id -u)
        ORIG_GID=$(id -g)
        RUNTIME_ROOT="''${XDG_RUNTIME_DIR:-/run/user/$ORIG_UID}"
        MERGED_PFX="$RUNTIME_ROOT/umu-pfx/$prefix_name"
        mkdir -p "$MERGED_PFX"

        cleanup_overlay() {
          unshare -r umount -l "$MERGED_PFX" 2>/dev/null || umount -l "$MERGED_PFX" 2>/dev/null || true
          rmdir "$MERGED_PFX" 2>/dev/null || true
          unshare -r rm -rf "$PREFIX_DIR/.work" 2>/dev/null || rm -rf "$PREFIX_DIR/.work" 2>/dev/null || true
        }
        trap cleanup_overlay EXIT INT TERM

        # 10. Hardware and GPU settings
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

        # 11. Run via in-kernel OverlayFS + app2unit systemd scope
        run_overlay_app() {
          unshare -r -m env \
            BASE_PFX="$BASE_PFX" \
            UPPER_DIR="$PREFIX_DIR/upper" \
            WORK_DIR="$PREFIX_DIR/.work" \
            MERGED_PFX="$MERGED_PFX" \
            ORIG_UID="$ORIG_UID" \
            ORIG_GID="$ORIG_GID" \
            UNIT_NAME="umu-pfx-$prefix_name.scope" \
            sh -c '
              mount -t overlay overlay -o "lowerdir=$BASE_PFX,upperdir=$UPPER_DIR,workdir=$WORK_DIR" "$MERGED_PFX" || exit 1
              exec unshare --user --map-user="$ORIG_UID" --map-group="$ORIG_GID" env WINEPREFIX="$MERGED_PFX" app2unit -u "$UNIT_NAME" -- "$@"
            ' _ "$@"
        }

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
           ' run_overlay_app "''${CMD[@]}"
        else
          run_overlay_app "''${CMD[@]}"
        fi

        ${pkgs.libnotify}/bin/notify-send "Closed" "UMU exited ($prefix_name)"
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

        # Resolve search dirs (works both when prefix is merged and offline in upper/)
        SEARCH_DIRS=()
        users_dir="$WINEPREFIX/drive_c/users"
        [[ ! -d "$users_dir" && -d "$WINEPREFIX/upper/drive_c/users" ]] && users_dir="$WINEPREFIX/upper/drive_c/users"

        if [[ -d "$users_dir" ]]; then
          while IFS= read -r -d "" d; do
            [[ -d "$d/Desktop" ]] && SEARCH_DIRS+=("$d/Desktop")
            [[ -d "$d/AppData/Roaming/Microsoft/Windows/Start Menu/Programs" ]] && SEARCH_DIRS+=("$d/AppData/Roaming/Microsoft/Windows/Start Menu/Programs")
          done < <(find "$users_dir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
        fi

        pdata_dir="$WINEPREFIX/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs"
        [[ ! -d "$pdata_dir" && -d "$WINEPREFIX/upper/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs" ]] && pdata_dir="$WINEPREFIX/upper/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs"
        [[ -d "$pdata_dir" ]] && SEARCH_DIRS+=("$pdata_dir")

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
              for check_cand in "$WINEPREFIX/upper/drive_c$path_no_drive" "$WINEPREFIX/drive_c$path_no_drive"; do
                if [[ -f "$check_cand" ]]; then
                  actual_exe="$check_cand"
                  break
                fi
              done
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

          if ! grep -rqF "$i_file" "$DESKTOP_DIR" && [[ ! -f "$DESKTOP_DIR/$base.desktop" && ! -f "$DESKTOP_DIR/$base-umu.desktop" ]]; then
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
      '')
    ];
  };
}
