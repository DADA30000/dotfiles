{
  pkgs,
  inputs,
  user-hash,
  user,
  lib,
  config,
  mkSandbox,
  ...
}:
{
  imports = [ ./packages.nix ];

  qt.enable = true;

  nixpkgs.config.allowUnfree = true;

  nixpkgs.overlays = [
    (
      final: prev:
      let
        customFetchurl =
          args:
          let
            nixFetch = import <nix/fetchurl.nix>;
            isSet = builtins.typeOf args == "set";
            supported = builtins.functionArgs nixFetch;
            hasUnsupported = isSet && builtins.any (k: !builtins.hasAttr k supported) (builtins.attrNames args);
            hasUrls = isSet && (args ? urls);
            isMirror = u: builtins.isString u && builtins.substring 0 9 u == "mirror://";
            hasMirror = isSet && (args ? url) && isMirror args.url;
            needsFallback = !isSet || hasUnsupported || hasUrls || hasMirror;
          in
          if needsFallback then
            prev.fetchurl args
          else
            (nixFetch args)
            // {
              overrideAttrs = f: (prev.fetchurl args).overrideAttrs f;
              override = f: (prev.fetchurl args).override f;
              overrideDerivation = f: (prev.fetchurl args).overrideDerivation f;
            };
      in
      {
        fetchurl =
          if builtins.typeOf prev.fetchurl == "set" && prev.fetchurl ? __functor then
            prev.fetchurl // { __functor = self: args: customFetchurl args; }
          else
            customFetchurl;
      }
    )
  ];

  sandboxing.enable = true;

  time.timeZone = "Europe/Moscow";

  i18n.defaultLocale = "ru_RU.UTF-8";

  system.stateVersion = "26.05";

  wivrn.enable = true;

  nix.gc.automatic = false;

  sing-box.enable = true;

  plymouth.enable = true;

  replays.enable = true;

  startup-sound.enable = false;

  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };

  cape = {
    enable = false;
    users = [ user ];
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
  docs = {

    enable = true;

    nos = {
      enable = false;
      darwin = false;
      stable = false;
    };

  };

  networking = {

    firewall.enable = false;

    networkmanager = {
      enable = true;
      wifi.backend = "iwd";
      plugins = with pkgs; [
        networkmanager-fortisslvpn
        networkmanager-iodine
        networkmanager-l2tp
        networkmanager-openconnect
        networkmanager-openvpn
        networkmanager-sstp
        networkmanager-strongswan
        networkmanager-vpnc
      ];
    };

  };

  flatpak = {

    # Enable system flatpak (currently breaks xdg portals)
    enable = false;

    packages = [
      "io.github.Soundux"
    ];

  };

  nix-mineral = {
    enable = true;
    preset = "performance";
    filesystems.enable = false;
    settings = {
      debug.debugfs = true;
      network = {
        random-mac = false;
        tcp-sack = true;
      };
      etc = {
        generic-machine-id = false;
        kicksecure-gitconfig = false;
      };
      kernel = {
        amd-iommu-force-isolation = false;
        strict-iommu = false;
        binfmt-misc = true;
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

    packages = with pkgs; [
      vista-fonts
      corefonts
      noto-fonts
      noto-fonts-monochrome-emoji
      liberation_ttf
      nerd-fonts.jetbrains-mono
      nerd-fonts.caskaydia-cove
      jetbrains-mono
      maple-mono.NF-CN
      unscii
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

    mutableUsers = true;

    groups.${user}.gid = config.users.users.${user}.uid;

    users.${user} = {
      isNormalUser = true;
      hashedPassword = user-hash;
      group = user;
      uid = 1000;
      initialPassword = if user-hash == null then "1234" else null;
      initialHashedPassword = lib.mkForce null;
      home = "/home/${user}";
      extraGroups = [
        "wheel"
        "uinput"
        "mlocate"
        "libvirtd"
        "i2c"
        "nginx"
        "input"
        "kvm"
        "ydotool"
        "vboxusers"
        "adbusers"
        "video"
        "gamemode"
        "docker"
        "cvdnetwork"
      ];
    };
  };

  nix = {

    package = pkgs.nixVersions.latest;

    # package = lib.mkForce (
    #   inputs.determinate.inputs.nix.packages.${pkgs.stdenv.hostPlatform.system}.default.appendPatches [
    #     ../../../stuff/detnix.patch
    #   ]
    # );

    settings = {

      # eval-cores = 0;

      # lazy-trees = false;

      # Disable IFD to speed up evaluation
      # allow-import-from-derivation = false;

      # Deduplicates stuff in /nix/store
      auto-optimise-store = true;

      # Change cache providers (lower priority number = higher priority)
      substituters = [
        "https://cache.nixos.org?priority=1"
      ];

      trusted-substituters = [
        "https://hyprland.cachix.org"
        "https://attic.xuyh0120.win/lantian"
      ];

      trusted-public-keys = [
        "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      ];

      # Enable flakes
      experimental-features = [
        "nix-command"
        "ca-derivations"
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

    compression = true;

    second-disk = {
      enable = true;
      compression = true;
      subvol = "games";
      path = "/home/${user}/Games";
    };

    swap = {

      file = {
        enable = false;
        path = "/var/lib/swapfile";
        size = 4 * 1024;
      };

      partition.enable = false;

    };

  };

  home-manager.extraSpecialArgs.kekma = {

    nix = config.docs.man-cache-nix;

    home = config.docs.man-cache-home;

  };

  boot = {

    tmp.useTmpfs = true;

    kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

    kernelParams = lib.mkAfter [
      "iommu=pt"
      "iommu.passthrough=1"
    ];

    initrd.systemd.enable = true;

    kernel.sysctl = {
      "net.core.default_qdisc" = "cake";
      "net.ipv4.tcp_congestion_control" = "bbr";
      "kernel.sysrq" = 1;
    };

    binfmt.registrations.exe = {
      magicOrExtension = "MZ";
      interpreter = "/etc/profiles/per-user/${user}/bin/run-exe";
      recognitionType = "magic";
    };

    loader = {
      timeout = 0;
      efi.canTouchEfiVariables = true;
      systemd-boot.memtest86.enable = true;
    };

  };

  environment = {

    etc = {
      stdenv.source = pkgs.stdenv;
      libxkbcommon.source = pkgs.libxkbcommon;
      "determinate/config.json".text = builtins.toJSON { garbageCollector.strategy = "disabled"; };
    };

    pathsToLink = [
      "/share/zsh"
      "/share/xdg-desktop-portal"
      "/share/applications"
    ];

    variables = {
      #AQ_DRM_DEVICES = "/dev/dri/card2";
      #AQ_NO_MODESET_PROBE = "1";
      #__GLX_VENDOR_LIBRARY_NAME = "mesa";
      #__EGL_VENDOR_LIBRARY_FILENAMES = "/run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json";
      GDK_PIXBUF_MODULE_FILE = "${pkgs.librsvg}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache";
      MANGOHUD_CONFIG = "fps_limit_method=early,fps_limit=0+165+144+120+90+60,no_display,toggle_hud=Delete,toggle_fps_limit=Shift_R+backslash,ram,vram,cpu_temp,gpu_temp,cpu_stats,gpu_stats,frame_timing,fps_metrics=avg+0.001+0.01+0.97";
      ALSOFT_DRIVERS = "pulse";
      APP2UNIT_SLICES = "a=app-graphical.slice b=background-graphical.slice s=session-graphical.slice";
      QT_QPA_PLATFORMTHEME = "qt5ct";
      QT_QPA_TRANSPARENT_BACKGROUND = "1";
      GTK_THEME = "Fluent-Dark";
      ENVFS_RESOLVE_ALWAYS = "1";
      MOZ_ENABLE_WAYLAND = "1";
      TERMINAL = "neovide-term";
      EGL_PLATFORM = "wayland";
      MOZ_DISABLE_RDD_SANDBOX = "1";
      NIXPKGS_ALLOW_UNFREE = "1";
    };

  };

  virtualisation = {

    spiceUSBRedirection.enable = true;

    # Set options for vm that is built using nixos-rebuild build-vm
    vmVariant = {
      systemd.user.services.mpvpaper.enable = false;
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

    libvirtd = {
      enable = true;
      qemu = {
        swtpm.enable = true;
        verbatimConfig = "max_core = 0";
      };
    };

    # docker.enable = true;

    podman = {
      enable = true;
      #  dockerCompat = true;
    };

  };

  systemd = {

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
      targets."xdg-desktop-autostart".enable = false;
      settings.Manager = {
        DefaultTimeoutStopSec = "1s";
        DefaultTasksMax = 4096;
      };
      # targets.nixos-fake-graphical-session.enable = false; # Fix early start of graphical-session.target, see https://github.com/NixOS/nixpkgs/pull/297434#issuecomment-2348783988
      services = {
        cgroup-executioner = {
          description = "Automatically terminate any application scope that hits TasksMax";
          wantedBy = [ "graphical-session.target" ];
          after = [ "graphical-session.target" ];

          serviceConfig = {
            ExecStart = "${pkgs.writeShellScript "cgroup-executioner" ''
              CGROUP_ROOT="/sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service"

              echo "Cgroup Executioner active (Pure Builtins). Polling root: $CGROUP_ROOT"

              while true; do
                  # Use Bash globbing instead of the 'find' binary
                  for event_file in "$CGROUP_ROOT"/*/*.scope/pids.events "$CGROUP_ROOT"/*/*/*.scope/pids.events; do
                      # Ensure the file actually exists (prevents raw glob string literal issues)
                      [[ -f "$event_file" ]] || continue
                      
                      # Read pids.events purely in Bash without 'grep'
                      while IFS= read -r line; do
                          if [[ "$line" == max\ [1-9]* ]]; then
                              
                              # Extract path structures natively without 'dirname' or 'basename'
                              scope_dir="''${event_file%/pids.events}"
                              scope_name="''${scope_dir##*/}"
                              
                              # Read current tasks purely in Bash without 'cat'
                              if [[ -f "$scope_dir/pids.current" ]]; then
                                  IFS= read -r current_tasks < "$scope_dir/pids.current"
                                  
                                  if [[ "$current_tasks" -gt 0 && "$scope_name" == *.scope ]]; then
                                      echo "CRITICAL: $scope_name breached TasksMax! Enforcing full teardown."
                                      ${pkgs.systemd}/bin/systemctl --user stop "$scope_name"
                                  fi
                              fi
                              break
                          fi
                      done < "$event_file"
                  done
                  
                  sleep 0.5
              done
            ''}";
            Restart = "always";
            RestartSec = "2s";
          };
        };
        dbus-broker.serviceConfig = {
          Type = "notify";
          ExecReload = "${pkgs.systemd}/bin/busctl call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig";
        };
      };
    };

    services = {

      NetworkManager-wait-online.enable = false;

      greetd = {
        wantedBy = lib.mkForce [ "systemd-user-sessions.service" ];
        after = [ "systemd-user-sessions.service" ];
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

      systemd-bsod = {
        enable = true;
        wantedBy = [ "sysinit.target" ];
        serviceConfig.ExecStart = "${pkgs.systemd}/lib/systemd/systemd-bsod --continuous";
      };

    };

  };

  services = {

    fwupd.enable = true;

    lact.enable = true;

    logind.settings.Login.HandlePowerKey = "suspend";

    blueman.enable = true;

    gvfs.enable = true;

    locate.enable = true;

    openssh.enable = true;

    tailscale.enable = true;

    zerotierone.enable = true;

    systembus-notify.enable = true;

    gnome.gnome-keyring.enable = true;

    journald.extraConfig = ''
      SystemMaxUse=1G
      RuntimeMaxUse=1G
    '';

    hardware.openrgb = {
      enable = true;
      package = pkgs.openrgb-with-all-plugins;
      motherboard = "amd";
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
    };

    udev.extraRules = ''
      SUBSYSTEMS=="usb", ATTRS{idVendor}=="0414", ATTRS{idProduct}=="8104", MODE="0660", TAG+="uaccess"
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="2833", ATTR{idProduct}=="5013", RUN+="${pkgs.systemd}/bin/systemctl restart quest-adb-reverse.service"
    '';

    printing = {
      enable = true;
      drivers = with pkgs; [
        cups-filters
        cups-browsed
        hplipWithPlugin
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

    polkit.enable = true;

    # Disable usual coredumps (I hate them)
    pam.loginLimits = [
      {
        domain = "*";
        item = "core";
        value = "0";
      }
    ];

  };

  programs = {

    ssh.extraConfig = ''
      ServerAliveInterval 60
      ServerAliveCountMax 3
    '';

    screen.enable = true;

    firejail.enable = true;

    zsh.enable = true;

    nix-ld.enable = true;

    ydotool.enable = true;

    seahorse.enable = true;

    dconf.enable = true;

    gamemode = {
      enable = true;
      enableRenice = true;
    };

    nh = {
      enable = true;
      package = pkgs.nh.override {
        nix-output-monitor = (
          pkgs.nix-output-monitor.overrideAttrs (prev: {
            patches = (prev.patches or [ ]) ++ [ ../../../stuff/patches/nom.patch ];
          })
        );
      };
    };

    steam = {
      enable = true;
      package =
        let
          overriddenSteam = pkgs.steam.override {
            privateTmp = false;
            extraEnv = {
              MANGOHUD = true;
              OBS_VKCAPTURE = true;
              RADV_TEX_ANISO = 16;
            };
            extraLibraries =
              p: with p; [
                atk
              ];
          };

          sandboxed = mkSandbox {
            appId = "com.valvesoftware.Steam";
            network = true;
            audio = true;
            gpu = true;
            wayland = true;
            nvidia_gpu = true;
            use_landlock = false;
            sandbox_tmp = false;
            sandbox_shm = false;
            additional_outside_commands = ''
              rust-bridge -r listen --address 127.0.0.1:[57343,27060] -s "$SANDBOXED_RUNTIME_DIR/steam" &
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
                      [
                        "/home/${user}/Games/steam"
                        (sloth.mkdir "/Games")
                      ]
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
      extraPackages = with pkgs; [
        libgdiplus
        fontconfig
        attr
        libXcursor
        libXinerama
        libXScrnSaver
        libXi
        nss
        nspr
        atk
        at-spi2-atk
        libdrm
        libGL
        libXcomposite
        libXdamage
        libXrandr
        libXext
        libXfixes
        mesa
        libva
        pipewire
      ];
    };

    uwsm = {
      enable = true;
      package = pkgs.uwsm.overrideAttrs (prev: {
        patches = (prev.patches or [ ]) ++ [ ../../../stuff/patches/uwsm_uuctl.patch ];
        postInstall = (prev.postInstall or "") + ''
          chmod -R 777 "$out/bin"
          wrapProgram "$out/bin/uuctl" \
            --add-flags "dmenu -i -p"
        '';
      });
      waylandCompositors = {
        hyprland = {
          prettyName = "Hyprland";
          comment = "Hyprland compositor managed by UWSM";
          binPath = "${inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/Hyprland"; # https://github.com/hyprwm/Hyprland/pull/12484
        };
      };
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

    neovim = {
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      enable = true;
    };

  };

  xdg.terminal-exec = {

    enable = true;

    settings.default = [
      "neovide-term.desktop"
    ];

  };

}
