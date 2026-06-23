{
  user,
  pkgs,
  inputs,
  config,
  lib,
  ...
}:
let
  gigabyte-laptop-wmi = pkgs.stdenv.mkDerivation {
    pname = "aorus-laptop";
    version = inputs.gigabyte-laptop-wmi.shortRev;

    src = inputs.gigabyte-laptop-wmi;

    makeFlags = [
      "KDIR=${config.boot.kernelPackages.kernel.dev}/lib/modules/${config.boot.kernelPackages.kernel.modDirVersion}/build"
    ];

    installPhase = ''
      dir=$out/lib/modules/${config.boot.kernelPackages.kernel.modDirVersion}/kernel/drivers/platform/x86
      mkdir -p $dir
      cp aorus-laptop.ko $dir/
    '';

  };
in
{

  fileSystems.${config.disks.second-disk.path}.options = [
    "x-systemd.requires=systemd-cryptsetup@Games.service"
  ];

  home-manager.users.${user} = import ./home.nix;

  networking.hostName = "laptop";

  graphics.nvidia.enable = true;

  amd-ai.enable = false;

  my-services = {

    cloudflare-ddns.enable = true;

    nginx = {
      enable = true;
      website.enable = true;
    };

  };

  environment = {

    systemPackages = with pkgs; [ nvtopPackages.full ];

    etc."crypttab".text = ''
      Games /dev/disk/by-label/Games-encrypted /etc/secrets/games.key luks,discard,no-read-workqueue,no-write-workqueue,noauto
    '';

  };

  systemd.services.load-aorus-laptop = {
    description = "Load Gigabyte Aorus Laptop driver asynchronously";
    after = [ "basic.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.kmod}/bin/modprobe aorus_laptop";
      RemainAfterExit = true;
    };
  };

  boot = {

    extraModulePackages = [ gigabyte-laptop-wmi ];

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

  services = {

    fwupd.enable = true;

    snapper.configs.ATM10 = {
      SUBVOLUME = "/home/${user}/Documents/ATM10";
      TIMELINE_CLEANUP = true;
      TIMELINE_CREATE = true;
      TIMELINE_LIMIT_WEEKLY = 4;
      TIMELINE_LIMIT_DAILY = 7;
      TIMELINE_LIMIT_HOURLY = 24;
    };

    tlp = {
      enable = true;
      pd.enable = true;
      settings = {
        CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
        PLATFORM_PROFILE_ON_AC = "performance";
        CPU_ENERGY_PERF_POLICY_ON_SAV = "power";
        CPU_BOOST_ON_SAV = 0;
        PLATFORM_PROFILE_ON_SAV = "low-power";
        CPU_DRIVER_OPMODE_ON_AC = "active";
        CPU_DRIVER_OPMODE_ON_BAT = "active";
        CPU_DRIVER_OPMODE_ON_SAV = "active";
        CPU_SCALING_GOVERNOR_ON_AC = "performance";
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
        CPU_SCALING_GOVERNOR_ON_SAV = "powersave";
        CPU_ENERGY_PERF_POLICY_ON_BAT = "powersave";
        CPU_BOOST_ON_AC = 1;
        CPU_BOOST_ON_BAT = 1;
        PLATFORM_PROFILE_ON_BAT = "low-power";
        AMDGPU_ABM_LEVEL_ON_AC = 0;
        AMDGPU_ABM_LEVEL_ON_BAT = 0;
        AMDGPU_ABM_LEVEL_ON_SAV = 0;
        PCIE_ASPM_ON_AC = "default";
        PCIE_ASPM_ON_BAT = "powersupersave";
        RUNTIME_PM_ON_AC = "on";
        RUNTIME_PM_ON_BAT = "auto";
        NMI_WATCHDOG = 0;
        WIFI_PWR_ON_AC = "off";
        WIFI_PWR_ON_BAT = "on";
      };
    };

  };

}
