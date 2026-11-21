{
  config,
  lib,
  ...
}:
let
  cfg = config.systemd-hardening;
  mkDefaults = lib.mapAttrs (_: lib.mkDefault);

  # ---------------------------------------------------------------------------
  # MAXIMUM LOCKDOWN REFERENCE EXAMPLE (Home Manager / systemd --user)
  # systemd 262 --user supports BOTH seccomp/process restrictions AND
  # mount-namespace sandboxing (via unprivileged user namespaces).
  #
  # Use `systemd.user.services.<name>.Service` for HM-defined units, and
  # `systemd.user.serviceDropins.<name>.Service` for NixOS/package-provided
  # user units (so you don't shadow their upstream ExecStart=).
  #
  # Service = {
  #   # --- Privilege & Capability Hygiene ---
  #   NoNewPrivileges = true;        # blocks setuid/setgid & file caps (breaks /run/wrappers/bin/* like wivrn-server)
  #   UMask = "0077";                # owner-only permissions on newly created files/sockets
  #
  #   # --- Filesystem Isolation (userns mount namespaces) ---
  #   # Specifiers: %h=$HOME, %t=$XDG_RUNTIME_DIR, %E=$XDG_CONFIG_HOME,
  #   # %D=$XDG_DATA_HOME, %C=$XDG_CACHE_HOME, %S=$XDG_STATE_HOME.
  #   # Prefix a path with "-" to ignore it if it does not exist yet.
  #   ProtectSystem = "strict";      # entire FS read-only except ReadWritePaths
  #   ReadWritePaths = [ "-%t/my-service" ];
  #   ProtectHome = true;            # hides $HOME completely (use "read-only" or false when granting ReadWritePaths under %h)
  #   PrivateTmp = true;             # private /tmp and /var/tmp (breaks X11 /tmp/.X11-unix IPC)
  #   PrivateDevices = true;         # minimal /dev (breaks GPU /dev/dri, /dev/nvidia*, audio /dev/snd)
  #
  #   # --- Kernel, Hardware & Procfs Protection ---
  #   ProtectKernelTunables = true;  # /proc/sys and /sys read-only
  #   ProtectKernelModules = true;   # blocks module load syscalls
  #   ProtectKernelLogs = true;      # blocks dmesg / /dev/kmsg
  #   ProtectControlGroups = true;   # /sys/fs/cgroup read-only (breaks cgroup managers)
  #   ProtectClock = true;           # blocks clock changes
  #   ProtectHostname = true;        # private UTS namespace
  #   ProtectProc = "invisible";     # hides other users' /proc/<pid>
  #   ProcSubset = "pid";            # hides /proc/meminfo, /proc/stat, etc.
  #
  #   # --- Namespace & IPC Isolation ---
  #   PrivateNetwork = true;         # loopback-only netns (breaks LAN/internet)
  #   PrivateIPC = true;             # isolates SysV IPC & POSIX mqueues
  #   KeyringMode = "private";       # isolates kernel keyring
  #   RestrictNamespaces = true;     # blocks creating nested namespaces
  #
  #   # --- Memory, Execution & Seccomp ---
  #   MemoryDenyWriteExecute = true; # enforces W^X (breaks Qt/QML, GTK/GJS, Mesa/Vulkan/GL, audio plugins)
  #   LockPersonality = true;        # locks personality(2) to native domain
  #   RestrictRealtime = true;       # blocks SCHED_FIFO/SCHED_RR (breaks PipeWire, WirePlumber, EasyEffects, WiVRn)
  #   RestrictSUIDSGID = true;       # blocks creating SUID/SGID files
  #   RestrictAddressFamilies = [ "AF_UNIX" ];
  #   SystemCallArchitectures = "native";
  #   SystemCallFilter = [ "@system-service" "~@privileged" "~@resources" ];
  #   SystemCallErrorNumber = "EPERM";
  # };
  # ---------------------------------------------------------------------------

  safeSyscalls = [
    "@system-service"
    "~@mount"
    "~@module"
    "~@raw-io"
    "~@reboot"
    "~@swap"
    "~@clock"
    "~@debug"
    "~@obsolete"
    "~@cpu-emulation"
  ];
  netAF = [
    "AF_UNIX"
    "AF_INET"
    "AF_INET6"
    "AF_NETLINK"
  ];

  base = {
    NoNewPrivileges = true;
    ProtectClock = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectControlGroups = true;
    LockPersonality = true;
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    KeyringMode = "private";
    SystemCallArchitectures = "native";
    SystemCallErrorNumber = "EPERM";
  };

  tight = base // {
    ProtectSystem = "strict";
    PrivateTmp = true;
    PrivateDevices = true;
    DevicePolicy = "closed";
    PrivateIPC = true;
    PrivateUsers = true;
    ProtectProc = "invisible";
    ProcSubset = "pid";
    MemoryDenyWriteExecute = true;
    UMask = "0077";
    SystemCallFilter = [
      "@system-service"
      "~@privileged"
      "~@resources"
    ];
  };

  bridge = tight // {
    ProtectHome = "read-only";
    PrivateNetwork = true;
    IPAddressDeny = "any";
    ReadWritePaths = [ "%t" ];
    RestrictAddressFamilies = [ "AF_UNIX" ];
  };

  gui = base // {
    ProtectSystem = "strict";
    ProtectHome = "read-only";
    ProtectProc = "invisible";
    SystemCallFilter = safeSyscalls;
  };

  audio = {
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = "read-only";
    ProtectClock = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectControlGroups = true;
    ProtectProc = "invisible";
    PrivateTmp = true;
    PrivateNetwork = true;
    IPAddressDeny = "any";
    LockPersonality = true;
    RestrictNamespaces = true;
    RestrictSUIDSGID = true;
    KeyringMode = "private";
    RestrictAddressFamilies = [
      "AF_UNIX"
      "AF_NETLINK"
    ];
    SystemCallArchitectures = "native";
    SystemCallErrorNumber = "EPERM";
  };

  light = {
    ProtectClock = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    LockPersonality = true;
    RestrictSUIDSGID = true;
    KeyringMode = "private";
    SystemCallArchitectures = "native";
  };
