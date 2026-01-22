{
  pkgs,
  inputs,
  user-hash,
  user,
  min-flag, # Needed for minimal ISO version
  avg-flag, # Needed for 8G ISO version
  lib,
  config,
  ...
}:
{

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

  services.tailscale.enable = true;

  services.zerotierone.enable = true;

  services.sunshine = {
    autoStart = true;
    enable = true;
    capSysAdmin = true;
    openFirewall = true;
  };

  services.earlyoom = {
    enable = true;
    enableNotifications = true;
  };

  services.systembus-notify.enable = true;

  programs.seahorse.enable = true;

  services.gnome.gnome-keyring.enable = true;

  programs.alvr = {
    enable = true;
    openFirewall = true;
  };

  # wivrn.enable = true;

  # Enable custom man page generation and nix-option-search
  # Can result in additional 10-20 build time if some default/example in option references local relative path, use defaultText if needed, and use strings in example
  # Darwin and stable cause additional eval time, around 10-15 seconds
  docs = {
    enable = true;
    nos.enable = false;
    nos.darwin = false;
    nos.stable = false;
  };

  nix.gc.automatic = false;

  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  boot.kernel.sysctl."net.core.default_qdisc" = "cake";

  services.scx = {
    enable = true;
    scheduler = "scx_bpfland";
  };

  virtualisation.podman =
    if !(avg-flag || min-flag) then
      {
        enable = true;
        dockerCompat = true;
      }
    else
      { };

  programs.git = {
    enable = true;
    config.safe.directory = "*";
  };

  programs.git.lfs.enable = true;

  programs.ydotool.enable = if !min-flag then true else false;

  # Disable annoying firewall
  networking.firewall.enable = false;

  # Enable singbox
  singbox.enable = true;

  # Run non-nix apps
  programs.nix-ld.enable = true;

  # Enable plymouth (boot animation)
  plymouth.enable = true;

  # Enable RAM compression
  zramSwap.enable = true;

  cape = {
    enable = false;
    users = [ user ];
  };

  virtualisation.libvirtd.qemu.verbatimConfig = ''max_core = 0'';

  # Enable USB redirection (optional)
  virtualisation.spiceUSBRedirection.enable = true;

  # Enable IOMMU
  boot.kernelParams = [
    "iommu=pt"
    "quiet"
    "plymouth.use-simpledrm"
  ];

  # Enable some important system zsh stuff
  programs.zsh.enable = true;

  # Enable portals
  #xdg.portal.enable = true;
  #xdg.portal.extraPortals = [
  #  pkgs.xdg-desktop-portal-gtk
  #];
  #xdg.portal.config.common.default = "*";

  # Enable OpenTabletDriver
  hardware.opentabletdriver.enable = true;

  programs.gamemode.enable = true;

  # Places /tmp in RAM
  boot.tmp.useTmpfs = true;

  # Use mainline (or latest stable) kernel instead of LTS kernel
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_zen;

  # Enable SysRQ
  boot.kernel.sysctl."kernel.sysrq" = 1;

  # Restrict amount of annoying cache
  boot.kernel.sysctl."vm.dirty_bytes" = 50000000;
  boot.kernel.sysctl."vm.dirty_background_bytes" = 50000000;

  # Adds systemd to initrd (speeds up boot process a little, and makes it prettier)
  boot.initrd.systemd.enable = true;

  # Disable usual coredumps (I hate them)
  security.pam.loginLimits = [
    {
      domain = "*";
      item = "core";
      value = "0";
    }
    #{
    #  domain = user;
    #  item = "core";
    #  value = "-1"; # -1 means unlimited
    #}
  ];

  programs.firejail.enable = true;

  # Enable systemd coredumps
  systemd.coredump.enable = false;

  # Enable NetworkManager
  systemd.services = {
    NetworkManager-wait-online.enable = false;
    systemd-bsod = {
      enable = true;
      wantedBy = [ "sysinit.target" ];
      serviceConfig.ExecStart = "${pkgs.systemd}/lib/systemd/systemd-bsod --continuous";
    };
  };
  networking.networkmanager = {
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

  # Allow making users through useradd
  users.mutableUsers = true;

  # Currently specialisations double eval time, and even when empty, still create addiitonal boot entry, not ideal.
  #specialisation.vm.configuration = if !(avg-flag || min-flag) then {
  #  virtualisation.libvirtd.enable = true;

  #  virtualisation.spiceUSBRedirection.enable = true;

  #  programs.virt-manager.enable = true;

  #  # Enable TPM emulation (optional)
  #  virtualisation.libvirtd.qemu = {
  #    swtpm.enable = true;
  #    ovmf.packages = [ pkgs.OVMFFull.fd ];
  #  };
  #  virtualisation.vmware.host = if (!checker) then {} else {
  #    enable = true;
  #    package = vmware-package;
  #  };
  #  boot.kernelPackages = pkgs.linuxPackages;
  #} else {};

  services.xserver = {
    enable = true;
    displayManager.lightdm = {
      enable = true;
      greeter.enable = false;
    };
  };

  # Configure UWSM to launch Hyprland from a display manager like SDDM
  programs.uwsm = {
    enable = true;
    package = pkgs.uwsm.overrideAttrs { patches = ../../stuff/uwsm_uuctl.patch; };
    waylandCompositors = {
      hyprland = {
        prettyName = "Hyprland";
        comment = "Hyprland compositor managed by UWSM";
        binPath = "${inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs { patches = [ ../../stuff/temp_fix_hyprland.patch ]; }}/bin/Hyprland"; # https://github.com/hyprwm/Hyprland/pull/12484
      };
    };
  };

  services.displayManager = {
    sessionData.autologinSession = "hyprland-uwsm";
    defaultSession = "hyprland-uwsm";
    autoLogin = {
      user = user;
      enable = true;
    };
  };

  # Fix early start of graphical-session.target, see https://github.com/NixOS/nixpkgs/pull/297434#issuecomment-2348783988
  systemd.services.display-manager.environment.XDG_CURRENT_DESKTOP = "X-NIXOS-SYSTEMD-AWARE";
  systemd.user.targets.nixos-fake-graphical-session.enable = false;

  # Enable DPI (Deep packet inspection) bypass
  zapret.enable = false;

  # Enable replays
  replays.enable = if !min-flag then true else false;

  # Enable startup sound on PC speaker (also plays after rebuilds)
  startup-sound.enable = false;

  # Enable zerotier
  zerotier.enable = false;

  # Enable locate (find files on system quickly)
  services.locate.enable = true;

  virtualisation.vmVariant = {

    # Set options for vm that is built using nixos-rebuild build-vm
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

  flatpak =
    if !(avg-flag || min-flag) then
      {

        # Enable system flatpak (currently breaks xdg portals)
        enable = false;

        # Packages to install from flatpak
        packages = [
          "io.github.Soundux"
        ];

      }
    else
      { };

  fonts = {

    # Enable some default fonts
    enableDefaultPackages = true;

    # Add some fonts
    packages = with pkgs; [
      vista-fonts
      corefonts
      noto-fonts
      nerd-fonts.jetbrains-mono
    ];

  };

  users.users."${user}" = {

    # Marks user as real, human user
    isNormalUser = true;

    # Sets password for this user using hash generated by mkpasswd
    hashedPassword = user-hash;

    initialPassword = if user-hash == null then "1234" else null;

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
        "https://hyprland.cachix.org"
        "https://cache.nixos.org?priority=1"
      ];
      trusted-public-keys = [ "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" ];

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

        # Enable OBS
        enable = true;

        # Enable virtual camera
        virt-cam = true;

      }
    else
      { };

  graphics = {

    enable = true;

    nvidia.enable = false;

    amdgpu = {

      enable = true;

      pro = if !(avg-flag || min-flag) then true else false;

    };

  };
  

  my-services =
    if !(avg-flag || min-flag) then
      {

        # Enable automatic Cloudflare DDNS
        cloudflare-ddns.enable = true;

        nginx = {

          # Enable nginx
          enable = true;

          cape.enable = true;

          # Enable my goofy website
          website.enable = true;

          # Enable nextcloud
          nextcloud.enable = false;

          # Website domain
          hostName = "sanic.space";

        };

      }
    else
      { };

  disks = {

    # Enable base disks configuration (NOT RECOMMENDED TO DISABLE, DISABLING IT WILL NUKE THE SYSTEM IF THERE IS NO ANOTHER FILESYSTEM CONFIGURATION)
    enable = true;

    impermanence = true;

    # Enable system compression
    compression = true;

    second-disk = {

      # Enable additional disk (must be btrfs)
      enable = true;

      # Enable compression on additional disk
      compression = true;

      # Filesystem label of the partition that is used for mounting
      label = "Games";

      # Which subvolume to mount
      subvol = "games";

      # Path to a place where additional disk will be mounted
      path = "/home/${user}/Games";

    };

    swap = {

      file = {

        # Enable swapfile
        enable = false;

        # Path to swapfile
        path = "/var/lib/swapfile";

        # Size of swapfile in MB
        size = 4 * 1024;

      };

      partition = {

        # Enable swap partition
        enable = false;

        # Label of swap partition
        label = "swap";

      };

    };

  };

  environment = {

    etc = {
      "determinate/config.json".text = builtins.toJSON { garbageCollector.strategy = "disabled"; };
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
        nvtopPackages.amd
        wl-clipboard
        networkmanager_dmenu
        neovide
        _7zz-rar
        quickshell.packages.${system}.default
        nix-alien.packages.${system}.nix-alien
        nix-search.packages.${system}.default
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
      # Remove from 4G ISO
      ++ (
        if !min-flag then
          [
            scanmem
            kdePackages.qtdeclarative
            comma
            remmina
            mangohud
            steam
            jdk25
            moonlight-qt
            osu-lazer-bin
            mindustry
            xonotic
            superTux
            superTuxKart
            pavucontrol
            prismlauncher
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
            ccls
            android-tools
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
      # Remove from 8G ISO
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

  qt.enable = true;

  boot.loader = {

    efi.canTouchEfiVariables = true;

    systemd-boot.enable = true;

    systemd-boot.memtest86.enable = true;

    timeout = 0;

  };

  services = {

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

    gvfs.enable = true;

    openssh.enable = true;

    #udisks2 = {
    #  enable = true;
    #  settings."mount_options.conf".defaults = {
    #    vfat_defaults="sync";
    #    exfat_defaults="sync";
    #    ntfs_defaults="sync";
    #    "ntfs:ntfs_defaults"="sync";
    #    "ntfs:ntfs3_defaults"="sync";
    #  };
    #};

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

  };

  programs = {

    dconf.enable = true;

    nh.enable = true;

    neovim = {

      defaultEditor = true;

      viAlias = true;

      vimAlias = true;

      enable = true;

    };

  };

  xdg.terminal-exec = {

    enable = true;

    settings = {

      default = [
        "kitty.desktop"
      ];

    };

  };

  users.defaultUserShell = pkgs.zsh;

  nixpkgs.config.allowUnfree = true;

  time.timeZone = "Europe/Moscow";

  i18n.defaultLocale = "ru_RU.UTF-8";

  console.keyMap = "ru";

  system.stateVersion = "24.11";

}
