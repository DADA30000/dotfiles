{
  inputs,
  lib,
  config,
  options,
  pkgs,
  ...
}:
let
  cfg = config.sandboxing;
  mkNixPak = inputs.nixpak.lib.nixpak {
    inherit (pkgs) lib;
    inherit pkgs;
  };
  singbox-sandbox-config = (pkgs.formats.json { }).generate "singbox-sandbox-config" {
    log.level = "error";
    route = {
      auto_detect_interface = true;
      final = "direct";
      rules = [
        {
          action = "sniff";
        }
        {
          outbound = "to-host-vpn";
          process_name = (config.singbox.processes_to_proxy or [ ]);
        }
      ];
    };
    inbounds = [
      {
        type = "tun";
        tag = "tun-in";
        interface_name = "tun-sb";
        address = "172.19.0.5/30";
        auto_route = true;
        strict_route = true;
        stack = "system";
        mtu = 1360;
        route_exclude_address = [
          "127.0.0.1/32"
          "192.168.0.0/16"
        ];
      }
    ];
    outbounds = [
      {
        type = "vless";
        tag = "to-host-vpn";
        server = "127.0.0.1";
        server_port = 1919;
        uuid = "a1c0d4be-6c12-485c-8515-4451ee91ddc3";
        packet_encoding = "xudp";
      }
      {
        type = "direct";
        tag = "direct";
      }
    ];
  };
  rust-bridge = pkgs.pkgsStatic.stdenv.mkDerivation {
    pname = "rust-bridge";
    version = "1.0";
    dontUnpack = true;
    nativeBuildInputs = with pkgs.pkgsStatic; [
      rustc
      stdenv.cc
    ];

    src = ../../../stuff/bridge.rs;

    buildPhase = ''
      rustc --target x86_64-unknown-linux-musl -C target-feature=+crt-static -C linker=$CC -C opt-level=z -C lto -C codegen-units=1 -C panic=abort -C strip=symbols -O $src -o rust-bridge
    '';

    installPhase = ''
      mkdir -p $out/bin
      install -m 0755 rust-bridge $out/bin/rust-bridge
    '';
  };
  way-secure = pkgs.rustPlatform.buildRustPackage {
    pname = "way-secure";
    version = "unstable";
    cargoLock.lockFile = "${inputs.way-secure}/Cargo.lock";
    src = pkgs.lib.cleanSource "${inputs.way-secure}";
    patches = [ ../../../stuff/patches/way-secure.patch ];
  };
  landlock = pkgs.stdenv.mkDerivation {
    pname = "landlock";
    version = "1.0";

    src = ../../../stuff/landlock.c;

    dontUnpack = true;

    buildPhase = ''
      gcc -O2 -Wall $src -o landlock
    '';

    installPhase = ''
      mkdir -p $out/bin
      install -m 0755 landlock $out/bin/landlock
    '';
  };
  # https://github.com/eycorsican/leaf is promising, ~16 mb usage without optimisations
  sing-box-lite = pkgs.sing-box.overrideAttrs (prev: {
    ldflags = (prev.ldflags or [ ]) ++ [
      "-s"
      "-w"
    ];
    tags = [
      "with_inbound_tun"
      "with_outbound_vless"
      "with_outbound_direct"
      "with_local_interceptor"
    ];
  });
  portal-xdg-open = pkgs.writeShellScriptBin "xdg-open" ''
    exec ${pkgs.systemd}/bin/busctl --user call \
      org.freedesktop.portal.Desktop \
      /org/freedesktop/portal/desktop \
      org.freedesktop.portal.OpenURI \
      OpenURI \
      ssa{sv} "" "$1" 0
  '';
  portal-files = pkgs.runCommand "portal-files" { } ''
    mkdir -p $out/applications

    cat > $out/applications/nixpak-portal.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=Nixpak Portal
    Exec=${portal-xdg-open}/bin/xdg-open %u
    MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;x-scheme-handler/about;x-scheme-handler/unknown;
    EOF

    cat > $out/mimeapps.list <<EOF
    [Default Applications]
    text/html=nixpak-portal.desktop
    x-scheme-handler/http=nixpak-portal.desktop
    x-scheme-handler/https=nixpak-portal.desktop
    x-scheme-handler/about=nixpak-portal.desktop
    x-scheme-handler/unknown=nixpak-portal.desktop
    EOF
  '';
  mkSandbox =
    if !cfg.enable then
      { package, ... }: package
    else
      args@{
        appId,
        package,
        gpu ? false,
        network ? false,
        network_singbox ? false,
        network_full ? false,
        webcam ? 0,
        audio ? false,
        wayland ? false,
        wayland_full ? false,
        x11_shared ? false,
        x11 ? false,
        portals_for_files ? true,
        nvidia_gpu ? false,
        main_desktop_file ? "none",
        additional_args ? { },
        additional_prestart_commands ? "",
        additional_wrap_commands ? "",
        extraAttrs ? [ ],
      }:
      let
        enabledModesCount = lib.length (
          lib.filter (x: x) [
            network
            network_singbox
            network_full
          ]
        );
        isExclusive = enabledModesCount <= 1;
      in
      assert lib.assertMsg isExclusive
        "Sandbox Error (${appId}): 'network', 'network_singbox', and 'network_full' are mutually exclusive. You have enabled ${toString enabledModesCount} modes.";
      let
        writeDash = pkgs.writers.writeDash;
        startup_script = writeDash "startup_script" ''
          if [ -e "/etc/.not-a-sandbox" ] || [ -e "$HOME/.not-a-sandbox" ]; then
            SANDBOX_DIR="$XDG_RUNTIME_DIR/.nixpak/${appId}"
            SANDBOXED_RUNTIME_DIR="$SANDBOX_DIR/runtime"
            COMMAND_PIPE="$SANDBOXED_RUNTIME_DIR/command_pipe"
            if [ -p "$COMMAND_PIPE" ] && dd if=/dev/null of="$COMMAND_PIPE" oflag=nonblock count=0 2>/dev/null && [ -f "$SANDBOX_DIR/cgroup_path" ]; then
              CMD_LINE=""
              SQ=$(printf '\047')
              for arg in "$TARGET" "$@"; do
                rem="$arg"
                escaped=""
                while true; do
                  case "$rem" in
                    *"$SQ"*)
                      escaped="''${escaped}''${rem%%$SQ*}$SQ\\$SQ$SQ"
                      rem="''${rem#*$SQ}"
                      ;;
                    *)
                      escaped="''${escaped}''${rem}"
                      break
                      ;;
                  esac
                done
                CMD_LINE="''${CMD_LINE}$SQ''${escaped}$SQ "
              done
              B64_CMD=$(printf "%s" "$CMD_LINE" | ${pkgs.coreutils}/bin/base64 -w 0)
              PAYLOAD="eval \"\$(printf '%s' '$B64_CMD' | ${pkgs.coreutils}/bin/base64 -d)\""
              printf "%s\n" "$PAYLOAD" >> "$COMMAND_PIPE"
            else
              if [ -f "$SANDBOX_DIR/scope" ]; then
                systemctl --user stop "$(< $SANDBOX_DIR/scope)"
                rm "$SANDBOX_DIR/cgroup_path"
                rm "$SANDBOX_DIR/scope"
              fi
              MY_CGROUP="/sys/fs/cgroup$(cat /proc/self/cgroup | cut -d: -f3)"
              MY_SCOPE="$(printf '%s\n' "$MY_CGROUP" | sed -rn 's|.*/([^/]+)$|\1|p' | head -n 1)"
              case "$MY_SCOPE" in
                *"${appId}"*)
                  printf '%s\n' "$MY_SCOPE" > "$SANDBOX_DIR/scope"
                  printf '%s\n' "$MY_CGROUP" > "$SANDBOX_DIR/cgroup_path"
                  ;;
                *)
                  exec app2unit -a "${appId}" -- "$0" "$@"
                  ;;
              esac
              export MY_CGROUP MY_SCOPE
              rm -f "$COMMAND_PIPE"
              mkdir -p "$SANDBOXED_RUNTIME_DIR"
              mkfifo "$COMMAND_PIPE"
              READY_PIPE="$SANDBOXED_RUNTIME_DIR/ready_pipe"
              rm -f "$READY_PIPE"
              mkfifo "$READY_PIPE"
              exec 5<> "$READY_PIPE"
              mkdir "$MY_CGROUP/inside"
              ${additional_wrap_commands}
              ${lib.optionalString network_singbox ''
                ${rust-bridge}/bin/rust-bridge host "$SANDBOXED_RUNTIME_DIR/singbox" 127.0.0.1:1919 &
              ''}
              ${lib.optionalString wayland ''
                SOCK="$SANDBOXED_RUNTIME_DIR/wayland-secure"
                NOTIFY_PIPE="$XDG_RUNTIME_DIR/.nixpak/${appId}/way-secure-notify-${appId}"
                pkill -f "way-secure.*-a ${appId}.*"
                while pgrep -f "way-secure.*-a ${appId}.*" > /dev/null; do
                  sleep 0.01
                done

                rm -f "$SOCK" "$SOCK.lock" "$NOTIFY_PIPE"
                mkfifo "$NOTIFY_PIPE"
                exec 3<> "$NOTIFY_PIPE"

                ${way-secure}/bin/way-secure --socket-path "$SOCK" -a "${appId}" -e flatpak -r 4 4> "$NOTIFY_PIPE" &
                if ${pkgs.coreutils}/bin/timeout 5 ${pkgs.coreutils}/bin/head -n 1 <&3 >/dev/null 2>&1; then
                    echo "way-secure started"
                else
                    echo "Error: way-secure failed to start within 5 seconds" >&2
                    exit 1
                fi
                exec 3<&-
                rm -f "$NOTIFY_PIPE"
              ''}
              ${lib.optionalString portals_for_files ''
                export PATH="${portal-xdg-open}/bin:$PATH"
                export XDG_DATA_DIRS="${portal-files}:''${XDG_DATA_DIRS:-/usr/share:/run/current-system/sw/share}"
                export XDG_CONFIG_DIRS="${portal-files}:''${XDG_CONFIG_DIRS:-/etc/xdg}"
              ''}
              ${lib.optionalString network_singbox ''
                export ORIG_UID="$(id -u)"
                export ORIG_GID="$(id -g)"
              ''}
              ${landlock}/bin/landlock "$SANDBOXED_DASH"/bin/dash -c '
                ${additional_prestart_commands}
                ${lib.optionalString x11 "${pkgs.xwayland-satellite}/bin/xwayland-satellite -nolisten local &"}
                ${lib.optionalString network_singbox ''
                  ${sing-box-lite}/bin/sing-box -c "${singbox-sandbox-config}" run &
                  ${rust-bridge}/bin/rust-bridge sandbox 127.0.0.1:1919 "$XDG_RUNTIME_DIR/singbox" &
                  exec ${landlock}/bin/landlock ${pkgs.util-linux}/bin/unshare --user --map-user="$ORIG_UID" --map-group="$ORIG_GID" -- ${pkgs.dash}/bin/dash -c "
                ''}
                ${lib.optionalString (!network_singbox) ''
                  exec ${pkgs.dash}/bin/dash -c "
                ''}
                  echo \"\$$\" > "/sys/fs/cgroup/cgroup.procs"
                  echo ready > \"\$XDG_RUNTIME_DIR/ready_pipe\"
                  (\"\$@\" &)
                  exec 3<> \"\$XDG_RUNTIME_DIR/command_pipe\"
                  while read -r cmd <&3; do 
                    (eval \"\$cmd\" &)
                  done
                " -- "$@"
              ' -- "$TARGET" "$@" &
              echo $! > "$SANDBOX_DIR/parent_pid"
              if ! ${pkgs.coreutils}/bin/timeout 5 ${pkgs.coreutils}/bin/head -n 1 <&5 >/dev/null 2>&1; then
                  echo "timeout"
                  systemctl --user stop "$MY_SCOPE"
                  exit 1
              fi
              exec 5<&-
              rm -f "$READY_PIPE"
              while [ $(wc -l < "$MY_CGROUP/inside/cgroup.procs" 2>/dev/null || echo 0) -gt 1 ]; do
                sleep 1
              done
              systemctl --user stop "$MY_SCOPE"
            fi
          else
            exec ${pkgs.dash}/bin/dash -c 'exec "$0" "$@"' "$TARGET" "$@"
          fi
        '';
        wrapWithProxy =
          pkg:
          let
            sandboxed_app = mkNixPak {
              config =
                { sloth, ... }:
                let
                  concat = sloth.concat';
                  mkdir-concat = one: two: sloth.mkdir (sloth.concat' one two);
                in
                {
                  imports = [ additional_args ];

                  app.package = pkgs.dash;
                  app.binPath = "bin/dash";

                  dbus.policies = {
                    # Notifications
                    "org.freedesktop.Notifications" = "talk";
                    # xdg-desktop-portal
                    "org.freedesktop.portal.Desktop" = "talk";
                    # show icon in tray
                    "org.kde.StatusNotifierWatcher" = "talk";
                    # add actions to tray icon
                    "com.canonical.AppMenu.Registrar" = "talk";
                    # Get and store individual secrets
                    "org.freedesktop.portal.Secret" = "talk";

                    "org.freedesktop.portal.Documents" = "talk";
                    "org.freedesktop.FileManager1" = "talk";
                  };

                  gpu.enable = gpu;

                  flatpak.appId = appId;

                  pasta = {
                    enable = network || network_singbox;
                    mode = "isolate";
                  };

                  bubblewrap = {

                    network = network || network_singbox || network_full;

                    env =
                      { }
                      // lib.optionalAttrs wayland {
                        WAYLAND_DISPLAY = "wayland-secure";
                      };

                    extraArgs = lib.mkIf network_singbox [
                      "--gid"
                      "0"
                      "--uid"
                      "0"
                      "--cap-add"
                      "CAP_NET_ADMIN"
                      "--cap-add"
                      "CAP_SETFCAP"
                    ];

                    sockets = {
                      pulse = audio;
                      pipewire = audio;
                      wayland = false;
                      x11 = false;
                    };

                    bind = {

                      dev =
                        [ ]
                        ++ (lib.optionals (webcam != 0) (builtins.genList (i: "/dev/video${toString i}") 10))
                        ++ (lib.optionals network_singbox [ "/dev/net/tun" ])
                        ++ (lib.optionals nvidia_gpu [
                          "/dev/nvidia0"
                          "/dev/nvidiactl"
                          "/dev/nvidia-modeset"
                          "/dev/nvidia-uvm"
                          "/dev/nvidia-uvm-tools"
                        ]);

                      rw = [
                        [
                          (sloth.concat' (sloth.env "MY_CGROUP") "/inside")
                          (sloth.mkdir "/sys/fs/cgroup")
                        ]
                        [
                          (mkdir-concat sloth.runtimeDir "/.nixpak/${appId}/shm")
                          "/dev/shm"
                        ]
                        [
                          (mkdir-concat sloth.runtimeDir "/.nixpak/${appId}/tmp")
                          "/tmp"
                        ]
                        [
                          (mkdir-concat sloth.runtimeDir "/.nixpak/${appId}/runtime")
                          sloth.runtimeDir
                        ]
                        [
                          (mkdir-concat sloth.homeDir "/.nixpak/${appId}/home")
                          sloth.homeDir
                        ]
                      ];

                      ro = [
                        "/etc/xdg"
                        "/run/current-system"
                        "/etc/fonts"
                        "/usr/share/fonts"
                        "/etc/localtime"
                        "/etc/profiles"
                        "/etc/static"
                        "/nix/profile"
                        "/nix/var/nix/profiles"
                        "/etc/ssl/certs"
                        "/etc/static/ssl/certs"
                        "/etc/pki"
                        "/etc/hosts"
                        "/etc/nsswitch.conf"
                        "/etc/machine-id"
                        "/etc/os-release"
                        "/etc/mime.types"
                        "/etc/passwd"
                        "/etc/group"
                        "/sys/class/hwmon"
                        (concat sloth.homeDir "/.nix-profile")
                        (concat sloth.homeDir "/.local/state/nix/profile")
                        (concat sloth.homeDir "/.icons")
                        (concat sloth.homeDir "/.themes")
                        (concat sloth.runtimeDir "/doc")
                        (concat (sloth.env "XDG_CONFIG_HOME") "/user-dirs.dirs")
                        (concat (sloth.env "XDG_CONFIG_HOME") "/user-dirs.conf")
                        (concat (sloth.env "XDG_CONFIG_HOME") "/gtk-4.0")
                        (concat (sloth.env "XDG_CONFIG_HOME") "/gtk-3.0")
                        (concat (sloth.env "XDG_CONFIG_HOME") "/qt6ct")
                        (concat (sloth.env "XDG_CONFIG_HOME") "/qt5ct")
                        (concat (sloth.env "XDG_CONFIG_HOME") "/Kvantum")
                        (concat (sloth.env "XDG_CACHE_HOME") "/fontconfig")
                      ]
                      ++ (lib.optionals gpu [
                        "/run/opengl-driver-32"
                        "/sys/class/drm"
                        "/sys/devices"
                        "/sys/bus/pci"
                      ])
                      ++ (lib.optionals x11_shared [ "/tmp/.X11-unix" ])
                      ++ (lib.optionals portals_for_files [ (concat (sloth.env "XDG_CONFIG_HOME") "/mimeapps.list") ])
                      ++ (lib.optionals wayland_full [
                        (sloth.concat [
                          (sloth.env "XDG_RUNTIME_DIR")
                          "/"
                          (sloth.env "WAYLAND_DISPLAY")
                        ])
                      ]);

                    };
                  };
                };
            };
            wrapped =
              pkgs.symlinkJoin {
                name = "${appId}-wrapper";
                paths = [ pkg ];
                nativeBuildInputs = [ pkgs.findutils ];
                postBuild = ''
                  echo "reached postBuild"

                  materialize_path() {
                    local target_path="$1"
                    local rel=''${target_path#$out/}
                    local current="$out"
                    IFS='/' read -ra parts <<< "$rel"
                    for part in "''${parts[@]}"; do
                      [[ -z "$part" ]] && continue
                      current="$current/$part"
                      if [[ -L "$current" ]] && [[ -d "$current" ]]; then
                        local link_target=$(readlink -f "$current")
                        rm "$current"
                        mkdir -p "$current"
                        find "$link_target" -maxdepth 1 -mindepth 1 -exec ln -s -t "$current/" {} +
                      fi
                    done
                  }

                  find "$out" -type l -not -xtype d | while read -r link; do
                    ls -la "$link"
                    target=$(readlink -fm "$link")
                    
                    is_desktop_or_service=0
                    is_executable=0
                    
                    if [[ "$link" == *.desktop ]] || [[ "$link" == *.service ]]; then
                      is_desktop_or_service=1
                    elif [[ "$link" != *.so* ]]; then
                      if LC_ALL=C grep -q "^.ELF" "$target" 2>/dev/null; then
                        is_executable=1
                      elif LC_ALL=C grep -q "^#!" "$target" 2>/dev/null; then
                        is_executable=1
                      fi
                    fi

                    if [ "$is_desktop_or_service" -eq 1 ] || [ "$is_executable" -eq 1 ]; then
                      materialize_path "$(dirname "$link")"
                      rm "$link"
                      
                      if [ "$is_desktop_or_service" -eq 1 ]; then
                        cp "$target" "$link"
                        chmod +w "$link"
                        sed -i "s|${pkg}|$out|g" "$link"
                      else
                        cp "${startup_script}" "$link"
                        sed -i "2a export SANDBOXED_DASH=\"${sandboxed_app.config.script}\"" "$link"
                        sed -i "1a export TARGET=\"$target\"" "$link"
                        chmod +x "$link"
                      fi
                    fi
                  done


                  if [[ -d "$out/share/applications" ]]; then
                    materialize_path "$out/share/applications"
                    
                    shopt -s nullglob
                    apps=("$out/share/applications/"*.desktop)
                    target_name="$out/share/applications/${appId}.desktop"

                    if [[ "${main_desktop_file}" != "none" ]]; then
                      src="$out/share/applications/${main_desktop_file}"
                      if [[ -e "$src" ]] && [[ "$src" != "$target_name" ]]; then
                        mv "$src" "$target_name"
                      fi
                    elif [[ ''${#apps[@]} -eq 1 ]]; then
                      if [[ "''${apps[0]}" != "$target_name" ]]; then
                        mv "''${apps[0]}" "$target_name"
                      fi
                    fi
                    shopt -u nullglob
                  fi
                '';
              }
              // {
                pname = "${appId}-wrapped";
                version = pkg.version or "1.0";
              };
          in
          wrapped
          // (lib.optionalAttrs (pkg ? override) {
            override = overrideArgs: wrapWithProxy (pkg.override overrideArgs);
          })
          // (lib.optionalAttrs (pkg ? overrideAttrs) {
            overrideAttrs = f: wrapWithProxy (pkg.overrideAttrs f);
          });
        mainWrapper = wrapWithProxy package;
        proxiedExtra = lib.genAttrs extraAttrs (
          attr:
          let
            origAttr = package.${attr} or null;
          in
          if lib.isDerivation origAttr then wrapWithProxy origAttr else origAttr
        );
      in
      mainWrapper
      // proxiedExtra
      // (lib.optionalAttrs (package ? override) {
        override =
          overrideArgs:
          mkSandbox (
            args
            // {
              package = package.override overrideArgs;
            }
          );
      })
      // (lib.optionalAttrs (package ? overrideAttrs) {
        overrideAttrs =
          f:
          mkSandbox (
            args
            // {
              package = package.overrideAttrs f;
            }
          );
      });
in
{
  options.sandboxing.enable = lib.mkEnableOption "app sandboxing using nixpak";
  config = {
    _module.args.mkSandbox = mkSandbox;
  }
  // lib.optionalAttrs (options ? home.file) {
    home = {
      packages = [ rust-bridge ];
      file.".not-a-sandbox".text = "not a sandbox";
    };
  }
  // lib.optionalAttrs (options ? environment.etc) {
    environment = {
      systemPackages = [ rust-bridge ];
      etc.".not-a-sandbox".text = "not a sandbox";
    };
  };
}
