{
  pkgs,
  inputs,
  lib,
  config,
  ...
}:
let
  user = "nixos";
  nix-install = ''
    if [[ $EUID -ne 0 ]]; then
      exec sudo nix-install
    fi
    setfont cyr-sun16
    clear
    echo -e "\e[34mПроверка наличия соединения с интернетом...\e[0m"
    if ! nc -zw1 google.com 443 > /dev/null 2>&1; then
      echo -e "\e[31mСоединение не установлено :(\e[0m"
      if gum confirm "Настроить подключение?"; then
        nmtui
        if ! nc -zw1 google.com 443 > /dev/null 2>&1; then
          echo -e "\e[34mСоединение не было установлено, перезапуск...\e[0m"
          sleep 2; exec nix-install
        fi
      fi
    fi
    echo -e "\e[32mСоединение установлено!\e[0m"
    sleep 1
    if gum confirm --default=false "Использовать оффлайн копию репозитория?"; then
      cd /repo
      exec ./start.sh
    fi
    url="https://github.com/DADA30000/dotfiles"
    clear
    if gum confirm --default=false "Поменять URL репозитория с файлами конфигурации? (скрипт запускает start.sh из репозитория, репозиторий должен быть публичным)"; then
      url=$(gum input --placeholder "Пример: https://github.com/DADA30000/dotfiles")
    fi
    if GIT_ASKPASS=true git ls-remote "$url" > /dev/null 2>&1; then
      clear
      echo -e "\e[34mКлонирование репозитория...\e[0m"
      mkdir /mnt2
      if git clone "$url" --depth 1 /mnt2/dotfiles; then
        cd /mnt2/dotfiles
        echo -e "\e[34mЗапуск start.sh...\e[0m"
        exec ./start.sh
      else
        echo -e "\e[31mОшибка клонирования репозитория, перезапуск скрипта...\e[0m"
        sleep 3
        rm -rf /mnt2
        exec nix-install
      fi
    else
      echo -e "\e[31mURL репозитория неверный или приватный, перезапуск скрипта...\e[0m"
      sleep 3
      exec nix-install
    fi
  '';
