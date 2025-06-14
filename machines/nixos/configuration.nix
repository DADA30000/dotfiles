{
  pkgs,
  inputs,
  user-hash,
  user,
  self,
  ...
}:
let
  krisp-patcher =
    pkgs.writers.writePython3Bin "krisp-patcher"
      {
        libraries = with pkgs.python3Packages; [
          capstone
          pyelftools
        ];
        flakeIgnore = [
          "E501" # line too long (82 > 79 characters)
          "F403" # 'from module import *' used; unable to detect undefined names
          "F405" # name may be undefined, or defined from star imports: module
        ];
      }
      ''
        import sys
        import shutil

        from elftools.elf.elffile import ELFFile
        from capstone import *
        from capstone.x86 import *

        if len(sys.argv) < 2:
            print(f"Usage: {sys.argv[0]} [path to discord_krisp.node]")
            # "Unix programs generally use 2 for command line syntax errors and 1 for all other kind of errors."
            sys.exit(2)

        executable = sys.argv[1]

        elf = ELFFile(open(executable, "rb"))
        symtab = elf.get_section_by_name('.symtab')

        krisp_initialize_address = symtab.get_symbol_by_name("_ZN7discordL17DoKrispInitializeEv")[0].entry.st_value
        isSignedByDiscord_address = symtab.get_symbol_by_name("_ZN7discord4util17IsSignedByDiscordERKNSt4__Cr12basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEE")[0].entry.st_value

        text = elf.get_section_by_name('.text')
        text_start = text['sh_addr']
        text_start_file = text['sh_offset']
        # This seems to always be zero (.text starts at the right offset in the file). Do it just in case?
        address_to_file = text_start_file - text_start

        # Done with the ELF now.
        # elf.close()

        krisp_initialize_offset = krisp_initialize_address - address_to_file
        isSignedByDiscord_offset = krisp_initialize_address - address_to_file

        f = open(executable, "rb")
        f.seek(krisp_initialize_offset)
        krisp_initialize = f.read(256)
        f.close()

        # States
        found_issigned_by_discord_call = False
        found_issigned_by_discord_test = False
        found_issigned_by_discord_je = False
        found_already_patched = False
        je_location = None
        je_size = 0

        # We are looking for a call to IsSignedByDiscord, followed by a test, followed by a je.
        # Then we replace the je with nops.

        md = Cs(CS_ARCH_X86, CS_MODE_64)
        md.detail = True
        for i in md.disasm(krisp_initialize, krisp_initialize_address):
            if i.id == X86_INS_CALL:
                if i.operands[0].type == X86_OP_IMM:
                    if i.operands[0].imm == isSignedByDiscord_address:
                        found_issigned_by_discord_call = True

            if i.id == X86_INS_TEST:
                if found_issigned_by_discord_call:
                    found_issigned_by_discord_test = True

            if i.id == X86_INS_JE:
                if found_issigned_by_discord_test:
                    found_issigned_by_discord_je = True
                    je_location = i.address
                    je_size = len(i.bytes)
                    break

            if i.id == X86_INS_NOP:
                if found_issigned_by_discord_test:
                    found_already_patched = True
                    break

        if je_location:
            print(f"Found patch location: 0x{je_location:x}")

            shutil.copyfile(executable, executable + ".orig")
            f = open(executable, 'rb+')
            f.seek(je_location - address_to_file)
            f.write(b'\x90' * je_size)   # je can be larger than 2 bytes given a large enough displacement :(
            f.close()
        else:
            if found_already_patched:
                print("Couldn't find patch location - already patched.")
            else:
                print("Couldn't find patch location - review manually. Sorry.")
      '';
  #mkNixPak = inputs.nixpak.lib.nixpak {
  #  inherit (pkgs) lib;
  #  inherit pkgs;
  #};
  #sandboxed-vesktop = mkNixPak {
  #  config = { sloth, ... }: {
  #    app.package = pkgs.vesktop;
  #    dbus.policies = {
  #      #"org.pulseaudio.Server" = "own";
  #      #"org.pipewire.Telephony" = "own";
  #      #"org.freedesktop.portal.Desktop" = "own";
  #      #"org.freedesktop.portal.Documents" = "own";
  #      #"org.freedesktop.impl.portal.desktop.hyprland" = "own";
  #      #"org.erikreider.swaync.cc" = "own";
  #      #"org.freedesktop.Notifications" = "own";
  #      #"org.freedesktop.systemd1" = "own";
  #      #"ca.desrt.dconf" = "own";
  #      #"org.freedesktop.DBus" = "own";
  #      #"org.a11y.Bus" = "own";
  #      #"fr.arouillard.waybar" = "own";
  #      #"org.gtk.vfs.Daemon" = "own";
  #      #"org.freedesktop.impl.portal.PermissionStore" = "own";
  #      "org.*" = "talk";
  #    };
  #    bubblewrap = {
  #      network = true;
  #      bind.rw = [
  #        (sloth.concat' sloth.homeDir "/.config/vesktop")
  #        (sloth.env "XDG_RUNTIME_DIR")
  #      ];
  #      bind.ro = [
  #        (sloth.concat' sloth.homeDir "/Downloads")
  #      ];
  #      bind.dev = [
  #        "/dev/dri"
  #      ];
  #    };
  #  };
  #};
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

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  virtualisation.libvirtd.enable = true;

  # Enable TPM emulation (optional)
  virtualisation.libvirtd.qemu = {
    swtpm.enable = true;
    ovmf.packages = [ pkgs.OVMFFull.fd ];
  };

  programs.git.enable = true;

  programs.git.lfs.enable = true;

  # Enable USB redirection (optional)
  virtualisation.spiceUSBRedirection.enable = true;

  programs.virt-manager.enable = true;

  programs.ydotool.enable = true;

  # Disable annoying firewall
  networking.firewall.enable = false;

  # Enable singbox proxy to my VPS with WireGuard
  singbox-wg.enable = true;

  # Enable singbox proxy to my XRay vpn (uncomment in default.nix in ../../modules/system)
  #singbox.enable = true;

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
  ];

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

  # Use mainline (or latest stable) kernel instead of LTS kernel
  #boot.kernelPackages = pkgs.linuxPackages_testing;
  #boot.kernelPackages = pkgs.linuxPackages_5_15;
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
  #systemd.services.NetworkManager-wait-online.enable = false;
  networking.networkmanager = {
    enable = true;
    wifi.backend = "iwd";
  };

  # Allow making users through useradd
  users.mutableUsers = true;

  virtualisation.vmware.host.enable = true;

  # Enable WayDroid
  virtualisation.waydroid.enable = false;

  # Autologin
  services.getty.autologinUser = user;

  # Enable DPI (Deep packet inspection) bypass
  zapret.enable = false;

  # Enable replays
  replays.enable = true;

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

  flatpak = {

    # Enable system flatpak
    enable = true;

    # Packages to install from flatpak
    packages = [
      "io.github.Soundux"
    ];

  };

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

  obs = {

    # Enable OBS
    enable = true;

    # Enable virtual camera
    virt-cam = false;

  };

  graphics = {

    enable = true;

    nvidia.enable = false;

    amdgpu = {

      enable = true;

      pro = false;

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
      NH_NO_CHECKS=1; # REMOVE LATER
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
        gimp3-with-plugins
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
        (firefox.override {
          nativeMessagingHosts = [
            (inputs.pipewire-screenaudio.packages.${pkgs.system}.default.overrideAttrs (
              finalAttrs: previousAttrs: { cargoHash = "sha256-H/Uf6Yo8z6tZduXh1zKxiOqFP8hW7Vtqc7p5GM8QDws="; }
            ))
          ];
        })
        wget
        nekoray
        killall
        gamemode
        screen
        unrar
        android-tools
        zip
        jdk23
        kdePackages.kdenlive
        mpv
        remmina
        ayugram-desktop
        adwaita-icon-theme
        osu-lazer-bin
        steam
        moonlight-qt
        prismlauncher
        nvtopPackages.amd
        qbittorrent
        pavucontrol
        any-nix-shell
        wl-clipboard
        bottles
        networkmanager_dmenu
        neovide
        comma
        lact
        libreoffice
        distrobox
        qalculate-gtk
        p7zip
        krisp-patcher
        inputs.anicli-ru.packages.${system}.default
        inputs.zen-browser.packages.${system}.twilight
        inputs.nix-alien.packages.${system}.nix-alien
        inputs.nix-search.packages.${system}.default
        (aria2.overrideAttrs { patches = [ ../../stuff/max-connection-to-unlimited.patch ]; })
        (discord.override {
          withOpenASAR = true;
          withVencord = true;
        })
        inputs.fabric.packages.${system}.default
        inputs.fabric-cli.packages.${system}.default
        (inputs.fabric.packages.${system}.run-widget.override {
          extraPythonPackages = with python3Packages; [
            ijson
            numpy
            pillow
            psutil
            requests
            setproctitle
            toml
            watchdog
          ];
          extraBuildInputs = [
            inputs.fabric-gray.packages.${system}.default
            networkmanager
            networkmanager.dev
            playerctl
          ];
        })
      ]
      ++ (import ../../modules/system/stuff { inherit pkgs user; }).scripts;

  };

  boot.loader = {

    efi.canTouchEfiVariables = true;

    systemd-boot.enable = true;

    systemd-boot.memtest86.enable = true;

    timeout = 0;

  };

  nix.package = pkgs.nixVersions.git;

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

  i18n = {
    defaultLocale = "ru_RU.UTF-8";
    extraLocaleSettings = { LC_CTYPE = "en_US.UTF-8"; };
  };

  console.keyMap = "ru";

  system.stateVersion = "24.11";

}
