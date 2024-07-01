{ config, lib, inputs, pkgs, options, user, hostname, ... }:
let
  spicePkgs = inputs.spicetify-nix.packages.${pkgs.system}.default;
  package = config.boot.kernelPackages.nvidiaPackages.beta;
  fileroller = "org.gnome.FileRoller.desktop";
  long-script = "${pkgs.beep}/bin/beep -f 130 -l 100 -n -f 262 -l 100 -n -f 330 -l 100 -n -f 392 -l 100 -n -f 523 -l 100 -n -f 660 -l 100 -n -f 784 -l 300 -n -f 660 -l 300 -n -f 146 -l 100 -n -f 262 -l 100 -n -f 311 -l 100 -n -f 415 -l 100 -n -f 523 -l 100 -n -f 622 -l 100 -n -f 831 -l 300 -n -f 622 -l 300 -n -f 155 -l 100 -n -f 294 -l 100 -n -f 349 -l 100 -n -f 466 -l 100 -n -f 588 -l 100 -n -f 699 -l 100 -n -f 933 -l 300 -n -f 933 -l 100 -n -f 933 -l 100 -n -f 933 -l 100 -n -f 1047 -l 400";
  adblock = pkgs.fetchgit {
    url = "https://github.com/rxri/spicetify-extensions";
    rev = "9168bc5d6c3b816ba404d91161fd577b3bf43e4a";
    sha256 = "sha256-kPjmDVyxtXG1puedQKD6HRP6eN/MPdEZ9Zs4Ao4RVtg=";
  };
  hazy = pkgs.fetchgit {
    url = "https://github.com/Astromations/Hazy";
    rev = "25e472cc4563918d794190e72cba6af8397d3a78";
    sha256 = "sha256-zK17CWwYJNSyo5pbYdIDUMKyeqKkFbtghFoK9JBR/C8=";
  };
