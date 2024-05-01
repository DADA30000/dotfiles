{ config, pkgs, inputs, libs, ... }:
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
env = WLR_NO_HARDWARE_CURSORS,1
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
monitor=HDMI-A-1,1920x1080@60,0x0,1
windowrule=animation [popin] ([default]), ^(wlogout)$
windowrulev2 = immediate, class:^(org.freedesktop.Xwayland)$
windowrule=windowdance,title:^(Rhythm Doctor)$
windowrule=noanim, class:^(ueberzugpp)$
windowrule=noanim, title:^(ueberzugpp)$
windowrule=forceinput,title:^(Rhythm Doctor)$
windowrule=float,^(org.kde.polkit-kde-authentication-agent-1)$
#windowrulev2 = opacity 0.0 override 0.0 override,class:^(xwaylandvideobridge)$
#windowrulev2 = noanim,class:^(xwaylandvideobridge)$
#windowrulev2 = nofocus,class:^(xwaylandvideobridge)$
#windowrulev2 = noinitialfocus,class:^(xwaylandvideobridge)$
#windowrulev2 = noborder,fullscreen:1
windowrule=opacity 0.99 0.99,^(Thunderbird)$
# windowrule=xray on,^(VencordDesktop)$
#windowrulev2 = forcergbx, class:firefox
#windowrule=xray on,^(firefox)$
#windowrule = opacity 0.85 override 0.85 override, title:^(.*)$
windowrule = opacity 0.99 override 0.99 override, ^(firefox)$
windowrule = opacity 0.99 override 0.99 override, ^(floorp)$
windowrule = opacity 0.99 override 0.99 override, ^(mercury-default)$
windowrule = opacity 0.99 override 0.99 override, ^(filezilla)$
exec-once = ulimit -c 0
exec-once = /nix/store/$(echo $(ls -la /nix/store | grep polkit-gnome | grep '^d' | awk '{print $9}') | cut -d ' ' -f 1)/libexec/polkit-gnome-authentication-agent-1
# exec-once = /usr/bin/swaylock --screenshots --config ~/.config/swaylock/config
exec-once = /usr/lib/xdg-desktop-portal-hyprland & ~/.config/waybar/bin/watch.sh & hyprpaper & firefox & ~/.config/hypr/ulauncher.sh & swaync & vesktop --enable-blink-features=MiddleClickAutoscroll --enable-features=UseOzonePlatform --ozone-platform=wayland
exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
exec-once = gpu-screen-recorder -w screen -q ultra -a "$(pactl get-default-sink).monitor" -f 60 -r 300 -c mp4 -o ~/Games/Replays
exec-once = nm-applet
# exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
exec-once = wl-paste --type text --watch cliphist store #Stores only text data
exec-once = wl-paste --type image --watch cliphist store #Stores only image data
# exec = killall mpvpaper; mpvpaper -p -o "no-audio loop" HDMI-A-1 wallpapers/wall2.mp4
#exec-once = killall swww-daemon -9; swww init; ~/.config/hypr/process-wallpaper/wallpaper.sh
#exec-once = /usr/bin/swaylock --screenshots --config ~/.config/swaylock/config
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

    sensitivity = 1 # -1.0 - 1.0, 0 means no modification.
    # force_no_accel = true
    accel_profile = flat
}

general {
    allow_tearing = true
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

    bezier = slidein, 0.39, 0.575, 0.565, 1
    bezier = myBezier, 0.05, 0.9, 0.1, 1.05
    bezier = linear, 0.0, 0.0, 0.0, 0.0
    bezier = woosh, 0.445, 0.05, 0, 1
#    animation = borderangle, 1, 40, linear, loop
    animation = windowsMove, 1, 5, default # 7
    animation = windowsIn, 1, 2, woosh, slide # 3
    animation = windows, 1, 7, default, slide # 7
    animation = windowsOut, 1, 5, woosh, slide # 7
    animation = fadeSwitch, 1, 7, default # 7
    animation = fadeOut, 1, 5, linear # 5
    animation = workspaces, 1, 4, woosh, slide # 8
}

debug {
    enable_stdout_logs = false
    disable_logs = true
}
dwindle {
    # See https://wiki.hyprland.org/Configuring/Dwindle-Layout/ for more
    pseudotile = true # master switch for pseudotiling. Enabling is bound to mainMod + P in the keybinds section below
    preserve_split = true # you probably want this
}

master {
    # See https://wiki.hyprland.org/Configuring/Master-Layout/ for more
    new_is_master = true
}