in
{
  options.systemd-hardening.enable = lib.mkEnableOption "per-service Home Manager systemd user hardening";

  config = lib.mkIf cfg.enable {
    # HM-Owned User Services (merged directly into systemd.user.services)
    systemd.user.services = lib.mkMerge [
      {
        # cgroup-executioner monitors user cgroups (/sys/fs/cgroup) & kills scopes
        cgroup-executioner.Service = mkDefaults (
          tight
          // {
            ProtectHome = true;
            ProtectControlGroups = false;
            ProtectProc = "default";
            ProcSubset = "all";
            PrivateNetwork = true;
            IPAddressDeny = "any";
            RestrictAddressFamilies = [ "AF_UNIX" ];
            SystemCallFilter = safeSyscalls;
          }
        );

        # libqb IPC needs host netns for @usbguard abstract socket + /dev/shm/qb-*
        usbguard-notifier.Service = mkDefaults (
          bridge
          // {
            PrivateNetwork = false;
            PrivateIPC = false;
            PrivateUsers = false;
            ReadWritePaths = [
              "%t"
              "/dev/shm"
            ];
          }
        );
        sunshine.Service = mkDefaults bridge;
        opentabletdriver.Service = mkDefaults bridge;

        valent.Service = mkDefaults (
          gui
          // {
            ProtectHome = false;
            ReadWritePaths = [
              "%h"
              "%t"
            ];
            RestrictAddressFamilies = netAF ++ [ "AF_BLUETOOTH" ];
          }
        );
      }

      (lib.mkIf config.services.ssh-agent.enable {
        ssh-agent.Service = mkDefaults bridge;
      })

      (lib.mkIf config.services.easyeffects.enable {
        easyeffects.Service = mkDefaults (
          audio
          // {
            ReadWritePaths = [
              "-%E/easyeffects"
              "-%D/easyeffects"
              "-%C/easyeffects"
              "%t"
            ];
            SystemCallFilter = safeSyscalls;
          }
        );
      })

      (lib.mkIf config.replays.enable {
        # User bridge forwarding env + setfacl (needs host UID map so replays UID resolves)
        replays.Service = mkDefaults (
          bridge
          // {
            PrivateUsers = false;
          }
        );
      })

      (lib.mkIf config.hyprland.enable {
        noctalia.Service = mkDefaults (
          gui
          // {
            ReadWritePaths = [
              "-%E/noctalia"
              "-%C/noctalia"
              "-%D/noctalia"
              "-%S/noctalia"
              "-%C/quickshell"
              "-%C/nvidia"
              "%t"
            ];
            RestrictAddressFamilies = netAF;
          }
        );

        oo7-daemon.Service = mkDefaults (
          tight
          // {
            ProtectHome = "read-only";
            PrivateNetwork = true;
            IPAddressDeny = "any";
            ReadWritePaths = [
              "-%D/keyrings"
              "%t"
            ];
            RestrictAddressFamilies = [ "AF_UNIX" ];
          }
        );

        oo7-portal.Service = mkDefaults (
          tight
          // {
            ProtectHome = "read-only";
            PrivateNetwork = true;
            IPAddressDeny = "any";
            ReadWritePaths = [
              "-%D/keyrings"
              "%t"
            ];
            RestrictAddressFamilies = [ "AF_UNIX" ];
          }
        );
      })
    ];

    # Mask unused PulseAudio daemon (PipeWire's pipewire-pulse handles audio)
    xdg.configFile."systemd/user/pulseaudio.service".source =
      config.lib.file.mkOutOfStoreSymlink "/dev/null";

    # System / Package-Provided User Units (via highest-priority drop-ins)
    systemd.user.serviceDropins = {
      dconf.Service = mkDefaults (
        tight
        // {
          ProtectHome = "read-only";
          PrivateNetwork = true;
          IPAddressDeny = "any";
          ReadWritePaths = [
            "-%E/dconf"
            "%t"
          ];
          RestrictAddressFamilies = [ "AF_UNIX" ];
        }
      );

      dbus-broker.Service = mkDefaults bridge;

      at-spi-dbus-bus.Service = mkDefaults bridge;

      systembus-notify.Service = mkDefaults bridge;

      xdg-permission-store.Service = mkDefaults (
        tight
        // {
          ProtectHome = "read-only";
          PrivateNetwork = true;
          IPAddressDeny = "any";
          ReadWritePaths = [
            "-%D/flatpak"
            "%t"
          ];
          RestrictAddressFamilies = [ "AF_UNIX" ];
        }
      );

      # uwsm session bindpid watcher (just runs waitpid -e %i)
      "wayland-session-bindpid@".Service = mkDefaults (
        tight
        // {
          ProtectHome = true;
          PrivateNetwork = true;
          IPAddressDeny = "any";
          ProtectProc = "default";
          ProcSubset = "all";
          RestrictAddressFamilies = [ "none" ];
        }
      );

      podman.Service = mkDefaults light;

      # Portals
      xdg-desktop-portal.Service = mkDefaults (
        gui
        // {
          ProtectHome = false;
          ReadWritePaths = [
            "%h"
            "%t"
          ];
          RestrictAddressFamilies = netAF;
        }
      );

      xdg-desktop-portal-gtk.Service = mkDefaults (
        gui
        // {
          ProtectHome = false;
          PrivateNetwork = true;
          IPAddressDeny = "any";
          ReadWritePaths = [
            "%h"
            "%t"
          ];
          RestrictAddressFamilies = [ "AF_UNIX" ];
        }
      );

      xdg-desktop-portal-hyprland.Service = mkDefaults (
        gui
        // {
          PrivateNetwork = true;
          IPAddressDeny = "any";
          ReadWritePaths = [
            "-%C"
            "%t"
          ];
          RestrictAddressFamilies = [ "AF_UNIX" ];
        }
      );

      # GVFS stack
      gvfs-metadata.Service = mkDefaults (
        tight
        // {
          ProtectHome = "read-only";
          PrivateNetwork = true;
          IPAddressDeny = "any";
          ReadWritePaths = [
            "-%D/gvfs-metadata"
            "%t"
          ];
          RestrictAddressFamilies = [ "AF_UNIX" ];
        }
      );

      gvfs-daemon.Service = mkDefaults (
        base
        // {
          ProtectSystem = "full";
          MemoryDenyWriteExecute = true;
          RestrictAddressFamilies = netAF;
          SystemCallFilter = [
            "@system-service"
            "~@module"
            "~@raw-io"
            "~@reboot"
            "~@swap"
            "~@clock"
            "~@debug"
            "~@obsolete"
            "~@cpu-emulation"
          ];
        }
      );

      gvfs-udisks2-volume-monitor.Service = mkDefaults (
        tight
        // {
          ProtectHome = "read-only";
          PrivateNetwork = true;
          IPAddressDeny = "any";
          ReadWritePaths = [ "%t" ];
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_NETLINK"
          ];
        }
      );

      gvfs-afc-volume-monitor.Service = mkDefaults (
        tight
        // {
          ProtectHome = "read-only";
          PrivateDevices = false;
          DevicePolicy = "auto";
          PrivateNetwork = true;
          IPAddressDeny = "any";
          ReadWritePaths = [ "%t" ];
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_NETLINK"
          ];
        }
      );

      gvfs-goa-volume-monitor.Service = mkDefaults (
        tight
        // {
          ProtectHome = "read-only";
          ReadWritePaths = [ "%t" ];
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_INET"
            "AF_INET6"
          ];
        }
      );

      gvfs-gphoto2-volume-monitor.Service = mkDefaults (
        tight
        // {
          ProtectHome = "read-only";
          PrivateDevices = false;
          DevicePolicy = "auto";
          PrivateNetwork = true;
          IPAddressDeny = "any";
          ReadWritePaths = [ "%t" ];
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_NETLINK"
          ];
        }
      );

      gvfs-mtp-volume-monitor.Service = mkDefaults (
        tight
        // {
          ProtectHome = "read-only";
          PrivateDevices = false;
          DevicePolicy = "auto";
          PrivateNetwork = true;
          IPAddressDeny = "any";
          ReadWritePaths = [ "%t" ];
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_NETLINK"
          ];
        }
      );

      # PipeWire / WirePlumber (keeps realtime audio + /dev/snd + Bluetooth)
      pipewire.Service = mkDefaults (
        audio
        // {
          ReadWritePaths = [
            "-%S/pipewire"
            "-%E/pipewire"
            "%t"
          ];
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_NETLINK"
            "AF_BLUETOOTH"
          ];
        }
      );

      pipewire-pulse.Service = mkDefaults (
        audio
        // {
          ReadWritePaths = [
            "-%E/pulse"
            "%t"
          ];
        }
      );

      wireplumber.Service = mkDefaults (
        audio
        // {
          ReadWritePaths = [
            "-%S/wireplumber"
            "-%E/wireplumber"
            "%t"
          ];
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_NETLINK"
            "AF_BLUETOOTH"
          ];
        }
      );

      # WiVRn user service is now a lightweight bridge to hardened wivrn@%u.service
      wivrn.Service = mkDefaults bridge;
    };
  };
}
