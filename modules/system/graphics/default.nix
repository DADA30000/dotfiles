{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.graphics;
in
{
  options.graphics = {
    enable = mkEnableOption "graphics";
    nvidia.enable = mkEnableOption "NVIDIA specific stuff (can be used together with AMDGPU)";
    vulkan_video = mkEnableOption "experimental mesa flags for vulkan video stuff";
    amdgpu = {
      enable = mkEnableOption "some AMDGPU specific stuff (can be used together with NVIDIA)";
      pro = mkEnableOption "OpenCL and ROCm";
    };
  };

  config = mkIf cfg.enable {
    boot.extraModprobeConfig = ''
      options nvidia NVreg_DynamicPowerManagement=0x02
      options nvidia NVreg_EnableS0ixPowerManagement=1
      options nvidia NVreg_PreserveVideoMemoryAllocations=1
    '';
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
        dynamicBoost.enable = true;
        modesetting.enable = true;
        package = config.boot.kernelPackages.nvidiaPackages.beta;
        open = true;
        nvidiaSettings = false;
        powerManagement = {
          enable = true;
          finegrained = true;
        };
        prime = {
          nvidiaBusId = "PCI:64:0:0";
          amdgpuBusId = "PCI:65:0:0";
          offload = {
            enable = true;
            enableOffloadCmd = true;
          };
        };
      };
    };
    services.xserver.videoDrivers = mkMerge [
      (mkIf cfg.amdgpu.enable [ "amdgpu" ])
      (mkIf cfg.nvidia.enable [ "nvidia" ])
    ];
    environment.variables = {
      ROC_ENABLE_PRE_VEGA = mkIf (cfg.amdgpu.pro && cfg.amdgpu.enable) 1;
      RADV_PERFTEST = mkIf cfg.vulkan_video "video_decode,video_encode";
      ANV_DEBUG = mkIf cfg.vulkan_video "video-decode,video-encode";
      ANV_VIDEO_DECODE = mkIf cfg.vulkan_video 1;
      ANV_VIDEO_ENCODE = mkIf cfg.vulkan_video 1;
    };
  };
}
