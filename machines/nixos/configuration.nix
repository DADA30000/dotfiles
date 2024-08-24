{ config, lib, inputs, pkgs, options, var, ... }:
{
  #Some servicess
  services = {
    printing.enable = true;
    gvfs.enable = true;
    openssh.enable = true;
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
    cron = {
      enable = true;
      systemCronJobs = [
        "*/59 * * * *   root  update-cloudflare-dns /cloudflare1.conf"
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
      pulse.enable = true;
    };
  };
  #Some security
  security = {
    pam.loginLimits = [ { domain = "*"; item = "core"; value = "0"; } ];
    rtkit.enable = true;
    polkit.enable = true;
  };
  #Some programs
  programs = {
    firejail.enable = true;
    dconf.enable = true;
    zsh.enable = true;
    adb.enable = true;
    nh.enable = true;
    neovim = {
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      enable = true;
    };
  };
  #Some boot settings
  boot = {
    extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];
    initrd.systemd.enable = true;
    kernel.sysctl."kernel.sysrq" = 1;
    kernelPackages = pkgs.linuxPackages_testing; 
    tmp.useTmpfs = true;
    extraModprobeConfig = ''
      options v4l2loopback devices=1 video_nr=1 card_label="OBS Cam" exclusive_caps=1
    '';
    kernelModules = [
      "v4l2loopback"
    ];
    loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot.enable = true;
      timeout = 0;
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
  nix.package = pkgs.nixVersions.latest;
  systemd.coredump.enable = false;
  hardware.opentabletdriver.enable = true;
  #Some environment stuff
  environment = {
    variables = {
      GTK_THEME = "Materia-dark";
      MOZ_ENABLE_WAYLAND = "1";
      TERMINAL = "kitty";
      EGL_PLATFORM = "wayland";
      MOZ_DISABLE_RDD_SANDBOX = "1";
    };
    systemPackages = with pkgs; [
      wget
      git-lfs
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
      nix-index
      iptables
      nftables
      ipset
      curl
      gawk
      remmina
      telegram-desktop
      xorg.xeyes
      steam-run
      adwaita-icon-theme
      osu-lazer-bin
      hyprshot
      nautilus
      cinnamon-translations
      file-roller
      appimage-run
      cliphist
      libnotify
      swappy
      steam
      moonlight-qt
      inputs.pollymc.packages.${pkgs.system}.pollymc
      nvtopPackages.amd
      qbittorrent
      pavucontrol
      brightnessctl
      imv
      myxer
      beep
      ffmpegthumbnailer
      zed-editor
      dotnetCorePackages.dotnet_8.sdk
      dotnetCorePackages.dotnet_8.runtime
      imv
      any-nix-shell
    ] ++ (import ./stuff.nix (pkgs)).scripts ++ (import ./stuff.nix pkgs).hyprland-pkgs;
  };
  #Some networking stuff
  networking = {
    hostName = var.hostname;
    networkmanager.enable = true;
  };
  #And here is some other small stuff
  documentation.nixos.enable = false;
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
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      (nerdfonts.override { fonts = [ "JetBrainsMono" ]; })
    ];
  };
  time.timeZone = "Europe/Moscow";
  i18n.defaultLocale = "ru_RU.UTF-8";
  console = {
    earlySetup = true;
    keyMap = "us,ru";
  };
  users.users."${var.user}" = {
    isNormalUser = true;
    hashedPassword = var.user-hash;
    extraGroups = [ "wheel" "uinput" "mlocate" "nginx" "input" "kvm" "adbusers" "video" ];
  };
  system.etc.overlay.mutable = false;
  users.mutableUsers = false;
  virtualisation.waydroid.enable = true;
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-hyprland pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "*";
  };
  system.stateVersion = "23.11";
}
