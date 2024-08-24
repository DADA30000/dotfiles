{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.amdgpu;
in
{
  options.amdgpu = {
    enable = mkEnableOption "Enable AMDGPU stuff";
    pro = mkEnableOption "Enable OpenCL and ROCm";
  };
  


  config = mkIf cfg.enable {
    hardware = {
      graphics = {
        enable = true;
        enable32Bit = true;
      };
      amdgpu = mkMerge [
        ({ initrd.enable = true; })
	(mkIf cfg.pro { opencl.enable = true; })
      ];
    };
    services.xserver.videoDrivers = [ "amdgpu" ];
    environment.variables.ROC_ENABLE_PRE_VEGA = mkIf cfg.pro "1";
  };
}
