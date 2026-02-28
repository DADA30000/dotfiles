{
  pkgs,
  inputs,
  user-hash,
  user,
  min-flag,
  avg-flag,
  lib,
  config,
  ...
}:
let
  collectUniqueInputs =
    inputsMap: seenPaths:
    let
      results = lib.mapAttrsToList (
        name: value:
        if value == null || !(value ? outPath) || (lib.elem value.outPath seenPaths) then
          [ ]
        else
          let
            currentInput = {
              inherit name;
              path = value.outPath;
            };
            children =
              if value ? inputs then collectUniqueInputs value.inputs (seenPaths ++ [ value.outPath ]) else [ ];
          in
          [ currentInput ] ++ children
      ) inputsMap;
    in
    lib.flatten results;
  allInputsRaw = collectUniqueInputs (removeAttrs inputs [ "self" ]) [ ];
  groupedByName = lib.groupBy (x: x.name) allInputsRaw;
  finalInputsList = lib.flatten (
    lib.mapAttrsToList (
      name: group:
      if (lib.length group) == 1 then
        group
      else
        lib.imap0 (idx: item: {
          name = "${item.name}-${toString idx}";
          path = item.path;
        }) group
    ) groupedByName
  );
  inputsFarm = pkgs.linkFarm "flake-inputs" finalInputsList;
