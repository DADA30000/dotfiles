{
  config,
  lib,
  ...
}:
with lib;
let
  root_label = null;
  boot_label = null;
  swap_label = null;
  second_label = null;
  cfg = config.disks;
  impermanence_subvolume_script = ''
    mkdir /btrfs_tmp
    mount -L ${if root_label == null then "nixos" else root_label} /btrfs_tmp
    if [[ -e /btrfs_tmp/root ]]; then
        mkdir -p /btrfs_tmp/old_roots
        timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/root)" "+%Y-%m-%-d_%H:%M:%S")
        mv /btrfs_tmp/root "/btrfs_tmp/old_roots/$timestamp"
    fi

    delete_subvolume_recursively() {
        IFS=$'\n'
        for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
            delete_subvolume_recursively "/btrfs_tmp/$i"
        done
        btrfs subvolume delete "$1"
    }

    for i in $(find /btrfs_tmp/old_roots/ -maxdepth 1 -mtime +30); do
        delete_subvolume_recursively "$i"
    done

    btrfs subvolume create /btrfs_tmp/root
    umount /btrfs_tmp
  '';
in
{
  options.disks = {
    compression = mkEnableOption "system compression";
    impermanence = mkEnableOption "impermanence (remove all files except those that are needed)";
    second-disk = {
      enable = mkEnableOption "additional disk (must be btrfs)";
      compression = mkEnableOption "compression on additional disk";
      path = mkOption {
        type = types.str;
        default = "/mnt/Games";
        example = "/home/joe/Stuff";
        description = "Path to a place where additional disk will be mounted";
      };
      subvol = mkOption {
        type = types.str;
        default = null;
        example = "games";
        description = "Which subvolume to mount";
      };
    };
    swap = {
      partition.enable = mkEnableOption "swap partition";
      file = {
        enable = mkEnableOption "swapfile";
        path = mkOption {
          type = types.str;
          default = "/var/lib/swapfile";
          example = "/var/lib/swap/swapfile";
          description = "Path to swapfile";
        };
        size = mkOption {
          type = types.int;
          default = 8 * 1024;
          example = 4 * 1024;
          description = "Size of swapfile in MB";
        };
      };
    };
    enable = mkOption {
      type = types.bool;
      default = true;
      example = false;
      description = "base disks configuration";
    };
  };

  config = mkIf cfg.enable {

    hardware.block.scheduler."nvme[0-9]*" = "none";

    environment.persistence."/persistent" = mkMerge [
      (mkIf (!cfg.impermanence) { enable = false; })
      (mkIf cfg.impermanence {
        enable = true;
        hideMounts = true;
        directories = [
          "/var/log"
          "/var/lib/bluetooth"
          "/var/lib/nixos"
          "/var/lib/systemd"
          "/etc/NetworkManager/system-connections"
          "/website"
          "/etc/nixos"
          "/etc/ssh"
          "/etc/lact"
          "/var/lib/libvirt"
          "/var/lib/flatpak"
          "/var/lib/sbctl"
          "/var/lib/waydroid"
          "/etc/waydroid-extra"
          "/var/db"
          "/var/lib/zerotier-one"
          "/var/lib/llama-cpp"
          {
            directory = "/var/lib/private";
            mode = "u=rwx,g=,o=";
          }
          {
            directory = "/etc/secrets";
            mode = "u=rwx,g=,o=";
          }
          {
            directory = "/etc/secrets/sing-box";
            user = "sing-box";
            group = "sing-box";
            mode = "u=rwx,g=rx,o=rx";
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
        ]
        ++ (lib.optionals cfg.swap.file.enable [ swap.file.path ]);
      })
    ];

    boot = mkIf cfg.impermanence {
      supportedFilesystems.btrfs = true;
      initrd = {
        supportedFilesystems.btrfs = true;
        systemd.services.impermanence_subvolume = {
          wantedBy = [
            "initrd.target"
          ];
          after = [
            "initrd-root-device.target"
          ];
          before = [
            "sysroot.mount"
          ];
          unitConfig.DefaultDependencies = "no";
          description = "Change subvolume for impermanence";
          serviceConfig.Type = "oneshot";
          script = impermanence_subvolume_script;
        };
      };
    };

    fileSystems = {

      "/" = {
        device = "/dev/disk/by-label/${if root_label == null then "nixos" else root_label}";
        fsType = "btrfs";
        neededForBoot = true;
        options = [
          "subvol=root"
          "compress-force=zstd"
        ];
      };

      "/persistent" = mkIf cfg.impermanence {
        device = "/dev/disk/by-label/${if root_label == null then "nixos" else root_label}";
        neededForBoot = true;
        fsType = "btrfs";
        options = [
          "subvol=persistent"
          "compress-force=zstd"
        ];
      };

      "/nix" = {
        device = "/dev/disk/by-label/${if root_label == null then "nixos" else root_label}";
        fsType = "btrfs";
        neededForBoot = true;
        options = [
          "subvol=nix"
          "compress-force=zstd"
        ];
      };

      "/home" = {
        device = "/dev/disk/by-label/${if root_label == null then "nixos" else root_label}";
        fsType = "btrfs";
        options = [
          "subvol=home"
          "compress-force=zstd"
          "nodev"
          "nosuid"
        ];
      };

      "/boot" = {
        device = "/dev/disk/by-label/${if boot_label == null then "boot" else boot_label}";
        fsType = "vfat";
        options = [
          "noauto"
          "x-systemd.automount"
          "fmask=0077"
          "dmask=0077"
        ];
      };

      ${cfg.second-disk.path} = mkIf cfg.second-disk.enable {
        device = "/dev/disk/by-label/${if second_label == null then "Games" else second_label}";
        fsType = "btrfs";
        options =
          optionals cfg.second-disk.compression [ "compress-force=zstd" ]
          ++ optionals (cfg.second-disk.subvol != null) [ "subvol=${cfg.second-disk.subvol}" ]
          ++ [
            "nofail"
            "noauto"
            "x-systemd.automount"
          ];
      };
    };

    swapDevices =
      optionals cfg.swap.file.enable [
        {
          device = cfg.swap.file.path;
          size = cfg.swap.file.size;
        }
      ]
      ++ optionals cfg.swap.partition.enable [
        {
          options = [ "nofail" ];
          device = "/dev/disk/by-label/${if swap_label == null then "swap" else swap_label}";
        }
      ];
  };
}
