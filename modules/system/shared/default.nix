{
  options,
  pkgs,
  user-hash,
  user,
  lib,
  config,
  inputs,
  evalAndSubstitute,
  rustHelpersPkg,
  ...
}:
let
  normalUsers = builtins.attrNames (lib.filterAttrs (_: u: u.isNormalUser) config.users.users);

  fastAuth = {
    nodelay = true;
    failDelay = {
      enable = true;
      delay = 500000;
    };
  };

  authServices = [
    "polkit-1"
    "login"
    "sshd"
    "su"
    "passwd"
  ];
in
{
  disabledModules = [ "profiles/base.nix" ];

  systemd-hardening.enable = true;

  replays.enable = true;

  document-portal.enable = true;

  environment.memoryAllocator.provider = options.environment.memoryAllocator.provider.default;

  nixpkgs.config.allowUnfree = true;

  sandboxing.enable = true;

  time.timeZone = "Europe/Moscow";

  i18n.defaultLocale = "ru_RU.UTF-8";

  system.stateVersion = "26.05";

  wivrn.enable = true;

  sing-box.enable = true;

  umu.enable = true;

  # Enable base disks configuration (NOT RECOMMENDED TO DISABLE, DISABLING IT WILL NUKE THE SYSTEM IF THERE IS NO ANOTHER FILESYSTEM CONFIGURATION)
  disks.enable = true;

  plymouth = {
    enable = true;
    simpledrm = true;
  };

  zramSwap = {
    enable = true;
    memoryPercent = 200;
  };

  console = {
    enable = true;
    earlySetup = true;
    keyMap = "ru";
    font = "${pkgs.terminus_font}/share/consolefonts/ter-u28b.psf.gz";
    packages = [ pkgs.terminus_font ];
  };

  hardware = {

    uinput.enable = true;

    xpadneo.enable = true;

    xone.enable = true;

    cpu.amd = {
      updateMicrocode = true;
      ryzen-smu.enable = true;
    };

    bluetooth = {
      enable = true;
      powerOnBoot = false;
      input.General.ClassicBondedOnly = false;
    };

  };

  # Enable custom man page generation
  # Can result in additional 10-20 build time if some default/example in option references local relative path, use defaultText if needed, and use strings in example
  docs.enable = true;

  networking = {

    hostId = "fe15f593";

    firewall.enable = false;

    wireless.iwd.settings.General.AddressRandomization = "network";

    networkmanager = {
      enable = true;
      wifi = {
        backend = "iwd";
        macAddress = "stable-ssid";
      };
    };

  };

  nix-mineral = {
    enable = true;
    filesystems.enable = false;
    settings = {
      etc.harden-gitconfig = false;
      debug = {
        debugfs = true;
        panic-reboot = false;
      };
      network = {
        random-mac = false;
        tcp-sack = true;
        icmp.ignore-all = false;
      };
      kernel = {
        cpu-mitigations = "smt-on";
        slab-debug = false;
        binfmt-misc = true;
        kfence = false;
      };
      system = {
        multilib = true;
        yama = "relaxed";
      };
    };
  };

  users = {

    allowNoPasswordLogin = true;

    defaultUserShell = pkgs.zsh;

    mutableUsers = false;

    users = {
      root.hashedPassword = "!";
      guest = {
        isNormalUser = true;
        hashedPassword = "";
      };
      ${user} = {
        isNormalUser = true;
        hashedPassword = user-hash;
        initialPassword = if user-hash == null then "1234" else null;
        initialHashedPassword = lib.mkForce null;
      };
    };
  };

  nix = {

    daemonCPUSchedPolicy = "idle";
    daemonIOSchedClass = "idle";

    package = pkgs.nixVersions.latest;

    settings = {
      allow-import-from-derivation = false;
      use-xdg-base-directories = true;
      auto-optimise-store = true;
      #max-connect-timeout = 1;
      #download-attempts = 1;
      #initial-connect-timeout = 1;
      allowed-users = normalUsers;
      substituters = [
        "https://cache.nixos.org?priority=1"
      ];
      trusted-substituters = [
        "https://hyprland.cachix.org"
      ];
      trusted-public-keys = [
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      ];
      experimental-features = [
        "nix-command"
        "flakes"
      ];
    };

  };

  obs = {

    enable = true;

    virt-cam = true;

  };

  graphics = {

    enable = true;

    amdgpu.pro = true;

  };

  home-manager = {

    users = {
      ${user} = { };
      guest = { };
    };

    extraSpecialArgs.kekma = {
      nix = if config.docs.enable then config.docs.man-cache-nix else "configuration.nix";
      home = if config.docs.enable then config.docs.man-cache-home else "home-configuration.nix";
      nvidia = config.graphics.nvidia.enable;
    };

  };

  boot = {

    blacklistedKernelModules = [
      "hid-uclogic"
      "wacom"
    ];

    zfs.forceImportRoot = false;

    tmp.useTmpfs = true;

    kernelParams = [
      "audit=0"
      "workqueue.power_efficient=Y"
      "drm.panic_screen=qr_code"
      "zfs.spa_slop_shift=8"
    ];

    initrd = {
      supportedFilesystems.zfs = true;
      systemd.services.ttm-dynamic-limit = {
        description = "Dynamically configure 75% TTM limit in modprobe.d";
        wantedBy = [ "systemd-modules-load.service" ];
        before = [
          "systemd-modules-load.service"
          "systemd-udevd.service"
          "systemd-udev-trigger.service"
        ];
        unitConfig.DefaultDependencies = false;
        serviceConfig.Type = "oneshot";

        path = with pkgs; [
          gawk
          coreutils
        ];

        script = ''
          LIMIT=$(awk '/MemTotal/ {printf "%d\n", ($2 / 4) * 0.75}' /proc/meminfo)
          mkdir -p /run/modprobe.d
          echo "options ttm pages_limit=$LIMIT" > /run/modprobe.d/ttm.conf
        '';
      };
    };

    kernel.sysctl = {
      "vm.swappiness" = 180;
      "vm.watermark_boost_factor" = 0;
      "vm.watermark_scale_factor" = 125;
      "vm.page-cluster" = 0;
      "net.core.default_qdisc" = "cake";
      "net.ipv4.tcp_congestion_control" = "bbr";
      "kernel.panic" = 0;
    };

    binfmt.registrations.exe = {
      magicOrExtension = "MZ";
      interpreter = "${rustHelpersPkg}/bin/run-exe";
      recognitionType = "magic";
    };

    loader = {
      timeout = 0;
      efi.canTouchEfiVariables = true;
      systemd-boot.memtest86.enable = true;
    };

    supportedFilesystems = [
      "ext2"
      "ext3"
      "ext4"
      "btrfs"
      "cifs"
      "f2fs"
      "ntfs"
      "vfat"
      "xfs"
      "zfs"
    ];

  };

  virtualisation = {

    spiceUSBRedirection.enable = true;

    podman = {
      enable = true;
      dockerCompat = true;
    };

    libvirtd = {
      enable = true;
      firewallBackend = "nftables";
      qemu = {
        swtpm.enable = true;
        verbatimConfig = "max_core = 0";
      };
    };

    # Set options for vm that is built using nixos-rebuild build-vm
    vmVariant = {
      virtualisation = {
        qemu.options = [
          "-display sdl,gl=on"
          "-device virtio-vga-gl"
          "-enable-kvm"
          "-audio driver=sdl,model=virtio"
        ];
        cores = 4;
        diskSize = 1024 * 8;
        msize = 16384 * 16;
        memorySize = 1024 * 8;
      };
    };

  };

  systemd = {

    slices.user.sliceConfig = {
      CPUWeight = 500;
      IOWeight = 500;
    };

    tmpfiles.rules = [
      "d /var/lib/AccountsService/users 0755 root root -"
    ]
    ++ (map (
      u:
      "f /var/lib/AccountsService/users/${u} 0644 root root - [User]\\nSession=\\nIcon=${pkgs.nixos-icons}/share/icons/hicolor/512x512/apps/nix-snowflake.png\\nSystemAccount=false\\n"
    ) normalUsers);

    oomd = {
      enable = true;
      enableUserSlices = true;
      enableSystemSlice = true;
      enableRootSlice = true;
      settings.OOM = {
        SwapUsedLimit = "90%";
        DefaultMemoryPressureLimit = "40%";
        DefaultMemoryPressureDurationSec = "2";
      };
    };

    user = {
      targets.xdg-desktop-autostart.enable = false;
      settings.Manager = {
        DefaultTimeoutStopSec = "1s";
        DefaultTasksMax = 4096;
        DefaultCPUAccounting = true;
        DefaultIOAccounting = true;
      };
      slices = {
        session.sliceConfig = {
          CPUWeight = 10000;
          IOWeight = 10000;
        };
        session-graphical.sliceConfig = {
          CPUWeight = 1000;
          IOWeight = 1000;
        };
        app-graphical.sliceConfig = {
          CPUWeight = 500;
          IOWeight = 500;
        };
        app.sliceConfig = {
          CPUWeight = 100;
          IOWeight = 100;
        };
        background-graphical.sliceConfig = {
          CPUWeight = 50;
          IOWeight = 50;
        };
        background.sliceConfig = {
          CPUWeight = 50;
          IOWeight = 50;
        };
      };
      services = {
        dbus-broker.serviceConfig = {
          Type = "notify";
          ExecReload = "${pkgs.systemd}/bin/busctl call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig";
        };
      };
    };

    services = {

      NetworkManager-wait-online.enable = false;

      nix-daemon.serviceConfig = {
        IOSchedulingClass = "idle";
        CPUSchedulingPolicy = "idle";
      };

      greetd = {
        wantedBy = lib.mkForce [ "systemd-user-sessions.service" ];
        after = [ "systemd-user-sessions.service" ];
        serviceConfig.Type = lib.mkForce "simple";
      };

      quest-adb-reverse = {
        description = "Quest 3S ADB Reverse (Root)";
        serviceConfig = {
          Type = "forking";
          Restart = "no";
          Environment = "HOME=/root";
          ExecStartPre = "${pkgs.bash}/bin/bash -c \"${pkgs.psmisc}/bin/killall adb || true\"";
          ExecStart = "${pkgs.android-tools}/bin/adb reverse tcp:9757 tcp:9757";
        };
      };

      hardware-control-daemon = {
        description = "Hardware Control Daemon for Fan, NV-Blindfold, and Ryzen TDP";
        wantedBy = [ "multi-user.target" ];
        after = [ "systemd-udev-settle.service" ];
        path = [
          pkgs.ryzenadj
          pkgs.coreutils
        ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "/run/current-system/sw/bin/hardware-control-daemon";
          Restart = "always";
          RestartSec = "2s";

          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectClock = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          ProtectProc = "invisible";
          PrivateNetwork = true;
          IPAddressDeny = "any";
          PrivateIPC = true;
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          KeyringMode = "private";
          ReadWritePaths = [
            "/sys"
            "/dev"
            "/run"
          ];
          InaccessiblePaths = [
            "-/run/dbus/system_bus_socket"
            "-/run/systemd/private"
          ];
          CapabilityBoundingSet = [
            "CAP_SYS_RAWIO"
            "CAP_SYS_ADMIN"
            "CAP_DAC_OVERRIDE"
            "CAP_FOWNER"
          ];
          RestrictAddressFamilies = [ "AF_UNIX" ];
          SystemCallArchitectures = "native";
          SystemCallErrorNumber = "EPERM";
          SystemCallFilter = [
            "@system-service"
            "~@mount"
            "~@module"
            "~@reboot"
            "~@swap"
            "~@clock"
            "~@obsolete"
            "~@cpu-emulation"
          ];
          UMask = "0077";
        };
      };

      avahi-daemon.serviceConfig = {
        # Allow root pre-drop_root cleanup of stale avahi-owned /run/avahi-daemon/pid;
        # avahi_caps_reduce() immediately drops CAP_DAC_OVERRIDE before drop_root().
        CapabilityBoundingSet = [ "CAP_DAC_OVERRIDE" ];
        # Send SIGTERM only to main avahi-daemon so avahi_chroot_helper stays alive to unlink /run/avahi-daemon/pid on stop.
        KillMode = "mixed";
      };

      "sunshine@" =
        let
          sunshine-system-runner = pkgs.writeShellScript "sunshine-system-runner" (evalAndSubstitute {
            string = builtins.readFile ../../../stuff/system/shared/sunshine-system-runner.sh;
          });
        in
        {
          description = "Sunshine Game Streaming Host for %i";
          after = [ "graphical.target" ];

          serviceConfig = {
            User = "%i";
            Group = "users";
            SupplementaryGroups = [ "uinput" ];

            ExecStart = "${sunshine-system-runner} %i";
            Restart = "on-failure";
            RestartSec = "3s";

            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = false;
            ProtectClock = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectControlGroups = true;
            ProtectProc = "invisible";
            LockPersonality = true;
            RestrictNamespaces = true;
            RestrictSUIDSGID = true;
            KeyringMode = "private";
            ReadOnlyPaths = [ "/home" ];
            ReadWritePaths = [
              "-/home/%i/.config/sunshine"
              "-/home/%i/.cache"
              "/run/user"
            ];
            InaccessiblePaths = [
              "-/root"
              "-/run/systemd/private"
            ];
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
              "AF_INET6"
              "AF_NETLINK"
            ];
            SystemCallArchitectures = "native";
            SystemCallErrorNumber = "EPERM";
            SystemCallFilter = [
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
            UMask = "0077";
          };
        };

      "opentabletdriver@" =
        let
          otd-system-runner = pkgs.writeShellScript "otd-system-runner" ''
            USER_NAME="$1"
            USER_UID="$(${pkgs.coreutils}/bin/id -u "$USER_NAME")"
            export XDG_RUNTIME_DIR="/run/user/$USER_UID"
            exec ${pkgs.opentabletdriver}/bin/otd-daemon
          '';
        in
        {
          description = "OpenTabletDriver Daemon for %i";
          after = [ "graphical.target" ];

          serviceConfig = {
            User = "%i";
            Group = "users";
            SupplementaryGroups = [ "uinput" ];
            DeviceAllow = [ "/dev/uinput rw" ];
            ExecStart = "${otd-system-runner} %i";
            Restart = "on-failure";
            RestartSec = "3s";

            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = false;
            ProtectClock = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectControlGroups = true;
            ProtectProc = "invisible";
            PrivateNetwork = true;
            IPAddressDeny = "any";
            LockPersonality = true;
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            KeyringMode = "private";
            ReadOnlyPaths = [ "/home" ];
            ReadWritePaths = [
              "-/home/%i/.config/OpenTabletDriver"
              "-/home/%i/.local/share/OpenTabletDriver"
              "/run/user"
            ];
            InaccessiblePaths = [
              "-/root"
              "-/run/dbus/system_bus_socket"
              "-/run/systemd/private"
            ];
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_NETLINK"
            ];
            SystemCallArchitectures = "native";
            SystemCallErrorNumber = "EPERM";
            SystemCallFilter = [
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
            UMask = "0077";
          };
        };

    };

  };

  services = {

    udev.packages = [
      (pkgs.runCommand "70-opentabletdriver-sanitized.rules" { } ''
        mkdir -p $out/lib/udev/rules.d
        substitute ${pkgs.opentabletdriver}/lib/udev/rules.d/70-opentabletdriver.rules \
          $out/lib/udev/rules.d/70-opentabletdriver.rules \
          --replace-fail 'KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", TAG+="uaccess", TAG+="udev-acl"' ""
      '')
    ];

    fwupd.enable = true;

    lact.enable = true;

    upower.enable = true;

    accounts-daemon.enable = true;

    gvfs.enable = true;

    systembus-notify.enable = true;

    speechd.enable = false;

    logind.settings.Login = {
      HandlePowerKey = "suspend";
      HoldoffTimeoutSec = "0.25s";
    };

    journald.settings.Journal = {
      SystemMaxUse = "1G";
      RuntimeMaxUse = "1G";
    };

    chrony = {
      enable = true;
      enableNTS = true;
      extraConfig = ''
        minsources 2
        authselectmode require
        cmdport 0
      '';
      servers = [
        "://cloudflare.com"
        "nts.netnod.se"
        "ptbtime1.ptb.de"
        "ntppool1.time.nl"
      ];
    };

    usbguard = {
      enable = true;
      dbus.enable = true;
      presentDevicePolicy = "allow";
      implicitPolicyTarget = "block";
      IPCAllowedUsers = [
        user
      ];
    };

    openssh = {
      enable = true;
      ports = [ 9000 ];
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    greetd =
      let
        tuigreet-patched = pkgs.tuigreet.overrideAttrs (prev: {
          patches = (prev.patches or [ ]) ++ [ ../../../stuff/patches/tuigreet.patch ];
        });
      in
      {
        enable = true;
        settings = {
          initial_session = {
            command = "env UWSM_WAIT_VARNAMES_SETTLETIME=0 uwsm start -g -1 hyprland-uwsm.desktop > /dev/null 2>&1";
            inherit user;
          };
          default_session = {
            command = "${tuigreet-patched}/bin/tuigreet --user-menu --time --cmd \"env UWSM_WAIT_VARNAMES_SETTLETIME=0 uwsm start -g -1 hyprland-uwsm.desktop > /dev/null 2>&1\"";
            user = "greeter";
          };
        };
      };

    udev.extraRules = ''
      SUBSYSTEMS=="usb", ATTRS{idVendor}=="0414", ATTRS{idProduct}=="8104", MODE="0660", TAG+="uaccess"
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="2833", ATTR{idProduct}=="5013", RUN+="${pkgs.systemd}/bin/systemctl restart quest-adb-reverse.service"
    '';

    printing = {
      enable = true;
      drivers = [
        pkgs.cups-filters
        pkgs.cups-browsed
        pkgs.hplipWithPlugin
      ];
    };

    avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };

    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    tlp = {
      enable = true;
      pd.enable = true;
      settings = {
        RADEON_DPM_PERF_LEVEL_ON_AC = "high";
        CPU_ENERGY_PERF_POLICY_ON_AC = "performance";

        CPU_DRIVER_OPMODE_ON_AC = "active";
        CPU_DRIVER_OPMODE_ON_BAT = "active";
        CPU_DRIVER_OPMODE_ON_SAV = "active";

        CPU_SCALING_GOVERNOR_ON_AC = "performance";
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
        CPU_SCALING_GOVERNOR_ON_SAV = "powersave";

        CPU_BOOST_ON_AC = 1;
        CPU_BOOST_ON_BAT = 1;
        CPU_BOOST_ON_SAV = 0;

        PCIE_ASPM_ON_SAV = "powersupersave";
        AMDGPU_ABM_LEVEL_ON_BAT = 0;
        AMDGPU_ABM_LEVEL_ON_SAV = 0;
        SOUND_POWER_SAVE_ON_AC = 0;
        USB_EXCLUDE_AUDIO = 0;
        USB_AUTOSUSPEND = 0;
      };
    };

  };

  security = {

    protectKernelImage = true;

    sudo.enable = false;

    rtkit.enable = true;

    wrappers = {
      fusermount3.enable = false;
      newgrp.enable = false;
      su.enable = false;
      sg.enable = false;
      mount.enable = false;
      umount.enable = false;
      qemu-bridge-helper = {
        setuid = lib.mkForce false;
        capabilities = "cap_net_admin+ep";
      };
    };

    polkit = {
      enable = true;
      adminIdentities = [ "unix-user:${user}" ];
      extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (action.id == "org.freedesktop.systemd1.manage-units") {
            var unit = action.lookup("unit");
            if (unit === "sunshine@" + subject.user + ".service" ||
                unit === "opentabletdriver@" + subject.user + ".service") {
              return polkit.Result.YES;
            }
          }
        });
      '';
    };

    # Disable usual coredumps (I hate them)
    pam = {
      services = lib.genAttrs authServices (_: fastAuth) // {
        systemd-run0.setEnvironment = false;
        greetd = {
          nodelay = true;
          failDelay = {
            enable = true;
            delay = 500000;
          };
          rules.auth.guest-permit = {
            order = config.security.pam.services.greetd.rules.auth.login.order - 10;
            control = "sufficient";
            modulePath = "pam_succeed_if.so";
            args = [
              "user = guest"
              "quiet"
            ];
          };
        };
      };
      loginLimits = [
        {
          domain = "*";
          item = "core";
          value = "0";
        }
      ];
    };

  };

  programs = {

    zsh.enable = true;

    nix-ld.enable = true;

    dconf.enable = true;

    appimage = {
      enable = true;
      binfmt = true;
    };

    uwsm = {
      enable = true;
      package = pkgs.uwsm.overrideAttrs (prev: {
        patches = (prev.patches or [ ]) ++ [ ../../../stuff/patches/uwsm.patch ];
        postInstall = (prev.postInstall or "") + ''
          chmod -R u+w "$out/bin"
          wrapProgram "$out/bin/uuctl" \
            --add-flags "dmenu -i -p"
        '';
      });
    };

  };

}
