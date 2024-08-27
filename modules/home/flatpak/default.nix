{ config, lib, pkgs, inputs, ... }:
with lib;
let
  cfg = config.flatpak;
in
{
  options.flatpak = {
    enable = mkEnableOption "Enable user flatpak";
    packages = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "com.github.tchx84.Flatseal" ];
      description = "Packages to install from flatpak";
    };
  };
  

  imports = [
    inputs.nix-flatpak.homeManagerModules.nix-flatpak
  ];
  config = mkIf cfg.enable {
    xdg.portal = {
      enable = true;
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
      config.common.default = "*";
    };
    services.flatpak = {
      enable = true;
      uninstallUnmanaged = true;
      packages = cfg.packages;
      update.auto = {
        enable = true;
        onCalendar = "daily";
      };
    };
  };
}
