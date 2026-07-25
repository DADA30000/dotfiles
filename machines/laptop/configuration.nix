{
  user,
  ...
}:
{

  networking.hostName = "laptop";

  graphics.nvidia.enable = true;

  amd-ai.enable = true;

  environment.etc.crypttab.text = ''
    Games /dev/disk/by-label/Games-encrypted /etc/credstore/games.key luks,discard,no-read-workqueue,no-write-workqueue,noauto
    Games2 /dev/disk/by-label/Games2-encrypted /etc/credstore/games2.key luks,noauto
  '';

  my-services = {

    cloudflare-ddns.enable = true;

    nginx = {
      enable = true;
      website.enable = true;
    };

  };

  home-manager = {

    users.${user} = import ./home.nix;

    sharedModules = [
      ({ lib, ... }: {
        home.activation.prepare-games = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          mkdir -p "$HOME/Games" "$HOME/Games2"
        '';
      })
    ];

  };

  boot = {

    lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
    };

    kernelParams = [
      "rd.shell=0"
      "ttm.pages_limit=6291456"
    ];

    initrd.luks.devices.nixos = {
      device = "/dev/disk/by-label/nixos-encrypted";
      allowDiscards = true;
      bypassWorkqueues = true;
    };

  };

  fileSystems = {

    "/home/${user}/Games" = {
      device = "/dev/disk/by-label/Games";
      fsType = "btrfs";
      options = [
        "subvol=games"
        "compress-force=zstd"
        "nofail"
        "noauto"
        "x-systemd.automount"
        "x-systemd.requires=systemd-cryptsetup@Games.service"
      ];
    };

    "/home/${user}/Games2" = {
      device = "/dev/disk/by-label/Games2";
      fsType = "btrfs";
      options = [
        "subvol=games"
        "compress-force=zstd"
        "nofail"
        "noauto"
        "x-systemd.automount"
        "x-systemd.requires=systemd-cryptsetup@Games2.service"
      ];
    };

  };

  services = {
    snapper.configs.snapshots = {
      SUBVOLUME = "/home/${user}/Documents/snapshots";
      ALLOW_USERS = [ user ];
      TIMELINE_CLEANUP = true;
      TIMELINE_CREATE = true;
      TIMELINE_LIMIT_WEEKLY = 4;
      TIMELINE_LIMIT_DAILY = 7;
      TIMELINE_LIMIT_HOURLY = 24;
    };
    #beesd.filesystems = {
    #  root = {
    #    spec = "/persistent";
    #    hashTableSizeMB = 512;
    #    verbosity = "crit";
    #    extraOptions = [
    #      "--loadavg-target"
    #      "4.0"
    #    ];
    #  };

    #  games = {
    #    spec = "/home/${user}/Games";
    #    hashTableSizeMB = 512;
    #    verbosity = "crit";
    #    extraOptions = [
    #      "--loadavg-target"
    #      "4.0"
    #    ];
    #  };

    #  games2 = {
    #    spec = "/home/${user}/Games2";
    #    hashTableSizeMB = 1024;
    #    verbosity = "crit";
    #    extraOptions = [
    #      "--loadavg-target"
    #      "3.0"
    #    ];
    #  };
    #};
  };

}
