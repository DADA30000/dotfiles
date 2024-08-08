{ config, lib, inputs, pkgs, options, var, ... }:
let
  fileroller = "org.gnome.FileRoller.desktop";
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.system};
  long-script = "${pkgs.beep}/bin/beep -f 130 -l 100 -n -f 262 -l 100 -n -f 330 -l 100 -n -f 392 -l 100 -n -f 523 -l 100 -n -f 660 -l 100 -n -f 784 -l 300 -n -f 660 -l 300 -n -f 146 -l 100 -n -f 262 -l 100 -n -f 311 -l 100 -n -f 415 -l 100 -n -f 523 -l 100 -n -f 622 -l 100 -n -f 831 -l 300 -n -f 622 -l 300 -n -f 155 -l 100 -n -f 294 -l 100 -n -f 349 -l 100 -n -f 466 -l 100 -n -f 588 -l 100 -n -f 699 -l 100 -n -f 933 -l 300 -n -f 933 -l 100 -n -f 933 -l 100 -n -f 933 -l 100 -n -f 1047 -l 400";
  hazy = pkgs.fetchgit {
    url = "https://github.com/Astromations/Hazy";
    rev = "25e472cc4563918d794190e72cba6af8397d3a78";
    sha256 = "sha256-zK17CWwYJNSyo5pbYdIDUMKyeqKkFbtghFoK9JBR/C8=";
  };
