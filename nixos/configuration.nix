# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
{ config, lib, inputs, pkgs, options, ... }:
let
  vars = { myUser = "l0lk3k"; };
  spicePkgs = inputs.spicetify-nix.packages.${pkgs.system}.default;
  package = config.boot.kernelPackages.nvidiaPackages.beta;
in
{
  services.sunshine = {
    autoStart = false;
    enable = true;
    capSysAdmin = true;
  };
  programs.dconf.enable = true;
  services.gvfs.enable = true;
  nix.settings = {
    substituters = ["https://hyprland.cachix.org" "https://nix-gaming.cachix.org" "https://nixpkgs-unfree.cachix.org" ];
    trusted-public-keys = ["hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4=" "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs=" ];
    experimental-features = [ "nix-command" "flakes" ];
  };
  security.wrappers.gsr-kms-server = {
    owner = "root";
    group = "root";
    capabilities = "cap_sys_admin+ep";
    source = "${pkgs.gpu-screen-recorder}/bin/gsr-kms-server";
  };
  documentation.nixos.enable = false;
  boot.extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];
  boot.initrd.systemd.enable = true;
 # services.nextcloud = {
 #   enable = true;
 #   configureRedis = true;
 #   config.adminpassFile = "/password";
 #   https = true;
 #   hostName = "nc.akff-sanic.ru";
 #   package = pkgs.nextcloud29;
 # };
  programs.xwayland.enable = true;
  systemd.services.NetworkManager-wait-online.enable = false;
 # services.nginx = {
 # enable = true;
 #   virtualHosts = {
 #     ${config.services.nextcloud.hostName} = {
 #       forceSSL = true;
 #       enableACME = true;
 #     };
 #     "akff-sanic.ru" = {
 #       forceSSL = true;
 #       enableACME = true;
 #       root = "/fileserver";
 #       extraConfig = ''
 #         autoindex on;
 #         add_before_body /.theme/header.html;
 #         add_after_body /.theme/footer.html; 
 #         autoindex_exact_size off;
 #       '';
 #     };
 #     "ip.akff-sanic.ru" = {
 #       forceSSL = true;
 #       enableACME = true;
 #       root = "/fileserver";
 #       extraConfig = ''
 #         autoindex on;
 #         add_before_body /.theme/header.html;
 #         add_after_body /.theme/footer.html; 
 #         autoindex_exact_size off;
 #       '';
 #     };
 #   };
 # };
 # security.acme = {
 #   acceptTerms = true;
 #   defaults.email = "vadimhack.ru@gmail.com";
 #   certs = { 
 #     ${config.services.nextcloud.hostName}.email = "vadimhack.ru@gmail.com"; 
 #   };
 # }; 
  fileSystems = {
    "/".options = [ "compress-force=zstd" ];
    "/home".options = [ "compress-force=zstd" ];
    "/nix".options = [ "compress-force=zstd" "noatime" ];
  };
  fileSystems."/home/${vars.myUser}/Games" =
  { device = "/dev/disk/by-label/Games";
    fsType = "btrfs";
    options = [ "compress-force=zstd" "subvol=games" "nofail"];
  };
  fileSystems."/var/lib/nextcloud" = 
  { device = "/dev/disk/by-label/Games";
    fsType = "btrfs";
    options = [ "compress-force=zstd" "subvol=nextcloud" "nofail" ];
  };
  boot.kernel.sysctl."kernel.sysrq" = 1;
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
  nix.settings.keep-outputs = true;
  nix.settings.keep-derivations = true;
  systemd.coredump.enable = false;
  security.pam.loginLimits = [
    { domain = "*"; item = "core"; value = "0"; }
  ];
  nixpkgs.overlays = [inputs.nvidia-patch.overlays.default];
  nix.settings.auto-optimise-store = true;
  boot.kernelPackages = pkgs.linuxPackages_6_8; 
  boot.tmp.useTmpfs = true;
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
  };
  services.xserver.videoDrivers = ["nvidia"];
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = false;
    open = false;
    nvidiaSettings = false;
    package = pkgs.nvidia-patch.patch-nvenc (pkgs.nvidia-patch.patch-fbc package);
  };
  boot.extraModprobeConfig = ''
    options v4l2loopback devices=1 video_nr=1 card_label="OBS Cam" exclusive_caps=1
  '';
  qt.enable = true;
  services.cron = {
    enable = true;
    systemCronJobs = [
      "*/59 * * * *   root  update-cloudflare-dns /cloudflare1.conf"
      "*/59 * * * *   root  update-cloudflare-dns /cloudflare2.conf"
    ];
  };
  systemd.services.zerotier = {
  description = "Starts a zerotier-one service";
  path = [pkgs.bash pkgs.zerotierone];
  script = ''
    exec zerotier-one
  '';
  wantedBy = [ "multi-user.target" ]; # starts after login
  };
  boot.kernelParams = [ 
    "nvidia_drm.fbdev=1"
    "amd_iommu=on" 
    "iommu=pt"
  ];
  boot.kernelModules = [
    "v4l2loopback"
  ];
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
  services.locate = {
        enable = true;
        package = pkgs.mlocate;
        interval = "hourly";
	localuser = null;
  };
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = false;
    pulse.enable = true;
    jack.enable = false;
  };
  security.polkit.enable = true;
  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;
  nixpkgs.config.allowUnfree = true;
  imports =
    [
      ./hardware-configuration.nix
      inputs.spicetify-nix.nixosModule
      inputs.home-manager.nixosModules.home-manager
    ];
  programs.spicetify =
    let
      hazy = pkgs.fetchgit {
        url = "https://github.com/Astromations/Hazy";
	rev = "0d45831a31b0c72e1d3ab8be501479e196a709d7";
        sha256 = "sha256-0t7/25hRfvyJ8K+nTzgMl8RabTBxtMIjQvDECzYvwg8=";
      };
      adblock = pkgs.fetchgit {
        url = "https://github.com/rxri/spicetify-extensions";
	rev = "96c03d40518f6527db9b4122cb628d88f36f47d0";
	sha256 = "sha256-JR2fda2IGpIbhHy7zK4A5LLT5yVjowZWTvNWPhjYHxE=";
      };
    in
    {
    enable = true;
      theme = {
        name = "Hazy";
        src = hazy;
        requiredExtensions = [
          # define extensions that will be installed with this theme
          {
	    filename = "adblock.js";
	    src = "${adblock}/adblock";
	  }
        ];
        appendName = false; # theme is located at "${src}/Dribbblish" not just "${src}"

        # changes to make to config-xpui.ini for this theme:
        injectCss = true;
        replaceColors = true;
        overwriteAssets = true;
        sidebarConfig = true;
      };
  };
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
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
    theme = "/boot/grub/themes/hyperfluent";
  };
  boot.loader.efi.canTouchEfiVariables = true;
   networking.hostName = "nixos"; # Define your hostname.
   networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.
   time.timeZone = "Europe/Moscow";
  i18n.defaultLocale = "ru_RU.UTF-8";
  console = {
     earlySetup = true;
     #packages = with pkgs; [ terminus_font ];
     font = null;
     useXkbConfig = true; # use xkb.options in tty.
   };
  services.xserver.xkb.layout = "us,ru";
  services.xserver.xkb.options = "grp:alt_shift_toggle";
  services.xserver.enable = true;
  services.xserver.displayManager.startx.enable = true;
  services.getty.autologinUser = "${vars.myUser}";
  services.printing.enable = true;
   users.users.${vars.myUser} = {
     isNormalUser = true;
     extraGroups = [ "wheel" "libvirtd" "uinput" "mlocate" "nginx" "input" "kvm" "adbusers" "vboxusers" "video" ]; # Enable ‘sudo’ for the user.
     packages = with pkgs; [
       tree
     ];
   };
   environment.variables = {
       "QT_STYLE_OVERRIDE"="kvantum";
     };
   environment.systemPackages = with pkgs; [
     wget
     neovim
     git
     osu-lazer-bin
     libsForQt5.qtstyleplugin-kvantum
     qt6Packages.qtstyleplugin-kvantum 
     waybar
     stow
     inotify-tools
     swaynotificationcenter
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
     (pkgs.writeShellScriptBin "qemu-system-x86_64-uefi" ''
     qemu-system-x86_64 \
       -bios ${pkgs.OVMF.fd}/FV/OVMF.fd \
       "$@"
     '')
     (firefox.override { nativeMessagingHosts = [ inputs.pipewire-screenaudio.packages.${pkgs.system}.default ff2mpv ]; })
     cinnamon.nemo-fileroller
     zip
     jdk21
     myxer
     (pkgs.callPackage ./ani-cli-ru.nix { })
     gpu-screen-recorder-gtk
     gpu-screen-recorder
     rclone
     (pkgs.nvtopPackages.nvidia.overrideAttrs (oldAttrs: { buildInputs = with lib; [ ncurses udev ]; }))
     android-tools
     virtiofsd
     virtio-win
     networkmanagerapplet
     wttrbar
     beep
   ] ++ (import ./waybar-scripts.nix pkgs);
   programs.nm-applet.enable = true;
   xdg.portal = { enable = true; extraPortals = [ pkgs.xdg-desktop-portal-hyprland ]; }; 
   xdg.portal.config.common.default = "*";
   programs.firefox.nativeMessagingHosts.ff2mpv = true;
   programs.adb.enable = true;
   services.flatpak.enable = true;
  services.openssh.enable = true;
  networking.firewall.enable = false;
  system.stateVersion = "23.11";
}