gestures {
    # See https://wiki.hyprland.org/Configuring/Variables/ for more
    workspace_swipe = false
}

misc {
    enable_swallow = true
    animate_manual_resizes = false
    animate_mouse_windowdragging = true
    swallow_regex = ^(kitty|lutris|alacritty)$
    swallow_exception_regex = ^(ncspot)$
    force_default_wallpaper = 2 # Set to 0 to disable the anime mascot wallpapers
}
binds {
    scroll_event_delay = 50
}
$mainMod = SUPER
bind = $mainMod_CTRL, V, exec, cliphist list | tofi | cliphist decode | wl-copy
bind = , Print, exec, hyprshot -m region
bind = SHIFT, Print, exec, hyprshot -m window
bind = ALT, Print, exec, hyprshot -m output
bind = CTRL, Print, exec, hyprshot -m region -r | swappy -f -
bind = CTRL_SHIFT, Print, exec, hyprshot -m window -r | swappy -f -
bind = CTRL_ALT, Print, exec, hyprshot -m output -r | swappy -f -
bind = $mainMod, F1, exec, ~/.config/hypr/gamemode.sh
bind = $mainMod, F2, exec, ~/.config/hypr/sheesh.sh
bind = $mainMod, Y, exec, ~/.config/hypr/ytfzf.sh &!
bind = $mainMod_CTRL, Q, exec, neovide --frame none +term +startinsert "+set laststatus=0 ruler" "+set cmdheight=0" "+map <c-t> :tabnew +term<enter>"
bind = $mainMod, O, exec, killall -SIGUSR1 .waybar-wrapped
bind = $mainMod, Q, exec, kitty
bind = $mainMod_CTRL, C, exec, hyprctl kill
bind = $mainMod, C, killactive,
bind = $mainMod, M, exec, wlogout -b 2 -L 500px -R 500px -c 30px -r 30px,
bind = $mainMod, E, exec, nemo
bind = $mainMod, V, togglefloating,
bindr = $mainMod, $mainMod_L, exec, ulauncher-toggle #pkill ulauncher || $(exec $(ulauncher)) #wofi --show drun --allow-images -D key_expand=Tab
bindr = $mainMod_CTRL, $mainMod_L, exec, pkill tofi || $(tofi-run) #wofi --show run
bind = $mainMod, P, pseudo, # dwindle
bind = $mainMod, J, togglesplit, # dwindle
bind = $mainMod_CTRL, R, exec, killall -SIGUSR1 gpu-screen-recorder && notify-send "GPU-Screen-Recorder" "Повтор успешно сохранён"
bind = $mainMod, F, exec, hyprctl dispatch fullscreen
bind = $mainMod_CTRL, F, fakefullscreen
bind = $mainMod, Space, hyprexpo:expo, toggle
bind = $mainMod_ALT, mouse_down, exec, hyprctl keyword misc:cursor_zoom_factor "$(hyprctl getoption misc:cursor_zoom_factor | grep float | awk '{print $2 + 1}')"    
bind = $mainMod_ALT, mouse_up, exec, hyprctl keyword misc:cursor_zoom_factor "$(hyprctl getoption misc:cursor_zoom_factor | grep float | awk '{print $2 - 1}')"
bind = $mainMod_CTRL, mouse_down, exec, hyprctl keyword misc:cursor_zoom_factor "$(hyprctl getoption misc:cursor_zoom_factor | grep float | awk '{print $2 + 100}')" 
bind = $mainMod_CTRL, mouse_up, exec, hyprctl keyword misc:cursor_zoom_factor "$(hyprctl getoption misc:cursor_zoom_factor | grep float | awk '{print $2 - 100}')"
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
exec-once=hyprctl setcursor Bibara-Modern-Classic 24
layerrule = ignorezero, waybar
layerrule = ignorezero, swaync-notification-window
layerrule = blur, swaync-control-center
layerrule = ignorezero, swaync-control-center
layerrule = blur, notifications
layerrule = blur, gtk-layer-shell
layerrule = blur, logout_dialog
layerrule = blur, launcher
plugin {
    hyprexpo {
        columns = 3
        gap_size = 5
        bg_col = rgb(111111)
        workspace_method = center current # [center/first] [workspace] e.g. first 1 or center m+1

        enable_gesture = true # laptop touchpad, 4 fingers
        gesture_distance = 300 # how far is the "max"
        gesture_positive = true # positive = swipe down. Negative = swipe up.
    }
}
    '';
  };
}