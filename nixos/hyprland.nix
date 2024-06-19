{ config, pkgs, inputs, lib, ... }:
{
  wayland.windowManager.hyprland = {
    enable = true;
    plugins = [ inputs.hyprland-plugins.packages.${pkgs.system}.hyprexpo ];
    package = inputs.hyprland.packages.${pkgs.system}.hyprland;
    extraConfig = ''
      env = GTK_THEME,Materia-dark
      env = XCURSOR_THEME,Bibata-Modern-Classic
      env = ENABLE_VKBASALT,1
      env = FZF_DEFAULT_COMMAND,locate ~
      env = QT_STYLE_OVERRIDE,kvantum
      env = GDK_BACKEND,wayland,x11
      env = CLUTTER_BACKEND,wayland
      env = MOZ_ENABLE_WAYLAND,1
      env = MOZ_DISABLE_RDD_SANDBOX,1
      env = _JAVA_AWT_WM_NONREPARENTING=1
      env = QT_AUTO_SCREEN_SCALE_FACTOR,1
      env = QT_QPA_PLATFORM,wayland;xcb
      env = LIBVA_DRIVER_NAME,nvidia
      env = GBM_BACKEND,nvidia-drm
      env = __GLX_VENDOR_LIBRARY_NAME,nvidia
      env = __NV_PRIME_RENDER_OFFLOAD,1
      env = __VK_LAYER_NV_optimus,NVIDIA_only
      env = PROTON_ENABLE_NGX_UPDATER,1
      env = NVD_BACKEND,direct
      env = __GL_GSYNC_ALLOWED,1
      env = __GL_VRR_ALLOWED,1
      env = WLR_DRM_NO_ATOMIC,1
      env = WLR_USE_LIBINPUT,1
      env = MOZ_X11_EGL,1
      env = VDPAU_DRIVER,nvidia
      env = EDITOR,nvim
      env = VISUAL,nvim
      env = __GL_MaxFramesAllowed,1
      env = TERMINAL,kitty
      bind=ALT,R,submap,passthrough
      submap=passthrough
      bind=,escape,submap,reset
      submap=reset
      monitor=Unknown-1,disabled
      monitor=HDMI-A-1,1920x1080@60,0x0,1

      windowrule = animation [popin] ([default]), ^(wlogout)$
      windowrule = pin, ^(polkit-gnome-authentication-agent-1)$
      windowrulev2 = immediate, class:^(org.freedesktop.Xwayland)$
      windowrule = windowdance,title:^(Rhythm Doctor)$
      windowrule = noanim, class:^(ueberzugpp)$
      windowrule = noanim, title:^(ueberzugpp)$
      windowrule = forceinput,title:^(Rhythm Doctor)$
      windowrule = float,^(org.kde.polkit-kde-authentication-agent-1)$
      windowrule = opacity 0.99 0.99,^(Thunderbird)$
      windowrule = opacity 0.99 override 0.99 override, ^(firefox)$
      windowrule = opacity 0.99 override 0.99 override, ^(floorp)$
      windowrule = opacity 0.99 override 0.99 override, ^(mercury-default)$
      windowrule = opacity 0.99 override 0.99 override, ^(filezilla)$
      exec-once = ulimit -c 0
      exec-once = /nix/store/$(echo $(ls -la /nix/store | grep polkit-gnome | grep '^d' | awk '{print $9}') | cut -d ' ' -f 1)/libexec/polkit-gnome-authentication-agent-1
      exec-once = waybar & hyprpaper & firefox & swaync & vesktop --enable-blink-features=MiddleClickAutoscroll
      exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
      exec-once = sleep 10; gpu-screen-recorder -w screen -q ultra -a "$(pactl get-default-sink).monitor" -f 60 -r 300 -c mp4 -o ~/Games/Replays
      exec-once = wl-paste --type text --watch cliphist store
      exec-once = wl-paste --type image --watch cliphist store
      env = XCURSOR_SIZE,24
      env = LIBVA_DRIVER_NAME,nvidia
      env = XDG_SESSION_TYPE,wayland
      env = GBM_BACKEND,nvidia_drm
      env = __GLX_VENDOR_LIBRARY_NAME,nvidia
      input {
          kb_layout = us,ru
          kb_variant =
          kb_model =
          kb_options = grp:alt_shift_toggle
          kb_rules =
          repeat_delay = 200
      
          follow_mouse = 1
      
          touchpad {
              natural_scroll = false
          }
      
          sensitivity = 1
          accel_profile = flat
      }
      
      general {
          gaps_in = 5
          gaps_out = 5
          border_size = 0
          col.active_border = rgb(4575da) rgb(6804b5)
          col.inactive_border = rgb(595959)
      
          layout = dwindle
      
          allow_tearing = false
      }
      
      decoration {
      
          rounding = 10
      
          blur {
              enabled = true
      	popups = true
      	popups_ignorealpha = 0.0
      	ignore_opacity = true
              size = 10
      	brightness = 0.8
              passes = 3
              noise = 0
              vibrancy = 0
          }
      
          drop_shadow = yes
          shadow_range = 4
          shadow_render_power = 3
          col.shadow = rgba(1a1a1aee)
      }
      
      animations {
          enabled = true
          first_launch_animation = true
	  bezier = aaaa, 0.2, 0.7, 0.7, 1  
      	  bezier = fade, 0.165, 0.84, 0.44, 1 
          bezier = slidein, 0.39, 0.575, 0.565, 1
          bezier = myBezier, 0.05, 0.9, 0.1, 1.05
          bezier = linear, 0.0, 0.0, 0.0, 0.0
          bezier = woosh, 0.445, 0.05, 0, 1
          animation = windowsMove, 1, 5, default
          animation = layers, 1, 2, woosh, slide
          animation = windowsIn, 1, 2, fade, popin 90%
          animation = windows, 1, 7, default, slide
          animation = windowsOut, 1, 3, fade, popin 90%
          animation = fadeSwitch, 1, 7, default
          animation = fadeOut, 1, 3, fade
	  ##animation = fadeIn
          animation = workspaces, 1, 4, woosh, slide
      }
      
      debug {
          enable_stdout_logs = false
          disable_logs = true
      }
      dwindle {
          pseudotile = true
          preserve_split = true
      }
      gestures {
          workspace_swipe = false
      }
      misc {
          enable_swallow = true
          animate_manual_resizes = false
          animate_mouse_windowdragging = false
          swallow_regex = ^(kitty|lutris|alacritty)$
          swallow_exception_regex = ^(ncspot)$
          force_default_wallpaper = 2
      }
      binds {
          scroll_event_delay = 50
      }
      $mainMod = SUPER
      bind = $mainMod_CTRL, V, exec, cliphist list | rofi -dmenu | cliphist decode | wl-copy
      bind = , Print, exec, hyprshot -m region
      bind = SHIFT, Print, exec, hyprshot -m window
      bind = ALT, Print, exec, hyprshot -m output
      bind = CTRL, Print, exec, hyprshot -m region -r | swappy -f -
      bind = CTRL_SHIFT, Print, exec, hyprshot -m window -r | swappy -f -
      bind = CTRL_ALT, Print, exec, hyprshot -m output -r | swappy -f -
      bind = $mainMod, F1, exec, gamemode.sh
      bind = $mainMod, F2, exec, sheesh.sh
      bind = $mainMod_CTRL, Q, exec, neovide --frame none +term +startinsert "+set laststatus=0 ruler" "+set cmdheight=0" "+map <c-t> :tabnew +term<enter>"
      bind = $mainMod, O, exec, killall -SIGUSR1 .waybar-wrapped
      bind = $mainMod, Q, exec, kitty
      bind = $mainMod_CTRL, C, exec, hyprctl kill
      bind = $mainMod, C, killactive,
      bind = $mainMod, M, exec, wlogout -b 2 -L 500px -R 500px -c 30px -r 30px,
      bind = $mainMod, E, exec, nemo
      bind = $mainMod, V, togglefloating,
      bindr = $mainMod, $mainMod_L, exec, pkill rofi || $(rofi -show drun -show-icons)
      bindr = $mainMod_CTRL, $mainMod_L, exec, pkill rofi || $(rofi -show run)
      bind = $mainMod, P, pseudo,
      bind = $mainMod, J, togglesplit,
      bind = $mainMod_CTRL, R, exec, killall -SIGUSR1 gpu-screen-recorder && notify-send "GPU-Screen-Recorder" "Повтор успешно сохранён"
      bind = $mainMod, F, exec, hyprctl dispatch fullscreen
      bind = $mainMod_CTRL, F, fakefullscreen
      bind = $mainMod, Space, hyprexpo:expo, toggle
      bind = $mainMod, left, movefocus, l
      bind = $mainMod, right, movefocus, r
      bind = $mainMod, up, movefocus, u
      bind = $mainMod, down, movefocus, d
      bind = $mainMod, 1, workspace, 1
      bind = $mainMod, 2, workspace, 2
      bind = $mainMod, 3, workspace, 3
      bind = $mainMod, 4, workspace, 4
      bind = $mainMod, 5, workspace, 5
      bind = $mainMod, 6, workspace, 6
      bind = $mainMod, 7, workspace, 7
      bind = $mainMod, 8, workspace, 8
      bind = $mainMod, 9, workspace, 9
      bind = $mainMod, 0, workspace, 10
      bind = $mainMod SHIFT, 1, movetoworkspace, 1
      bind = $mainMod SHIFT, 2, movetoworkspace, 2
      bind = $mainMod SHIFT, 3, movetoworkspace, 3
      bind = $mainMod SHIFT, 4, movetoworkspace, 4
      bind = $mainMod SHIFT, 5, movetoworkspace, 5
      bind = $mainMod SHIFT, 6, movetoworkspace, 6
      bind = $mainMod SHIFT, 7, movetoworkspace, 7
      bind = $mainMod SHIFT, 8, movetoworkspace, 8
      bind = $mainMod SHIFT, 9, movetoworkspace, 9
      bind = $mainMod SHIFT, 0, movetoworkspace, 10
      bind = $mainMod, S, togglespecialworkspace, magic
      bind = $mainMod SHIFT, S, movetoworkspace, special:magic
      bind = $mainMod, mouse_down, workspace, e+1
      bind = $mainMod, mouse_up, workspace, e-1
      bindm = $mainMod, mouse:272, movewindow
      layerrule = blur,waybar
      layerrule = blur,swaync-notification-window
      bindm = $mainMod, mouse:273, resizewindow
      exec-once=hyprctl setcursor Bibata-Modern-Classic 24
      layerrule = ignorezero, waybar
      layerrule = ignorezero, swaync-notification-window
      layerrule = blur, swaync-control-center
      layerrule = ignorezero, swaync-control-center
      layerrule = ignorezero, rofi
      layerrule = blur, notifications
      layerrule = blur, gtk-layer-shell
      layerrule = blur, logout_dialog
      layerrule = blur, launcher
      layerrule = blur, wofi
      layerrule = noanim, selection
      layerrule = blur, rofi
      layerrule = animation popin 90%, rofi
      layerrule = animation slide left, swaync-control-center
      layerrule = animation popin 90%, logout_dialog
      plugin {
          hyprexpo {
              columns = 3
              gap_size = 5
              bg_col = rgb(111111)
              workspace_method = first 1
      
              enable_gesture = true
              gesture_distance = 300
              gesture_positive = true
          }
      }
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
      preload = [ "${./wallpaper.jpg}" ];
      wallpaper = [
        "HDMI-A-1,${./wallpaper.jpg}"
      ];
    };
  };
}
