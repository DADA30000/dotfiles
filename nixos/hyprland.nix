{ config, pkgs, inputs, lib, ... }:
{
  wayland.windowManager.hyprland = {
    enable = true;
    plugins = [ inputs.hyprland-plugins.packages.${pkgs.system}.hyprexpo ];
    package = inputs.hyprland.packages.${pkgs.system}.hyprland;
    settings = {
      "$mod" = "SUPER";
      bind = [
	", Print, exec, hyprshot -m region"
        "SHIFT, Print, exec, hyprshot -m window"
        "ALT, Print, exec, hyprshot -m output"
        "CTRL, Print, exec, hyprshot -m region -r d | swappy -f -"
        "CTRL_SHIFT, Print, exec, hyprshot -m window -r d | swappy -f -"
        "CTRL_ALT, Print, exec, hyprshot -m output -r d | swappy -f -"
	"ALT,R,submap,passthrough"
	"$mod_CTRL, Q, exec, neovide --frame none +term +startinsert '+set laststatus=0 ruler' '+set cmdheight=0' '+map <c-t> :tabnew +term<enter>'"
	"$mod_CTRL, C, exec, hyprctl kill"
	"$mod_CTRL, R, exec, killall -SIGUSR1 gpu-screen-recorder && notify-send 'GPU-Screen-Recorder' 'Повтор успешно сохранён'"
	"$mod_CTRL, F, fakefullscreen"
	"$mod_CTRL, V, exec, cliphist list | rofi -dmenu | cliphist decode | wl-copy"
        "$mod, F1, exec, gamemode.sh"
        "$mod, F2, exec, sheesh.sh"
        "$mod, O, exec, killall -SIGUSR1 .waybar-wrapped"
        "$mod, Q, exec, kitty"
        "$mod, C, killactive,"
        "$mod, M, exec, wlogout -b 2 -L 500px -R 500px -c 30px -r 30px,"
        "$mod, E, exec, nemo"
        "$mod, V, togglefloating,"
        "$mod, P, pseudo,"
        "$mod, J, togglesplit,"
        "$mod, F, exec, hyprctl dispatch fullscreen"
        "$mod, Space, hyprexpo:expo, toggle"
        "$mod, left, movefocus, l"
        "$mod, right, movefocus, r"
        "$mod, up, movefocus, u"
        "$mod, down, movefocus, d"
        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod, 6, workspace, 6"
        "$mod, 7, workspace, 7"
        "$mod, 8, workspace, 8"
        "$mod, 9, workspace, 9"
        "$mod, 0, workspace, 10"
        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
        "$mod SHIFT, 6, movetoworkspace, 6"
        "$mod SHIFT, 7, movetoworkspace, 7"
        "$mod SHIFT, 8, movetoworkspace, 8"
        "$mod SHIFT, 9, movetoworkspace, 9"
        "$mod SHIFT, 0, movetoworkspace, 10"
        "$mod, S, togglespecialworkspace, magic"
        "$mod SHIFT, S, movetoworkspace, special:magic"
        "$mod, mouse_down, workspace, e+1"
        "$mod, mouse_up, workspace, e-1"
      ];
      bindr = [
 	"$mod, $mod_L, exec, pkill rofi || $(rofi -show drun -show-icons)"
        "$mod_CTRL, $mod_L, exec, pkill rofi || $(rofi -show run)"
      ];
      bindm = [
        "$mod, mouse:272, movewindow"
	"$mod, mouse:273, resizewindow"
      ];
      windowrule = [
        "pin, ^(polkit-gnome-authentication-agent-1)$"
	"opacity 0.99 override 0.99 override, title:^(MainPicker)$"
      ];
      layerrule = [
	"blur, waybar"
        "blur, rofi"
        "blur, wofi"
        "blur, launcher"
        "blur, logout_dialog"
        "blur, notifications"
        "blur, gtk-layer-shell"
        "blur, swaync-control-center"
        "blur, swaync-notification-window"
	"blur, .*"
	"blurpopups, .*"
	"noanim, selection"
	"ignorealpha 0.9, selection"
	"ignorezero, corner0"
	"ignorezero, overview"
	"ignorezero, indicator0"
	"ignorezero, datemenu"
	"ignorezero, launcher"
	"ignorezero, quicksettings"
	"ignorezero, swaync-control-center"
        "ignorezero, rofi"
	"ignorezero, waybar"
        "ignorezero, swaync-notification-window"
        "animation popin 90%, rofi"
	"animation popin 90%, logout_dialog"
        "animation slide left, swaync-control-center"
      ];  
      exec-once = [
        "killall screen; ~/bot/start-bot.sh"
        "firefox & vesktop --enable-blink-features=MiddleClickAutoscroll"
        "sleep 10; gpu-screen-recorder -w screen -q ultra -a $(pactl get-default-sink).monitor -a $(pactl get-default-source) -f 60 -r 300 -c mp4 -o ~/Games/Replays"
        "wl-paste --type text --watch cliphist store"
        "wl-paste --type image --watch cliphist store"
	"hyprctl setcursor Bibata-Modern-Classic 24"
      ]; 
      input = {
	kb_layout = "us,ru";
        kb_options = "grp:alt_shift_toggle";
        repeat_delay = 200;
        follow_mouse = 1;
        touchpad = { natural_scroll = false; };
        sensitivity = 1;
        accel_profile = "flat";
      };
      general = {
        gaps_in = 5;
        gaps_out = 5;
        border_size = 0;
        "col.active_border" = "rgb(4575da) rgb(6804b5)";
        "col.inactive_border" = "rgb(595959)";
        layout = "dwindle";
        allow_tearing = false;
      };
      decoration = {
        rounding = 10;
        blur = {
          enabled = true;
      	  popups = true;
      	  popups_ignorealpha = 0;
      	  ignore_opacity = true;
          size = 10;
      	  brightness = 0.8;
          passes = 3;
          noise = 0;
          vibrancy = 0;
        };
        drop_shadow = "yes";
        shadow_range = 4;
        shadow_render_power = 3;
        "col.shadow" = "rgba(1a1a1aee)";
      };
      animations = {
        enabled = true;
        first_launch_animation = true;
      	bezier = [
	  "fade, 0.165, 0.84, 0.44, 1"
	  "woosh, 0.445, 0.05, 0, 1"
	];
        animation = [ 
	  "windowsMove, 1, 5, default"
          "windowsIn, 1, 2, fade, popin 90%"
          "windows, 1, 7, default, slide"
          "windowsOut, 1, 3, fade, popin 90%"
          "fadeSwitch, 1, 7, default"
          "fadeOut, 1, 3, fade"
          "workspaces, 1, 4, woosh, slide"
	  "layers, 1, 3, fade, popin 90%"
	];
      };
      debug = {
        enable_stdout_logs = false;
        disable_logs = true;
      };
      dwindle = {
        pseudotile = true;
        preserve_split = true;
      };
      gestures = {
        workspace_swipe = true;
      };
      misc = {
        enable_swallow = true;
        animate_manual_resizes = false;
        animate_mouse_windowdragging = false;
        swallow_regex = "^(kitty|lutris|bottles|alacritty)$";
        swallow_exception_regex = "^(ncspot)$";
        force_default_wallpaper = 2;
      };
      binds = {
        scroll_event_delay = 50;
      };
      plugin = {
        hyprexpo = {
          columns = 3;
          gap_size = 5;
          bg_col = "rgb(111111)";
          workspace_method = "first 1";
          enable_gesture = true;
          gesture_distance = 300;
          gesture_positive = true;
        };
      };
    };
    extraConfig = ''
      submap=passthrough
        bind=,escape,submap,reset
      submap=reset      
    '';
  };
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
    enable = true;
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
