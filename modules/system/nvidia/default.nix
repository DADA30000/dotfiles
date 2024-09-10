{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.nvidia;
in
{
  options.nvidia = {
    enable = mkEnableOption "Enable nvidia stuff";
  };
  

  config = mkIf cfg.enable {
    services.xserver.videoDrivers = ["nvidia"];
    hardware = {
      graphics = {
        enable = true;
        enable32Bit = true;
      };
      nvidia = {
        modesetting.enable = true;
        powerManagement.enable = true;
        open = false;
        nvidiaSettings = false;
        package = config.boot.kernelPackages.nvidiaPackages.beta;
      };
    };
  };
}
