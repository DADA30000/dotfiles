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
  read-text = pkgs.writeShellScript "read-text-hyprland" ''
    # Arguments:
    # $1 = Hyprshot Mode (e.g., "region", "window", "output")
    # $2 = Languages (e.g., "eng+rus", "jpn+osd")

    # 1. Take the shot
    img="/tmp/ocr_snap.png"
    rm -f $img
    XDG_PICTURES_DIR=${config.xdg.userDirs.pictures} hyprshot -z -m "$1" -o /tmp -f ocr_snap.png

    if [[ ! -s "$img" ]]; then
      exit 0
    fi

    # 2. Universal Pre-processing (Solves the "Small Text" issue)
    magick "$img" -resize 400% -colorspace gray -sharpen 0x1 "$img"

    # 3. OCR and Display
    # We use a specific title so Hyprland rules can catch it
    tesseract "$img" stdout -l "$2" --psm 1 | \
    zenity --text-info \
           --title="Извлечённый текст" \
           --editable \
           --width=800 --height=500

    # 4. Cleanup
    rm "$img"
  '';
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
      tesseract
      imagemagick
      libsForQt5.qtsvg
      kdePackages.qtsvg
      kdePackages.dolphin
      kdePackages.ark
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
      qimgv
      myxer
      ffmpeg-full
      gpu-screen-recorder
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
      portalPackage = mkMerge [
        (mkIf (
          !cfg.stable && !cfg.from-unstable
        ) inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland)
        (mkIf (
          cfg.from-unstable && !cfg.stable
        ) inputs.unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland)
      ];
      package = mkMerge [
        (mkIf (
          !cfg.stable && !cfg.from-unstable
        ) inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.default)
        (mkIf (
          cfg.from-unstable && !cfg.stable
        ) inputs.unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.hyprland)
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
          ", MENU, exec, app2unit -- ${read-text} region eng+osd"
          "SUPER, MENU, exec, app2unit -- ${read-text} window eng+osd"
          "SHIFT, MENU, exec, app2unit -- ${read-text} output eng+osd"
          "CTRL, MENU, exec, app2unit -- ${read-text} region jpn+chi_sim+kor+rus+osd"
          "SUPER, MENU, exec, app2unit -- ${read-text} window jpn+chi_sim+kor+rus+osd"
          "SHIFT, MENU, exec, app2unit -- ${read-text} output jpn+chi_sim+kor+rus+osd"
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
          "$mod, Z, exec, app2unit -- zen-twilight"
          "$mod, D, exec, app2unit -- discordcanary || app2unit -- discord"
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
        monitor = [ ", highres, auto, 1" ];
        bindr = [
          ''$mod, $mod_L, exec, pkill rofi || rofi -show drun -show-icons -hover-select -me-select-entry ''' -me-accept-entry MousePrimary -run-command 'bash -c "exec_path=\$(echo \"\$*\" | grep -oP \"(^|(?<=\s))(?![^=\s]+=[^\s]+)[/\w\.-]+\" | head -n1); n=\$(basename \"\$exec_path\" | sed \"s/\\\\x2d/-/g\" | tr -cd \"[:alnum:]. _-\"); app2unit -a \"\$n\" -- \"\$@\"" -- {cmd}' ''
          "$mod_CTRL, $mod_L, exec, pkill rofi || rofi -show run -hover-select -me-select-entry '' -me-accept-entry MousePrimary -run-command 'app2unit -- {cmd}'"
        ];
        bindm = [
          "$mod, mouse:272, movewindow"
          "$mod, mouse:273, resizewindow"
        ];
        windowrule = [
          "float on, match:title ^(Извлечённый текст)$"
          "no_max_size on, match:class polkit-mate-authentication-agent-1"
          "pin on, match:class polkit-mate-authentication-agent-1"
          "fullscreen_state 0 2, match:class (firefox), match:title ^(.*Discord.* — Mozilla Firefox.*)$"
          "opacity 0.99 override 0.99 override, match:title QDiskInfo"
          "opacity 0.99 override 0.99 override, match:title MainPicker"
          "opacity 0.99 override 0.99 override, match:class thunderbird"
          "opacity 0.99 override 0.99 override, match:class spotify"
          "opacity 0.99 override 0.99 override, match:class org.prismlauncher.PrismLauncher"
          "opacity 0.99 override 0.99 override, match:class mpv"
          "opacity 0.99 override 0.99 override, match:class org.qbittorrent.qBittorrent"
          "opacity 0.99 override 0.99 override, match:class die"
        ];
        permission = [
          "${lib.escapeRegex (lib.getExe pkgs.hyprpicker)}, screencopy, allow"
          "${lib.escapeRegex (lib.getExe pkgs.wayvr)}, screencopy, allow"
          "${lib.escapeRegex (lib.getExe pkgs.grim)}, screencopy, allow"
          "${lib.escapeRegex (lib.getExe config.programs.hyprlock.package)}, screencopy, allow"
          "${lib.escapeRegex "${config.wayland.windowManager.hyprland.portalPackage}"}/libexec/.xdg-desktop-portal-hyprland-wrapped, screencopy, allow"
        ];
        layerrule = [
          "blur on, match:namespace .*"
          "blur_popups on, match:namespace .*"
          "no_anim on, match:namespace selection"
          "no_anim on, match:namespace hyprpicker"
          "ignore_alpha 0.9, match:namespace selection"
          "ignore_alpha 0, match:namespace corner0"
          "ignore_alpha 0, match:namespace overview"
          "ignore_alpha 0, match:namespace indicator0"
          "ignore_alpha 0, match:namespace datemenu"
          "ignore_alpha 0, match:namespace launcher"
          "ignore_alpha 0, match:namespace quicksettings"
          "ignore_alpha 0, match:namespace swaync-control-center"
          "ignore_alpha 0, match:namespace rofi"
          "ignore_alpha 0, match:namespace waybar"
          "ignore_alpha 0, match:namespace swaync-notification-window"
          "animation popin 90%, match:namespace rofi"
          "animation popin 90%, match:namespace logout_dialog"
          "animation slide left, match:namespace swaync-control-center"
        ];
        exec-once = [
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
          touchdevice.enabled = true;
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
          disable_watchdog_warning = true;
          disable_hyprland_logo = true;
          background_color = "0x000000";
          enable_swallow = false;
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
        ExecStart = "${pkgs.mate-polkit}/libexec/polkit-mate-authentication-agent-1";
        Restart = "always";
        StartLimitInterval = 0;
      };
    };
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
            color = "rgba(0, 0, 0, 1)";
          }
        ];

        input-field = [
          {
            monitor = "";
            size = "12.5%, 5%";
            outline_thickness = 2;
            dots_size = 0.2;
            dots_spacing = 0.15;
            dots_center = true;
            outer_color = "rgb(000000)";
            inner_color = "rgb(000000)";
            font_color = "rgb(255, 255, 255)";
            fade_on_empty = true;
            fail_text = "";
            placeholder_text = "";
            hide_input = false;
            position = "0%, 0%";
            halign = "center";
            valign = "center";
          }
        ];

        label = [
          {
            monitor = "";
            text = "$TIME";
            color = "rgb(255, 255, 255)";
            font_size = 50;
            font_family = "Noto Sans";
            position = "0%, 30%";
            halign = "center";
            valign = "center";
          }
          {
            monitor = "";
            text = "Введите пароль от пользователя $USER";
            color = "rgb(255, 255, 255)";
            font_size = 25;
            font_family = "Noto Sans";
            position = "0%, 15%";
            halign = "center";
            valign = "center";
          }
          {
            monitor = "";
            text = "$ATTEMPTS[]";
            color = "rgb(255, 255, 255, 0.05)";
            font_size = 25;
            font_family = "Noto Sans";
            position = "-48%, -48%";
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
        wallpaper = {
          monitor = "";
          path = "${../../../stuff/wallpaper.jpg}";
          fit_mode = "cover";
        };
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
            background-image: image(url("${../../../stuff/wlogout/lock.png}"));
        }

        #logout {
            background-image: image(url("${../../../stuff/wlogout/logout.png}"));
        }

        #shutdown {
            background-image: image(url("${../../../stuff/wlogout/shutdown.png}"));
        }

        #reboot {
            background-image: image(url("${../../../stuff/wlogout/reboot.png}"));
        }
      '';
    };
  };
}
