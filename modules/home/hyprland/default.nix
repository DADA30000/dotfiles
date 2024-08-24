{ config, pkgs, inputs, lib, ... }:
with lib;
let
  cfg = config.hyprland;
in
{
  options.hyprland = {
    enable = mkEnableOption "Enable my Hyprland configuration";
    stable = mkEnableOption "Whether to use release from nixpkgs, or use latest git";
    enable-plugins = mkEnableOption "Enable Hyprland plugins";
  };
  
  

  config = mkIf cfg.enable {
    wayland.windowManager.hyprland = {
      package = mkIf (!cfg.stable) inputs.hyprland.packages.${pkgs.system}.hyprland;
      plugins = lib.optionals (cfg.enable-plugins && cfg.stable) [ pkgs.hyprlandPlugins.hypr-dynamic-cursors ] ++ lib.optionals (cfg.enable-plugins && !cfg.stable) [ inputs.hypr-dynamic-cursors.packages.${pkgs.system}.hypr-dynamic-cursors ];
      enable = true;
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
          "$mod_CTRL, U, exec, update-damn-nixos ${config.home.username}"
          "$mod_CTRL, V, exec, cliphist list | rofi -dmenu -hover-select -me-select-entry '' -me-accept-entry MousePrimary | cliphist decode | wl-copy"
          "$mod_ALT, mouse_down, exec, hyprctl keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor | grep float | awk '{print $2 + 1}')"
          "$mod_ALT, mouse_up, exec, hyprctl keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor | grep float | awk '{print $2 - 1}')"
          "$mod_CTRL, mouse_down, exec, hyprctl keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor | grep float | awk '{print $2 + 100}')"
          "$mod_CTRL, mouse_up, exec, hyprctl keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor | grep float | awk '{print $2 - 100}')"
          "$mod, F1, exec, gamemode.sh"
          "$mod, F2, exec, sheesh.sh"
          "$mod, O, exec, killall -SIGUSR1 .waybar-wrapped"
          "$mod, Q, exec, kitty"
          "$mod, C, killactive,"
          "$mod, M, exec, wlogout -b 2 -L 500px -R 500px -c 30px -r 30px,"
          "$mod, E, exec, nautilus -w"
          "$mod, V, togglefloating,"
          "$mod, P, pseudo,"
          "$mod, J, togglesplit,"
          "$mod, F, exec, hyprctl dispatch fullscreen"
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
          "$mod, $mod_L, exec, pkill rofi || rofi -show drun -show-icons -hover-select -me-select-entry '' -me-accept-entry MousePrimary"
          "$mod_CTRL, $mod_L, exec, pkill rofi || rofi -show run -hover-select -me-select-entry '' -me-accept-entry MousePrimary"
        ];
        bindm = [
          "$mod, mouse:272, movewindow"
          "$mod, mouse:273, resizewindow"
        ];
        windowrule = [
	  "nomaxsize, ^(polkit-mate-authentication-agent-1)$"
          "pin, ^(polkit-mate-authentication-agent-1)$"
          "opacity 0.99 override 0.99 override, title:^(MainPicker)$"
          "opacity 0.99 override 0.99 override, ^(org.qbittorrent.qBittorrent)$"
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
          "firefox & flatpak run dev.vencord.Vesktop"
          "wl-paste --type text --watch cliphist store"
          "wl-paste --type image --watch cliphist store"
          "hyprctl setcursor GoogleDot-Black 24"
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
        cursor = {
          no_hardware_cursors = false;
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
        plugin = mkIf cfg.enable-plugins {
          hyprexpo = {
            columns = 3;
            gap_size = 5;
            bg_col = "rgb(111111)";
            workspace_method = "first 1";
            enable_gesture = true;
            gesture_distance = 300;
            gesture_positive = true;
          };
          dynamic-cursors = {
            enabled = true;
            mode = "stretch";
            shake.enabled = false;
            stretch.function = "negative_quadratic";
          };
        };
      };
      extraConfig = ''
        submap=passthrough
          bind=,escape,submap,reset
        submap=reset
      '';
    };
    systemd.user.services.polkit_mate = {
      Install= {
        wantedBy = [ "hyprland-session.target" ];
      };
      Service = {
	ExecStart = "${pkgs.mate.mate-polkit}/libexec/polkit-mate-authentication-agent-1";
	Restart = "always";
      };
    };
  };
}
