{
  config,
  lib,
  ...
}:
let
  cfg = config.systemd-hardening;
  mkDefaults = lib.mapAttrs (_: lib.mkDefault);

  # ---------------------------------------------------------------------------
  # MAXIMUM LOCKDOWN REFERENCE EXAMPLE (NixOS System Services)
  # Start from this template for a new service, then relax ONLY what it needs.
  #
  # serviceConfig = {
  #   # --- Identity & Privilege Dropping ---
  #   DynamicUser = true;            # transient UID/GID; implies RemoveIPC, PrivateTmp, ProtectSystem=strict, ProtectHome=read-only, RestrictSUIDSGID (breaks static UIDs)
  #   NoNewPrivileges = true;        # blocks setuid/setgid & file caps on execve (breaks /run/wrappers/bin/*, sudo, su)
  #   CapabilityBoundingSet = "";    # drops ALL Linux caps; add back only needed ones e.g. [ "CAP_NET_BIND_SERVICE" ]
  #   AmbientCapabilities = "";
  #
  #   # --- Filesystem Isolation ---
  #   ProtectSystem = "strict";      # entire FS read-only except /dev, /proc, /sys & ReadWritePaths / StateDirectory / RuntimeDirectory / CacheDirectory / LogsDirectory
  #   ProtectHome = true;            # hides /home, /root, /run/user ("read-only" or "tmpfs" are softer alternatives)
  #   PrivateTmp = true;             # isolated /tmp and /var/tmp (breaks shared /tmp IPC)
  #   PrivateDevices = true;         # minimal /dev (/dev/null, zero, urandom); implies DevicePolicy=closed (breaks GPU, disks, /dev/net/tun)
  #   DevicePolicy = "closed";       # or "strict" with explicit DeviceAllow= lines
  #   UMask = "0077";                # owner-only permissions on newly created files/sockets
  #
  #   # --- Kernel, Hardware & Procfs Protection ---
  #   ProtectKernelTunables = true;  # /proc/sys, /sys, /proc/irq, /proc/bus read-only (breaks sysfs/hwmon/tracing/sysctl writers)
  #   ProtectKernelModules = true;   # blocks loading/unloading kernel modules
  #   ProtectKernelLogs = true;      # blocks dmesg / /dev/kmsg
  #   ProtectControlGroups = true;   # /sys/fs/cgroup read-only (breaks container/VM/cgroup managers)
  #   ProtectClock = true;           # blocks clock changes (breaks chronyd/NTP)
  #   ProtectHostname = true;        # private UTS namespace (blocks hostname changes)
  #   ProtectProc = "invisible";     # hides other users' /proc/<pid> entries
  #   ProcSubset = "pid";            # hides non-PID /proc files like /proc/stat, /proc/net
  #
  #   # --- Namespace & IPC Isolation ---
  #   PrivateNetwork = true;         # loopback-only netns (breaks real networking & netlink)
  #   IPAddressDeny = "any";         # pair with IPAddressAllow="localhost" or CIDRs
  #   PrivateIPC = true;             # isolates SysV IPC & POSIX mqueues
  #   PrivateUsers = true;           # userns mapping only root + service UID (breaks PAM/polkit)
  #   KeyringMode = "private";       # isolates kernel keyring from other services
  #   RestrictNamespaces = true;     # blocks creating new namespaces (breaks containers/sandboxes)
  #
  #   # --- Memory, Execution & Seccomp ---
  #   MemoryDenyWriteExecute = true; # enforces W^X (breaks JIT: V8, JVM, LuaJIT, Mesa/GL, Qt)
  #   LockPersonality = true;        # locks personality(2) to native domain
  #   RestrictRealtime = true;       # blocks SCHED_FIFO/SCHED_RR (breaks audio/VR daemons)
  #   RestrictSUIDSGID = true;       # blocks creating SUID/SGID files
  #   RestrictAddressFamilies = [ "none" ]; # socket allowlist, e.g. [ "AF_UNIX" "AF_INET" "AF_INET6" ]
  #   SystemCallArchitectures = "native";   # blocks 32-bit/x32 syscall ABIs
  #   SystemCallFilter = [ "@system-service" "~@privileged" "~@resources" ];
  #   SystemCallErrorNumber = "EPERM";
  # };
  # ---------------------------------------------------------------------------

  safeSyscalls = [ "@system-service" "~@mount" "~@module" "~@raw-io" "~@reboot" "~@swap" "~@clock" "~@debug" "~@obsolete" "~@cpu-emulation" ];
  hwSyscalls = [ "@system-service" "~@mount" "~@module" "~@reboot" "~@swap" "~@clock" "~@obsolete" "~@cpu-emulation" ];
  mountSyscalls = [ "@system-service" "@mount" "~@module" "~@reboot" "~@swap" "~@clock" "~@debug" "~@obsolete" "~@cpu-emulation" ];
  netAF = [ "AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK" ];

  base = {
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectClock = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
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
    ProtectHome = true;
    PrivateDevices = true;
    DevicePolicy = "closed";
    ProtectKernelTunables = true;
    ProtectProc = "invisible";
    ProcSubset = "pid";
    PrivateIPC = true;
    MemoryDenyWriteExecute = true;
    UMask = "0077";
    SystemCallFilter = [
      "@system-service"
      "~@privileged"
      "~@resources"
    ];
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

  libvirtAux = base // {
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateDevices = true;
    DevicePolicy = "closed";
    ProtectKernelTunables = true;
    ProtectProc = "invisible";
    PrivateNetwork = true;
    IPAddressDeny = "any";
    PrivateIPC = true;
    MemoryDenyWriteExecute = true;
    CapabilityBoundingSet = [
      "CAP_DAC_OVERRIDE"
      "CAP_DAC_READ_SEARCH"
      "CAP_CHOWN"
    ];
    RestrictAddressFamilies = [ "AF_UNIX" ];
    # Based on upstream libvirt virtlogd lockdown (allows @resources for libnuma constructor)
    SystemCallFilter = [
      "@system-service"
      "~@clock"
      "~@cpu-emulation"
      "~@debug"
      "~@module"
      "~@mount"
      "~@obsolete"
      "~@privileged"
      "~@raw-io"
      "~@reboot"
      "~@swap"
    ];
    UMask = "0077";
  };

  hasZfs = config.boot.supportedFilesystems.zfs or false;
