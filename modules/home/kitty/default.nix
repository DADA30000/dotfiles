{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.kitty;
in
{
  options.kitty = {
    enable = mkEnableOption "kitty terminal emulator";
  };

  config = mkIf cfg.enable {
    programs.kitty = {
      enable = true;
      shellIntegration.enableZshIntegration = true;
      font = {
        name = "JetBrainsMono NF Medium";
        size = 12;
      };
      package = pkgs.symlinkJoin {
        name = "kitty-wrapped";
        paths = [ pkgs.kitty ];
        buildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/kitty \
            --add-flags "--single-instance"
        '';
      };
      keybindings = {
        "ctrl+left" = "neighboring_window left";
        "ctrl+up" = "neighboring_window up";
        "ctrl+right" = "neighboring_window right";
        "ctrl+down" = "neighboring_window down";
        "shift+left" = "move_window left";
        "shift+up" = "move_window up";
        "shift+right" = "move_window right";
        "shift+down" = "move_window down";
      };
      extraConfig = builtins.readFile ../../../stuff/home/kitty/kitty.conf;
    };
  };
}
