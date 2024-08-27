{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.btop;
in
{
  options.btop = {
    enable = mkEnableOption "Enable btop process manager";
  };
  


  config = mkIf cfg.enable {
    programs.btop = {
      enable = true;
      settings = {
        color_theme = "${pkgs.btop}/share/btop/themes/dracula.theme";
        update_ms = 200;
        theme_background = false;
      };
    };
  };
}