in
{

  powerManagement.cpuFreqGovernor = "performance";

  qt.enable = true;

  nixpkgs.config.allowUnfree = true;

  time.timeZone = "Europe/Moscow";

  i18n.defaultLocale = "ru_RU.UTF-8";

  console.keyMap = "ru";

  system.stateVersion = "24.11";

  wivrn.enable = true;

  nix.gc.automatic = false;

  singbox.enable = true;

  plymouth.enable = true;

  hardware.opentabletdriver.enable = true;

  zapret.enable = false;

  replays.enable = if !min-flag then true else false;

  startup-sound.enable = false;

  zerotier.enable = false;

  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };

  cape = {
    enable = false;
    users = [ user ];
  };

  # Enable custom man page generation and nix-option-search
  # Can result in additional 10-20 build time if some default/example in option references local relative path, use defaultText if needed, and use strings in example
  # Darwin and stable cause additional eval time, around 10-15 seconds
  docs = {
    enable = true;
    nos = {
      enable = true;
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

  flatpak =
    if !(avg-flag || min-flag) then
      {

        # Enable system flatpak (currently breaks xdg portals)
        enable = false;

        packages = [
          "io.github.Soundux"
        ];

      }
    else
      { };

  fonts = {

    enableDefaultPackages = true;

    packages = with pkgs; [
      vista-fonts
      corefonts
      noto-fonts
      nerd-fonts.jetbrains-mono
    ];

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
      home = "/home/${user}";
      extraGroups = [
        "wheel"
        "uinput"
        "mlocate"
        "libvirtd"
        "nginx"
        "input"
        "kvm"
        "ydotool"
        "adbusers"
        "video"
      ];
    };
  };

  nix = {

    package = pkgs.nixVersions.latest;

    settings = {

      # eval-cores = 0;

      # Disable IFD to speed up evaluation
      # allow-import-from-derivation = false;

      # Deduplicates stuff in /nix/store
      auto-optimise-store = true;

      # Change cache providers (lower priority number = higher priority)
      substituters = [
        # "https://hyprland.cachix.org"
        "https://cache.nixos.org?priority=1"
      ];
      # trusted-public-keys = [ "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" ];

      # Enable flakes
      experimental-features = [
        "nix-command"
        "ca-derivations"
        "flakes"
      ];
    };
  };

  obs =
    if !(avg-flag || min-flag) then
      {
        enable = true;
        virt-cam = true;
      }
    else
      { };

  graphics = {

    enable = true;

    nvidia.enable = false;

    vulkan_video = true;

    amdgpu = {
      enable = true;
      pro = if !(avg-flag || min-flag) then true else false;
    };

  };

  my-services =
    if !(avg-flag || min-flag) then
      {

        cloudflare-ddns.enable = true;

        nginx = {
          enable = true;
          cape.enable = true;
          website.enable = true;
          nextcloud.enable = false;
          hostName = "sanic.space";
        };

      }
    else
      { };

  disks = {

    # Enable base disks configuration (NOT RECOMMENDED TO DISABLE, DISABLING IT WILL NUKE THE SYSTEM IF THERE IS NO ANOTHER FILESYSTEM CONFIGURATION)
    enable = true;

    impermanence = true;

    compression = true;

    second-disk = {
      enable = true;
      compression = true;
      label = "Games";
      subvol = "games";
      path = "/home/${user}/Games";
    };

    swap = {

      file = {
        enable = false;
        path = "/var/lib/swapfile";
        size = 4 * 1024;
      };

      partition = {
        enable = false;
        label = "swap";
      };

    };

  };

  home-manager = {

    users.${user} = import ./home.nix;

    extraSpecialArgs = {
      inherit avg-flag min-flag;
      kekma = {
        nix = config.docs.man-cache-nix;
        home = config.docs.man-cache-home;
      };
    };

  };

  boot = {

    tmp.useTmpfs = true;

    kernelPackages = lib.mkDefault pkgs.linuxPackages_zen;

    initrd.systemd.enable = true;

    kernelParams = [
      "iommu=pt"
      "quiet"
      "plymouth.use-simpledrm"
    ];

    kernel.sysctl = {
      "net.core.default_qdisc" = "cake";
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
      systemd-boot = {
        enable = true;
        memtest86.enable = true;
      };
    };

  };

  environment = {

    etc = {
      "determinate/config.json".text = builtins.toJSON { garbageCollector.strategy = "disabled"; };
      inputs.source = inputsFarm;
    };

    pathsToLink = [
      "/share/zsh"
      "/share/xdg-desktop-portal"
      "/share/applications"
    ];

    variables = {
      APP2UNIT_SLICES = "a=app-graphical.slice b=background-graphical.slice s=session-graphical.slice";
      QT_QPA_PLATFORMTHEME = "qt5ct";
      GTK_THEME = "Fluent-Dark";
      ENVFS_RESOLVE_ALWAYS = "1";
      MOZ_ENABLE_WAYLAND = "1";
      TERMINAL = "kitty";
      EGL_PLATFORM = "wayland";
      MOZ_DISABLE_RDD_SANDBOX = "1";
      NIXPKGS_ALLOW_UNFREE = "1";
    };

    systemPackages =
      with pkgs;
      with inputs;
      # Keep in every ISO
      [
        gemini-cli
        jq
        wayvr
        bs-manager
        xhost
        dante
        ente-auth
        mtkclient
        sidequest
        libsForQt5.qt5ct
        patchelf
        file
        mpv
        gnome-boxes
        libsForQt5.qtstyleplugin-kvantum
        kdePackages.qtstyleplugin-kvantum
        lsd
        kdiskmark
        nixfmt
        gdu
        nixd
        wget
        zenity
        killall
        screen
        unrar
        zip
        adwaita-icon-theme
        vmpk
        wl-clipboard
        networkmanager_dmenu
        neovide
        _7zz-rar
        quickshell.packages.${system}.default
        nix-alien.packages.${system}.nix-alien
        nix-search.packages.${system}.default
        (nvtopPackages.full.override { nvidia = false; })
        (kdePackages.qt6ct.overrideAttrs (prev: {
          patches = prev.patches or [ ] ++ [ ../../stuff/qt6ct-shenanigans.patch ];
          buildInputs =
            prev.buildInputs or [ ]
            ++ (with kdePackages; [
              kconfig
              kcolorscheme
              kiconthemes
              qqc2-desktop-style
            ]);
        }))
        (aria2.overrideAttrs (prev: {
          patches = prev.patches or [ ] ++ [ ../../stuff/max-connection-to-unlimited.patch ];
        }))
      ]
      # Remove from min ISO
      ++ (
        if !min-flag then
          [
            scanmem
            kdePackages.qtdeclarative
            comma
            remmina
            mangohud
            jdk25
            moonlight-qt
            osu-lazer-bin
            mindustry
            xonotic
            # superTux
            supertuxkart
            pavucontrol
            qalculate-gtk
            distrobox
            qbittorrent
            ayugram-desktop
            gdb
            gcc
            nodejs
            libreoffice
            protonplus
            gimp3-with-plugins
            gamescope
            android-tools
            (prismlauncher.override {
              prismlauncher-unwrapped = prismlauncher-unwrapped.overrideAttrs (prev: {
                patches = prev.patches or [ ] ++ [ ../../stuff/prismlauncher.patch ];
              });
            })
            (bottles.override {
              removeWarningPopup = true;
            })
            (discord-canary.override {
              withOpenASAR = true;
              withVencord = true;
            })
          ]
        else
          [ ]
      )
      # Remove from 8G and min ISO
      ++ (
        if !(avg-flag || min-flag) then
          [
            ungoogled-chromium
            heroic
            gsettings-desktop-schemas
          ]
        else
          [ ]
      );

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

    podman =
      if !(avg-flag || min-flag) then
        {
          enable = true;
          dockerCompat = true;
        }
      else
        { };

  };

  systemd = {

    # Fix early start of graphical-session.target, see https://github.com/NixOS/nixpkgs/pull/297434#issuecomment-2348783988
    user.targets.nixos-fake-graphical-session.enable = false;

    coredump.enable = false;

    services = {

      # Fix early start of graphical-session.target, see https://github.com/NixOS/nixpkgs/pull/297434#issuecomment-2348783988
      display-manager.environment.XDG_CURRENT_DESKTOP = "X-NIXOS-SYSTEMD-AWARE";

      NetworkManager-wait-online.enable = false;

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

    gvfs.enable = true;

    locate.enable = true;

    openssh.enable = true;

    tailscale.enable = true;

    zerotierone.enable = true;

    systembus-notify.enable = true;

    gnome.gnome-keyring.enable = true;

    displayManager = {
      defaultSession = "hyprland-uwsm";
      autoLogin = {
        user = user;
        enable = true;
      };
    };

    scx = {
      enable = true;
      scheduler = "scx_bpfland";
    };

    sunshine = {
      autoStart = true;
      enable = false;
      capSysAdmin = true;
      openFirewall = true;
    };

    earlyoom = {
      enable = true;
      enableNotifications = true;
    };

    xserver = {
      enable = true;
      displayManager.lightdm = {
        enable = true;
        greeter.enable = false;
      };
    };

    udev.extraRules = ''
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

  };

  security = {

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

    firejail.enable = true;

    gamemode.enable = true;

    zsh.enable = true;

    nix-ld.enable = true;

    ydotool.enable = if !min-flag then true else false;

    seahorse.enable = true;

    steam.enable = true;

    dconf.enable = true;

    nh.enable = true;

    uwsm = {
      enable = true;
      package = pkgs.uwsm.overrideAttrs { patches = ../../stuff/uwsm_uuctl.patch; };
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
      "kitty.desktop"
    ];

  };

}
