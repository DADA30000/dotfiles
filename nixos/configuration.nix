{ config, lib, inputs, pkgs, options, user, ... }:
let
  spicePkgs = inputs.spicetify-nix.packages.${pkgs.system}.default;
  package = config.boot.kernelPackages.nvidiaPackages.beta;
  long-script = "${pkgs.beep}/bin/beep -f 130 -l 100 -n -f 262 -l 100 -n -f 330 -l 100 -n -f 392 -l 100 -n -f 523 -l 100 -n -f 660 -l 100 -n -f 784 -l 300 -n -f 660 -l 300 -n -f 146 -l 100 -n -f 262 -l 100 -n -f 311 -l 100 -n -f 415 -l 100 -n -f 523 -l 100 -n -f 622 -l 100 -n -f 831 -l 300 -n -f 622 -l 300 -n -f 155 -l 100 -n -f 294 -l 100 -n -f 349 -l 100 -n -f 466 -l 100 -n -f 588 -l 100 -n -f 699 -l 100 -n -f 933 -l 300 -n -f 933 -l 100 -n -f 933 -l 100 -n -f 933 -l 100 -n -f 1047 -l 400";
  adblock = pkgs.fetchgit {
    url = "https://github.com/rxri/spicetify-extensions";
    rev = "96c03d40518f6527db9b4122cb628d88f36f47d0";
    sha256 = "sha256-JR2fda2IGpIbhHy7zK4A5LLT5yVjowZWTvNWPhjYHxE=";
  };
  hazy = pkgs.fetchgit {
    url = "https://github.com/Astromations/Hazy";
    rev = "0d45831a31b0c72e1d3ab8be501479e196a709d7";
    sha256 = "sha256-0t7/25hRfvyJ8K+nTzgMl8RabTBxtMIjQvDECzYvwg8=";
  };
