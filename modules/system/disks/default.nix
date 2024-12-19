{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.disks;
in
{
  options.disks = {
    compression = mkEnableOption "Enable system compression";
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
    fileSystems."/" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "btrfs";
      options = [
        "subvol=root"
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
