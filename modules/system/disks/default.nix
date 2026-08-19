{
  config,
  pkgs,
  lib,
  ...
}:
let
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
      ".local/share/icons"
      ".local/share/gnupg"
      ".local/share/direnv"
      ".local/share/keyrings"
      ".local/share/easyeffects"
      ".local/share/qBittorrent"
      ".local/share/applications"
      ".config/pi"
      ".config/git"
      ".config/zen"
      ".config/wivrn"
      ".config/gtk-3.0"
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
    impermanence = lib.mkEnableOption "Impermanence (remove all files except those that are needed)";
    enable = lib.mkEnableOption "Base disks configuration";
    encryption = lib.mkEnableOption "Enable LUKS encryption for the main drive";
    ssdOptimizations = lib.mkEnableOption "Enable SSD optimizations (TRIM, bypass workqueues, etc.)";
    autoScanZfs = lib.mkEnableOption "Try to scan for zfs drives and mount to /mnt";
  };

  config = lib.mkIf cfg.enable {

    fileSystems = {
      "/boot".device = lib.mkForce "/dev/disk/by-label/BOOT";
      "/".neededForBoot = true;
      "/nix".neededForBoot = true;
      "/home".neededForBoot = true;
    }
    // lib.optionalAttrs cfg.impermanence {
      "/persist".neededForBoot = true;
    };

    hardware.block.scheduler."*" = "bfq";

    environment.persistence."/persist" = lib.mkMerge [
      (lib.mkIf (!cfg.impermanence) { enable = false; })
      (lib.mkIf cfg.impermanence {
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

    networking.hostId = "fe15f593";

    services.udev.extraRules = lib.mkIf cfg.autoScanZfs ''
      ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_TYPE}=="crypto_LUKS", RUN+="${pkgs.systemd}/bin/systemctl --no-block restart zfs-automount.service"
      ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_TYPE}=="zfs_member", RUN+="${pkgs.systemd}/bin/systemctl --no-block restart zfs-automount.service"
    '';

    systemd.services.zfs-automount = lib.mkIf cfg.autoScanZfs {
      description = "Universal LUKS & ZFS Auto-Mount Engine";
      wantedBy = [
        "graphical.target"
        "multi-user.target"
      ];
      after = [
        "local-fs.target"
        "multi-user.target"
        "graphical.target"
      ];
      unitConfig.RequiresMountsFor = "/etc/credstore";

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "zfs-automount-all" ''
          set -euo pipefail
          export PATH="/run/current-system/sw/bin:$PATH"

          for dev in /dev/disk/by-label/*-encrypted; do
            [ -e "$dev" ] || continue
            label="$(basename "$dev")"
            name="''${label%-encrypted}"

            [ "$name" = "nixos" ] && continue
            [ "$name" = "rpool" ] && continue

            key="/etc/credstore/$name.key"

            if [ -f "$key" ] && [ ! -e "/dev/mapper/$name" ]; then
              crypt_args=("--key-file" "$key")

              if [ "$(lsblk -n -d -o ROTATIONAL "$dev" 2>/dev/null)" = "0" ]; then
                crypt_args+=(
                  "--allow-discards"
                  "--perf-no_read_workqueue"
                  "--perf-no_write_workqueue"
                )
              fi

              cryptsetup open "$dev" "$name" "''${crypt_args[@]}" || true
            fi
          done

          importable_pools="$(zpool import -d /dev/mapper -d /dev/disk/by-label -d /dev/disk/by-id -d /dev 2>/dev/null | awk '/pool:/ {print $2}' || true)"

          for pool in $importable_pools; do
            [ "$pool" = "nixos" ] && continue
            [ "$pool" = "rpool" ] && continue

            zpool import -d /dev/mapper -d /dev/disk/by-label -d /dev/disk/by-id -d /dev -N -f "$pool" || true
          done

          for pool in $(zpool list -H -o name 2>/dev/null || true); do
            [ "$pool" = "nixos" ] && continue
            [ "$pool" = "rpool" ] && continue

            mkdir -p "/mnt/$pool"
            if ! mountpoint -q "/mnt/$pool"; then
              mount -t zfs "$pool/data" "/mnt/$pool" 2>/dev/null || mount -t zfs "$pool" "/mnt/$pool" 2>/dev/null || zfs mount "$pool" 2>/dev/null || true
            fi

            chmod 1777 "/mnt/$pool" 2>/dev/null || true

            ${lib.concatMapStringsSep "\n" (u: ''
              mkdir -p "/mnt/$pool/${u}"
              chown "${u}:users" "/mnt/$pool/${u}"
              chmod 0700 "/mnt/$pool/${u}"
            '') (builtins.attrNames (lib.filterAttrs (_: u: u.isNormalUser) config.users.users))}
          done
        '';
      };
    };

    boot = lib.mkMerge [
      (lib.mkIf cfg.encryption {
        initrd.luks.devices.nixos = {
          device = "/dev/disk/by-label/nixos-encrypted";
          allowDiscards = true;
          bypassWorkqueues = true;
        };
      })
      (lib.mkIf cfg.impermanence {
        initrd = {
          systemd.services.zfs-rollback = {
            wantedBy = [ "initrd.target" ];
            after = [ "zfs-import-nixos.service" ];
            before = [ "sysroot.mount" ];
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
      })
    ];

    disko.devices = {
      disk.main = {
        type = "disk";
        device = "/dev/INSTALLER_DISK_REPLACE";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                extraArgs = [
                  "-n"
                  "BOOT"
                ];
                mountOptions = [
                  "noauto"
                  "x-systemd.automount"
                  "fmask=0077"
                  "dmask=0077"
                ];
              };
            };

            root = {
              size = "100%";
              content =
                if cfg.encryption then
                  {
                    type = "luks";
                    name = "nixos";
                    extraFormatArgs = [
                      "--label"
                      "nixos-encrypted"
                    ];
                    passwordFile = "/tmp/secret.key";
                    initrdUnlock = false;
                    settings = lib.optionalAttrs cfg.ssdOptimizations {
                      allowDiscards = true;
                      bypassWorkqueues = true;
                    };
                    content = {
                      type = "zfs";
                      pool = "nixos";
                    };
                  }
                else
                  {
                    type = "zfs";
                    pool = "nixos";
                  };
            };
          };
        };
      };

      zpool.nixos = {
        type = "zpool";
        options = {
          ashift = "12";
          autotrim = if cfg.ssdOptimizations then "on" else "off";
        };
        rootFsOptions = {
          compression = "zstd";
          acltype = "posixacl";
          xattr = "sa";
          atime = "off";
          mountpoint = "none";
          normalization = "formD";
          dnodesize = "auto";
        };
        datasets = {
          root = {
            type = "zfs_fs";
            mountpoint = "/";
            options.mountpoint = "legacy";
            postCreateHook = "zfs snapshot nixos/root@blank";
          };
          nix = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options.mountpoint = "legacy";
          };
          home = {
            type = "zfs_fs";
            mountpoint = "/home";
            options.mountpoint = "legacy";
            mountOptions = [
              "nodev"
              "nosuid"
            ];
            postCreateHook = "zfs snapshot nixos/home@blank";
          };
        }
        // lib.optionalAttrs cfg.impermanence {
          persist = {
            type = "zfs_fs";
            mountpoint = "/persist";
            options.mountpoint = "legacy";
          };
        };
      };
    };
  };
}
