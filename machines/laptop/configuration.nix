{
  user,
  config,
  pkgs,
  lib,
  ...
}:
{
  networking.hostId = "fe15f593";
  graphics.nvidia.enable = true;
  amd-ai.enable = true;
  nix-mineral.settings.kernel.intel-iommu = false;
  home-manager.users.${user} = import ./home.nix;

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_TYPE}=="crypto_LUKS", RUN+="${pkgs.systemd}/bin/systemctl --no-block restart zfs-automount.service"
    ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_TYPE}=="zfs_member", RUN+="${pkgs.systemd}/bin/systemctl --no-block restart zfs-automount.service"
  '';

  my-services = {
    cloudflare-ddns.enable = true;
    nginx = {
      enable = true;
      website.enable = true;
    };
  };

  boot = {
    supportedFilesystems.zfs = true;
    lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
    };
    kernelParams = [
      "rd.shell=0"
      "ttm.pages_limit=6291456"
      "zfs.spa_slop_shift=8"
      "zfs.zfs_arc_max=4294967296"
    ];
    initrd = {
      supportedFilesystems.zfs = true;
      luks.devices.nixos = {
        device = "/dev/disk/by-label/nixos-encrypted";
        allowDiscards = true;
        bypassWorkqueues = true;
      };
    };
  };

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "zfs-eject" ''
      set -euo pipefail
      POOL="''${1:-}"
      if [ -z "$POOL" ]; then
        echo "Usage: sudo zfs-eject <pool-name>"
        exit 1
      fi

      echo "Ejecting pool: $POOL..."

      for mp in $(zfs list -H -o mountpoint -r "$POOL" 2>/dev/null || true); do
        if [ -n "$mp" ] && [ "$mp" != "none" ] && [ "$mp" != "legacy" ] && mountpoint -q "$mp" 2>/dev/null; then
          umount "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null || true
        fi
      done
      if mountpoint -q "/mnt/$POOL" 2>/dev/null; then
        umount "/mnt/$POOL" 2>/dev/null || umount -l "/mnt/$POOL" 2>/dev/null || true
      fi

      if zpool list "$POOL" >/dev/null 2>&1; then
        zpool export "$POOL"
      fi

      if [ -e "/dev/mapper/$POOL" ]; then
        cryptsetup close "$POOL"
      fi

      echo "Successfully and safely ejected $POOL. You can now pull the cable."
    '')
  ];

  systemd.services.zfs-automount = {
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

    path = [
      pkgs.cryptsetup
      pkgs.zfs
      pkgs.util-linux
      pkgs.systemd
      pkgs.coreutils
      pkgs.gawk
    ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "zfs-automount-all" ''
        set -euo pipefail

        for dev in /dev/disk/by-label/*-encrypted; do
          [ -e "$dev" ] || continue
          label="$(basename "$dev")"
          name="''${label%-encrypted}"

          [ "$name" = "nixos" ] && continue
          [ "$name" = "rpool" ] && continue

          key="/etc/credstore/$name.key"

          if [ -f "$key" ] && [ ! -e "/dev/mapper/$name" ]; then
            cryptsetup open "$dev" "$name" \
              --key-file "$key" \
              --allow-discards \
              --perf-no_read_workqueue \
              --perf-no_write_workqueue || true
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
}
