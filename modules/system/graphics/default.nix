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
    enable = mkEnableOption "Enable graphics";
    nvidia.enable = mkEnableOption "Enable NVIDIA specific stuff (can be used together with AMDGPU)";
    vulkan_video = mkEnableOption "Enable experimental mesa flags for vulkan video stuff";
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
        (mkIf cfg.amdgpu.enable { initrd.enable = false; })
        (mkIf cfg.amdgpu.pro { opencl.enable = true; })
      ];
      nvidia = mkIf cfg.nvidia.enable {
        modesetting.enable = true;
        powerManagement.enable = true;
        open = true;
        nvidiaSettings = true;
        #package = config.boot.kernelPackages.nvidiaPackages.beta;
      };
    };
    services.xserver.videoDrivers = mkMerge [
      (mkIf cfg.nvidia.enable [ "nvidia" ])
      (mkIf cfg.amdgpu.enable [ "amdgpu" ])
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
