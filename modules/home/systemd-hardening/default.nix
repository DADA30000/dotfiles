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
  # This module hardens UPSTREAM / NixOS-provided user services only; custom
  # dotfiles user services carry their hardening directly in their own modules.
  #
  # IMPORTANT systemd --user caveats:
  # - Any mount/UTS/net namespace directive (ProtectSystem, ProtectHome,
  #   PrivateTmp, PrivateDevices, ProtectKernel*, ProtectControlGroups,
  #   ProtectClock, ProtectHostname, ProtectProc, ProcSubset, PrivateUsers,
  #   PrivateNetwork) implicitly creates an unprivileged CLONE_NEWUSER with
  #   uid_map `UID UID 1`. Do NOT use those on xdg-desktop-portal*, portal
  #   clients (which need /proc/<pid>/root in the host userns), or units
  #   calling setfacl for other UIDs.
  # - PrivateIPC=true fails mounting /dev/mqueue in unprivileged userns.
  # - IPAddressDeny= requires root BPF cgroup privileges (ignored in --user).
  # - Close UID-1000 sandbox escape via %t/bus & %t/systemd/private using the
  #   `dbus` helper on `systemd.user.serviceDropins.<name>` (or
  #   `systemd.user.dbusProxy.services.<name>` for HM-owned services).
  #
  # Use `systemd.user.services.<name>.Service` for HM-defined units, and
  # `systemd.user.serviceDropins.<name>` for NixOS/package-provided user units
  # (so you don't shadow their upstream ExecStart=).
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
  # portal-using apps, and dbus-broker reloads).
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
  options.systemd-hardening.enable = lib.mkEnableOption "per-service Home Manager upstream systemd user hardening";

  config = lib.mkIf cfg.enable {
    # Upstream HM-Module-Provided User Services
    systemd.user.services = lib.mkMerge [
      (lib.mkIf config.services.ssh-agent.enable {
        ssh-agent.Service = mkDefaults (
          bridge
          // {
            InaccessiblePaths = [
              "-%t/bus"
              "-%t/systemd/private"
              "-/run/dbus/system_bus_socket"
            ];
          }
        );
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
    ];

    # Mask unused PulseAudio daemon (PipeWire's pipewire-pulse handles audio)
    xdg.configFile."systemd/user/pulseaudio.service".source =
      config.lib.file.mkOutOfStoreSymlink "/dev/null";

    systemd.user.tmpfiles.rules = [
      "d %h/.local/share/flatpak/db 0700 - - -"
    ];

    # System / Package-Provided User Units (via highest-priority drop-ins)
    systemd.user.serviceDropins = {
      dconf = {
        dbus = {
          own = [ "ca.desrt.dconf" ];
          blockSystemBus = true;
        };
        Service = mkDefaults (
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
      };

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

      at-spi-dbus-bus = {
        dbus.blockSystemBus = true;
        Service = mkDefaults (
          bridge
          // {
            InaccessiblePaths = [ "-%t/systemd/private" ];
          }
        );
      };

      systembus-notify = {
        dbus.talk = [ "org.freedesktop.Notifications" ];
        Service = mkDefaults bridge;
      };

      xdg-permission-store = {
        dbus = {
          own = [ "org.freedesktop.impl.portal.PermissionStore" ];
          blockSystemBus = true;
        };
        Service = mkDefaults (
          tight
          // {
            ProtectHome = "read-only";
            PrivateNetwork = true;
            ReadWritePaths = [
              "-%h/.local/share/flatpak"
              "%t"
            ];
            RestrictAddressFamilies = [ "AF_UNIX" ];
          }
        );
      };

      # uwsm session bindpid watcher (just runs waitpid -e %i)
      "wayland-session-bindpid@" = {
        dbus = {
          block = true;
          blockSystemBus = true;
        };
        Service = mkDefaults (
          tight
          // {
            ProtectHome = true;
            PrivateNetwork = true;
            ProtectProc = "default";
            ProcSubset = "all";
            RestrictAddressFamilies = [ "none" ];
          }
        );
      };

      # Portals must stay in host userns so /proc/<pid>/root opens succeed;
      # xdg-desktop-portal also spawns bwrap for xdg-desktop-portal-validate-icon --sandbox
      xdg-desktop-portal.Service = mkDefaults (
        hostUserns
        // {
          RestrictNamespaces = "user mnt ipc net pid";
          RestrictAddressFamilies = netAF;
          SystemCallFilter = [ "@mount" ] ++ lib.remove "~@mount" safeSyscalls;
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
      gvfs-metadata = {
        dbus = {
          own = [ "org.gtk.vfs.Metadata" ];
          blockSystemBus = true;
        };
        Service = mkDefaults (
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
      };

      gvfs-daemon.Service = mkDefaults (
        base
        // {
          ProtectSystem = "full";
          MemoryDenyWriteExecute = true;
          RestrictAddressFamilies = netAF;
          InaccessiblePaths = [ "-%t/systemd/private" ];
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

      gvfs-udisks2-volume-monitor = {
        dbus = {
          own = [ "org.gtk.vfs.UDisks2VolumeMonitor" ];
          talk = [ "org.gtk.vfs.Daemon" ];
        };
        Service = mkDefaults (
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
      };

      gvfs-afc-volume-monitor = {
        dbus = {
          own = [ "org.gtk.vfs.AfcVolumeMonitor" ];
          talk = [ "org.gtk.vfs.Daemon" ];
          blockSystemBus = true;
        };
        Service = mkDefaults (
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
      };

      gvfs-goa-volume-monitor = {
        dbus = {
          own = [ "org.gtk.vfs.GoaVolumeMonitor" ];
          talk = [
            "org.gtk.vfs.Daemon"
            "org.gnome.OnlineAccounts"
          ];
          blockSystemBus = true;
        };
        Service = mkDefaults (
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
      };

      gvfs-gphoto2-volume-monitor = {
        dbus = {
          own = [ "org.gtk.vfs.GPhoto2VolumeMonitor" ];
          talk = [ "org.gtk.vfs.Daemon" ];
          blockSystemBus = true;
        };
        Service = mkDefaults (
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
      };

      gvfs-mtp-volume-monitor = {
        dbus = {
          own = [ "org.gtk.vfs.MTPVolumeMonitor" ];
          talk = [ "org.gtk.vfs.Daemon" ];
          blockSystemBus = true;
        };
        Service = mkDefaults (
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
      };

      # PipeWire / WirePlumber (keeps realtime audio + /dev/snd + Bluetooth + RTKit on system bus)
      pipewire = {
        dbus.talk = [ "org.freedesktop.portal.Desktop" ];
        Service = mkDefaults (
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
      };

      pipewire-pulse = {
        dbus.own = [ "org.pulseaudio.Server" ];
        Service = mkDefaults (
          audio
          // {
            ReadWritePaths = [
              "-%E/pulse"
              "%t"
            ];
          }
        );
      };

      wireplumber = {
        dbus = {
          own = [
            "org.freedesktop.ReserveDevice1.*"
            "org.pipewire.Telephony"
          ];
          talk = [
            "org.freedesktop.impl.portal.PermissionStore"
            "org.freedesktop.impl.portal.desktop.gtk"
            "org.mpris.MediaPlayer2.*"
            "org.freedesktop.Notifications"
          ];
        };
        Service = mkDefaults (
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
      };
    };
  };
}
