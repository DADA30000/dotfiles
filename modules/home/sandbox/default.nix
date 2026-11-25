{
  lib,
  pkgs,
  inputs,
  config,
  osConfig,
  ...
}:
let
  staticBwrap = pkgs.pkgsStatic.bubblewrap;
  patchedStaticDbusProxy = pkgs.pkgsStatic.xdg-dbus-proxy.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ../../../stuff/patches/xdg-dbus-proxy-unicast-signals.patch
    ];
  });

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
        cp ${patchedStaticDbusProxy}/bin/xdg-dbus-proxy $out/bin/
        remove-references-to -t ${pkgs.pkgsStatic.glib.dev} $out/bin/xdg-dbus-proxy
        remove-references-to -t ${pkgs.pkgsStatic.glib.out} $out/bin/xdg-dbus-proxy
        ${pkgs.nukeReferences}/bin/nuke-refs $out/bin/xdg-dbus-proxy
        chmod +x $out/bin/xdg-dbus-proxy
      '';

  processes_to_proxy = osConfig.sing-box.processes_to_proxy;

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

  way-secure-pkg = pkgs.rustPlatform.buildRustPackage {
    pname = "way-secure";
    version = "unstable";
    src = inputs.way-secure;
    cargoLock.lockFile = "${inputs.way-secure}/Cargo.lock";
  };

  pw-portal-shim-pkg = pkgs.stdenv.mkDerivation {
    pname = "pw-portal-shim";
    version = "1.0.0";
    src = ../../../stuff/home/sandbox/pw-portal-shim.c;
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [
      pkgs.dbus
      pkgs.pipewire
    ];
    buildPhase = ''
      $CC -shared -fPIC -O2 -Wall \
        $(pkg-config --cflags --libs dbus-1 libpipewire-0.3) \
        -ldl $src -o libpw-portal-shim.so
    '';
    installPhase = ''
      mkdir -p $out/lib $out/bin
      cp libpw-portal-shim.so $out/lib/
      cat << EOF > $out/bin/pw-portal-v4l2
      #!/bin/sh
      LIBPW_V4L2='${pkgs.pipewire}/\''${LIB}/pipewire-0.3/v4l2/libpw-v4l2.so'
      SHIM="$out/lib/libpw-portal-shim.so"
      if [ -z "\$LD_PRELOAD" ]; then
        export LD_PRELOAD="\$SHIM \$LIBPW_V4L2"
      else
        export LD_PRELOAD="\$SHIM \$LIBPW_V4L2 \$LD_PRELOAD"
      fi
      exec "\$@"
      EOF
      chmod +x $out/bin/pw-portal-v4l2
    '';
  };

  syscallsJson = pkgs.runCommand "sb-syscalls.json" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python3 - "${pkgs.linuxHeaders}/include/asm/unistd_64.h" "${pkgs.linuxHeaders}/include/asm/unistd_32.h" "$out" << 'EOF'
    import json, re, sys

    def parse_header(path):
        res = {}
        with open(path, "r") as f:
            for line in f:
                m = re.match(r"^\s*#define\s+__NR_([a-zA-Z0-9_]+)\s+(\d+)\s*$", line)
                if m:
                    res[m.group(1)] = int(m.group(2))
        return res

    data = {
        "x86_64": parse_header(sys.argv[1]),
        "i386": parse_header(sys.argv[2]),
    }
    with open(sys.argv[3], "w") as out:
        json.dump(data, out, sort_keys=True)
    EOF
  '';

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

  seccompActionType = lib.types.enum [
    "eperm"
    "enosys"
    "eacces"
    "einval"
    "enotsup"
    "kill"
    "trap"
  ];

  mkDenyBucketType =
    notifyName:
    lib.types.submodule {
      options = {
        # Return EPERM (1) for matching rules in this notification bucket.
        eperm = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Syscall rules failing with EPERM under notify=${notifyName}.";
        };
        # Return ENOSYS (38) for matching rules in this notification bucket.
        enosys = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Syscall rules failing with ENOSYS under notify=${notifyName}.";
        };
        # Return EACCES (13) for matching rules in this notification bucket.
        eacces = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Syscall rules failing with EACCES under notify=${notifyName}.";
        };
        # Return EINVAL (22) for matching rules in this notification bucket.
        einval = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Syscall rules failing with EINVAL under notify=${notifyName}.";
        };
        # Return ENOTSUP (95) for matching rules in this notification bucket.
        enotsup = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Syscall rules failing with ENOTSUP under notify=${notifyName}.";
        };
        # Terminate the offending process with SIGKILL.
        kill = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Syscall rules terminating the process with SIGKILL under notify=${notifyName}.";
        };
        # Terminate the offending process with SIGSYS.
        trap = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Syscall rules trapping the process with SIGSYS under notify=${notifyName}.";
        };
      };
    };

  mkDbusPolicyOptions = kind: {
    # D-Bus names allowed to talk with (e.g. "org.freedesktop.Notifications").
    talks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "${kind} D-Bus names allowed for --talk.";
    };
    # D-Bus names allowed to own on the bus.
    owns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "${kind} D-Bus names allowed for --own.";
    };
    # D-Bus names visible via --see without full talk access.
    sees = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "${kind} D-Bus names allowed for --see.";
    };
    # D-Bus method call filter rules passed as --call=<rule> to xdg-dbus-proxy.
    calls = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "${kind} D-Bus --call filter rules.";
    };
    # Extra raw arguments appended to xdg-dbus-proxy invocation.
    extra_args = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra raw arguments passed to xdg-dbus-proxy for ${kind} bus.";
    };
  };

  sandboxConfigModule =
    { config, ... }:
    {
      options = {
        # Network mode: "off" (unshared), "sandboxed" (pasta), "singbox" (VPN), or "passthrough" (host).
        network = lib.mkOption {
          type = lib.types.enum [
            "off"
            "sandboxed"
            "singbox"
            "passthrough"
          ];
          default = "sandboxed";
          description = "Network isolation mode.";
        };
        # Wayland display mode: "off", "sandboxed" (way-secure proxy), or "passthrough" (host socket).
        wayland = lib.mkOption {
          type = lib.types.enum [
            "off"
            "sandboxed"
            "passthrough"
          ];
          default = "sandboxed";
          description = "Wayland display access mode.";
        };
        # X11 display mode: "off", "sandboxed" (xwayland-satellite), or "passthrough" (/tmp/.X11-unix).
        x11 = lib.mkOption {
          type = lib.types.enum [
            "off"
            "sandboxed"
            "passthrough"
          ];
          default = "off";
          description = "X11 display access mode.";
        };
        # PulseAudio access mode: "off", "sandboxed" (restricted socket), or "passthrough" (host native).
        pulse = lib.mkOption {
          type = lib.types.enum [
            "off"
            "sandboxed"
            "passthrough"
          ];
          default = "sandboxed";
          description = "PulseAudio access mode.";
        };
        # PipeWire access mode: "off", "sandboxed" (restricted socket), or "passthrough" (host pipewire-0).
        pipewire = lib.mkOption {
          type = lib.types.enum [
            "off"
            "sandboxed"
            "passthrough"
          ];
          default = "sandboxed";
          description = "PipeWire access mode.";
        };
        # Microphone policy for sandboxed audio: "off" (blocked), "portal" (AccessDialog), or "allow" (unprompted capture).
        microphone = lib.mkOption {
          type = lib.types.enum [
            "off"
            "portal"
            "allow"
          ];
          default = "off";
          description = "Microphone capture policy for sandboxed PulseAudio/PipeWire.";
        };
        # Webcam policy: "off", "portal" (pw-portal-v4l2 LD_PRELOAD), or "auto" (all /dev/video* nodes).
        webcam = lib.mkOption {
          type = lib.types.enum [
            "off"
            "portal"
            "auto"
          ];
          default = "off";
          description = "Webcam access mode.";
        };
        # Shared memory (/dev/shm) mode: "sandboxed" (per-sandbox dir) or "passthrough" (host /dev/shm).
        shm = lib.mkOption {
          type = lib.types.enum [
            "sandboxed"
            "passthrough"
          ];
          default = "sandboxed";
          description = "/dev/shm isolation mode.";
        };
        # Temporary directory (/tmp) mode: "sandboxed" (per-sandbox dir) or "passthrough" (host /tmp).
        tmp = lib.mkOption {
          type = lib.types.enum [
            "sandboxed"
            "passthrough"
          ];
          default = "sandboxed";
          description = "/tmp isolation mode.";
        };
        # Whether to expose /dev/dri and NVIDIA device nodes inside the sandbox.
        gpu = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable GPU / 3D hardware acceleration binds.";
        };
        # Whether to bind /dev/input and /dev/uinput for gamepads and controllers.
        gamepad = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable /dev/input and /dev/uinput gamepad binds.";
        };
        # Whether to apply Landlock signal scoping across sandboxed processes.
        landlock = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable Landlock signal scoping.";
        };
        # Whether to configure XDG portal opener env vars and mimeapps.list bind.
        portals = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable XDG portal integration (xdg-open shim and mimeapps.list).";
        };
        # Whether to store sandbox home in ephemeral runtime storage (cleaned on exit).
        tmpfs = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Use ephemeral runtime home directory cleaned up on exit.";
        };
        # Whether to share the host PID namespace instead of unsharing PIDs.
        share_pid = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Share host PID namespace.";
        };
        # Whether to share the host IPC namespace instead of unsharing IPC.
        share_ipc = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Share host IPC namespace.";
        };
        # Whether to wrap bwrap execution with vpnify.
        vpnify = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Wrap sandbox execution inside vpnify.";
        };
        # Whether to generate and bind /.flatpak-info inside the sandbox.
        flatpak_info = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Mount /.flatpak-info metadata for portal/PipeWire client identification.";
        };
        # Whether to isolate the sandbox inside a dedicated app2unit systemd scope and cgroup tree.
        scope = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Run inside a dedicated app2unit systemd scope with cgroup migration.";
        };
        # Whether invocations default to CLI TTY forwarding and exit status propagation.
        cli = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Default to CLI mode (foreground stdio/TTY forwarding).";
        };

        # Session D-Bus proxy configuration and policy rules.
        dbus = lib.mkOption {
          type = lib.types.submodule {
            options = {
              # Session D-Bus mode: "off", "sandboxed" (xdg-dbus-proxy), or "passthrough".
              mode = lib.mkOption {
                type = lib.types.enum [
                  "off"
                  "sandboxed"
                  "passthrough"
                ];
                default = "sandboxed";
                description = "Session D-Bus access mode.";
              };
            }
            // mkDbusPolicyOptions "Session";
          };
          default = { };
          description = "Session D-Bus proxy configuration.";
        };

        # System D-Bus proxy configuration and policy rules.
        system_dbus = lib.mkOption {
          type = lib.types.submodule {
            options = {
              # Whether to run an xdg-dbus-proxy instance for the system bus.
              enable = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Enable filtered system D-Bus proxy.";
              };
            }
            // mkDbusPolicyOptions "System";
          };
          default = { };
          description = "System D-Bus proxy configuration.";
        };

        # Seccomp BPF filter configuration, allow/deny rule lists, and notification policy.
        seccomp = lib.mkOption {
          type = lib.types.submodule {
            options = {
              # Whether to compile and install the seccomp BPF filter.
              enable = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Enable seccomp syscall filtering.";
              };
              # Default denial action when an unmatched syscall is blocked in allowlist mode.
              action = lib.mkOption {
                type = seccompActionType;
                default = "eperm";
                description = "Default action for blocked syscalls.";
              };
              # Default notification channel for blocked syscalls: "none", "log", or "notify".
              notify = lib.mkOption {
                type = lib.types.enum [
                  "none"
                  "log"
                  "notify"
                ];
                default = "notify";
                description = "Default reporting mode for blocked syscalls.";
              };
              # Allowed syscall rules ([@prio:]syscall[:cond[&&cond...]]). Empty enables denylist mode.
              allow = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Seccomp allow rules; empty list switches to denylist mode.";
              };
              # Explicit deny rule buckets grouped by notification mode and denial action.
              deny = lib.mkOption {
                type = lib.types.submodule {
                  options = {
                    # Silent in-kernel denials (never forwarded to supervisor).
                    none = lib.mkOption {
                      type = mkDenyBucketType "none";
                      default = { };
                      description = "In-BPF silent deny rules.";
                    };
                    # Denials logged exclusively to <sandbox_dir>/logs/seccomp.log.
                    log = lib.mkOption {
                      type = mkDenyBucketType "log";
                      default = { };
                      description = "Log-only deny rules.";
                    };
                    # Denials reported exclusively via desktop notification (notify-send).
                    notify = lib.mkOption {
                      type = mkDenyBucketType "notify";
                      default = { };
                      description = "Desktop-notification deny rules.";
                    };
                  };
                };
                default = { };
                description = "Explicit seccomp deny rules grouped by notify and action.";
              };
            };
          };
          default = { };
          description = "Seccomp filter configuration.";
        };

        # Extra bind mounts and directories created inside the sandbox.
        binds = lib.mkOption {
          type = lib.types.submodule {
            options = {
              # Read-write bind mounts ("path" or "src:dst"; supports allowed env vars).
              rw = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Read-write bind mounts.";
              };
              # Read-only bind mounts ("path" or "src:dst"; supports allowed env vars).
              ro = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Read-only bind mounts.";
              };
              # Device bind mounts ("path" or "src:dst"; supports allowed env vars).
              dev = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Device bind mounts (--dev-bind-try).";
              };
              # Directories created inside the sandbox before bind mounts are applied.
              mkdir = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Directories created inside the sandbox (--dir).";
              };
            };
          };
          default = { };
          description = "Custom bind mounts and directories.";
        };

        # Environment variables set inside the sandbox (--setenv).
        env = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Environment variables injected into the sandbox.";
        };
        # TCP bridge specifications ("from:addr:ports" or "to:addr:ports") via rust-bridge.
        bridges = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "TCP socket bridge rules for rust-bridge.";
        };
        # Extra raw arguments appended to the bwrap command line.
        bwrap_args = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Raw extra arguments passed to bwrap.";
        };
        # Paths to helper executables used by sb-run and the GUI.
        bins = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Helper binary paths map.";
        };
        # Host path lists and allowed environment variable names for path expansion.
        paths = lib.mkOption {
          type = lib.types.submodule {
            options = {
              # Environment variable names expanded in binds and env strings.
              allowed_env_vars = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Allowed environment variable names for path expansion.";
              };
              # Host system paths mounted read-only into every sandbox.
              ro_system_paths = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "System paths mounted read-only.";
              };
              # Subpaths under $HOME mounted read-only for theming/profiles.
              user_theme_subpaths = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Home subpaths mounted read-only.";
              };
              # Subpaths under $XDG_CONFIG_HOME mounted read-only for theming/VR configs.
              xdg_config_subpaths = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "XDG_CONFIG_HOME subpaths mounted read-only.";
              };
              # Subpaths under $XDG_DATA_HOME mounted read-only for icons/themes/shell data.
              xdg_data_subpaths = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "XDG_DATA_HOME subpaths mounted read-only.";
              };
              # NVIDIA device nodes mounted when gpu = true.
              nvidia_nodes = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "NVIDIA device nodes bound when gpu is enabled.";
              };
            };
          };
          default = { };
          description = "Base host paths and expansion rules.";
        };
        # Arguments passed to pasta when network = "sandboxed".
        pasta_args = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Arguments passed to pasta in sandboxed network mode.";
        };
        # Default sing-box JSON configuration path used when network = "singbox".
        singbox_config = lib.mkOption {
          type = lib.types.str;
          default = "$XDG_DATA_HOME/sb-run/sing-box.json";
          description = "Default sing-box configuration file path.";
        };
        # Syscall number table JSON path used by seccomp compiler and supervisor.
        syscalls_file = lib.mkOption {
          type = lib.types.str;
          default = "$XDG_DATA_HOME/sb-run/syscalls.json";
          description = "Path to the syscall number table JSON.";
        };
      };

      config = lib.mkIf config.portals {
        env = {
          PATH = lib.mkDefault "${portal-xdg-open}/bin:/run/current-system/sw/bin:/bin:/usr/bin";
          XDG_DATA_DIRS = lib.mkDefault "${portal-files}:/usr/share:/run/current-system/sw/share";
          XDG_CONFIG_DIRS = lib.mkDefault "${portal-files}:/etc/xdg";
        };
      };
    };

  baseSandboxConfig = {
    singbox_config = "${config.xdg.dataHome}/sb-run/sing-box.json";
    syscalls_file = "${config.xdg.dataHome}/sb-run/syscalls.json";
    bins = {
      bwrap = "${staticBwrap}/bin/bwrap";
      sb_executor = "/run/current-system/sw/bin/sb-executor";
      dbus_proxy = "${staticDbusProxy}/bin/xdg-dbus-proxy";
      way_secure = "${way-secure-pkg}/bin/way-secure";
      pasta = "${pasta-pkg}/bin/pasta";
      xwayland_satellite = "${pkgs.xwayland-satellite}/bin/xwayland-satellite";
      singbox = "${sing-box-lite}/bin/sing-box";
      rust_bridge = "/run/current-system/sw/bin/rust-bridge";
      app2unit = "app2unit";
      systemctl = "${pkgs.systemd}/bin/systemctl";
      vpnify = "/run/wrappers/bin/vpnify";
      notify_send = "${pkgs.libnotify}/bin/notify-send";
      neovide = "neovide";
      pw_v4l2 = "${pw-portal-shim-pkg}/bin/pw-portal-v4l2";
    };

    seccomp = {
      allow = [
        "exit"
        "exit_group"
        "fork"
        "vfork"
        "clone:arg0!&0x7e020080"
        "execve"
        "execveat"
        "wait4"
        "waitid"
        "waitpid"
        "getpid"
        "getppid"
        "gettid"
        "getpgid"
        "getpgrp"
        "setpgid"
        "getsid"
        "setsid"
        "getuid"
        "geteuid"
        "getgid"
        "getegid"
        "getresuid"
        "getresgid"
        "getgroups"
        "getuid32"
        "geteuid32"
        "getgid32"
        "getegid32"
        "getresuid32"
        "getresgid32"
        "getgroups32"
        "capget"
        "prctl"
        "arch_prctl"
        "seccomp"
        "landlock_create_ruleset"
        "landlock_add_rule"
        "landlock_restrict_self"
        "lsm_get_self_attr"
        "lsm_list_modules"
        "getrlimit"
        "ugetrlimit"
        "setrlimit"
        "prlimit64"
        "getrusage"
        "times"
        "uname"
        "sysinfo"
        "umask"
        "getpriority"
        "setpriority"
        "sched_yield"
        "sched_getaffinity"
        "sched_setaffinity"
        "sched_getparam"
        "sched_setparam"
        "sched_getscheduler"
        "sched_setscheduler"
        "sched_getattr"
        "sched_setattr"
        "sched_get_priority_max"
        "sched_get_priority_min"
        "sched_rr_get_interval"
        "sched_rr_get_interval_time64"
        "ioprio_get"
        "ioprio_set"
        "set_tid_address"
        "set_robust_list"
        "get_robust_list"
        "set_thread_area"
        "get_thread_area"
        "rseq"
        "rseq_slice_yield"
        "pidfd_open"
        "pidfd_send_signal"
        "kcmp:arg2==0"

        # Signals / timers / clocks (read-only)
        "rt_sigaction"
        "rt_sigprocmask"
        "rt_sigreturn"
        "rt_sigpending"
        "rt_sigtimedwait"
        "rt_sigtimedwait_time64"
        "rt_sigqueueinfo"
        "rt_tgsigqueueinfo"
        "rt_sigsuspend"
        "sigaction"
        "signal"
        "sigpending"
        "sigprocmask"
        "sigreturn"
        "sigsuspend"
        "sigaltstack"
        "restart_syscall"
        "kill"
        "tkill"
        "tgkill"
        "pause"
        "alarm"
        "nanosleep"
        "clock_nanosleep"
        "clock_nanosleep_time64"
        "clock_gettime"
        "clock_gettime64"
        "clock_getres"
        "clock_getres_time64"
        "gettimeofday"
        "time"
        "getitimer"
        "setitimer"
        "timer_create"
        "timer_delete"
        "timer_getoverrun"
        "timer_gettime"
        "timer_gettime64"
        "timer_settime"
        "timer_settime64"
        "timerfd_create"
        "timerfd_gettime"
        "timerfd_gettime64"
        "timerfd_settime"
        "timerfd_settime64"

        # Memory management & futex
        "brk"
        "mmap"
        "mmap2"
        "munmap"
        "mprotect"
        "mremap"
        "msync"
        "mincore"
        "madvise"
        "mlock"
        "mlock2"
        "munlock"
        "membarrier"
        "memfd_create"
        "mseal"
        "map_shadow_stack"
        "pkey_alloc"
        "pkey_free"
        "pkey_mprotect"
        "futex"
        "futex_time64"
        "futex_wait"
        "futex_wake"
        "futex_requeue"
        "futex_waitv"
        "getcpu"
        "getrandom"

        # Filesystem / FD / I/O
        "read"
        "write"
        "open"
        "openat"
        "openat2"
        "creat"
        "close"
        "close_range"
        "lseek"
        "_llseek"
        "pread64"
        "pwrite64"
        "readv"
        "writev"
        "preadv"
        "pwritev"
        "preadv2"
        "pwritev2"
        "readahead"
        "stat"
        "stat64"
        "fstat"
        "fstat64"
        "lstat"
        "lstat64"
        "newfstatat"
        "fstatat64"
        "statx"
        "statfs"
        "statfs64"
        "fstatfs"
        "fstatfs64"
        "access"
        "faccessat"
        "faccessat2"
        "chdir"
        "fchdir"
        "getcwd"
        "getdents"
        "getdents64"
        "readlink"
        "readlinkat"
        "link"
        "linkat"
        "unlink"
        "unlinkat"
        "symlink"
        "symlinkat"
        "rename"
        "renameat"
        "renameat2"
        "mkdir"
        "mkdirat"
        "rmdir"
        "chmod"
        "fchmod"
        "fchmodat"
        "fchmodat2"
        "truncate"
        "truncate64"
        "ftruncate"
        "ftruncate64"
        "fallocate"
        "fadvise64"
        "fadvise64_64"
        "fsync"
        "fdatasync"
        "sync_file_range"
        "utime"
        "utimes"
        "futimesat"
        "utimensat"
        "utimensat_time64"
        "dup"
        "dup2"
        "dup3"
        "fcntl"
        "fcntl64"
        "flock"
        "ioctl"
        "getxattr"
        "lgetxattr"
        "fgetxattr"
        "listxattr"
        "llistxattr"
        "flistxattr"
        "copy_file_range"
        "sendfile"
        "sendfile64"
        "splice"
        "tee"

        # Event loops / pipes / IPC
        "pipe"
        "pipe2"
        "poll"
        "ppoll"
        "ppoll_time64"
        "select"
        "_newselect"
        "pselect6"
        "pselect6_time64"
        "epoll_create"
        "epoll_create1"
        "epoll_ctl"
        "epoll_wait"
        "epoll_pwait"
        "epoll_pwait2"
        "eventfd"
        "eventfd2"
        "signalfd"
        "signalfd4"
        "inotify_init"
        "inotify_init1"
        "inotify_add_watch"
        "inotify_rm_watch"
        "shmget"
        "shmat"
        "shmdt"
        "shmctl"
        "semget"
        "semop"
        "semtimedop"
        "semtimedop_time64"
        "semctl"
        "mknodat:arg2_u32&0x1000&&arg2_u32!&0xe000"

        # Networking & sockets
        "socket:arg0==1"
        "socket:arg0==2"
        "socket:arg0==10"
        "socket:arg0==16&&arg2==0"
        "socket:arg0==16&&arg2==15"
        "socketpair:arg0==1"
        "bind"
        "listen"
        "accept"
        "accept4"
        "connect"
        "shutdown"
        "getsockname"
        "getpeername"
        "setsockopt"
        "getsockopt"
        "sendto"
        "sendmsg"
        "sendmmsg"
        "recvfrom"
        "recvmsg"
        "recvmmsg"
        "recvmmsg_time64"
      ];
      deny = {
        log = {
          enosys = [ "clone3" ];
          eperm = [
            "clone"
            "unshare"
            "setns"
            "ptrace"
            "io_uring_setup"
            "get_mempolicy"
            "mbind"
            "fremovexattr"
            "sync"
          ];
        };
        notify.eperm = [
          "@10:ioctl:arg1_u32==0x5412"
          "@10:ioctl:arg1_u32==0x541c"
        ];
      };
    };

    dbus = {
      talks = [
        "org.freedesktop.portal.Desktop"
        "org.freedesktop.portal.Documents"
        "org.freedesktop.portal.Secret"
        "org.freedesktop.portal.Camera"
        "org.freedesktop.Notifications"
        "org.freedesktop.FileManager1"
        "org.freedesktop.ScreenSaver"
        "org.gnome.Mutter.IdleMonitor"
        "org.kde.StatusNotifierWatcher"
        "org.ayatana.indicator.application"
        "com.canonical.AppMenu.Registrar"
        "org.mpris.MediaPlayer2.Player"
      ];
      owns = [
        "org.kde.StatusNotifierItem.*"
        "org.kde.StatusNotifierItem"
        "org.mpris.MediaPlayer2.*"
      ];
    };

    pasta_args = [
      "--config-net"
      "--no-dhcp"
      "--no-dhcpv6"
      "--no-ra"
      "--no-map-gw"
      "-t"
      "none"
      "-u"
      "none"
      "-T"
      "none"
      "-U"
      "none"
      "--ns-ifname"
      "eth0"
      "--address"
      "192.168.1.100"
      "--netmask"
      "255.255.255.0"
      "--gateway"
      "192.168.1.1"
      "--dns-forward"
      "192.168.1.1"
      "--search"
      "none"
    ];

    paths = {
      allowed_env_vars = [
        "HOME"
        "XDG_RUNTIME_DIR"
        "XDG_CONFIG_HOME"
        "XDG_DATA_HOME"
        "XDG_STATE_HOME"
        "XDG_CACHE_HOME"
        "USER"
      ];
      ro_system_paths = [
        "/nix/store"
        "/bin"
        "/usr/bin"
        "/run/current-system"
        "/etc/xdg"
        "/etc/fonts"
        "/etc/localtime"
        "/etc/zoneinfo"
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
        "/etc/xdg/openxr"
      ];
      user_theme_subpaths = [
        ".nix-profile"
        ".local/state/nix/profile"
        ".icons"
        ".themes"
        ".fonts"
      ];
      xdg_config_subpaths = [
        "user-dirs.dirs"
        "user-dirs.conf"
        "fontconfig"
        "gtk-4.0"
        "gtk-3.0"
        "qt6ct"
        "qt5ct"
        "Kvantum"
        "starship.toml"
        "fastfetch"
        "openvr"
        "openxr"
      ];
      xdg_data_subpaths = [
        "zsh/.zshenv"
        "zsh/.zshrc"
        "icons"
        "themes"
        "color-schemes"
        "fonts"
      ];
      nvidia_nodes = [
        "/dev/nvidia0"
        "/dev/nvidiactl"
        "/dev/nvidia-modeset"
        "/dev/nvidia-uvm"
        "/dev/nvidia-uvm-tools"
      ];
    };
  };

  evalSandboxConfig =
    extraModules:
    removeAttrs
      (lib.evalModules {
        modules = [
          sandboxConfigModule
          baseSandboxConfig
        ]
        ++ extraModules;
      }).config
      [ "_module" ];

  sbRunConfigFile = (pkgs.formats.json { }).generate "sb-run-config.json" (evalSandboxConfig [ ]);

  mkSandbox =
    args@{
      appId,
      package,
      main_desktop_file ? "none",
      additional_outside_commands ? "",
      additional_inside_commands ? "",
      extraAttrs ? [ ],
      ...
    }:
    let
      sandboxModuleArgs = removeAttrs args [
        "appId"
        "package"
        "main_desktop_file"
        "additional_outside_commands"
        "additional_inside_commands"
        "extraAttrs"
      ];

      evaluatedConfig = evalSandboxConfig [ sandboxModuleArgs ];
      appConfigJson = (pkgs.formats.json { }).generate "sb-run-${appId}.json" evaluatedConfig;

      wrapperScript = pkgs.writeShellScript "sandbox-launcher-${appId}" ''
        if [ ! -e "/.sb-sandbox" ] && [ -z "''${SB_SANDBOX:-}" ]; then
          MY_CGROUP="/sys/fs/cgroup$(cat /proc/self/cgroup | cut -d: -f3)"
          MY_SCOPE="$(basename "$MY_CGROUP" 2>/dev/null)"
          case "$MY_SCOPE" in
            *"${appId}"*)
              ;;
            *)
              exec app2unit -a "${appId}" -- "$0" "$@"
              ;;
          esac

          mkdir -p "$MY_CGROUP/helpers"
          echo $$ > "$MY_CGROUP/helpers/cgroup.procs"
          echo "+memory +pids +cpu +io" > "$(dirname "$MY_CGROUP")/cgroup.subtree_control" 2>/dev/null || true
          echo "+memory +pids +cpu +io" > "$MY_CGROUP/cgroup.subtree_control" 2>/dev/null || true
          mkdir -p "$MY_CGROUP/inside"
          export MY_CGROUP MY_SCOPE

          export START_TIME=$(date +%s%N)
          export APP_ID="${appId}"

          export SANDBOX_DIR="$XDG_RUNTIME_DIR/.nixpak/${appId}"
          export SANDBOXED_RUNTIME_DIR="$SANDBOX_DIR/runtime"
          mkdir -p "$SANDBOXED_RUNTIME_DIR"

          ${additional_outside_commands}
          exec sb-run --config ${appConfigJson} --id ${lib.escapeShellArg appId} \
            ${
              lib.optionalString (
                additional_inside_commands != ""
              ) "--inside-init ${lib.escapeShellArg additional_inside_commands}"
            } \
            -- "$TARGET" "$@"
        else
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

  cfg = config.sandboxing;
in
{
  options.sandboxing.enable = lib.mkEnableOption "app sandboxing";

  config = lib.mkMerge [
    {
      _module.args = {
        inherit staticBwrap mkSandbox;
      };
    }
    (lib.mkIf cfg.enable {
      home.packages = [
        staticBwrap
        pasta-pkg
        way-secure-pkg
        pw-portal-shim-pkg
      ];
      xdg.dataFile = {
        "sb-run/config.json".source = sbRunConfigFile;
        "sb-run/syscalls.json".source = syscallsJson;
        "sb-run/sing-box.json".source = sing-box-sandbox-config;
      };
    })
  ];
}
