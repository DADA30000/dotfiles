{
  user,
  ...
}:
{
  security.pam.loginLimits = [{ domain = "*"; item = "memlock"; type = "-"; value = "infinity"; }];

  home-manager.users.${user} = import ./home.nix;

  networking.hostName = "laptop";

  graphics.nvidia.enable = true;

  virtualisation.virtualbox.host = {

    enable = true;

    addNetworkInterface = true;

  };

  boot = {
  
    lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
    };

    kernelParams = [ 
      "rd.shell=0" 
      "amdgpu.gttsize=24576" 
    ];
    
    initrd.luks.devices.nixos = {
      device = "/dev/disk/by-label/nixos-encrypted";
      allowDiscards = true;
      bypassWorkqueues = true;
    };

  };

  services = {

    fwupd.enable = true;

    tlp = {
      enable = true;
      pd.enable = true;
    };

  };

}