in
{
  boot.supportedFilesystems.zfs = lib.mkForce false;
  nixpkgs.hostPlatform = "x86_64-linux";
  networking.wireless.enable = false;
  networking.hostName = "iso";
  imports = [
    ../../modules/system
  ];

  services = {
    resolved.enable = true;
    dnscrypt-proxy2 = {
      enable = true;
      settings = {
        server_names = [
          "cloudflare"
          "scaleway-fr"
          "google"
          "yandex"
        ];
        listen_addresses = [
          "127.0.0.1:53"
          "[::1]:53"
        ];
      };
    };
  };
  networking = {
    nameservers = [
      "::1"
      "127.0.0.1"
    ];
    resolvconf.dnsSingleRequest = true;
  };

  programs.ydotool.enable = true;

  # Disable annoying firewall
  networking.firewall.enable = false;

  # Enable singbox proxy to my VPS with WireGuard
  singbox-wg.enable = false;

  # Enable singbox proxy to my XRay vpn (uncomment in default.nix in ../../modules/system)
  #singbox.enable = true;

  # Run non-nix apps
  programs.nix-ld.enable = true;

  #boot.crashDump.enable = true;

  # Enable RAM compression
  zramSwap.enable = true;

  # Enable stuff in /bin and /usr/bin
  #services.envfs.enable = true;

  # Enable IOMMU
  #boot.kernelParams = [ "iommu=pt" ];

  # Enable some important system zsh stuff
  programs.zsh.enable = true;

  # Enable portals
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  xdg.portal.config.common.default = "*";

  # Enable OpenTabletDriver
  hardware.opentabletdriver.enable = true;

  # Places /tmp in RAM
  #boot.tmp.useTmpfs = true;

  # Use mainline (or latest stable) kernel instead of LTS kernel
  #boot.kernelPackages = pkgs.linuxPackages_testing;
  boot.kernelPackages = pkgs.linuxPackages_latest;
  #chaotic.scx.enable = true;

  # Enable SysRQ
  boot.kernel.sysctl."kernel.sysrq" = 1;

  # Restrict amount of annoying cache
  boot.kernel.sysctl."vm.dirty_bytes" = 50000000;
  boot.kernel.sysctl."vm.dirty_background_bytes" = 50000000;

  # Adds systemd to initrd (speeds up boot process a little, and makes it prettier)
  #boot.initrd.systemd.enable = true;

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
  #systemd.services.NetworkManager-wait-online.enable = false;
  networking.networkmanager.enable = true;

  # Allow making users through useradd
  # users.mutableUsers = true;

  # Enable WayDroid
  #virtualisation.waydroid.enable = false;

  # Autologin
  #services.getty.autologinUser = lib.mkForce user;

  # Enable russian anicli
  #anicli-ru.enable = true;

  # Enable DPI (Deep packet inspection) bypass
  #zapret.enable = false;

  # Enable replays
  replays.enable = true;

  # Enable startup sound on PC speaker (also plays after rebuilds)
  #startup-sound.enable = false;

  # Enable zerotier
  #zerotier.enable = false;

  # Enable spotify with theme
  spicetify.enable = true;

  # Enable mlocate (find files on system quickly)
  mlocate.enable = true;

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
      cores = 6;
      diskSize = 1024 * 8;
      msize = 16384 * 16;
      memorySize = 1024 * 4;
    };

  };

  #flatpak = {

  #  # Enable system flatpak
  #  enable = false;

  #  # Packages to install from flatpak
  #  packages = [
  #  ];

  #};

  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
    };
  };

  fonts = {

    fontconfig.enable = true;

    # Enable some default fonts
    enableDefaultPackages = true;

    # Add some fonts
    packages = with pkgs; [
      noto-fonts
      (nerdfonts.override { fonts = [ "JetBrainsMono" ]; })
    ];

  };

  security.sudo.wheelNeedsPassword = false;

  system.activationScripts = {

    repo = {

      # Run after /dev has been mounted
      deps = [ "specialfs" ];

      text = ''
        PATH=$PATH:${pkgs.gzip}/bin
        mkdir /repo
        ${pkgs.gnutar}/bin/tar -xzvf ${../../stuff/repo.tar.gz} -C /repo
        chown root:root -R /repo 
      '';

    };

  };

  users.users."${user}" = {

    # Marks user as real, human user
    isNormalUser = true;

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
    ];

  };

  nix.settings = {

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

  #obs = {

  #  # Enable OBS
  #  enable = true;

  #  # Enable virtual camera
  #  virt-cam = false;

  #};

  # Enable nvidia stuff
  #nvidia.enable = false;

  #amdgpu = {

  #  # Enable AMDGPU stuff
  #  enable = true;

  #  # Enable OpenCL and ROCm
  #  pro = false;

  #};

  #my-services = {

  #  # Enable automatic Cloudflare DDNS
  #  cloudflare-ddns.enable = false;

  #  nginx = {

  #    # Enable nginx
  #    enable = false;

  #    # Enable my goofy website
  #    website.enable = true;

  #    # Enable nextcloud
  #    nextcloud.enable = false;

  #    # Website domain
  #    hostName = "sanic.space";

  #  };

  #};

  #disks = {

  #  # Enable base disks configuration (NOT RECOMMENDED TO DISABLE, DISABLING IT WILL NUKE THE SYSTEM IF THERE IS NO ANOTHER FILESYSTEM CONFIGURATION)
  #  enable = false;

  #  # Enable system compression
  #  compression = true;

  #  second-disk = {

  #    # Enable additional disk (must be btrfs)
  #    enable = true;

  #    # Enable compression on additional disk
  #    compression = true;

  #    # Filesystem label of the partition that is used for mounting
  #    label = "Games";

  #    # Which subvolume to mount
  #    subvol = "games";

  #    # Path to a place where additional disk will be mounted
  #    path = "/home/${user}/Games";

  #  };

  #  swap = {

  #    file = {

  #      # Enable swapfile
  #      enable = false;

  #      # Path to swapfile
  #      path = "/var/lib/swapfile";

  #      # Size of swapfile in MB
  #      size = 4 * 1024;

  #    };

  #    partition = {

  #      # Enable swap partition
  #      enable = true;

  #      # Label of swap partition
  #      label = "swap";

  #    };

  #  };

  #};

  environment = {

    pathsToLink = [ "/share/zsh" ];

    variables = {
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
        gum
        lolcat
        openssl
        pyright
        lsd
        gamescope
        kdiskmark
        nixfmt-rfc-style
        gdb
        gdu
        gcc
        nixd
        nodejs
        yarn
        ccls
        inputs.pipewire-screenaudio.packages.${pkgs.system}.default
        wget
        nekoray
        git-lfs
        git
        killall
        gamemode
        screen
        unrar
        android-tools
        zip
        mpv
        nix-index
        remmina
        telegram-desktop
        adwaita-icon-theme
        osu-lazer-bin
        steam
        moonlight-qt
        qbittorrent
        pavucontrol
        any-nix-shell
        wl-clipboard
        bottles
        networkmanager_dmenu
        neovide
        comma
        qalculate-gtk
        p7zip
        inputs.nix-alien.packages.${system}.nix-alien
        inputs.nix-search.packages.${system}.default
        (writeShellScriptBin "nix-install" nix-install)
      ]
      ++ (import ../../modules/system/stuff pkgs).scripts;

  };

  nix.package = pkgs.nixVersions.latest;

  services = {

    printing.enable = true;

    gvfs.enable = true;

    openssh.enable = true;

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

  xdg = {

    mime.enable = true;

    icons.enable = true;

    autostart.enable = true;

  };

  users.defaultUserShell = pkgs.zsh;

  nixpkgs.config.allowUnfree = true;

  time.timeZone = "Europe/Moscow";

  i18n.defaultLocale = "ru_RU.UTF-8";

  console = {

    earlySetup = true;

    font = "${pkgs.terminus_font}/share/consolefonts/ter-k16n.psf.gz";

    keyMap = "ru";

  };

  system.stateVersion = "23.11";

}