in
{
  #Some services
  services = {
    getty.autologinUser = user;
    printing.enable = true;
    gvfs.enable = true;
    xserver.videoDrivers = ["nvidia" "amdgpu"];
    flatpak.enable = true;
    openssh.enable = true;
    sunshine = {
      autoStart = false;
      enable = true;
      capSysAdmin = true;
      package = ( pkgs.sunshine.override { cudaSupport = true; } );
    };
    cron = {
      enable = true;
      systemCronJobs = [
        "*/59 * * * *   root  update-cloudflare-dns /cloudflare1.conf"
        "*/59 * * * *   root  update-cloudflare-dns /cloudflare2.conf"
      ];
    };
    locate = {
      enable = true;
      package = pkgs.mlocate;
      interval = "hourly";
      localuser = null;
    };
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = false;
      pulse.enable = true;
      jack.enable = false;
    };
    xserver = {
      xkb.layout = "us,ru";
      xkb.options = "grp:alt_shift_toggle";
      displayManager.startx.enable = true;
      enable = true;
    };
  };
  #Some security
  security = {
    pam.loginLimits = [ { domain = "*"; item = "core"; value = "0"; } ];
    rtkit.enable = true;
    polkit.enable = true;
    wrappers.gsr-kms-server = {
      owner = "root";
      group = "root";
      capabilities = "cap_sys_admin+ep";
      source = "${pkgs.gpu-screen-recorder}/bin/gsr-kms-server";
    };
  };
  #Some programs
  programs = {
    dconf.enable = true;
    xwayland.enable = true;
    virt-manager.enable = true;
    zsh.enable = true;
    nm-applet.enable = true;
    adb.enable = true;
    firefox.nativeMessagingHosts.ff2mpv = true;
    spicetify = {
      enable = true;
      theme = {
        name = "Hazy";
        src = hazy;
        requiredExtensions = [
          {
	    filename = "adblock.js";
	    src = "${adblock}/adblock";
	  }
        ];
        appendName = false;
        injectCss = true;
        replaceColors = true;
        overwriteAssets = true;
        sidebarConfig = true;
      };
    };
  };
  #Some boot settings
  boot = {
    extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];
    initrd.systemd.enable = true;
    kernel.sysctl."kernel.sysrq" = 1;
    kernelPackages = pkgs.linuxPackages_zen; 
    tmp.useTmpfs = true;
    extraModprobeConfig = ''
      options v4l2loopback devices=1 video_nr=1 card_label="OBS Cam" exclusive_caps=1
    '';
    kernelParams = [ 
      "nvidia_drm.fbdev=1"
      "amd_iommu=on" 
      "iommu=pt"
    ];
    kernelModules = [
      "v4l2loopback"
    ];
    loader = {
      efi.canTouchEfiVariables = true;
      grub = {
        enable = true;
        efiSupport = true;
        device = "nodev";
        theme = "/boot/grub/themes/hyperfluent";
      };
    };
  };
  #Some nix settings
  nix.settings = {
    keep-outputs = true;
    keep-derivations = true;
    auto-optimise-store = true;
    substituters = [
      "https://hyprland.cachix.org" 
      "https://nix-gaming.cachix.org" 
      "https://nixpkgs-unfree.cachix.org"
    ];
    trusted-public-keys = [ 
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" 
      "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4=" 
      "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs=" 
    ];
    experimental-features = [ 
      "nix-command" 
      "flakes"
    ];
  };
  #Some systemd stuff
  systemd = {
    coredump.enable = false;
    services = {
      NetworkManager-wait-online.enable = false;
      startup-sound = {
        wantedBy = ["sysinit.target"];
        enable = true;
        preStart = "${pkgs.kmod}/bin/modprobe pcspkr";
        serviceConfig = {
          ExecStart = long-script;
        };
      };
      zerotier = {
        description = "Starts a zerotier-one service";
        path = [pkgs.bash pkgs.zerotierone];
        script = ''
          exec zerotier-one
        '';
        wantedBy = [ "multi-user.target" ];
      };
    };
  };
  #Some hardware stuff
  hardware = {
    opengl = {
      enable = true;
      driSupport = true;
      driSupport32Bit = true;
      extraPackages = with pkgs; [
        nvidia-vaapi-driver
        libvdpau-va-gl
        vaapiVdpau
      ];
    };
    nvidia = {
      modesetting.enable = true;
      powerManagement.enable = true;
      powerManagement.finegrained = false;
      open = false;
      nvidiaSettings = false;
      package = pkgs.nvidia-patch.patch-nvenc (pkgs.nvidia-patch.patch-fbc package);
      #package = package;
    };    
  };
  #Some environment stuff
  environment = {
    variables = {
      QT_STYLE_OVERRIDE = "kvantum";
      GTK_THEME = "Materia-dark";
      XCURSOR_THEME = "Bibata-Modern-Classic";
      MOZ_ENABLE_WAYLAND = "1";
      EDITOR = "nvim";
      VISUAL = "nvim";
      TERMINAL = "kitty";
      XCURSOR_SIZE = "24";
      EGL_PLATFORM = "wayland";
      MOZ_DISABLE_RDD_SANDBOX = "1";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      GBM_BACKEND = "nvidia-drm";
      LIBVA_DRIVER_NAME = "nvidia";
    };
    systemPackages = with pkgs; [
      wget
      git
      neovim
      osu-lazer-bin
      libsForQt5.qtstyleplugin-kvantum
      qt6Packages.qtstyleplugin-kvantum 
      waybar
      stow
      inotify-tools
      fastfetch
      hyprshot
      cinnamon.nemo
      cinnamon.cinnamon-translations
      killall
      wl-clipboard
      pulseaudio
      nwg-look
      gnome.file-roller
      nordzy-icon-theme
      appimage-run
      lutris
      cliphist
      networkmanager_dmenu
      libnotify
      swappy
      bibata-cursors
      steam
      screen
      gamemode
      moonlight-qt
      desktop-file-utils
      inputs.pollymc.packages.${pkgs.system}.pollymc
      inputs.nix-fast-build.packages.${pkgs.system}.default
      inputs.nps.packages.${pkgs.system}.nps
      (nvtopPackages.nvidia.overrideAttrs (oldAttrs: { buildInputs = with lib; [ ncurses udev ]; }))
      (firefox.override { nativeMessagingHosts = [ inputs.pipewire-screenaudio.packages.${pkgs.system}.default ff2mpv ]; })
      wlogout
      xdg-user-dirs
      mpv
      ncmpcpp
      polkit_gnome
      mpd
      neovide
      fragments
      unrar
      pavucontrol
      brightnessctl
      ytfzf
      mlocate
      imv
      cinnamon.nemo-fileroller
      zip
      jdk21
      myxer
      (pkgs.callPackage ./ani-cli-ru.nix { })
      gpu-screen-recorder-gtk
      gpu-screen-recorder
      rclone
      android-tools
      virtiofsd
      virtio-win
      networkmanagerapplet
      wttrbar
      beep
    ] ++ (import ./waybar-scripts.nix pkgs);
  };
  #And here is some other small stuff
  documentation.nixos.enable = false;
   virtualisation.libvirtd.enable = true;
  nixpkgs.overlays = [inputs.nvidia-patch.overlays.default];
  qt.enable = true;
  xdg.mime.defaultApplications = {
    "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
    "application/x-compressed-tar" = "org.gnome.FileRoller.desktop";
    "application/x-bzip2-compressed-tar" = "org.gnome.FileRoller.desktop";
    "application/x-bzip1-compressed-tar" = "org.gnome.FileRoller.desktop";
    "application/x-tzo" = "org.gnome.FileRoller.desktop";
    "application/x-xz"= "org.gnome.FileRoller.desktop";
    "application/x-lzma-compressed-tar" = "org.gnome.FileRoller.desktop";
    "application/zstd" = "org.gnome.FileRoller.desktop";
    "application/x-7z-compressed" = "org.gnome.FileRoller.desktop";
    "application/x-zstd-compressed-tar" = "org.gnome.FileRoller.desktop";
    "application/x-lzma" = "org.gnome.FileRoller.desktop";
    "application/x-lz4" = "org.gnome.FileRoller.desktop";
    "application/x-xz-compressed-tar" = "org.gnome.FileRoller.desktop";
    "application/x-lz4-compressed-tar" = "org.gnome.FileRoller.desktop";
    "application/x-archive" = "org.gnome.FileRoller.desktop";
    "application/x-cpio" = "org.gnome.FileRoller.desktop";
    "application/x-lzop" = "org.gnome.FileRoller.desktop";
    "application/x-bzip1" = "org.gnome.FileRoller.desktop";
    "application/x-tar" = "org.gnome.FileRoller.desktop";
    "application/x-bzip2" = "org.gnome.FileRoller.desktop";
    "application/gzip" = "org.gnome.FileRoller.desktop";
    "application/x-lzip-compressed-tar" = "org.gnome.FileRoller.desktop";
    "application/x-tarz "= "org.gnome.FileRoller.desktop";
    "application/zip" = "org.gnome.FileRoller.desktop";
    "inode/directory" = "nemo.desktop";
  };
  users.defaultUserShell = pkgs.zsh;
  nixpkgs.config.allowUnfree = true;
  imports =
    [
      # ./my-services.nix
      ./hardware-configuration.nix
      inputs.spicetify-nix.nixosModule
      inputs.home-manager.nixosModules.home-manager
    ];
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      (nerdfonts.override { fonts = [ "JetBrainsMono" "0xProto" "Hack" ]; })
    ];
    fontconfig = {
      antialias = true;
      cache32Bit = true;
      hinting.enable = true;
      hinting.autohint = true;
    };
  };
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;
  time.timeZone = "Europe/Moscow";
  i18n.defaultLocale = "ru_RU.UTF-8";
  console = {
    earlySetup = true;
    font = null;
    useXkbConfig = true;
  };
  users.users."${user}" = {
    isNormalUser = true;
    extraGroups = [ "wheel" "libvirtd" "uinput" "mlocate" "nginx" "input" "kvm" "adbusers" "vboxusers" "video" ];
    packages = with pkgs; [
      tree
    ];
  };
    xdg.portal = { enable = true; extraPortals = [ pkgs.xdg-desktop-portal-hyprland ]; }; 
  xdg.portal.config.common.default = "*";
  networking.firewall.enable = false;
  system.stateVersion = "23.11";
}
