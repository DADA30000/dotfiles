{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.graphics;
in
{
  options.graphics = {
    enable = mkEnableOption "Enable graphics";
    nvidia.enable = mkEnableOption "Enable NVIDIA specific stuff (can be used together with AMDGPU)";
    amdgpu = {
      enable = mkEnableOption "Enable some AMDGPU specific stuff (can be used together with NVIDIA)";
      pro = mkEnableOption "Enable OpenCL and ROCm";
    };
  };

  config = mkIf cfg.enable {
    hardware = {
      graphics = {
        enable = true;
        enable32Bit = true;
      };
      amdgpu = mkMerge [
        (mkIf cfg.amdgpu.enable { initrd.enable = true; })
        (mkIf cfg.amdgpu.pro { opencl.enable = true; })
      ];
      nvidia = mkIf cfg.nvidia.enable {
        modesetting.enable = true;
        powerManagement.enable = true;
        open = false;
        nvidiaSettings = false;
        package = config.boot.kernelPackages.nvidiaPackages.beta;
      };
    };
    services.xserver.videoDrivers = mkMerge [
      (mkIf cfg.nvidia.enable [ "nvidia" ])
      (mkIf cfg.amdgpu.enable [ "amdgpu" ])
    ];
    environment.variables.ROC_ENABLE_PRE_VEGA = mkIf (cfg.amdgpu.pro && cfg.amdgpu.enable) "1";
  };
}
