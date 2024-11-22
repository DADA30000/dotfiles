{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.cava;
in
{
  options.cava = {
    enable = mkEnableOption "Enable cava audio visualizer";
  };

  config = mkIf cfg.enable {
    programs.cava = {
      enable = true;
      settings = {
        general = {
          framerate = 60;
          bar_width = 4;
        };
        color = {
          gradient = 1;
          gradient_count = 2;
          gradient_color_1 = "'#4575da'";
          gradient_color_2 = "'#6804b5'";
        };
        smoothing = {
          noise_reduction = 50;
        };
      };
    };
  };
}
