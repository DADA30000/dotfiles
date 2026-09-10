{
  pkgs,
  user-hash,
  user,
  lib,
  config,
  mkSandbox,
  ...
}:
let
  fastAuth = {
    nodelay = true;
    failDelay = {
      enable = true;
      delay = 500000;
    };
  };

  authServices = [
    "sudo"
    "polkit-1"
    "login"
    "sshd"
    "su"
    "passwd"
    "greetd"
    "hyprlock"
  ];
in
{
  disabledModules = [ "profiles/base.nix" ];

  imports = [ ./packages.nix ];

  qt.enable = true;

  nixpkgs.config.allowUnfree = true;

  sandboxing.enable = true;

  time.timeZone = "Europe/Moscow";

  i18n.defaultLocale = "ru_RU.UTF-8";

  system.stateVersion = "26.05";

  wivrn.enable = true;

  sing-box.enable = true;

  plymouth.enable = true;

  replays.enable = true;

  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };

  console = {
    enable = true;
    earlySetup = true;
    keyMap = "ru";
    font = "${pkgs.terminus_font}/share/consolefonts/ter-u28b.psf.gz";
    packages = [ pkgs.terminus_font ];
  };

  hardware = {

    steam-hardware.enable = true;

    xpadneo.enable = true;

    xone.enable = true;

    opentabletdriver.enable = true;

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

  # Enable custom man page generation and nix-option-search
  # Can result in additional 10-20 build time if some default/example in option references local relative path, use defaultText if needed, and use strings in example
  # Darwin and stable cause additional eval time, around 10-15 seconds
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
      plugins = [
        pkgs.networkmanager-fortisslvpn
        pkgs.networkmanager-iodine
        pkgs.networkmanager-l2tp
        pkgs.networkmanager-openconnect
        pkgs.networkmanager-openvpn
        pkgs.networkmanager-sstp
        pkgs.networkmanager-strongswan
        pkgs.networkmanager-vpnc
      ];
    };

  };

  nix-mineral = {
    enable = true;
    preset = "performance";
    filesystems.enable = false;
    settings = {
      debug.debugfs = true;
      etc.kicksecure-gitconfig = false;
      network = {
        random-mac = false;
        tcp-sack = true;
      };
      kernel = {
        amd-iommu-force-isolation = false;
        strict-iommu = false;
        binfmt-misc = true;
        io-uring = true;
        sysrq = "none";
      };
      system = {
        multilib = true;
        yama = "relaxed";
      };
    };
  };

  fonts = {

    enableDefaultPackages = true;

    fontDir = {
      enable = true;
      decompressFonts = true;
    };

    packages = [
      pkgs.vista-fonts
      pkgs.corefonts
      pkgs.noto-fonts
      pkgs.noto-fonts-monochrome-emoji
      pkgs.liberation_ttf
      pkgs.nerd-fonts.jetbrains-mono
    ];

    fontconfig.defaultFonts = {
      emoji = [
        "JetBrainsMono Nerd Font"
        "Noto Emoji"
        "Noto Color Emoji"
      ];
      serif = [
        "Noto Serif"
        "Liberation Serif"
      ];
      sansSerif = [
        "Noto Sans"
        "Arial"
        "Liberation Sans"
      ];
      monospace = [
        "JetBrainsMono Nerd Font"
        "Liberation Mono"
      ];
    };

  };

  users = {

    defaultUserShell = pkgs.zsh;

    mutableUsers = false;

    users = {
      root.hashedPassword = "!";
      ${user} = {
        isNormalUser = true;
        hashedPassword = user-hash;
        initialPassword = if user-hash == null then "1234" else null;
        initialHashedPassword = lib.mkForce null;
        home = "/home/${user}";
        extraGroups = [
          "wheel"
          "kvm"
          "adbusers"
        ];
      };
    };
  };

  nix = {

    package = pkgs.lixPackageSets.latest.lix;

    daemonCPUSchedPolicy = "batch";

    daemonIOSchedClass = "idle";

    daemonIOSchedPriority = 7;

    settings = {
      allow-import-from-derivation = false;
      use-xdg-base-directories = true;
      auto-optimise-store = true;
      max-connect-timeout = 1;
      download-attempts = 1;
      initial-connect-timeout = 1;
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

    vulkan_video = true;

    amdgpu = {
      enable = true;
      pro = true;
    };

  };

  disks = {

    # Enable base disks configuration (NOT RECOMMENDED TO DISABLE, DISABLING IT WILL NUKE THE SYSTEM IF THERE IS NO ANOTHER FILESYSTEM CONFIGURATION)
    enable = true;

    impermanence = true;

  };

  home-manager.extraSpecialArgs.kekma = {

    nix = config.docs.man-cache-nix;

    home = config.docs.man-cache-home;

    nvidia = config.graphics.nvidia.enable;

  };

  boot = {

    zfs.forceImportRoot = false;

    tmp.useTmpfs = true;

    kernelPackages =
      let
        zfsCompatibleKernelPackages = lib.filterAttrs (
          name: kernelPackages:
          (builtins.match "linux_[0-9]+_[0-9]+" name) != null
          && (builtins.tryEval kernelPackages).success
          && (!kernelPackages.${config.boot.zfs.package.kernelModuleAttribute}.meta.broken)
        ) pkgs.linuxKernel.packages;
      in
      lib.last (
        lib.sort (a: b: (lib.versionOlder a.kernel.version b.kernel.version)) (
          builtins.attrValues zfsCompatibleKernelPackages
        )
      );

    kernelParams = [
      "iommu=pt"
      "iommu.passthrough=1"
      "zfs.spa_slop_shift=8"
    ];

    initrd = {
      supportedFilesystems.zfs = true;
      systemd = {
        enable = true;
        services.systemd-bsod.wantedBy = [ "initrd.target" ];
      };
    };

    kernel.sysctl = {
      "vm.swappiness" = 100;
      "net.core.default_qdisc" = "cake";
      "net.ipv4.tcp_congestion_control" = "bbr";
      "kernel.sysrq" = 1;
    };

    binfmt.registrations.exe = {
      magicOrExtension = "MZ";
      interpreter = "/run/current-system/sw/bin/run-exe";
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

  environment.etc = {
    texinfo.source = pkgs.texinfo;
    bashInteractive.source = pkgs.bashInteractive;
    "determinate/config.json".text = builtins.toJSON { garbageCollector.strategy = "disabled"; };
  };

  virtualisation = {

    spiceUSBRedirection.enable = true;

    podman = {
      enable = true;
      dockerCompat = true;
    };

    libvirtd = {
      enable = true;
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

    additionalUpstreamSystemUnits = [ "systemd-bsod.service" ];

    tmpfiles.rules = [
      "d /var/lib/AccountsService/users 0755 root root -"
      "f /var/lib/AccountsService/users/l0lk3k 0644 root root - [User]\\nSession=\\nIcon=${pkgs.nixos-icons}/share/icons/hicolor/512x512/apps/nix-snowflake.png\\nSystemAccount=false\\n"
    ];

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
        session-graphical.sliceConfig = {
          CPUWeight = 500;
          IOWeight = 500;
        };
        session.sliceConfig = {
          CPUWeight = 500;
          IOWeight = 500;
        };
        app-graphical.sliceConfig = {
          CPUWeight = 300;
          IOWeight = 300;
          MemoryLow = "1500M";
        };
        app.sliceConfig = {
          CPUWeight = 200;
          IOWeight = 200;
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
        "wayland-wm@hyprland" = {
          overrideStrategy = "asDropin";
          serviceConfig = {
            CPUWeight = 1000;
            IOWeight = 1000;
            MemoryLow = "500M";
          };
        };
        cgroup-executioner = {
          description = "Automatically terminate any application scope that hits TasksMax";
          wantedBy = [ "graphical-session.target" ];
          after = [ "graphical-session.target" ];
          serviceConfig = {
            Restart = "always";
            RestartSec = "2s";
            ExecStart = "/run/current-system/sw/bin/cgroup-executioner";
          };
        };
      };
    };

    services = {

      systemd-bsod.wantedBy = [ "sysinit.target" ];

      NetworkManager-wait-online.enable = false;

      greetd = {
        wantedBy = lib.mkForce [ "systemd-user-sessions.service" ];
        after = [ "systemd-user-sessions.service" ];
        serviceConfig.Type = lib.mkForce "simple";
      };

      nix-daemon.serviceConfig = {
        Nice = 19;
        CPUSchedulingPolicy = "batch";
        CPUWeight = 1;
        IOWeight = 1;
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

    };

  };

  services = {

    fwupd.enable = true;

    lact.enable = true;

    upower.enable = true;

    logind.settings.Login.HandlePowerKey = "suspend";

    blueman.enable = true;

    accounts-daemon.enable = true;

    gvfs.enable = true;

    systembus-notify.enable = true;

    gnome.gnome-keyring.enable = true;

    journald.settings.Journal = {
      SystemMaxUse = "1G";
      RuntimeMaxUse = "1G";
    };

    hardware.openrgb = {
      enable = true;
      package = pkgs.openrgb-with-all-plugins;
      motherboard = "amd";
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

    greetd = {
      enable = true;
      settings = {
        initial_session = {
          command = "uwsm start hyprland-uwsm.desktop > /dev/null 2>&1";
          user = user;
        };
        default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd \"uwsm start hyprland-uwsm.desktop > /dev/null 2>&1\"";
          user = "greeter";
        };
      };
    };

    scx = {
      enable = true;
      scheduler = "scx_bpfland";
    };

    sunshine = {
      autoStart = true;
      enable = true;
      capSysAdmin = true;
      openFirewall = true;
      package = (
        pkgs.sunshine.override { cudaSupport = if config.graphics.nvidia.enable then true else false; }
      );
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
      jack.enable = true;
      pulse.enable = true;
    };

    tlp = {
      enable = true;
      pd.enable = true;
      settings = {
        #RADEON_DPM_PERF_LEVEL_ON_AC = "auto";
        #RADEON_DPM_PERF_LEVEL_ON_BAT = "low";
        CPU_DRIVER_OPMODE_ON_AC = "active";
        CPU_SCALING_GOVERNOR_ON_AC = "performance";
        CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
        CPU_BOOST_ON_AC = 1;
        PLATFORM_PROFILE_ON_AC = "performance";
        AMDGPU_ABM_LEVEL_ON_AC = 0;
        PCIE_ASPM_ON_AC = "default";
        RUNTIME_PM_ON_AC = "on";
        WIFI_PWR_ON_AC = "off";
        CPU_DRIVER_OPMODE_ON_BAT = "active";
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
        CPU_ENERGY_PERF_POLICY_ON_BAT = "balance_power";
        CPU_BOOST_ON_BAT = 1;
        PLATFORM_PROFILE_ON_BAT = "low-power";
        AMDGPU_ABM_LEVEL_ON_BAT = 0;
        PCIE_ASPM_ON_BAT = "powersupersave";
        RUNTIME_PM_ON_BAT = "auto";
        WIFI_PWR_ON_BAT = "on";
        CPU_DRIVER_OPMODE_ON_SAV = "active";
        CPU_SCALING_GOVERNOR_ON_SAV = "powersave";
        CPU_ENERGY_PERF_POLICY_ON_SAV = "power";
        CPU_BOOST_ON_SAV = 0;
        CPU_HWP_DYN_BOOST_ON_SAV = 0;
        PLATFORM_PROFILE_ON_SAV = "low-power";
        CPU_MIN_PERF_ON_SAV = 0;
        CPU_MAX_PERF_ON_SAV = 1;
        AMDGPU_ABM_LEVEL_ON_SAV = 0;
        NMI_WATCHDOG = 0;
        SOUND_POWER_SAVE_ON_AC = 0;
        SOUND_POWER_SAVE_ON_BAT = 1;
        SOUND_POWER_SAVE_CONTROLLER = "Y";
        USB_AUTOSUSPEND = 1;
        USB_EXCLUDE_AUDIO = 0; # Allows idle USB audio devices to sleep
      };
    };

  };

  security = {

    wrappers.su.enable = false;

    rtkit.enable = true;

    polkit = {
      enable = true;
      enablePkexecWrapper = true;
    };

    # Disable usual coredumps (I hate them)
    pam = {
      services = lib.genAttrs authServices (_: fastAuth);
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

    ssh.extraConfig = ''
      ServerAliveInterval 60
      ServerAliveCountMax 3
    '';

    zsh.enable = true;

    nix-ld.enable = true;

    ydotool.enable = true;

    seahorse.enable = true;

    dconf.enable = true;

    steam = {
      enable = true;
      package =
        let
          overriddenSteam = pkgs.steam.override {
            privateTmp = false;
          };

          sandboxed = mkSandbox rec {
            appId = "com.valvesoftware.Steam";
            network = true;
            audio = true;
            gpu = true;
            wayland = true;
            use_landlock = false;
            sandbox_tmp = false;
            sandbox_shm = false;
            additional_outside_commands = ''
              rust-bridge -r listen --address 127.0.0.1:[57343,27060] -s "$SANDBOXED_RUNTIME_DIR/steam" &
              mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_DATA_HOME/vulkan"
              SANDBOXED_XDG_DATA_HOME="$HOME/.nixpak/${appId}/home''${XDG_DATA_HOME#"/home/$USER"}"
              ln -sf "$HOME/.nixpak/${appId}/home/.steam" "$HOME/.steam"
              ln -sf "$SANDBOXED_XDG_DATA_HOME/Steam" "$XDG_DATA_HOME/Steam"
              ln -sf "$SANDBOXED_XDG_DATA_HOME/vulkan/implicit_layer.d" "$XDG_DATA_HOME/vulkan/implicit_layer.d"
            '';
            additional_inside_commands = ''
              rust-bridge -r pass --address 127.0.0.1:[57343,27060] -s "$XDG_RUNTIME_DIR/steam" -d
            '';
            additional_args =
              { sloth, ... }:
              {
                dbus.policies = {
                  "com.steampowered.*" = "own";
                  "com.feralinteractive.GameMode" = "talk";
                };
                bubblewrap = {
                  sharePid = true;
                  bind = {
                    dev = [ "/dev" ];
                    ro = [
                      (sloth.mkdir (sloth.concat' (sloth.env "XDG_CONFIG_HOME") "/openvr"))
                      (sloth.mkdir (sloth.concat' (sloth.env "XDG_CONFIG_HOME") "/openxr"))
                      (sloth.mkdir (sloth.concat' (sloth.env "XDG_RUNTIME_DIR") "/wivrn"))
                    ];
                    rw = lib.mkAfter [
                      (sloth.mkdir (
                        sloth.concat [
                          "/mnt/data-nvme/"
                          (sloth.env "USER")
                          "/SteamLibrary"
                        ]
                      ))
                      (sloth.mkdir (
                        sloth.concat [
                          "/mnt/data-hdd/"
                          (sloth.env "USER")
                          "/SteamLibrary"
                        ]
                      ))
                      "/tmp"
                      "/sys/class"
                      "/sys/bus"
                      "/sys/dev"
                      "/sys/devices"
                      "/sys/block"
                      "/run/udev"
                    ];
                  };
                };
              };
            package = overriddenSteam;
          };
        in
        sandboxed
        // {
          override = attrs: (sandboxed.override attrs) // { run = overriddenSteam.run; };
          run = overriddenSteam.run;
        };
      protontricks.enable = true;
      extraPackages = [
        pkgs.libgdiplus
        pkgs.fontconfig
        pkgs.attr
        pkgs.libXcursor
        pkgs.libXinerama
        pkgs.libXScrnSaver
        pkgs.libXi
        pkgs.nss
        pkgs.nspr
        pkgs.atk
        pkgs.at-spi2-atk
        pkgs.libdrm
        pkgs.libGL
        pkgs.libXcomposite
        pkgs.libXdamage
        pkgs.libXrandr
        pkgs.libXext
        pkgs.libXfixes
        pkgs.mesa
        pkgs.libva
        pkgs.pipewire
      ];
    };

    uwsm = {
      enable = true;
      package = pkgs.uwsm.overrideAttrs (prev: {
        patches = (prev.patches or [ ]) ++ [ ../../../stuff/patches/uwsm.patch ];
        postInstall = (prev.postInstall or "") + ''
          chmod -R 777 "$out/bin"
          wrapProgram "$out/bin/uuctl" \
            --add-flags "dmenu -i -p"
        '';
      });
    };

    git = {
      enable = true;
      lfs.enable = true;
      config.safe.directory = "*";
    };

    appimage = {
      enable = true;
      binfmt = true;
    };

  };

  xdg.terminal-exec = {

    enable = true;

    settings.default = [
      "neovide-term.desktop"
    ];

  };

}
