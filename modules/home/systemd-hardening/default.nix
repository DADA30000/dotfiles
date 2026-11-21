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
  # IMPORTANT systemd --user caveats:
  # - Any mount/UTS/net namespace directive (ProtectSystem, ProtectHome,
  #   PrivateTmp, PrivateDevices, ProtectKernel*, ProtectControlGroups,
  #   ProtectClock, ProtectHostname, ProtectProc, ProcSubset, PrivateUsers,
  #   PrivateNetwork) implicitly creates an unprivileged CLONE_NEWUSER with
  #   uid_map `UID UID 1`. Do NOT use those on xdg-desktop-portal*, portal
  #   clients (which need /proc/<pid>/root in the host userns), or units
  #   calling setfacl for other UIDs (e.g. replays.service).
  # - PrivateIPC=true fails mounting /dev/mqueue in unprivileged userns.
  # - IPAddressDeny= requires root BPF cgroup privileges (ignored in --user).
  #
  # Use `systemd.user.services.<name>.Service` for HM-defined units, and
  # `systemd.user.serviceDropins.<name>.Service` for NixOS/package-provided
  # user units (so you don't shadow their upstream ExecStart=).
  #
  # Service = {
  #   # --- Privilege & Capability Hygiene (host-userns safe) ---
  #   NoNewPrivileges = true;        # blocks setuid/setgid & file caps
  #   UMask = "0077";                # owner-only permissions on newly created files/sockets
  #   KeyringMode = "private";       # isolates kernel keyring
  #   LockPersonality = true;        # locks personality(2) to native domain
  #   RestrictNamespaces = true;     # blocks creating nested namespaces
  #   RestrictRealtime = true;       # blocks SCHED_FIFO/SCHED_RR (breaks PipeWire/WirePlumber/EasyEffects)
  #   RestrictSUIDSGID = true;       # blocks creating SUID/SGID files
  #   MemoryDenyWriteExecute = true; # enforces W^X (breaks Qt/QML, GTK/GJS, Mesa/Vulkan/GL, audio plugins)
  #   RestrictAddressFamilies = [ "AF_UNIX" ];
  #   SystemCallArchitectures = "native";
  #   SystemCallFilter = [ "@system-service" "~@privileged" "~@resources" ];
  #   SystemCallErrorNumber = "EPERM";
  #
  #   # --- Filesystem & Namespace Isolation (triggers CLONE_NEWUSER in --user) ---
  #   # Specifiers: %h=$HOME, %t=$XDG_RUNTIME_DIR, %E=$XDG_CONFIG_HOME,
  #   # %D=$XDG_DATA_HOME, %C=$XDG_CACHE_HOME, %S=$XDG_STATE_HOME.
  #   # Prefix a path with "-" to ignore it if it does not exist yet.
  #   ProtectSystem = "strict";      # entire FS read-only except ReadWritePaths
  #   ReadWritePaths = [ "-%t/my-service" ];
  #   ProtectHome = true;            # hides $HOME completely (use "read-only" when granting ReadWritePaths under %h)
  #   PrivateTmp = true;             # private /tmp and /var/tmp (breaks X11 /tmp/.X11-unix IPC)
  #   PrivateDevices = true;         # minimal /dev (breaks GPU /dev/dri, /dev/nvidia*, audio /dev/snd)
  #   ProtectKernelTunables = true;  # /proc/sys and /sys read-only
  #   ProtectKernelModules = true;   # blocks module load syscalls
  #   ProtectKernelLogs = true;      # blocks dmesg / /dev/kmsg
  #   ProtectControlGroups = true;   # /sys/fs/cgroup read-only (breaks cgroup managers)
  #   ProtectClock = true;           # blocks clock changes
  #   ProtectHostname = true;        # private UTS namespace
  #   ProtectProc = "invisible";     # hides other users' /proc/<pid>
  #   ProcSubset = "pid";            # hides /proc/meminfo, /proc/stat, etc.
  #   PrivateNetwork = true;         # loopback-only netns (breaks LAN/internet)
  #   PrivateUsers = true;           # isolates user namespace
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

  # Pure process/seccomp/socket hardening without mount/UTS/net namespaces,
  # keeping the unit in the host user namespace (required for portals,
  # portal-using apps, dbus-broker reloads, and cross-UID setfacl).
  hostUserns = {
    NoNewPrivileges = true;
    LockPersonality = true;
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    KeyringMode = "private";
    SystemCallArchitectures = "native";
    SystemCallErrorNumber = "EPERM";
  };

  # Base for leaf daemons that can safely run in an unprivileged userns.
  base = hostUserns // {
    ProtectClock = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectControlGroups = true;
  };

  tight = base // {
    ProtectSystem = "strict";
    PrivateTmp = true;
    PrivateDevices = true;
    DevicePolicy = "closed";
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
    ReadWritePaths = [ "%t" ];
    RestrictAddressFamilies = [ "AF_UNIX" ];
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
in
{
  options.systemd-hardening.enable = lib.mkEnableOption "per-service Home Manager systemd user hardening";

  config = lib.mkIf cfg.enable {
    # HM-Owned User Services (merged directly into systemd.user.services)
    # Note: noctalia.service is intentionally left unsandboxed — it is the
    # desktop shell (app launcher via app2unit scopes, screenshots to
    # ~/Pictures/Screenshots, Polkit/NM secret agent, notifications, plugins).
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
            RestrictAddressFamilies = [ "AF_UNIX" ];
            SystemCallFilter = safeSyscalls;
          }
        );

        # libqb IPC needs host netns for @usbguard abstract socket + /dev/shm/qb-*
        usbguard-notifier.Service = mkDefaults (
          bridge
          // {
            PrivateNetwork = false;
            PrivateUsers = false;
            ReadWritePaths = [
              "%t"
              "/dev/shm"
            ];
          }
        );
        sunshine.Service = mkDefaults bridge;
        opentabletdriver.Service = mkDefaults bridge;

        # Uses xdg-desktop-portal -> must stay in host userns
        valent.Service = mkDefaults (
          hostUserns
          // {
            RestrictAddressFamilies = netAF ++ [ "AF_BLUETOOTH" ];
            SystemCallFilter = safeSyscalls;
          }
        );
      }

      (lib.mkIf config.services.ssh-agent.enable {
        ssh-agent.Service = mkDefaults bridge;
      })

      (lib.mkIf config.services.easyeffects.enable {
        # Uses xdg-desktop-portal + realtime audio -> host userns, allow RT
        easyeffects.Service = mkDefaults (
          hostUserns
          // {
            RestrictRealtime = false;
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_NETLINK"
            ];
            SystemCallFilter = safeSyscalls;
          }
        );
      })

      (lib.mkIf config.replays.enable {
        # Runs setfacl -m u:replays:r on /run/user/%U/replays.env -> must stay
        # in host userns so the `replays` system UID is mapped in uid_map.
        replays.Service = mkDefaults (
          hostUserns
          // {
            MemoryDenyWriteExecute = true;
            UMask = "0077";
            RestrictAddressFamilies = [ "AF_UNIX" ];
            SystemCallFilter = [
              "@system-service"
              "~@privileged"
              "~@resources"
            ];
          }
        );
      })

      (lib.mkIf config.hyprland.enable {
        oo7-daemon.Service = mkDefaults (
          tight
          // {
            ProtectHome = "read-only";
            PrivateNetwork = true;
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
          ReadWritePaths = [
            "-%E/dconf"
            "-%C/dconf"
            "%t"
          ];
          RestrictAddressFamilies = [ "AF_UNIX" ];
        }
      );

      # Session D-Bus stays in host userns for clean reloads & peer credentials
      dbus-broker.Service = mkDefaults (
        hostUserns
        // {
          MemoryDenyWriteExecute = true;
          UMask = "0077";
          RestrictAddressFamilies = [ "AF_UNIX" ];
          SystemCallFilter = [
            "@system-service"
            "~@privileged"
            "~@resources"
          ];
        }
      );

      at-spi-dbus-bus.Service = mkDefaults bridge;

      systembus-notify.Service = mkDefaults bridge;

      xdg-permission-store.Service = mkDefaults (
        tight
        // {
          ProtectHome = "read-only";
          PrivateNetwork = true;
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
          ProtectProc = "default";
          ProcSubset = "all";
          RestrictAddressFamilies = [ "none" ];
        }
      );

      # Portals must stay in host userns so /proc/<pid>/root opens succeed
      xdg-desktop-portal.Service = mkDefaults (
        hostUserns
        // {
          RestrictAddressFamilies = netAF;
          SystemCallFilter = safeSyscalls;
        }
      );

      xdg-desktop-portal-gtk.Service = mkDefaults (
        hostUserns
        // {
          RestrictAddressFamilies = [ "AF_UNIX" ];
          SystemCallFilter = safeSyscalls;
        }
      );

      xdg-desktop-portal-hyprland.Service = mkDefaults (
        hostUserns
        // {
          RestrictAddressFamilies = [ "AF_UNIX" ];
          SystemCallFilter = safeSyscalls;
        }
      );

      # GVFS stack
      gvfs-metadata.Service = mkDefaults (
        tight
        // {
          ProtectHome = "read-only";
          PrivateNetwork = true;
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

      # WiVRn user service is a lightweight bridge to hardened wivrn@%u.service
      wivrn.Service = mkDefaults bridge;
    };
  };
}
