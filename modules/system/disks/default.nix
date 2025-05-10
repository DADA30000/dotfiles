{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.disks;
  impermanence_subvolume_script = ''
    mkdir /btrfs_tmp
    mount -L nixos /btrfs_tmp
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
    compression = mkEnableOption "Enable system compression";
    impermanence = mkEnableOption "Enable impermanence (remove all files except those that are needed)";
    second-disk = {
      enable = mkEnableOption "Enable additional disk (must be btrfs)";
      compression = mkEnableOption "Enable compression on additional disk";
      label = mkOption {
        type = types.str;
        default = "Games";
        example = "stuff";
        description = "Filesystem label of the partition that is used for mounting";
      };
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
      file = {
        enable = mkEnableOption "Enable swapfile";
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
      partition = {
        enable = mkEnableOption "Enable swap partition";
        label = mkOption {
          type = types.str;
          default = "swap";
          example = "swappart";
          description = "Label of swap partition";
        };
      };
    };
    enable = mkOption {
      type = types.bool;
      default = true;
      example = false;
      description = "Enable base disks configuration";
    };
  };

  config = mkIf cfg.enable {

    environment.persistence."/persistent" = mkMerge [
      (mkIf (!cfg.impermanence) { enable = false; })
      (mkIf cfg.impermanence {
        enable = true;
        hideMounts = true;
        directories = [
          "/var/log"
          "/var/lib/bluetooth"
          "/var/lib/nixos"
          "/var/lib/systemd/coredump"
          "/etc/NetworkManager/system-connections"
          "/website"
          "/etc/nixos"
          "/var/lib/libvirt"
          "/var/lib/acme"
        ];
        files = [
          "/cloudflare1.conf"
          "/cloudflare2.conf"
        ] ++ lib.optionals cfg.swap.file.enable [ swap.file.path ];
      })
    ];

    boot.initrd.systemd.services.impermanence_subvolume = mkIf cfg.impermanence {
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
      #path = [ pkgs.btrfs-progs pkgs.coreutils pkgs.util-linux pkgs.mount ];
      serviceConfig.Type = "oneshot";
      script = impermanence_subvolume_script;
    };

    boot.supportedFilesystems.btrfs = mkIf cfg.impermanence true;

    boot.initrd.supportedFilesystems.btrfs = mkIf cfg.impermanence true;

    fileSystems."/" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "btrfs";
      options = [
        "subvol=root"
        "compress-force=zstd"
      ];
    };

    fileSystems."/persistent" = mkIf cfg.impermanence {
      device = "/dev/disk/by-label/nixos";
      neededForBoot = true;
      fsType = "btrfs";
      options = [
        "subvol=persistent"
        "compress-force=zstd"
      ];
    };

    fileSystems."/nix" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "btrfs";
      options = [
        "subvol=nix"
        "compress-force=zstd"
      ];
    };

    fileSystems."/home" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "btrfs";
      options = [
        "subvol=home"
        "compress-force=zstd"
      ];
    };

    fileSystems."/boot" = {
      device = "/dev/disk/by-label/boot";
      fsType = "vfat";
    };

    fileSystems."${cfg.second-disk.path}" = mkIf cfg.second-disk.enable {
      device = "/dev/disk/by-label/${cfg.second-disk.label}";
      fsType = "btrfs";
      options =
        optionals cfg.second-disk.compression [ "compress-force=zstd" ]
        ++ optionals (cfg.second-disk.subvol != null) [ "subvol=${cfg.second-disk.subvol}" ]
        ++ [ "nofail" ];
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
          device = "/dev/disk/by-label/${cfg.swap.partition.label}";
        }
      ];
  };
}
