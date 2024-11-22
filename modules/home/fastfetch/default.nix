{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.fastfetch;
in
{
  options.fastfetch = {
    enable = mkEnableOption "Enable fastfetch config";
    zsh-start = mkEnableOption "Enable fastfetch printing when zsh starts up";
    logo-path = mkOption {
      type = types.path;
      default = ../../stuff/logo.png;
      example = ./logo.png;
      description = "Path to the logo that fastfetch will output";
    };
  };

  config = mkIf cfg.enable {
    programs.zsh.initExtra = mkIf cfg.zsh-start ''
      if ! [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
        fastfetch --logo-color-1 'cyan' --logo-color-2 'blue'
      fi
    '';
    programs.fastfetch = {
      enable = true;
      settings = {
        logo = {
          type = "kitty-direct";
          source = cfg.logo-path;
          width = 50;
          height = 20;
        };
        display = {
          separator = " ";
        };
        modules = [
          {
            type = "command";
            key = " ";
            text = "nixos.sh";
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
          #{
          #  type = "display";
          #  key = "├─󰍹";
          #  keyColor = "blue";
          #}
          {
            type = "brightness";
            key = "├─󰃞";
            keyColor = "blue";
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
          {
            type = "gamepad";
            key = "├─";
            keyColor = "blue";
          }
          {
            type = "bluetooth";
            key = "├─";
            keyColor = "blue";
          }
          {
            type = "sound";
            key = "├─";
            keyColor = "blue";
          }
          {
            type = "shell";
            key = "├─";
            keyColor = "blue";
          }
          {
            type = "de";
            key = "├─";
            keyColor = "blue";
          }
          {
            type = "wm";
            key = "├─";
            keyColor = "blue";
          }
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
