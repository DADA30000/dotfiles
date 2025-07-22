{
  pkgs,
  inputs,
  user-hash,
  user,
  min-flag ? false, # Needed for minimal ISO version
  avg-flag ? false, # Needed for 8G ISO version
  lib,
  ...
}:
let
  bundle = pkgs.fetchurl {
    url = "https://github.com/DADA30000/dotfiles/releases/download/vmware/VMware-Workstation-Full-17.6.3-24583834.x86_64.bundle";
    hash = "sha256-eVdZF3KN7UxtC4n0q2qBvpp3PADuto0dEqwNsSVHjuA=";
  };
  vmware-package = pkgs.vmware-workstation.overrideAttrs {
    src = bundle;
  };
  hash = builtins.hashFile "sha256" "${inputs.nixpkgs}/nixos/modules/virtualisation/vmware-host.nix";
  checker = if hash == "71d417c40302bce51887cf5c790084f0638aff6e61077c6c09b887b6ea505fe9" then true else throw "vmware module has been updated, update hash and src in package, current hash is ${hash}"; #It's needed so that I wouldn't miss an vmware update
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/system
  ];

  systemd.services.lactd = {

    enable = true;

    wantedBy = [ "multi-user.target" ];

    serviceConfig = {

      ExecStart = "${pkgs.lact}/bin/lact daemon";

      #ExecStartPre = "${pkgs.coreutils-full}/bin/sleep 10";

      Restart = "always";

      Nice = -10;

    };

  };

  services.preload.enable = true;

  virtualisation.podman = if !(avg-flag || min-flag) then {
    enable = true;
    dockerCompat = true;
  } else {};


  programs.git.enable = true;

  programs.git.lfs.enable = true;

  programs.ydotool.enable = if !min-flag then true else false;

  # Disable annoying firewall
  networking.firewall.enable = false;

  # Enable singbox
  singbox.enable = true;

  # Enable AmneziaVPN client
  programs.amnezia-vpn.enable = false;

  # Run non-nix apps
  programs.nix-ld.enable = true;

  #boot.crashDump.enable = true;

  # Enable plymouth (boot animation)
  plymouth.enable = true;

  # Enable RAM compression
  zramSwap.enable = true;

  # Enable stuff in /bin and /usr/bin
  services.envfs.enable = false;

  # Enable IOMMU
  boot.kernelParams = [
    "iommu=pt"
    "quiet"
    "plymouth.use-simpledrm"
  ];

  #boot.blacklistedKernelModules = [ "serial8250" "8250" ];

  #systemd.suppressedSystemUnits = [
  #  "dev-ttyS0.device"
  #  "dev-ttyS1.device"
  #  "dev-ttyS2.device"
  #  "dev-ttyS3.device"
  #];

  #boot.initrd.systemd.suppressedUnits = [
  #  "dev-ttyS0.device"
  #  "dev-ttyS1.device"
  #  "dev-ttyS2.device"
  #  "dev-ttyS3.device"
  #];

  # Enable some important system zsh stuff
  programs.zsh.enable = true;

  # Enable portals
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  xdg.portal.config.common.default = "*";

  # Enable OpenTabletDriver
  hardware.opentabletdriver.enable = true;

  # Enable PulseAudio
  services.pulseaudio.enable = false;

  # Places /tmp in RAM
  boot.tmp.useTmpfs = true;

  services.ollama = if !(avg-flag || min-flag) then {
    enable = true;
    acceleration = "rocm";
    rocmOverrideGfx = "10.3.0";
  } else {};

  # Use mainline (or latest stable) kernel instead of LTS kernel
  #boot.kernelPackages = pkgs.linuxPackages_testing;
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_zen;
  #chaotic.scx.enable = true;

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
  ];

  # Enable systemd coredumps
  systemd.coredump.enable = false;

  # Enable generation of NixOS documentation for modules (slows down builds)
  documentation.nixos.enable = false;

  # Enable systemd-networkd for internet
  #systemd.network.wait-online.enable = false;
  #boot.initrd.systemd.network.enable = true;
  #systemd.network.enable = true;
  #networking.useNetworkd = true;

  # Enable dhcpcd for using internet using ethernet cable
  #networking.dhcpcd.enable = true;

  # Enable NetworkManager
  systemd.services = {
    NetworkManager-wait-online.enable = false;
  };
  networking.networkmanager = {
    enable = true;
    wifi.backend = "iwd";
  };

  # Allow making users through useradd
  users.mutableUsers = true;

  specialisation.vm.configuration = if !(avg-flag || min-flag) then {
    virtualisation.libvirtd.enable = true;

    virtualisation.spiceUSBRedirection.enable = true;

    programs.virt-manager.enable = true;

    # Enable TPM emulation (optional)
    virtualisation.libvirtd.qemu = {
      swtpm.enable = true;
      ovmf.packages = [ pkgs.OVMFFull.fd ];
    };
    virtualisation.vmware.host = if (!checker) then {} else {
      enable = true;
      package = vmware-package;
    };
    boot.kernelPackages = pkgs.linuxPackages;
  } else {};

  services.xserver = {
    enable = true;
    displayManager.lightdm = {
      enable = true;
      greeter.enable = false;
    };
  };

  services.displayManager = {
    sessionData.autologinSession = "hyprland";
    sessionPackages = [ inputs.hyprland.packages.${pkgs.system}.default ];
    defaultSession = "hyprland";
    autoLogin = {
      user = user;
      enable = true;
    };
  };

  # Fix early start of graphical-session.target, see https://github.com/NixOS/nixpkgs/pull/297434#issuecomment-2348783988
  systemd.services.display-manager.environment.XDG_CURRENT_DESKTOP = "X-NIXOS-SYSTEMD-AWARE";
  systemd.user.targets.nixos-fake-graphical-session.enable = false;

  # Autologin
  #services.getty.autologinUser = user;

  # Enable DPI (Deep packet inspection) bypass
  zapret.enable = false;

  # Enable replays
  replays.enable = if !min-flag then true else false;

  # Enable startup sound on PC speaker (also plays after rebuilds)
  startup-sound.enable = false;

  # Enable zerotier
  zerotier.enable = false;

  # Enable mlocate (find files on system quickly) (Deprecated, will be removed soon)
  #mlocate.enable = true;

  # Enable locate (find files on system quickly)
  services.locate.enable = true;

  virtualisation.vmVariant = {

    # Set options for vm that is built using nixos-rebuild build-vm
    systemd.user.services.mpvpaper.enable = false;
    virtualisation = {
      qemu.options = [
        "-display gtk,gl=on"
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

  flatpak = if !(avg-flag || min-flag) then {

    # Enable system flatpak
    enable = true;

    # Packages to install from flatpak
    packages = [
      "io.github.Soundux"
    ];

  } else {};

  fonts = {

    # Enable some default fonts
    enableDefaultPackages = true;

    # Add some fonts
    packages = with pkgs; [
      noto-fonts
      #(nerdfonts.override { fonts = [ "JetBrainsMono" ]; })
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
      "nginx"
      "input"
      "kvm"
      "ydotool"
      "adbusers"
      "video"
      "corectrl"
      "libvirtd"
      "libvirt"
      "uccp"
    ];

  };

  nix.settings = {

    # Disable IFD to speed up evaluation
    allow-import-from-derivation = false;

    # Deduplicates stuff in /nix/store
    auto-optimise-store = true;

    # Enable Hyprland cache
    substituters = [ "https://hyprland.cachix.org" ];
    trusted-public-keys = [ "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" ];

    # Enable flakes
    experimental-features = [
      "nix-command"
      "flakes"
    ];

  };

  obs = if !(avg-flag || min-flag) then {

    # Enable OBS
    enable = true;

    # Enable virtual camera
    virt-cam = false;

  } else {};

  graphics = {

    enable = true;

    nvidia.enable = false;

    amdgpu = {

      enable = true;

      pro = if !(avg-flag || min-flag) then true else false;

    };

  };

  my-services = {

    # Enable automatic Cloudflare DDNS
    cloudflare-ddns.enable = true;

    nginx = {

      # Enable nginx
      enable = true;

      # Enable my goofy website
      website.enable = true;

      # Enable nextcloud
      nextcloud.enable = false;

      # Website domain
      hostName = "sanic.space";

    };

  };

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
        enable = true;

        # Label of swap partition
        label = "swap";

      };

    };

  };

  environment = {

    pathsToLink = [ "/share/zsh" ];

    variables = {
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
      [
        kdePackages.qtstyleplugin-kvantum
        lsd
        kdiskmark
        nixfmt-rfc-style
        gdu
        nixd
        (firefox.override {
          nativeMessagingHosts = [
            (inputs.pipewire-screenaudio.packages.${pkgs.system}.default.overrideAttrs (
              finalAttrs: previousAttrs: { cargoHash = "sha256-H/Uf6Yo8z6tZduXh1zKxiOqFP8hW7Vtqc7p5GM8QDws="; }
            ))
          ];
        })
        wget
        killall
        screen
        unrar
        zip
        mpv
        adwaita-icon-theme
        nvtopPackages.amd
        any-nix-shell
        wl-clipboard
        networkmanager_dmenu
        neovide
        p7zip
        inputs.nix-alien.packages.${system}.nix-alien
        inputs.nix-search.packages.${system}.default
        (aria2.overrideAttrs { patches = [ ../../stuff/max-connection-to-unlimited.patch ]; })
      ]
      ++ (if !min-flag then [
        rust-analyzer
        comma
        remmina
        cargo
        mangohud
        steam
        android-tools
        jdk23
        rustc
        moonlight-qt
        osu-lazer-bin
        pavucontrol
        prismlauncher
        qalculate-gtk
        lact
        inputs.anicli-ru.packages.${system}.default
        distrobox
        bottles
        qbittorrent
        ayugram-desktop
        gdb
        gcc
        zenity
        nodejs
        libreoffice
        yarn
        protonplus
        gamemode
        gimp3-with-plugins
        inputs.zen-browser.packages.${system}.twilight
        gamescope
        ccls
        heroic
        (discord.override {
          withOpenASAR = true;
          withVencord = true;
        })
      ] else [])
      ++ (if !(avg-flag || min-flag) then [] else [])
      ++ (import ../../modules/system/stuff { inherit pkgs user; }).scripts;

  };

  boot.loader = {

    efi.canTouchEfiVariables = true;

    systemd-boot.enable = true;

    systemd-boot.memtest86.enable = true;

    timeout = 0;

  };

  nix.package = pkgs.nixVersions.latest;

  services = {

    printing.enable = true;

    gvfs.enable = true;

    openssh.enable = true;

    pipewire = {
      enable = true;
      #package = pkgs.pipewire.overrideAttrs (finalAttrs: previousAttrs: {
      #  src = pkgs.fetchFromGitLab {
      #    domain = "gitlab.freedesktop.org";
      #    owner = "pipewire";
      #    repo = "pipewire";
      #    rev = "fb4475b5dabf853290d8f682649818649621d973";
      #    sha256 = "sha256-R++9vtrDgTbfeQgauC+wlRBQLaYaIHOanBKXJGqTLg8=";
      #  };
      #  buildInputs = previousAttrs.buildInputs ++ [ pkgs.libebur128 ];
      #});
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

    adb.enable = true;

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
