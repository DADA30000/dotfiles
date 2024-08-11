{ config, pkgs, inputs, lib, ... }:
{
  programs.hyprlock = {
    enable = true;
    settings = {
      background = [
      {
          monitor = "";
          color = "rgba(0, 0, 0, 0.7)";
      }];
      
      input-field = [
      {
          monitor = "";
          size = "200, 50";
          outline_thickness = 1;
          dots_size = 0.2;
          dots_spacing = 0.15;
          dots_center = true;
          outer_color = "rgb(000000)";
          inner_color = "rgb(100, 100, 100)";
          font_color = "rgb(10, 10, 10)";
          fade_on_empty = true;
          placeholder_text = "<i>Введите пароль...</i>";
          hide_input = false;
          position = "0, -20";
          halign = "center";
          valign = "center";
      }];
      
      label = [ 
      {
          monitor = "";
          text = "Введите пароль от пользователя $USER $TIME $ATTEMPTS";
          color = "rgba(200, 200, 200, 1.0)";
          font_size = 25;
          font_family = "Noto Sans";
      
          position = "0, 200";
          halign = "center";
          valign = "center";
      }];
    };
  };
  services.hyprpaper = {
    enable = false;
    settings = {
      ipc = "on";
      splash = false;
      preload = [ "${./stuff/wallpaper.jpg}" ];
      wallpaper = [
        "HDMI-A-1,${./stuff/wallpaper.jpg}"
      ];
    };
  };
  programs.rofi = {
    enable = true;
    package = pkgs.rofi-wayland;
    font = "JetBrainsMono NF 14";
    theme = ./stuff/theme.rasi;
  };
  programs.wlogout = {
    enable = true;
    layout = [
      {
          label = "lock";
          action = "hyprlock";
          text = "Lock";
          keybind = "l";
      }
      {
          label = "logout";
          action = "hyprctl dispatch exit";
          text = "Logout";
          keybind = "e";
      }
      {
          label = "shutdown";
          action = "systemctl poweroff";
          text = "Shutdown";
          keybind = "s";
      }
      {
          label = "reboot";
          action = "systemctl reboot";
          text = "Reboot";
          keybind = "r";
      }
    ];
    style = ''
      * {
      	background-image: none;
      	font-family: "JetBrainsMono Nerd Font";
      	font-size: 16px;
      }
      window {
      	background-color: rgba(0, 0, 0, 0);
      }
      button {
          color: #FFFFFF;
              border-style: solid;
      	border-radius: 15px;
      	border-width: 3px;
      	background-color: rgba(0, 0, 0, 0);
      	background-repeat: no-repeat;
      	background-position: center;
      	background-size: 25%;
      }
      
      button:focus, button:active, button:hover {
      	background-color: rgba(0, 0, 0, 0);
      	color: #4470D2;
      }
      
      #lock {
          background-image: image(url("${./stuff/lock.png}"));
      }
      
      #logout {
          background-image: image(url("${./stuff/logout.png}"));
      }
      
      #shutdown {
          background-image: image(url("${./stuff/shutdown.png}"));
      }
      
      #reboot {
          background-image: image(url("${./stuff/reboot.png}"));
      }
    '';
  };  
}
