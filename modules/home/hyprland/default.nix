{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:
with lib;
let
  cfg = config.hyprland;
in
{
  options.hyprland = {
    enable = mkEnableOption "Enable my Hyprland configuration";
    from-unstable = mkEnableOption "Use Hyprland package from UNSTABLE nixpkgs";
    stable = mkEnableOption "Use Hyprland from nixpkgs";
    enable-plugins = mkEnableOption "Enable Hyprland plugins";
    mpvpaper = mkEnableOption "Enable video wallpapers with mpvpaper";
    hyprpaper = mkEnableOption "Enable image wallpapers with hyprpaper";
    wlogout = mkEnableOption "Enable power options menu";
    hyprlock = mkEnableOption "Enable locking program";
    rofi = mkEnableOption "Enable rofi (used as applauncher and dmenu)";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      app2unit
      hyprshot
      pulseaudio
      hyprshot
      nautilus
      file-roller
      cliphist
      libnotify
      swappy
      brightnessctl
      imv
      myxer
      ffmpegthumbnailer
      bun
      esbuild
      fd
      dart-sass
      swww
      hyprpicker
      wttrbar
    ];
    wayland.windowManager.hyprland = {
      #portalPackage = mkMerge [
      #  (mkIf (!cfg.stable && !cfg.from-unstable) inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland)
      #  (mkIf (cfg.from-unstable && !cfg.stable) inputs.unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland)
      #];
      portalPackage = mkMerge [
        (mkIf (!cfg.stable && !cfg.from-unstable) inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland)
        (mkIf (cfg.from-unstable && !cfg.stable) inputs.unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland)
      ];
      package = mkMerge [
        (mkIf (!cfg.stable && !cfg.from-unstable) inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland)
        (mkIf (cfg.from-unstable && !cfg.stable) inputs.unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.hyprland)
      ];
      plugins =
        lib.optionals (cfg.enable-plugins && cfg.stable && !cfg.from-unstable) [
          pkgs.hyprlandPlugins.hyprtrails
        ]
        ++ lib.optionals (cfg.enable-plugins && !cfg.stable && !cfg.from-unstable) [
          inputs.hyprland-plugins.packages.${pkgs.stdenv.hostPlatform.system}.hyprtrails
        ]
        ++ lib.optionals (cfg.enable-plugins && !cfg.stable && cfg.from-unstable) [
          inputs.unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.hyprlandPlugins.hyprtrails
        ];
      enable = true;
      settings = {
        "$mod" = "SUPER";
        bind = [
          ", code:122, exec, pactl set-sink-volume @DEFAULT_SINK@ -4096"
          ", code:123, exec, pactl set-sink-volume @DEFAULT_SINK@ +4096"
          ", Print, exec, app2unit -- env XDG_PICTURES_DIR=${config.xdg.userDirs.pictures} hyprshot -m region -z"
          "SUPER, Print, exec, app2unit -- env XDG_PICTURES_DIR=${config.xdg.userDirs.pictures} hyprshot -m window -z"
          "SHIFT, Print, exec, app2unit -- env XDG_PICTURES_DIR=${config.xdg.userDirs.pictures} hyprshot -m output -z"
          "CTRL, Print, exec, app2unit -- env XDG_PICTURES_DIR=${config.xdg.userDirs.pictures} hyprshot -z -m region -r d | swappy -f -"
          "CTRL SUPER, Print, exec, app2unit -- env XDG_PICTURES_DIR=${config.xdg.userDirs.pictures} hyprshot -z -m window -r d | swappy -f -"
          "CTRL SHIFT, Print, exec, app2unit -- env XDG_PICTURES_DIR=${config.xdg.userDirs.pictures} hyprshot -z -m output -r d | swappy -f -" # change later to "Satty" https://github.com/gabm/Satty
          "ALT,R,submap,passthrough"
          "$mod CTRL, Q, exec, app2unit -- neovide --frame none +term +startinsert '+set laststatus=0 ruler' '+set cmdheight=0' '+map <c-t> :tabnew +term<enter>'"
          "$mod CTRL, R, exec, app2unit -- killall -SIGUSR1 gpu-screen-recorder && notify-send 'GPU-Screen-Recorder' 'Повтор успешно сохранён'"
          "$mod CTRL, U, exec, app2unit -- update-damn-nixos"
          "$mod CTRL, V, exec, rofi -modi clipboard:cliphist-rofi -show clipboard -show-icons -hover-select -me-select-entry '' -me-accept-entry MousePrimary"
          "$mod ALT, mouse_down, exec, hyprctl keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor | grep float | awk '{print $2 + 1}')"
          "$mod ALT, mouse_up, exec, hyprctl keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor | grep float | awk '{if ($2 >= 2) {print $2 - 1} else {print 1}}')"
          "$mod CTRL, mouse_down, exec, hyprctl keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor | grep float | awk '{print $2 + 100}')"
          "$mod CTRL, mouse_up, exec, hyprctl keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor | grep float | awk '{if ($2 >= 101) {print $2 - 100} else {print 1}}')"
          "$mod CTRL, F, fullscreenstate, 0 2"
          "$mod CTRL, C, exec, hyprctl kill"
          "$mod, I, exec, app2unit -- toggle-restriction"
          "$mod, F1, exec, app2unit -- gamemode.sh"
          "$mod, F2, exec, app2unit -- sheesh.sh"
          "$mod, O, exec, killall -SIGUSR1 .waybar-wrapped"
          "$mod, Q, exec, app2unit -- kitty"
          "$mod, C, killactive,"
          "$mod, B, exec, uuctl"
          "$mod, M, exec, app2unit -- wlogout -b 2 -L 500px -R 500px -c 30px -r 30px,"
          "$mod, E, exec, app2unit -- nautilus -w"
          "$mod, V, togglefloating,"
          "$mod, P, pseudo,"
          "$mod, J, togglesplit,"
          "$mod, F, fullscreen,"
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
        monitor = [ ", preferred, auto, 1" ];
        bindr = [
          "$mod, $mod_L, exec, pkill rofi || rofi -show drun -show-icons -hover-select -me-select-entry '' -me-accept-entry MousePrimary -run-command 'app2unit -- {cmd}'"
          "$mod_CTRL, $mod_L, exec, pkill rofi || rofi -show run -hover-select -me-select-entry '' -me-accept-entry MousePrimary -run-command 'app2unit -- {cmd}'"
        ];
        bindm = [
          "$mod, mouse:272, movewindow"
          "$mod, mouse:273, resizewindow"
        ];
        windowrule = [
          "nomaxsize, class:^(polkit-mate-authentication-agent-1)$"
          "pin, class:^(polkit-mate-authentication-agent-1)$"
          "fullscreenstate 0 2, class:(firefox), title:^(.*Discord.* — Mozilla Firefox.*)$"
          "opacity 0.99 override 0.99 override, title:^(QDiskInfo)$"
          "opacity 0.99 override 0.99 override, title:^(MainPicker)$"
          "opacity 0.99 override 0.99 override, class:^(thunderbird)$"
          "opacity 0.99 override 0.99 override, class:^(spotify)$"
          "opacity 0.99 override 0.99 override, class:^(org.prismlauncher.PrismLauncher)$"
          "opacity 0.99 override 0.99 override, class:^(mpv)$"
          "opacity 0.99 override 0.99 override, class:^(org.qbittorrent.qBittorrent)$"
          "opacity 0.99 override 0.99 override, class:^(die)$"
        ];
        permission = [
          "${lib.escapeRegex (lib.getExe pkgs.hyprpicker)}, screencopy, allow"
          "${lib.escapeRegex (lib.getExe pkgs.grim)}, screencopy, allow"
          "${lib.escapeRegex (lib.getExe config.programs.hyprlock.package)}, screencopy, allow"
          "${lib.escapeRegex "${config.wayland.windowManager.hyprland.portalPackage}"}/libexec/.xdg-desktop-portal-hyprland-wrapped, screencopy, allow"
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
          "noanim, hyprpicker"
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
          #"pactl load-module module-null-sink sink_name=audiorelay-virtual-mic-sink sink_properties=device.description=Virtual-Mic-Sink; pactl load-module module-remap-source master=audiorelay-virtual-mic-sink.monitor source_name=audiorelay-virtual-mic-sink source_properties=device.description=Virtual-Mic"
          #"firefox & sleep 1; firefox --new-window https://discord.com/channels/@me"
          "app2unit -- wl-paste --watch cliphist store"
          "fumon"
          "hyprctl setcursor Bibata-Modern-Classic 24"
        ];
        input = {
          kb_layout = "us,ru";
          kb_options = "grp:alt_shift_toggle";
          repeat_delay = 150;
          repeat_rate = 35;
          follow_mouse = 1;
          touchpad = {
            natural_scroll = true;
            scroll_factor = 0.5;
            disable_while_typing = false;
          };
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
        debug = {
          full_cm_proto = true;
        };
        ecosystem = {
          enforce_permissions = true;
        };
        cursor = {
          no_hardware_cursors = false;
          zoom_disable_aa = true;
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
            passes = 4;
            noise = 0;
            vibrancy = 0;
          };
        };
        animations = {
          enabled = true;
          workspace_wraparound = false;
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
        misc = {
          disable_hyprland_logo = true;
          background_color = "0x000000";
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
            enabled = false;
            mode = "tilt";
            shake.enabled = false;
            stretch.function = "negative_quadratic";
          };
          hyprtrails = {
            color = "rgba(bbddffff)";
            bezier_step = 0.001;
            history_points = 6;
            points_per_step = 4;
            histoty_step = 1;
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
      Install = {
        WantedBy = [ "hyprland-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.mate.mate-polkit}/libexec/polkit-mate-authentication-agent-1";
        Restart = "always";
        StartLimitInterval = 0;
      };
    };
    #systemd.user.services.custom_sink = {
    #  Install = {
    #    WantedBy = [ "pipewire-pulse.service" ];
    #  };
    #  Unit = {
    #    After = [ "pipewire-pulse.service" ];
    #  };
    #  Service = {
    #    Type = "oneshot";
    #    ExecStart = [
    #      "${pkgs.pulseaudio}/.bin-unwrapped/pactl load-module module-null-sink sink_name=custom_sink sink_properties=device.description='Custom_Sink'"
    #      "${pkgs.pulseaudio}/.bin-unwrapped/pactl load-module module-loopback source=custom_sink.monitor sink=alsa_output.usb-3142_fifine_Headset-00.analog-stereo"
    #    ];
    #  };
    #};
    xdg.portal = {
      enable = true;
      extraPortals = [
        pkgs.xdg-desktop-portal-gtk
      ];
      config.common.default = "*";
    };
    programs.hyprlock = mkIf cfg.hyprlock {
      enable = true;
      settings = {
        background = [
          {
            monitor = "";
            color = "rgba(0, 0, 0, 0.7)";
          }
        ];

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
          }
        ];

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
          }
        ];
      };
    };
    services.hyprpaper = mkIf (cfg.hyprpaper && !cfg.mpvpaper) {
      enable = true;
      settings = {
        ipc = "on";
        splash = false;
        preload = [ "${../../../stuff/wallpaper.jpg}" ];
        wallpaper = [
          ",${../../../stuff/wallpaper.jpg}"
        ];
      };
    };
    #systemd.user.services.hyprpaper.Service.ExecStartPre = mkIf (cfg.hyprpaper && !cfg.mpvpaper) "${pkgs.coreutils-full}/bin/sleep 1.8";
    systemd.user.services.mpvpaper = mkIf (!cfg.hyprpaper && cfg.mpvpaper) {
      Unit = {
        Description = "Play video wallpaper.";
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.mpvpaper}/bin/mpvpaper -s -o 'no-audio loop input-ipc-server=/tmp/mpvpaper-socket hwdec=auto' '*' ${../../../stuff/wallpaper.mp4}";
      };
    };
    programs.rofi = mkIf cfg.rofi {
      enable = true;
      font = "JetBrainsMono NF 14";
      theme = ../../../stuff/theme.rasi;
    };
    programs.wlogout = mkIf cfg.wlogout {
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
            background-image: image(url("${../../../stuff/lock.png}"));
        }

        #logout {
            background-image: image(url("${../../../stuff/logout.png}"));
        }

        #shutdown {
            background-image: image(url("${../../../stuff/shutdown.png}"));
        }

        #reboot {
            background-image: image(url("${../../../stuff/reboot.png}"));
        }
      '';
    };
  };
}
