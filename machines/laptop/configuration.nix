{
  user,
  pkgs,
  inputs,
  ...
}:
{
  environment.systemPackages = with pkgs; [ nvtopPackages.full ];

  security.pam.loginLimits = [{ domain = "*"; item = "memlock"; type = "-"; value = "infinity"; }];

  home-manager.users.${user} = import ./home.nix;

  networking.hostName = "laptop";

  graphics.nvidia.enable = true;

  # nix.settings = {

  #   substituters = [ "https://attic.xuyh0120.win/lantian" ];
  #   
  #   trusted-public-keys = [ "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=" ];

  # };

  virtualisation.virtualbox.host = {

    # enable = true;

    addNetworkInterface = true;

  };

  boot = {

    kernelPackages = pkgs.linuxPackagesFor inputs.nix-cachyos-kernel.packages.${pkgs.system}.linux-cachyos-latest-lto-zen4;

    lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
    };

    kernelParams = [ 
      "rd.shell=0" 
      "ttm.pages_limit=6291456"
    ];
    
    initrd = {
      luks.devices = {
        nixos = {
          device = "/dev/disk/by-label/nixos-encrypted";
          allowDiscards = true;
          bypassWorkqueues = true;
        };
        Games = {
          device = "/dev/disk/by-label/Games-encrypted";
          allowDiscards = true;
          bypassWorkqueues = true;
        };
      };
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

    searx = {
      enable = true;
      redisCreateLocally = true;
      environmentFile = "/var/lib/searx-secret";
      settings = {
        search.formats = [ "html" "json" ];
        server = {
          port = 8000;
          bind_address = "127.0.0.1";
          limiter = false;
        };
      };
    };

    open-webui = {
      enable = true;
      host = "127.0.0.1";
      port = 8080;
      environment = {
        WEBUI_AUTH = "False";
        OLLAMA_API_BASE_URL = "http://127.0.0.1:11434";
      };
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
