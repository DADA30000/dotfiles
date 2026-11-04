{
  config,
  pkgs,
  inputs,
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
    nvidia = {
      enable = mkEnableOption "NVIDIA specific stuff (can be used together with AMDGPU)";
      initrd = mkEnableOption "nvidia initrd driver";
    };
    amdgpu = {
      initrd = mkEnableOption "amdgpu initrd driver";
      pro = mkEnableOption "OpenCL and ROCm";
    };
  };

  config = mkIf cfg.enable {
    services.xserver.videoDrivers = mkIf cfg.nvidia.enable [ "nvidia" ];
    boot.initrd.kernelModules = mkIf cfg.nvidia.initrd [
      "nvidia"
      "nvidia_modeset"
      "nvidia_uvm"
      "nvidia_drm"
    ];
    hardware = {
      graphics = {
        enable = true;
        enable32Bit = true;
        extraPackages = with pkgs; [
          rocmPackages.clr
          inputs.chaotic.legacyPackages.${pkgs.stdenv.hostPlatform.system}.low-latency-layer
        ];
      };
      amdgpu = mkMerge [
        (mkIf cfg.amdgpu.initrd { initrd.enable = true; })
        (mkIf cfg.amdgpu.pro {
          opencl.enable = true;
        })
      ];
      nvidia = mkIf cfg.nvidia.enable {
        dynamicBoost.enable = true;
        package = config.boot.kernelPackages.nvidiaPackages.latest;
        modesetting.enable = true;
        open = true;
        nvidiaSettings = false;
        videoAcceleration = true;
        moduleParams.nvidia = {
          NVreg_RegistryDwords = "RmLogonRC=0x1;RmEngineContextSwitchTimeoutUs=0x01FFFFFF";
          NVreg_EnableS0ixPowerManagement = 1;
          NVreg_DynamicPowerManagementVideoMemoryThreshold = 0;
        };
        prime = {
          # Dummy values
          intelBusId = "PCI:254:0:0";
          nvidiaBusId = "PCI:255:0:0";
          offload = {
            enable = true;
            enableOffloadCmd = true;
          };
        };
        powerManagement = {
          enable = true;
          finegrained = true;
          kernelSuspendNotifier = true;
        };
      };
    };
  };
}
