{
  user,
  pkgs,
  inputs,
  config,
  ...
}:
let
  nv-blindfold-pkg = pkgs.stdenv.mkDerivation {
    name = "nv-blindfold";
    src = pkgs.writeText "nv-blindfold.c" (builtins.readFile ../../stuff/nv-blindfold.c);
    unpackPhase = "true";
    buildPhase = ''
      gcc -O2 $src -o nv-blindfold
    '';
    installPhase = ''
      mkdir -p $out/bin
      cp nv-blindfold $out/bin/
    '';
  };
  fan-control-pkg = pkgs.stdenv.mkDerivation {
    name = "fan-control";
    src = pkgs.writeText "fan-control.c" (builtins.readFile ../../stuff/fan-control.c);
    unpackPhase = "true";
    buildPhase = "gcc -O2 $src -o fan-control";
    installPhase = "mkdir -p $out/bin && cp fan-control $out/bin/";
  };
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

  graphics = {
    nvidia.enable = true;
    amdgpu.pro = true;
  };

  amd-ai.enable = true;

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

  security.wrappers = {
    nv-blindfold = {
      setuid = true;
      owner = "root";
      group = "root";
      source = "${nv-blindfold-pkg}/bin/nv-blindfold";
    };
    fan-control = {
      setuid = true;
      owner = "root";
      group = "root";
      source = "${fan-control-pkg}/bin/fan-control";
    };
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
        CPU_DRIVER_OPMODE_ON_AC = "active";
        CPU_SCALING_GOVERNOR_ON_AC = "performance";
        CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
        CPU_BOOST_ON_AC = 1;
        PLATFORM_PROFILE_ON_AC = "performance";
        AMDGPU_ABM_LEVEL_ON_AC = 0;
        PCIE_ASPM_ON_AC = "default";
        RUNTIME_PM_ON_AC = "on";
        WIFI_PWR_ON_AC = "off";
        CPU_DRIVER_OPMODE_ON_BAT = "active";
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
        CPU_ENERGY_PERF_POLICY_ON_BAT = "balance_power";
        CPU_BOOST_ON_BAT = 1;
        PLATFORM_PROFILE_ON_BAT = "low-power";
        AMDGPU_ABM_LEVEL_ON_BAT = 0;
        PCIE_ASPM_ON_BAT = "powersupersave";
        RUNTIME_PM_ON_BAT = "auto";
        WIFI_PWR_ON_BAT = "on";
        CPU_DRIVER_OPMODE_ON_SAV = "active";
        CPU_SCALING_GOVERNOR_ON_SAV = "powersave";
        CPU_ENERGY_PERF_POLICY_ON_SAV = "power";
        CPU_BOOST_ON_SAV = 0;
        CPU_HWP_DYN_BOOST_ON_SAV = 0;
        PLATFORM_PROFILE_ON_SAV = "low-power";
        CPU_MIN_PERF_ON_SAV = 0;
        CPU_MAX_PERF_ON_SAV = 1;
        AMDGPU_ABM_LEVEL_ON_SAV = 0;
        NMI_WATCHDOG = 0;
        SOUND_POWER_SAVE_ON_AC = 0;
        SOUND_POWER_SAVE_ON_BAT = 1;
        SOUND_POWER_SAVE_CONTROLLER = "Y";
        USB_AUTOSUSPEND = 1;
        USB_EXCLUDE_AUDIO = 0; # Allows idle USB audio devices to sleep
      };
    };

  };

}
