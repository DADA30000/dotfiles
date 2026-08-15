{
  config,
  lib,
  ...
}:
with lib;
let
  boot_label = null;
  cfg = config.disks;
  normalUsers = builtins.attrNames (lib.filterAttrs (_: user: user.isNormalUser) config.users.users);
  commonUserPersistence = {
    files = [
      ".cache/rofi-entry-history.txt"
      ".cache/cliphist/db"
    ];
    directories = [
      "Videos"
      "Desktop"
      "Pictures"
      "Projects"
      "Documents"
      "Downloads"
      ".ssh"
      ".umu"
      ".nixpak"
      ".thunderbird"
      ".local/state/wireplumber"
      ".local/share/zsh"
      ".local/share/gnupg"
      ".local/share/direnv"
      ".local/share/keyrings"
      ".local/share/easyeffects"
      ".local/share/qBittorrent"
      ".config/git"
      ".config/zen"
      ".config/wivrn"
      ".config/sunshine"
      ".config/kdeconnect"
      ".config/easyeffects"
      ".config/qBittorrent"
      ".config/nvim/undodir"
      ".config/net.imput.helium"
    ];
  };
in
{
  options.disks = {
    impermanence = mkEnableOption "impermanence (remove all files except those that are needed)";
    enable = mkOption {
      type = types.bool;
      default = true;
      example = false;
      description = "base disks configuration";
    };
  };

  config = mkIf cfg.enable {

    hardware.block.scheduler."*" = "bfq";

    environment.persistence."/persist" = mkMerge [
      (mkIf (!cfg.impermanence) { enable = false; })
      (mkIf cfg.impermanence {
        enable = true;
        hideMounts = true;
        users = lib.genAttrs normalUsers (_: commonUserPersistence);
        directories = [
          "/website"
          "/etc/NetworkManager/system-connections"
          "/etc/nixos"
          "/etc/ssh"
          "/etc/lact"
          "/etc/waydroid-extra"
          "/var/log"
          "/var/db/sudo/lectured"
          "/var/lib/bluetooth"
          "/var/lib/nixos"
          "/var/lib/systemd"
          "/var/lib/libvirt"
          "/var/lib/flatpak"
          "/var/lib/sbctl"
          "/var/lib/waydroid"
          "/var/lib/zerotier-one"
          "/var/lib/llama-cpp"
          {
            directory = "/var/lib/private";
            mode = "u=rwx,g=,o=";
          }
          {
            directory = "/etc/credstore";
            mode = "u=rwx,g=,o=";
          }
          {
            directory = "/var/lib/acme";
            user = "acme";
            group = "acme";
            mode = "u=rwx,g=rx,o=rx";
          }
          {
            directory = "/var/lib/suricata";
            user = "suricata";
            group = "suricata";
            mode = "u=rwx,g=rx,o=rx";
          }
          {
            directory = "/var/lib/cape";
            user = "cape";
            group = "cape";
            mode = "u=rwx,g=,o=";
          }
          {
            directory = "/var/lib/postgresql";
            user = "postgres";
            group = "postgres";
            mode = "u=rwx,g=rx,o=";
          }
        ];
        files = [
          "/etc/machine-id"
          "/var/lib/searx-secret"
        ];
      })
    ];

    boot = mkIf cfg.impermanence {
      supportedFilesystems.zfs = true;
      initrd = {
        supportedFilesystems.zfs = true;
        systemd.services.zfs-rollback = {
          wantedBy = [
            "initrd.target"
          ];
          after = [
            "zfs-import-nixos.service"
          ];
          before = [
            "sysroot.mount"
          ];
          path = [ config.boot.zfs.package ];
          unitConfig.DefaultDependencies = false;
          description = "Rollback ZFS root and home to blank snapshots";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = [
              "${config.boot.zfs.package}/bin/zfs rollback -r nixos/root@blank"
              "${config.boot.zfs.package}/bin/zfs rollback -r nixos/home@blank"
            ];
          };
        };
      };
    };

    fileSystems = {

      "/" = {
        device = "nixos/root";
        fsType = "zfs";
        neededForBoot = true;
      };

      "/persist" = mkIf cfg.impermanence {
        device = "nixos/persist";
        fsType = "zfs";
        neededForBoot = true;
      };

      "/nix" = {
        device = "nixos/nix";
        fsType = "zfs";
        neededForBoot = true;
      };

      "/home" = {
        device = "nixos/home";
        fsType = "zfs";
        neededForBoot = true;
        options = [
          "nodev"
          "nosuid"
        ];
      };

      "/boot" = {
        device = "/dev/disk/by-label/${if boot_label == null then "BOOT" else boot_label}";
        fsType = "vfat";
        options = [
          "noauto"
          "x-systemd.automount"
          "fmask=0077"
          "dmask=0077"
        ];
      };
    };
  };
}
