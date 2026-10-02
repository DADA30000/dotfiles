{
  user,
  ...
}:
{
  graphics.nvidia.enable = true;
  amd-ai.enable = false;
  nix-mineral.settings.kernel.intel-iommu = false;

  home-manager.users = {
    ${user} = import ./home.nix;
    guest = import ./home.nix;
  };

  # Rebinding that special GIMATE key on my laptop to a useful sysrq/print key.
  services.udev.extraHwdb = ''
    evdev:input:b0003v*
     KEYBOARD_KEY_70067=sysrq
  '';

  disks = {
    encryption = true;
    ssdOptimizations = true;
    autoScanZfs = true;
  };

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
    ];
  };

}