in
{
  #Some services
  services = {
    getty.autologinUser = var.user;
    printing.enable = true;
    gvfs.enable = true;
    #desktopManager.plasma6.enable = true;
    #displayManager.sddm = {
    #  enable = true;
    #  #settings = {
    #  #  Autologin = {
    #  #    Session = "plasma.desktop";
    #  #    User = var.user
    #  #  };
    #  #};
    #  wayland = {
    #    enable = true;
    #    compositor = "kwin";
    #  };
    #};
    flatpak = {
      enable = true;
      uninstallUnmanaged = true;
      packages = [
        "dev.vencord.Vesktop"
	"com.usebottles.bottles"
	"com.github.tchx84.Flatseal"
      ];
      update.auto = {
        enable = true;
        onCalendar = "daily";
      };
    };
    openssh.enable = true;
    #sunshine = {
    #  autoStart = false;
    #  enable = true;
    #  capSysAdmin = true;
    #  package = ( pkgs.sunshine.override { cudaSupport = true; } );
    #};
    cron = {
      enable = true;
      systemCronJobs = [
        "*/59 * * * *   root  update-cloudflare-dns /cloudflare1.conf"
      ];
    };
    dnscrypt-proxy2 = {
      enable = true;
      settings = {
        server_names = [ "cloudflare" "scaleway-fr" "yandex" "google" ];
	listen_addresses = [ "127.0.0.1:53" "[::1]:53" ];
      };
    };
    resolved = {
      enable = true;
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
      videoDrivers = ["amdgpu"];
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
    zsh.enable = true;
    adb.enable = true;
    firefox.nativeMessagingHosts.ff2mpv = true;
    nh = {
      enable = true;
      flake = "/etc/nixos";
    };
    spicetify = {
      enable = true;
      enabledExtensions = with spicePkgs.extensions; [
        adblock
        hidePodcasts
        shuffle # shuffle+ (special characters are sanitized out of extension names)
      ];
      theme = {
        name = "Hazy";
        src = hazy;
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
    kernelPackages = pkgs.linuxPackages_xanmod_latest; 
    tmp.useTmpfs = true;
    initrd.kernelModules = [
      "amdgpu"
    ];
    extraModprobeConfig = ''
      options v4l2loopback devices=1 video_nr=1 card_label="OBS Cam" exclusive_caps=1
    '';
    kernelParams = [ 
      "amd_iommu=on" 
      "iommu=pt"
    ];
    kernelModules = [
      "v4l2loopback"
    ];
    loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot.enable = true;
      timeout = 0;
      #grub = {
      #  enable = true;
      #  efiSupport = true;
      #  device = "nodev";
      #  timeoutStyle = "hidden";
      #  extraConfig = "set timeout=1";
      #  minegrub-world-sel = { 
      #    enable = true;
      #    customIcons = [{
      #      name = "nixos";
      #      lineTop = "NixOS (06/07/2024, 2:24 AM)";
      #      lineBottom = "Creative Mode, Cheats, Version: unstable";
      #      customImg = builtins.path {
      #        path = ./stuff/nixos-img.png;
      #        name = "nixos-img";
      #      };
      #    }];
      #  };
      #};
    };
  };
  #Some nix settings
  nix.settings = {
    auto-optimise-store = true;
    substituters = [
      "https://hyprland.cachix.org" 
      "https://nixpkgs-unfree.cachix.org"
    ];
    trusted-public-keys = [ 
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" 
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
      zapret = {
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        path = with pkgs; [
          iptables
          nftables
	  ipset
	  curl
	  zapret
          gawk
        ];
        serviceConfig = {
          Type = "forking";
          Restart = "no";
          TimeoutSec = "30sec";
          IgnoreSIGPIPE = "no";
          KillMode = "none";
          GuessMainPID = "no";
          ExecStart = "${pkgs.zapret}/bin/zapret start";
          ExecStop = "${pkgs.zapret}/bin/zapret stop";
          EnvironmentFile = pkgs.writeText "zapret-environment" ''
	    MODE="nfqws"
  	    FWTYPE="nftables"
  	    MODE_HTTP=1
  	    MODE_HTTP_KEEPALIVE=1
  	    MODE_HTTPS=1
  	    MODE_QUIC=0
  	    MODE_FILTER=none
  	    DISABLE_IPV6=1
  	    INIT_APPLY_FW=1
  	    NFQWS_OPT_DESYNC="--dpi-desync=fake,split2 --dpi-desync-fooling=datanoack"
  	    #NFQWS_OPT_DESYNC="--dpi-desync=split2"
  	    #NFQWS_OPT_DESYNC="--dpi-desync=fake,split2 --dpi-desync-ttl=9 --dpi-desync-fooling=md5sig"
  	    TMPDIR=/tmp
  	    SET_MAXELEM=522288
  	    IPSET_OPT="hashsize 262144 maxelem $SEX_MAXELEM"
  	    IP2NET_OPT4="--prefix-length=22-30 --v4-threshold=3/4"
  	    IP2NET_OPT6="--prefix-length=56-64 --v6-threshold=5"
  	    AUTOHOSTLIST_RETRANS_THRESHOLD=3
  	    AUTOHOSTLIST_FAIL_THRESHOLD=3
  	    AUTOHOSTLIST_FAIL_TIME=60
  	    AUTOHOSTLIST_DEBUGLOG=0
  	    MDIG_THREADS=30
  	    GZIP_LISTS=1
  	    DESYNC_MARK=0x40000000
  	    DESYNC_MARK_POSTNAT=0x20000000
  	    FLOWOFFLOAD=donttouch
  	    GETLIST=get_antifilter_ipsmart.sh
          '';
        };
      };
      startup-sound = {
        wantedBy = ["sysinit.target"];
        enable = false;
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
    user.services = {
      polkit_gnome = {
        path = [pkgs.bash];
	wantedBy = [ "hyprland-session.target" ];
	script = ''
	  exec ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1
	'';
	serviceConfig = {
	  Restart = "always";
	};
      };
      replays = {
        path = with pkgs; [ bash gpu-screen-recorder pulseaudio ];
	wantedBy = [ "graphical-session.target" ];
	script = ''
	  export PATH=/run/wrappers/bin:$PATH
          exec gpu-screen-recorder -w screen -q ultra -a $(pactl get-default-sink).monitor -a $(pactl get-default-source) -f 60 -r 300 -c mp4 -o ~/Games/Replays
        '';
	serviceConfig = {
	  Restart = "always";
	};
      };
    };
  };
  #Some hardware stuff
  hardware = {
    opentabletdriver.enable = true;
    graphics = {
      enable = true;
      enable32Bit = true;
    };
    amdgpu = {
      initrd.enable = true;
      opencl.enable = true;
      #amdvlk = {
      #  support32Bit.enable = true;
      #  enable = true;
      #  supportExperimental.enable = true;
      #};
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
      ROC_ENABLE_PRE_VEGA = "1";
    };
    systemPackages = with pkgs; [
      wget
      git
      neovim
      hyprshot
      killall
      gamemode
      screen
      unrar
      pulseaudio
      android-tools
      elegant-sddm
      cached-nix-shell
      zip
      jdk21
      mlocate
      neovide
      mpv
      firefox
      wl-clipboard
      ipset
      nix-index
      zerotierone
    ] ++ (import ./stuff.nix (pkgs)).scripts ++ (import ./stuff.nix pkgs).hyprland-pkgs;
  };
  #Some networking stuff
  networking = {
    hostName = var.hostname;
    networkmanager.enable = true;
    nameservers = [ "::1" "127.0.0.1" ];
    resolvconf.dnsSingleRequest = true;
    nftables.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 80 9993 ];
      allowedUDPPorts = [ 22 80 9993 ];
    };
  };
  #And here is some other small stuff
  documentation.nixos.enable = false;
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
  imports =
    [
      #./my-services.nix
      ./disks.nix
      ./hardware-configuration.nix
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
  time.timeZone = "Europe/Moscow";
  i18n.defaultLocale = "ru_RU.UTF-8";
  console = {
    earlySetup = true;
    font = null;
    useXkbConfig = true;
  };
  users.users."${var.user}" = {
    isNormalUser = true;
    hashedPassword = var.user-hash;
    extraGroups = [ "wheel" "uinput" "mlocate" "nginx" "input" "kvm" "adbusers" "video" ];
  };
  users.users.tpws = {
    isSystemUser = true;
    group = "tpws";
  };
  users.groups.tpws = {};
  virtualisation.waydroid.enable = true;
  xdg.portal = { enable = true; extraPortals = [ pkgs.xdg-desktop-portal-hyprland pkgs.xdg-desktop-portal-gtk ]; }; 
  xdg.portal.config.common.default = "*";
  system.stateVersion = "23.11";
}
