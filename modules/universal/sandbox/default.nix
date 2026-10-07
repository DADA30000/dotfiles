{
  lib,
  options,
  pkgs,
  inputs,
  osConfig,
  config,
  ...
}:
let
  staticBwrap = pkgs.pkgsStatic.bubblewrap;
  staticDbusProxy =
    pkgs.runCommand "xdg-dbus-proxy"
      {
        nativeBuildInputs = [
          pkgs.nukeReferences
          pkgs.removeReferencesTo
        ];
      }
      ''
        mkdir -p $out/bin
        cp ${pkgs.pkgsStatic.xdg-dbus-proxy}/bin/xdg-dbus-proxy $out/bin/
        remove-references-to -t ${pkgs.pkgsStatic.glib.dev} $out/bin/xdg-dbus-proxy
        remove-references-to -t ${pkgs.pkgsStatic.glib.out} $out/bin/xdg-dbus-proxy
        ${pkgs.nukeReferences}/bin/nuke-refs $out/bin/xdg-dbus-proxy
        chmod +x $out/bin/xdg-dbus-proxy
      '';
  sloth = import ./sloth.nix { inherit lib; };

  processes_to_proxy =
    if osConfig ? sing-box.processes_to_proxy then
      osConfig.sing-box.processes_to_proxy
    else if config ? sing-box.processes_to_proxy then
      config.sing-box.processes_to_proxy
    else
      [
        "Battle.net.exe"
        ".AyuGram-wrapped"
        ".Discord-wrapped"
        ".spotify-wrapped"
        ".DiscordCanary-wrapped"
        "TeamSpeak"
        "electron"
        "prismlauncher"
      ];

  sing-box-sandbox-config = (pkgs.formats.json { }).generate "sing-box-sandbox-config" {
    log.level = "info";
    log.timestamp = true;
    route = {
      final = "direct";
      rules = [
        {
          action = "sniff";
        }
        {
          inbound = [
            "dns-in"
            "dns-in6"
          ];
          outbound = "direct";
        }
        {
          port = [ 53 ];
          outbound = "direct";
        }
        {
          ip_cidr = [
            "127.0.0.0/8"
            "::1/128"
          ];
          outbound = "real-direct";
        }
        {
          outbound = "to-host-vpn";
          process_name = processes_to_proxy;
        }
      ];
    };
    inbounds = [
      {
        type = "direct";
        tag = "dns-in";
        listen = "127.0.0.1";
        listen_port = 53;
      }
      {
        type = "direct";
        tag = "dns-in6";
        listen = "::1";
        listen_port = 53;
      }
      {
        type = "tun";
        tag = "tun-in";
        interface_name = "sb-net";
        address = [
          "172.19.0.5/30"
          "fd00::5/126"
        ];
        auto_route = true;
        strict_route = true;
        auto_redirect = true;
        iproute2_table_index = 254;
        stack = "system";
        mtu = 1480;
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
        type = "vless";
        tag = "direct";
        server = "127.0.0.1";
        server_port = 2121;
        uuid = "a1c0d4be-6c12-485c-8515-4451ee91ddc3";
        packet_encoding = "xudp";
      }
      {
        tag = "real-direct";
        type = "direct";
      }
    ];
  };

  sing-box-lite =
    (pkgs.sing-box.override {
      withNaiveOutbound = false;
      withStaticCronet = false;
    }).overrideAttrs
      (prev: {
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

  pasta-pkg = pkgs.passt.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ../../../stuff/patches/passt-fix-user-namespace-detection.patch
    ];
  });

  sb-executor-pkg = pkgs.pkgsStatic.stdenv.mkDerivation {
    pname = "sb-executor";
    name = "sb-executor";
    dontUnpack = true;
    nativeBuildInputs = [
      pkgs.pkgsStatic.rustc
      pkgs.clippy
      pkgs.rustfmt
    ];
    buildPhase = ''
      rustfmt --edition 2024 --check ${../../../stuff/system/packages/sb-executor.rs}
      clippy-driver --edition 2024 \
        -D warnings \
        -W clippy::all \
        -W clippy::pedantic \
        -W clippy::nursery \
        ${../../../stuff/system/packages/sb-executor.rs} --emit=metadata -o lint_check.rmeta
      rm -f lint_check.rmeta

      rustc --edition 2024 \
        --target x86_64-unknown-linux-musl \
        -D warnings \
        -D dead-code \
        -D unused-imports \
        -C target-feature=+crt-static \
        -C linker=$CC \
        -C overflow-checks=on \
        -C link-arg=-Wl,-z,relro,-z,now \
        -C link-arg=-Wl,-z,noexecstack \
        -C opt-level=3 \
        -C lto=fat \
        -C codegen-units=1 \
        -C panic=abort \
        -C strip=symbols \
        -O ${../../../stuff/system/packages/sb-executor.rs} -o sb-executor
    '';
    installPhase = ''
      mkdir -p $out/bin
      install -m 0755 sb-executor $out/bin/sb-executor
    '';
  };

  sb-run-pkg = pkgs.pkgsStatic.stdenv.mkDerivation {
    pname = "sb-run";
    name = "sb-run";
    dontUnpack = true;
    nativeBuildInputs = [
      pkgs.pkgsStatic.rustc
      pkgs.clippy
      pkgs.rustfmt
    ];
    buildPhase = ''
      rustfmt --edition 2024 --check ${../../../stuff/system/packages/sb-run.rs}
      clippy-driver --edition 2024 \
        -D warnings \
        -W clippy::all \
        -W clippy::pedantic \
        -W clippy::nursery \
        ${../../../stuff/system/packages/sb-run.rs} --emit=metadata -o lint_check.rmeta
      rm -f lint_check.rmeta

      rustc --edition 2024 \
        --target x86_64-unknown-linux-musl \
        -D warnings \
        -D dead-code \
        -D unused-imports \
        -C target-feature=+crt-static \
        -C linker=$CC \
        -C overflow-checks=on \
        -C link-arg=-Wl,-z,relro,-z,now \
        -C link-arg=-Wl,-z,noexecstack \
        -C opt-level=3 \
        -C lto=fat \
        -C codegen-units=1 \
        -C panic=abort \
        -C strip=symbols \
        -O ${../../../stuff/system/packages/sb-run.rs} -o sb-run
    '';
    installPhase = ''
      mkdir -p $out/bin
      install -m 0755 sb-run $out/bin/sb-run
    '';
  };

  way-secure-pkg = pkgs.rustPlatform.buildRustPackage {
    pname = "way-secure";
    version = "unstable";
    src = inputs.way-secure;
    cargoLock.lockFile = "${inputs.way-secure}/Cargo.lock";
  };

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
    args@{
      appId,
      package,
      gpu ? false,
      network ? "off", # "off" | "sandboxed" | "singbox" | "passthrough"
      webcam ? 0,
      audio_pulse ? "off", # "off" | "sandboxed" | "passthrough"
      audio_pipewire ? "off", # "off" | "sandboxed" | "passthrough"
      wayland ? "off", # "off" | "sandboxed" | "passthrough"
      x11 ? "off", # "off" | "sandboxed" | "passthrough"
      use_landlock ? true,
      portals_for_files ? true,
      sandbox_shm ? true,
      sandbox_tmp ? true,
      main_desktop_file ? "none",
      additional_args ? { },
      additional_inside_commands ? "",
      additional_outside_commands ? "",
      extraAttrs ? [ ],
    }:
    let
      rawArgs =
        if builtins.isFunction additional_args then
          additional_args { inherit sloth lib pkgs; }
        else
          additional_args;

      dbusCfg = rawArgs.dbus or { };
      bwrapCfg = rawArgs.bubblewrap or { };

      dbusEnabled = dbusCfg.enable or true;
      dbusPolicies = dbusCfg.policies or { };

      dbusFlags = lib.concatLists (
        lib.mapAttrsToList (name: policy: [ "--dbus-${policy}=${name}" ]) dbusPolicies
      );

      extractList =
        val:
        if builtins.isList val then
          val
        else if builtins.isAttrs val && val ? content then
          extractList val.content
        else
          [ ];

      rwFlags = map (
        p: "--rw=${if builtins.isList p then "${builtins.head p}:${builtins.elemAt p 1}" else toString p}"
      ) (extractList (bwrapCfg.bind.rw or [ ]));

      roFlags = map (
        p: "--ro=${if builtins.isList p then "${builtins.head p}:${builtins.elemAt p 1}" else toString p}"
      ) (extractList (bwrapCfg.bind.ro or [ ]));

      devFlags = map (
        p: "--dev=${if builtins.isList p then "${builtins.head p}:${builtins.elemAt p 1}" else toString p}"
      ) (extractList (bwrapCfg.bind.dev or [ ]));

      sharePidFlag = lib.optional (bwrapCfg.sharePid or false) "--share-pid";
      landlockFlag = lib.optional (!use_landlock) "--no-landlock";
      portalsFlag = lib.optional (!portals_for_files) "--no-portals";
      portalEnvFlags = lib.optionals portals_for_files [
        "--env"
        "PATH=${portal-xdg-open}/bin:/run/current-system/sw/bin:/bin:/usr/bin"
        "--env"
        "XDG_DATA_DIRS=${portal-files}:/usr/share:/run/current-system/sw/share"
        "--env"
        "XDG_CONFIG_DIRS=${portal-files}:/etc/xdg"
      ];
      envFlags = lib.concatLists (
        lib.mapAttrsToList (k: v: [
          "--env"
          "${k}=${v}"
        ]) (bwrapCfg.env or { })
      );

      sbRunFlags = lib.flatten [
        "--id"
        appId
        "--executor-bin"
        "${sb-executor-pkg}/bin/sb-executor"
        "--net"
        network
        (lib.optionals (network == "singbox") [
          "--singbox-bin"
          "${sing-box-lite}/bin/sing-box"
          "--singbox-config"
          "${sing-box-sandbox-config}"
        ])
        (lib.optionals (network == "sandboxed") [
          "--pasta-bin"
          "${pasta-pkg}/bin/pasta"
        ])
        (lib.optional gpu "--gpu")
        [
          "--pulse"
          audio_pulse
          "--pipewire"
          audio_pipewire
          "--wayland"
          wayland
          (lib.optionals (wayland == "sandboxed") [
            "--way-secure-bin"
            "${way-secure-pkg}/bin/way-secure"
          ])
          "--x11"
          x11
          (lib.optionals (x11 == "sandboxed") [
            "--xwayland-satellite-bin"
            "${pkgs.xwayland-satellite}/bin/xwayland-satellite"
          ])
          "--shm"
          (if sandbox_shm then "sandboxed" else "passthrough")
          "--tmp"
          (if sandbox_tmp then "sandboxed" else "passthrough")
        ]
        landlockFlag
        portalsFlag
        portalEnvFlags
        (lib.optional (webcam != 0) [
          "--webcam"
          (toString webcam)
        ])
        (
          if dbusEnabled then
            [
              "--dbus"
              "sandboxed"
              "--dbus-proxy-bin"
              "${staticDbusProxy}/bin/xdg-dbus-proxy"
            ]
          else
            [
              "--dbus"
              "off"
            ]
        )
        (lib.optional (dbusCfg.system or false) "--system-dbus")
        dbusFlags
        rwFlags
        roFlags
        devFlags
        envFlags
        sharePidFlag
        (if (args.cli or false) then "--cli" else "--gui")
      ];

      wrapperScript = pkgs.writeShellScript "sandbox-launcher-${appId}" ''
        if [ -e "/etc/.not-a-sandbox" ] || [ -e "$HOME/.not-a-sandbox" ]; then
          MY_CGROUP="/sys/fs/cgroup$(cat /proc/self/cgroup | cut -d: -f3)"
          MY_SCOPE="$(basename "$MY_CGROUP" 2>/dev/null)"
          case "$MY_SCOPE" in
            *"${appId}"*)
              ;;
            *)
              exec app2unit -a "${appId}" -- "$0" "$@"
              ;;
          esac

          export START_TIME=$(date +%s%N)
          export APP_ID="${appId}"

          export SANDBOX_DIR="$XDG_RUNTIME_DIR/.nixpak/${appId}"
          export SANDBOXED_RUNTIME_DIR="$SANDBOX_DIR/runtime"
          mkdir -p "$SANDBOXED_RUNTIME_DIR"

          ${additional_outside_commands}
          exec ${sb-run-pkg}/bin/sb-run ${lib.escapeShellArgs sbRunFlags} -- "$0" "$@"
        else
          ${additional_inside_commands}
          exec "$TARGET" "$@"
        fi
      '';

      wrapWithProxy =
        pkg:
        let
          wrapped =
            pkgs.symlinkJoin {
              name = "${appId}-wrapper";
              paths = [ pkg ];
              nativeBuildInputs = [ pkgs.findutils ];
              postBuild = ''
                materialize_path() {
                  local target_path="$1"
                  local rel="''${target_path#$out/}"
                  local current="$out"
                  IFS='/' read -ra parts <<< "$rel"
                  for part in "''${parts[@]}"; do
                    [[ -z "$part" ]] && continue
                    current="$current/$part"
                    if [[ -L "$current" ]] && [[ -d "$current" ]]; then
                      local link_target
                      link_target="$(readlink -f "$current")"
                      rm "$current"
                      mkdir -p "$current"
                      find "$link_target" -maxdepth 1 -mindepth 1 -exec ln -s -t "$current/" {} +
                    fi
                  done
                }

                find "$out" -type l -not -xtype d | while read -r link; do
                  target="$(readlink -fm "$link")"
                  
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
                      cp "${wrapperScript}" "$link"
                      sed -i "1a TARGET=\"$target\"" "$link"
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

  pipewireRestrictedSocketConfig = {
    "module.protocol-native.args".sockets = [
      { name = "pipewire-0"; }
      { name = "pipewire-0-manager"; }
      { name = "pipewire-0-restricted"; }
    ];
    "module.access.args"."access.socket" = {
      "pipewire-0" = "unrestricted";
      "pipewire-0-manager" = "unrestricted";
      "pipewire-0-restricted" = "flatpak";
    };
  };

  pipewirePulseRestrictedSocketConfig = {
    "pulse.properties"."server.address" = [
      "unix:native"
      {
        address = "unix:restricted";
        "client.access" = "restricted";
      }
    ];
    "pulse.rules" = [
      {
        matches = [
          { "pipewire.client.access" = "restricted"; }
          { "pipewire.client.access" = "flatpak"; }
        ];
        actions.quirks = [
          "block-source-volume"
          "block-sink-volume"
        ];
      }
    ];
  };

  wireplumberRestrictedPermissionsConfig = {
    "access.permission-managers" = [
      {
        name = "sandbox-restricted";
        default_permissions = "rx";
        core_permissions = "rx";
        rules = [
          {
            matches = [
              { "device.name" = "~.*"; }
              { "node.name" = "~.*"; }
            ];
            actions.set-permissions = "rx";
          }
        ];
      }
    ];
    "access.rules" = [
      {
        matches = [
          { "pipewire.client.access" = "restricted"; }
          { "pipewire.client.access" = "flatpak"; }
        ];
        actions.update-props.permission_manager_name = "sandbox-restricted";
      }
    ];
  };
in
{
  options.sandboxing.enable = lib.mkEnableOption "app sandboxing";
  config = {
    _module.args = {
      inherit staticBwrap mkSandbox;
    };
  }
  // lib.optionalAttrs (options ? home.file) {
    home = {
      packages = [
        staticBwrap
        pasta-pkg
        way-secure-pkg
      ];
      file.".not-a-sandbox".text = "not a sandbox";
    };
    xdg.configFile = {
      "pipewire/pipewire.conf.d/99-restricted-socket.conf".text =
        builtins.toJSON pipewireRestrictedSocketConfig;
      "pipewire/pipewire-pulse.conf.d/99-restricted-socket.conf".text =
        builtins.toJSON pipewirePulseRestrictedSocketConfig;
      "wireplumber/wireplumber.conf.d/99-restricted-permissions.conf".text =
        builtins.toJSON wireplumberRestrictedPermissionsConfig;
    };
  }
  // lib.optionalAttrs (options ? environment.etc) {
    environment = {
      systemPackages = [
        staticBwrap
        pasta-pkg
        way-secure-pkg
      ];
      etc.".not-a-sandbox".text = "not a sandbox";
    };
    services.pipewire = {
      package = pkgs.pipewire.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ../../../stuff/patches/pipewire-quirk-block-mute.patch
        ];
      });
      wireplumber.extraConfig."99-restricted-permissions" = wireplumberRestrictedPermissionsConfig;
      extraConfig = {
        pipewire."99-restricted-socket" = pipewireRestrictedSocketConfig;
        pipewire-pulse."99-restricted-socket" = pipewirePulseRestrictedSocketConfig;
      };
    };
  };
}
