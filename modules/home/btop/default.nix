{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
with lib;
let
  package = (pkgs.btop.override { cudaSupport = true; }).overrideAttrs {
    src = inputs.btop;
  };
  cfg = config.btop;
in
{
  options.btop = {
    enable = mkEnableOption "btop process manager";
  };

  config = mkIf cfg.enable {
    programs.btop = {
      enable = true;
      package = package;
      settings = {
        color_theme = "${package}/share/btop/themes/dracula.theme";
        update_ms = 200;
        theme_background = false;
      };
    };
  };
}
