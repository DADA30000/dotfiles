{
  user,
  config,
  ...
}:
{

  fileSystems.${config.disks.second-disk.path}.options = [
    "x-systemd.requires=systemd-cryptsetup@Games.service"
  ];

  home-manager.users.${user} = import ./home.nix;

  networking.hostName = "laptop";

  graphics.nvidia.enable = true;

  amd-ai.enable = true;

  my-services = {

    cloudflare-ddns.enable = true;

    nginx = {
      enable = true;
      website.enable = true;
    };

  };

  environment.etc."crypttab".text = ''
    Games /dev/disk/by-label/Games-encrypted /etc/secrets/games.key luks,discard,no-read-workqueue,no-write-workqueue,noauto
  '';

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

  services.snapper.configs.ATM10 = {
    SUBVOLUME = "/home/${user}/Documents/ATM10";
    TIMELINE_CLEANUP = true;
    TIMELINE_CREATE = true;
    TIMELINE_LIMIT_WEEKLY = 4;
    TIMELINE_LIMIT_DAILY = 7;
    TIMELINE_LIMIT_HOURLY = 24;
  };

}
