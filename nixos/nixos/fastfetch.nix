{ pkgs, config, ... }:
{
  programs.fastfetch = {
    enable = true;
    settings =
  {
      logo = {
          type = "kitty-direct";
          source = ./stuff/logo.png;
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
          {
              type = "display";
              key = "├─󰍹";
              keyColor = "blue";
          }
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
}