in
{
  #Some services
  services = {
    getty.autologinUser = user;
    printing.enable = true;
    gvfs.enable = true;
    flatpak.enable = true;
    openssh.enable = true;
    #desktopManager.plasma6.enable = true;
    #displayManager = {
    #  sddm = {
    #    enable = true;
    #    theme = "elegant";
    #    settings = {
    #      Autologin = {
    #	    Session = "plasma.desktop";
    #	    User = user;
    #      };
    #    };
    #    wayland = {
    #      enable = true;
    #      compositor = "kwin";
    #    };
    #  };
    #};
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
      videoDrivers = ["nvidia" "amdgpu"];
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
	timeoutStyle = "hidden";
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
      libvirtd = {
        path = with pkgs; [ libvirt killall ];
        preStart = 
        let
          qemuHook = pkgs.writeScript "qemu-hook" ''
            #!${pkgs.bash}/bin/bash
            GUEST_NAME="$1"
            HOOK_NAME="$2"
            STATE_NAME="$3"
            MISC="''${@:4}"
            
            BASEDIR="$(dirname $0)"
            
            HOOKPATH="$BASEDIR/qemu.d/$GUEST_NAME/$HOOK_NAME/$STATE_NAME"
            set -e # If a script exits with an error, we should as well.
            
            if [ -f "$HOOKPATH" ]; then
            eval \""$HOOKPATH"\" "$@"
            elif [ -d "$HOOKPATH" ]; then
            while read file; do
              eval \""$file"\" "$@"
            done <<< "$(find -L "$HOOKPATH" -maxdepth 1 -type f -executable -print;)"
            fi 
          '';
        in ''
          mkdir -p /var/lib/libvirt/hooks
          mkdir -p /var/lib/libvirt/hooks/qemu.d/win10/prepare/begin
          mkdir -p /var/lib/libvirt/hooks/qemu.d/win10/release/end
          # Copy hook files
          ln -sf ${./stuff/start.sh} /var/lib/libvirt/hooks/qemu.d/win10/prepare/begin/start.sh
          ln -sf ${./stuff/stop.sh} /var/lib/libvirt/hooks/qemu.d/win10/release/end/stop.sh
          ln -sf ${qemuHook} /var/lib/libvirt/hooks/qemu
        '';
      };
    };
    user.services = {
      polkit_gnome = {
        path = [pkgs.bash];
	script = ''
	  exec ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1
	'';
	wantedBy = [ "hyprland-session.target" ];
      };
    };
  };
  #Some hardware stuff
  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
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
      inotify-tools
      fastfetch
      hyprshot
      cinnamon.nemo-with-extensions
      cinnamon.cinnamon-translations
      killall
      wl-clipboard
      pulseaudio
      nwg-look
      gnome.file-roller
      appimage-run
      lutris
      cliphist
      libnotify
      swappy
      bibata-cursors
      steam
      screen
      gamemode
      moonlight-qt
      desktop-file-utils
      inputs.pollymc.packages.${pkgs.system}.pollymc
      (nvtopPackages.nvidia.overrideAttrs (oldAttrs: { buildInputs = with lib; [ ncurses udev ]; }))
      (firefox.override { nativeMessagingHosts = [ inputs.pipewire-screenaudio.packages.${pkgs.system}.default ff2mpv ]; })
      mpv
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
      android-tools
      networkmanagerapplet
      beep
      elegant-sddm
      #inputs.kwin-effects-forceblur.packages.${pkgs.system}.default
      #(pkgs.callPackage ./linux-wallpaperengine.nix { })
    ] ++ (import ./stuff.nix pkgs).scripts ++ (import ./stuff.nix pkgs).hyprland-pkgs;
  };
  nixpkgs.config.permittedInsecurePackages = [ "freeimage-unstable-2021-11-01" ];
  #And here is some other small stuff
  documentation.nixos.enable = false;
  virtualisation.libvirtd.enable = true;
  nixpkgs.overlays = [
    inputs.nvidia-patch.overlays.default
  ];
  xdg.mime.defaultApplications = {
    "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
    "application/x-compressed-tar" = fileroller;
    "application/x-bzip2-compressed-tar" = fileroller;
    "application/x-bzip1-compressed-tar" = fileroller;
    "application/x-tzo" = fileroller;
    "application/x-xz"= fileroller;
    "application/x-lzma-compressed-tar" = fileroller;
    "application/zstd" = fileroller;
    "application/x-7z-compressed" = fileroller;
    "application/x-zstd-compressed-tar" = fileroller;
    "application/x-lzma" = fileroller;
    "application/x-lz4" = fileroller;
    "application/x-xz-compressed-tar" = fileroller;
    "application/x-lz4-compressed-tar" = fileroller;
    "application/x-archive" = fileroller;
    "application/x-cpio" = fileroller;
    "application/x-lzop" = fileroller;
    "application/x-bzip1" = fileroller;
    "application/x-tar" = fileroller;
    "application/x-bzip2" = fileroller;
    "application/gzip" = fileroller;
    "application/x-lzip-compressed-tar" = fileroller;
    "application/x-tarz "= fileroller;
    "application/zip" = fileroller;
    "inode/directory" = "nemo.desktop";
    "text/html" = "firefox.desktop";
    "video/mp4" = "mpv.desktop";
    "audio/mpeg" = "mpv.desktop";
    "audio/flac" = "mpv.desktop";
  };
  users.defaultUserShell = pkgs.zsh;
  nixpkgs.config.allowUnfree = true;
  imports =
    [
      #./my-services.nix
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
  networking.hostName = hostname;
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
    extraGroups = [ "wheel" "libvirtd" "libvirt ""uinput" "mlocate" "nginx" "input" "kvm" "adbusers" "vboxusers" "video" ];
    packages = with pkgs; [
      tree
    ];
  };
    xdg.portal = { enable = true; extraPortals = [ pkgs.xdg-desktop-portal-hyprland pkgs.xdg-desktop-portal-gtk ]; }; 
  xdg.portal.config.common.default = "*";
  networking.firewall.enable = false;
  system.stateVersion = "23.11";
}
