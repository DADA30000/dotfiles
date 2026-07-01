{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.fastfetch;
in
{
  options.fastfetch = {
    enable = mkEnableOption "fastfetch config";
    zsh-start = mkEnableOption "fastfetch printing when zsh starts up";
    logo-path = mkOption {
      type = types.path;
      defaultText = "../../../stuff/modules/home/fastfetch/logo_fill.txt";
      default = ../../../stuff/modules/home/fastfetch/logo_fill.txt;
      example = "./logo_fill.txt";
      description = "Path to the logo that fastfetch will output";
    };
  };

  config = mkIf cfg.enable {
    programs.zsh.initContent = mkIf cfg.zsh-start "fastfetch";
    programs.fastfetch = {
      enable = true;
      package = pkgs.symlinkJoin {
        name = "fastfetch";
        paths = [ pkgs.fastfetch ];
        buildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/fastfetch \
            --unset DISPLAY \
            --unset WAYLAND_DISPLAY
        '';
      };
      settings = {
        logo = {
          type = "raw";
          source = cfg.logo-path;
          width = 55;
          height = 20;
          padding.top = 1;
        };
        display = {
          separator = " ";
        };
        modules = [
          {
            type = "command";
            key = " ";
            text = "nixos.sh 1";
          }
          {
            type = "command";
            key = " ";
            text = "nixos.sh 2";
          }
          {
            type = "command";
            key = " ";
            text = "nixos.sh 3";
          }
          {
            type = "command";
            key = " ";
            text = "nixos.sh 4";
          }
          "break"
          {
            type = "cpu";
            key = "╭─";
            keyColor = "blue";
          }
          {
            type = "gpu";
            key = "├─󰢮";
            keyColor = "blue";
          }
          {
            type = "disk";
            key = "├─";
            keyColor = "blue";
          }
          {
            type = "memory";
            key = "├─󰑭";
            keyColor = "blue";
          }
          {
            type = "swap";
            key = "├─󰓡";
            keyColor = "blue";
          }
          {
            type = "display";
            key = "├─󰍹";
            keyColor = "blue";
          }
          {
            type = "brightness";
            key = "├─󰃞";
            keyColor = "blue";
            ddcciSleep = null;
          }
          {
            type = "battery";
            key = "├─";
            keyColor = "blue";
          }
          {
            type = "poweradapter";
            key = "├─";
            keyColor = "blue";
          }
          # {
          #   type = "gamepad";
          #   key = "├─";
          #   keyColor = "blue";
          # }
          {
            type = "bluetooth";
            key = "├─";
            keyColor = "blue";
          }
          # {
          #   type = "sound";
          #   key = "├─";
          #   keyColor = "blue";
          # }
          # {
          #   type = "shell";
          #   key = "├─";
          #   keyColor = "blue";
          # }
          # {
          #   type = "de";
          #   key = "├─";
          #   keyColor = "blue";
          # }
          # {
          #   type = "wm";
          #   key = "├─";
          #   keyColor = "blue";
          # }
          {
            type = "os";
            key = "├─";
            keyColor = "blue";
          }
          {
            type = "kernel";
            key = "├─";
            format = "{1} {2}";
            keyColor = "blue";
          }
          {
            type = "uptime";
            key = "╰─󰅐";
            keyColor = "blue";
          }
        ];
      };
    };
  };
}
