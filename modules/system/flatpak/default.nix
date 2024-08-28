{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.flatpak;
in
{
  options.flatpak = {
    enable = mkEnableOption "Enable system flatpak";
    packages = mkOption {
      type = types.listOf (types.oneOf [ types.str types.attrs ]);
      default = [ ];
      example = [ "com.github.tchx84.Flatseal" ];
      description = "Packages to install from flatpak";
    };
  };
  


  config = mkIf cfg.enable {
    services.flatpak = {
      enable = true;
      uninstallUnmanaged = true;
      packages = cfg.packages;
      remotes = mkOptionDefault [
        { name = "sober"; location = "${./sober.flatpakrepo}"; }
      ];
      update.auto = {
        enable = true;
        onCalendar = "daily";
      };
    };
    xdg.portal = {
      enable = true;
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
      config.common.default = "*";
    };
  };
}