in
{
  options.systemd-hardening.enable = lib.mkEnableOption "per-service NixOS systemd security hardening";

  config = lib.mkIf cfg.enable {
    systemd.services = lib.mkMerge [
      # Core System Services
      {
        nscd.serviceConfig = mkDefaults (
          tight
          // {
            CapabilityBoundingSet = "";
            RestrictAddressFamilies = netAF;
            UMask = "0022";
          }
        );
        dbus-broker.serviceConfig = mkDefaults (
          base
          // {
            ProtectHome = true;
            ProtectKernelTunables = true;
            PrivateIPC = true;
            MemoryDenyWriteExecute = true;
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_NETLINK"
            ];
            SystemCallFilter = safeSyscalls;
          }
        );
        # nix-daemon spawns sandboxed builds (needs namespaces/chown/mounts)
        nix-daemon.serviceConfig = mkDefaults (light // { RestrictRealtime = true; });
        # Fan / NV-Blindfold / Ryzen TDP: needs /sys, /dev (hwmon/PCI/SMU), /run/hwcontrol.sock, /proc/cpuinfo
        hardware-control-daemon.serviceConfig = mkDefaults (
          base
          // {
            ProtectSystem = "strict";
            ProtectHome = true;
            ProtectProc = "invisible";
            PrivateNetwork = true;
            IPAddressDeny = "any";
            PrivateIPC = true;
            MemoryDenyWriteExecute = true;
            ReadWritePaths = [
              "/sys"
              "/dev"
              "/run"
            ];
            CapabilityBoundingSet = [
              "CAP_SYS_RAWIO"
              "CAP_SYS_ADMIN"
              "CAP_DAC_OVERRIDE"
              "CAP_FOWNER"
            ];
            RestrictAddressFamilies = [ "AF_UNIX" ];
            SystemCallFilter = hwSyscalls;
            UMask = "0077";
          }
        );
        # Writes kprobes to /sys/kernel/tracing
        log-module-autoloads.serviceConfig = mkDefaults (
          base
          // {
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateDevices = true;
            DevicePolicy = "closed";
            PrivateNetwork = true;
            IPAddressDeny = "any";
            PrivateIPC = true;
            MemoryDenyWriteExecute = true;
            ReadWritePaths = [ "/sys/kernel/tracing" ];
            CapabilityBoundingSet = [
              "CAP_SYS_ADMIN"
              "CAP_PERFMON"
              "CAP_DAC_OVERRIDE"
            ];
            RestrictAddressFamilies = [ "AF_UNIX" ];
            SystemCallFilter = safeSyscalls;
            UMask = "0077";
          }
        );

        # Vconsole reload helper & password agents
        reload-systemd-vconsole-setup.serviceConfig = mkDefaults (
          tight
          // {
            CapabilityBoundingSet = "";
            PrivateNetwork = true;
            IPAddressDeny = "any";
            RestrictAddressFamilies = [ "AF_UNIX" ];
          }
        );
        systemd-ask-password-console.serviceConfig = mkDefaults (
          base
          // {
            ProtectSystem = "strict";
            ProtectHome = true;
            ProtectKernelTunables = true;
            PrivateNetwork = true;
            IPAddressDeny = "any";
            PrivateIPC = true;
            MemoryDenyWriteExecute = true;
            RestrictAddressFamilies = [ "AF_UNIX" ];
            SystemCallFilter = safeSyscalls;
            UMask = "0077";
          }
        );
        systemd-ask-password-plymouth.serviceConfig = mkDefaults (
          base
          // {
            ProtectSystem = "strict";
            ProtectHome = true;
            ProtectKernelTunables = true;
            PrivateNetwork = true;
            IPAddressDeny = "any";
            PrivateIPC = true;
            MemoryDenyWriteExecute = true;
            RestrictAddressFamilies = [ "AF_UNIX" ];
            SystemCallFilter = safeSyscalls;
            UMask = "0077";
          }
        );
        systemd-ask-password-wall.serviceConfig = mkDefaults (
          tight
          // {
            PrivateNetwork = true;
            IPAddressDeny = "any";
            RestrictAddressFamilies = [ "AF_UNIX" ];
          }
        );

        # User-bridged hardware shims (sunshine@, opentabletdriver@)
        "sunshine@".serviceConfig = mkDefaults (
          base
          // {
            ProtectSystem = "strict";
            ProtectHome = "read-only";
            ProtectKernelTunables = true;
            ProtectProc = "invisible";
            RestrictRealtime = false;
            ReadWritePaths = [
              "-/home/%i/.config/sunshine"
              "-/home/%i/.cache"
              "/run/user/%U"
            ];
            RestrictAddressFamilies = netAF;
            SystemCallFilter = safeSyscalls;
            UMask = "0077";
          }
        );
        "opentabletdriver@".serviceConfig = mkDefaults (
          base
          // {
            ProtectSystem = "strict";
            ProtectHome = "read-only";
            ProtectKernelTunables = true;
            ProtectProc = "invisible";
            PrivateNetwork = true;
            IPAddressDeny = "any";
            ReadWritePaths = [
              "-/home/%i/.config/OpenTabletDriver"
              "-/home/%i/.local/share/OpenTabletDriver"
              "/run/user/%U"
            ];
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_NETLINK"
            ];
            SystemCallFilter = safeSyscalls;
            UMask = "0077";
          }
        );
      }

      # Networking, DNS & VPN
      (lib.mkIf config.networking.networkmanager.enable {
        NetworkManager.serviceConfig = mkDefaults {
          LockPersonality = true;
          ProtectHostname = true;
          ProtectKernelModules = true;
          KeyringMode = "private";
          RestrictAddressFamilies = netAF ++ [ "AF_PACKET" ];
          SystemCallArchitectures = "native";
          SystemCallErrorNumber = "EPERM";
          # Strict allowlist matching systemd-networkd + NM's libbpf/setns/chroot usage
          SystemCallFilter = [
            "@system-service"
            "bpf"
            "setns"
            "chroot"
            "~@clock"
            "~@cpu-emulation"
            "~@debug"
            "~@module"
            "~@mount"
            "~@obsolete"
            "~@raw-io"
            "~@reboot"
            "~@swap"
          ];
          UMask = "0022";
        };
        NetworkManager-dispatcher.serviceConfig = mkDefaults (
          base
          // {
            ProtectSystem = "full";
            ProtectHome = true;
            PrivateDevices = true;
            DevicePolicy = "closed";
            PrivateIPC = true;
            RestrictAddressFamilies = netAF;
            SystemCallFilter = safeSyscalls;
          }
        );
      })

      (lib.mkIf config.networking.wireless.iwd.enable {
        iwd.serviceConfig = mkDefaults (
          base
          // {
            ProtectKernelTunables = true;
            ProtectProc = "invisible";
            ProcSubset = "pid";
            PrivateIPC = true;
            MemoryDenyWriteExecute = true;
            RestrictAddressFamilies = netAF ++ [
              "AF_PACKET"
              "AF_ALG"
            ];
            SystemCallFilter = [
              "@system-service"
              "~@privileged"
              "~@resources"
            ];
            UMask = "0077";
          }
        );
      })

      (lib.mkIf config.services.dnsmasq.enable {
        dnsmasq.serviceConfig = mkDefaults (
          tight
          // {
            CapabilityBoundingSet = [
              "CAP_NET_BIND_SERVICE"
              "CAP_NET_ADMIN"
              "CAP_NET_RAW"
              "CAP_SETUID"
              "CAP_SETGID"
              "CAP_DAC_OVERRIDE"
            ];
            RestrictAddressFamilies = netAF;
            SystemCallFilter = safeSyscalls;
          }
        );
      })

      (lib.mkIf config.services.stubby.enable {
        stubby.serviceConfig = mkDefaults (
          tight
          // {
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
              "AF_INET6"
            ];
          }
        );
      })

      (lib.mkIf config.sing-box.enable {
        sing-box.serviceConfig = mkDefaults (
          tight
          // {
            CapabilityBoundingSet = "";
            RestrictAddressFamilies = netAF;
          }
        );
        sing-box-core.serviceConfig = mkDefaults {
          KeyringMode = "private";
          PrivateIPC = true;
          ProtectHostname = true;
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = safeSyscalls;
          UMask = "0077";
        };
        zapret.serviceConfig = mkDefaults {
          KeyringMode = "private";
          PrivateIPC = true;
          ProtectHostname = true;
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = [
            "@system-service"
            "~@privileged"
            "~@resources"
          ];
          UMask = "0077";
        };
      })

      (lib.mkIf (config.sing-box.enable && config.sing-box.fptn.enable) {
        fptn.serviceConfig = mkDefaults {
          KeyringMode = "private";
          PrivateIPC = true;
          ProtectHostname = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          SystemCallArchitectures = "native";
          UMask = "0077";
        };
      })

      (lib.mkIf config.services.avahi.enable {
        avahi-daemon.serviceConfig = mkDefaults {
          KeyringMode = "private";
          PrivateIPC = true;
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          SystemCallArchitectures = "native";
          UMask = "0077";
        };
      })

      (lib.mkIf config.services.chrony.enable {
        chronyd.serviceConfig = mkDefaults {
          KeyringMode = "private";
          PrivateIPC = true;
          ProtectHostname = true;
          RestrictNamespaces = true;
          RestrictSUIDSGID = true;
          SystemCallArchitectures = "native";
          UMask = "0077";
        };
      })

      # SSH, Printing, Desktop & Security Daemons
      (lib.mkIf config.services.openssh.enable {
        sshd.serviceConfig = mkDefaults (
          light
          // {
            ProtectKernelTunables = true;
            ProtectControlGroups = true;
            PrivateTmp = true;
            RestrictNamespaces = true;
            RestrictRealtime = true;
          }
        );
      })

      (lib.mkIf config.services.printing.enable {
        cups.serviceConfig = mkDefaults (
          base
          // {
            ProtectSystem = "full";
            ProtectHome = true;
            ProtectKernelTunables = true;
            PrivateIPC = true;
            MemoryDenyWriteExecute = true;
            RestrictAddressFamilies = netAF;
            SystemCallFilter = safeSyscalls;
          }
        );
        cups-browsed.serviceConfig = mkDefaults (
          tight
          // {
            CapabilityBoundingSet = "";
            ReadWritePaths = [ "/var/cache/cups" ];
            RestrictAddressFamilies = netAF;
            UMask = "0022";
          }
        );
      })

      (lib.mkIf config.services.accounts-daemon.enable {
        accounts-daemon.serviceConfig = (mkDefaults {
          NoNewPrivileges = true;
          ProtectClock = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectProc = "invisible";
          ProcSubset = "pid";
          PrivateIPC = true;
          IPAddressDeny = "any";
          RestrictSUIDSGID = true;
          KeyringMode = "private";
          SystemCallErrorNumber = "EPERM";
          UMask = "0077";
        }) // {
          # Replace upstream ~@mount denylist with strict allowlist
          SystemCallFilter = lib.mkForce [
            ""
            "@system-service"
            "~@mount"
            "~@privileged"
            "~@resources"
          ];
        };
      })

      (lib.mkIf config.services.usbguard.enable {
        # libqb IPC uses abstract @usbguard socket + /dev/shm/qb-* (needs shared IPC/netns)
        usbguard.serviceConfig = mkDefaults {
          KeyringMode = "private";
          ProtectClock = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelTunables = true;
          ProtectProc = "invisible";
          ProcSubset = "pid";
          RestrictSUIDSGID = true;
        };
        usbguard-dbus.serviceConfig = mkDefaults (
          tight
          // {
            CapabilityBoundingSet = "";
            PrivateIPC = false;
            IPAddressDeny = "any";
            ReadWritePaths = [ "/dev/shm" ];
            RestrictAddressFamilies = [ "AF_UNIX" ];
          }
        );
      })

      (lib.mkIf config.services.acpid.enable {
        acpid.serviceConfig = mkDefaults (
          tight
          // {
            PrivateDevices = false;
            DevicePolicy = "closed";
            DeviceAllow = [ "char-input r" ];
            PrivateNetwork = false;
            CapabilityBoundingSet = "";
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_NETLINK"
            ];
          }
        );
      })

      (lib.mkIf config.hardware.bluetooth.enable {
        bluetooth.serviceConfig = mkDefaults {
          KeyringMode = "private";
          PrivateIPC = true;
          ProtectClock = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectProc = "invisible";
          ProcSubset = "pid";
          RestrictNamespaces = true;
          RestrictSUIDSGID = true;
          SystemCallArchitectures = "native";
          UMask = "0077";
        };
      })

      (lib.mkIf config.services.upower.enable {
        upower.serviceConfig = mkDefaults {
          KeyringMode = "private";
          PrivateIPC = true;
          ProtectClock = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectProc = "invisible";
          ProcSubset = "pid";
          RestrictSUIDSGID = true;
          UMask = "0077";
        };
      })

      (lib.mkIf config.services.fwupd.enable {
        fwupd.serviceConfig = mkDefaults {
          PrivateIPC = true;
          ProcSubset = "pid";
          UMask = "0077";
        };
      })

      (lib.mkIf config.services.tlp.pd.enable {
        tlp-pd.serviceConfig = mkDefaults (
          base
          // {
            ProtectProc = "invisible";
            ProcSubset = "pid";
            PrivateIPC = true;
            PrivateNetwork = true;
            IPAddressDeny = "any";
            PrivateDevices = true;
            DevicePolicy = "closed";
            RestrictAddressFamilies = [ "AF_UNIX" ];
            SystemCallFilter = safeSyscalls;
            UMask = "0077";
          }
        );
      })

      # Hardware, GPU & Storage Daemons
      (lib.mkIf config.services.lact.enable {
        lactd.serviceConfig = mkDefaults (
          base
          // {
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateNetwork = true;
            IPAddressDeny = "any";
            PrivateIPC = true;
            MemoryDenyWriteExecute = true;
            ReadWritePaths = [
              "/etc/lact"
              "/run"
              "/sys"
            ];
            CapabilityBoundingSet = [
              "CAP_SYS_ADMIN"
              "CAP_DAC_OVERRIDE"
              "CAP_CHOWN"
            ];
            RestrictAddressFamilies = [ "AF_UNIX" ];
            SystemCallFilter = hwSyscalls;
            UMask = "0027";
          }
        );
      })

      (lib.mkIf (config.graphics.nvidia.enable or false) {
        nvidia-powerd.serviceConfig = mkDefaults (
          base
          // {
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateNetwork = true;
            IPAddressDeny = "any";
            PrivateIPC = true;
            MemoryDenyWriteExecute = true;
            ReadWritePaths = [
              "/sys"
              "/run"
            ];
            CapabilityBoundingSet = [
              "CAP_SYS_ADMIN"
              "CAP_SYS_RAWIO"
              "CAP_DAC_OVERRIDE"
            ];
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_NETLINK"
            ];
            SystemCallFilter = hwSyscalls;
            UMask = "0077";
          }
        );
      })

      (lib.mkIf config.services.udisks2.enable {
        udisks2.serviceConfig = mkDefaults (
          base
          // {
            ProtectHome = "read-only";
            PrivateNetwork = true;
            IPAddressDeny = "any";
            PrivateIPC = true;
            MemoryDenyWriteExecute = true;
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_NETLINK"
            ];
            SystemCallFilter = mountSyscalls;
          }
        );
      })

      (lib.mkIf hasZfs {
        zfs-zed.serviceConfig = mkDefaults (
          base
          // {
            ProtectSystem = "full";
            ProtectHome = true;
            PrivateIPC = true;
            MemoryDenyWriteExecute = true;
            RestrictAddressFamilies = netAF;
            SystemCallFilter = mountSyscalls;
          }
        );
        zpool-trim.serviceConfig = mkDefaults (
          base
          // {
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateNetwork = true;
            IPAddressDeny = "any";
            PrivateIPC = true;
            MemoryDenyWriteExecute = true;
            CapabilityBoundingSet = [ "CAP_SYS_ADMIN" ];
            RestrictAddressFamilies = [ "AF_UNIX" ];
            SystemCallFilter = safeSyscalls;
          }
        );
      })

      # Virtualization & Containers
      (lib.mkIf config.virtualisation.podman.enable {
        podman.serviceConfig = mkDefaults light;
      })

      (lib.mkIf config.virtualisation.libvirtd.enable {
        libvirtd.serviceConfig = mkDefaults light;
        libvirt-guests.serviceConfig = mkDefaults (light // { ProtectHome = true; });
        virtlogd.serviceConfig = mkDefaults (
          libvirtAux
          // {
            ReadWritePaths = [
              "/var/log/libvirt"
              "/run/libvirt"
            ];
          }
        );
        virtlockd.serviceConfig = mkDefaults (
          libvirtAux
          // {
            ReadWritePaths = [
              "/run/libvirt"
              "/var/lib/libvirt"
            ];
          }
        );
        virtsecretd.serviceConfig = mkDefaults (
          libvirtAux
          // {
            ReadWritePaths = [
              "/etc/libvirt/secrets"
              "/run/libvirt"
            ];
          }
        );
        virtqemud.serviceConfig = mkDefaults light;
        virtlxcd.serviceConfig = mkDefaults light;
        virtvboxd.serviceConfig = mkDefaults light;
        virtxend.serviceConfig = mkDefaults light;
      })

      # Custom Web / DDNS
      (lib.mkIf (config.my-services.nginx.enable && config.my-services.cloudflare-ddns.enable) {
        cloudflare-ddns.serviceConfig = mkDefaults (
          tight
          // {
            DynamicUser = true;
            CapabilityBoundingSet = "";
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
            ];
          }
        );
      })
    ];
  };
}
