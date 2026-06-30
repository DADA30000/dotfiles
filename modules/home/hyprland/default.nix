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
  nautilus-extensions = pkgs.callPackage ./nautilus-extensions.nix { };
  nautilus-listener = pkgs.callPackage ./nautilus-listener.nix { };
  mkPluginPermissionEntries = list: map (plugin: mkPluginPermissionEntry plugin) list;
  mkPluginExecEntries = list: lib.concatLines (map (plugin: mkPluginExecEntry plugin) list);
  mkPluginExecEntry = plugin: "hl.exec_cmd [[${plugin-loader plugin}/bin/hypr-plugin-loader]]";
  mkPluginPermissionEntry = plugin: {
    binary = "${lib.escapeRegex "${plugin-loader plugin}/bin/hypr-plugin-loader"}";
    type = "plugin";
    mode = "allow";
  };
  plugins =
    lib.optionals (cfg.enable-plugins && cfg.stable && !cfg.from-unstable) [
      #pkgs.hyprlandPlugins.hyprtrails
    ]
    ++ lib.optionals (cfg.enable-plugins && !cfg.stable && !cfg.from-unstable) [
      inputs.split-monitor-workspaces.packages.${pkgs.stdenv.hostPlatform.system}.split-monitor-workspaces
      #inputs.hyprland-plugins.packages.${pkgs.stdenv.hostPlatform.system}.hyprtrails
    ]
    ++ lib.optionals (cfg.enable-plugins && !cfg.stable && cfg.from-unstable) [
      #inputs.unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.hyprlandPlugins.hyprtrails
    ];
  plugin-loader =
    pkg:
    pkgs.stdenv.mkDerivation {
      pname = "${pkg.pname}-loader";
      version = "1.0";

      src = pkgs.writeText "hypr-plugin-loader.c" ''
        #include <stdio.h>
        #include <stdlib.h>
        #include <string.h>
        #include <unistd.h>
        #include <sys/socket.h>
        #include <sys/un.h>

        #define PLUGIN_PATH "${
          if lib.types.package.check pkg then "${pkg}/lib/lib${pkg.pname}.so" else pkg
        }"

        int main() {
            const char *xdg_runtime = getenv("XDG_RUNTIME_DIR");
            const char *hypr_sig = getenv("HYPRLAND_INSTANCE_SIGNATURE");

            if (!xdg_runtime || !hypr_sig) {
                fprintf(stderr, "Missing Env Vars\n");
                return 1;
            }

            int sock = socket(AF_UNIX, SOCK_STREAM, 0);
            if (sock < 0) return 1;

            struct sockaddr_un addr;
            memset(&addr, 0, sizeof(addr));
            addr.sun_family = AF_UNIX;
            snprintf(addr.sun_path, sizeof(addr.sun_path), "%s/hypr/%s/.socket.sock", xdg_runtime, hypr_sig);

            if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
                close(sock);
                return 1;
            }

            char command[2048];
            snprintf(command, sizeof(command), "/plugin load %s", PLUGIN_PATH);

            if (write(sock, command, strlen(command)) < 0) {
                close(sock);
                return 1;
            }

            shutdown(sock, SHUT_WR);

            char buffer[4096];
            ssize_t bytes_read = read(sock, buffer, sizeof(buffer) - 1);
            if (bytes_read > 0) {
                buffer[bytes_read] = '\0';
                printf("Hyprland response: %s\n", buffer);
            }

            close(sock);
            return 0;
        }
      '';

      dontUnpack = true;

      buildPhase = ''
        $CC -O3 -flto -march=native -pipe -fPIE -pie -Wl,-s $src -o hypr-plugin-loader
      '';

      installPhase = ''
        mkdir -p $out/bin
        cp hypr-plugin-loader $out/bin/
      '';
    };
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
    enable = mkEnableOption "my Hyprland configuration";
    from-unstable = mkEnableOption "Use Hyprland package from UNSTABLE nixpkgs";
    stable = mkEnableOption "Use Hyprland from nixpkgs";
    enable-plugins = mkEnableOption "Hyprland plugins";
    mpvpaper = mkEnableOption "video wallpapers with mpvpaper";
    wallpaper = mkEnableOption "image wallpapers with swaybg";
    wlogout = mkEnableOption "power options menu";
    hyprlock = mkEnableOption "locking program";
    rofi = mkEnableOption "rofi (used as applauncher and dmenu)";
    additional-monitors = mkOption {
      default = [ ];
      type = lib.types.listOf lib.types.attrs;
    };
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      gtk3
      kdePackages.kservice
      rofi-bluetooth
      tesseract
      imagemagick
      libsForQt5.qtsvg
      kdePackages.qtsvg
      kdePackages.dolphin
      kdePackages.ark
      app2unit
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
      enable = true;
      configType = "lua";
      settings =
        let
          mod = "SUPER";
          make-bind-exec-obj = keys: exec: args: {
            _args = [
              keys
              (lib.generators.mkLuaInline "hl.dsp.exec_cmd [[${exec}]]")
            ]
            ++ args;
          };
          bind-exec =
            list:
            map (
              pair: make-bind-exec-obj (builtins.elemAt pair 0) (builtins.elemAt pair 1) (lib.lists.drop 2 pair)
            ) list;
          make-bind-obj = keys: exec: args: {
            _args = [
              keys
              (lib.generators.mkLuaInline exec)
            ]
            ++ args;
          };
          bind =
            list:
            map (
              pair: make-bind-obj (builtins.elemAt pair 0) (builtins.elemAt pair 1) (lib.lists.drop 2 pair)
            ) list;
        in
        {
          monitor = [
            {
              output = "";
              mode = "highres";
              position = "auto";
              scale = "auto";
            }
          ]
          ++ cfg.additional-monitors;
          curve = [
            {
              _args = [
                "easeIn"
                {
                  type = "bezier";
                  points = [
                    [
                      0.38
                      0.04
                    ]
                    [
                      1
                      0.075
                    ]
                  ];
                }
              ];
            }
            {
              _args = [
                "fade"
                {
                  type = "bezier";
                  points = [
                    [
                      0.165
                      0.84
                    ]
                    [
                      0.44
                      1
                    ]
                  ];
                }
              ];
            }
            {
              _args = [
                "woosh"
                {
                  type = "bezier";
                  points = [
                    [
                      0.445
                      0.05
                    ]
                    [
                      0
                      1
                    ]
                  ];
                }
              ];
            }
          ];
          gesture = [
            {
              fingers = 3;
              direction = "horizontal";
              action = "workspace";
            }
          ];
          animation = [
            {
              leaf = "windowsMove";
              enabled = true;
              speed = 5;
              bezier = "default";
            }
            {
              leaf = "windowsIn";
              enabled = true;
              speed = 2;
              bezier = "fade";
              style = "popin 90%";
            }
            {
              leaf = "windows";
              enabled = true;
              speed = 7;
              bezier = "default";
              style = "slide";
            }
            {
              leaf = "windowsOut";
              enabled = true;
              speed = 3;
              bezier = "fade";
              style = "popin 90%";
            }
            {
              leaf = "fadeSwitch";
              enabled = true;
              speed = 7;
              bezier = "default";
            }
            {
              leaf = "fadeOut";
              enabled = true;
              speed = 3;
              bezier = "fade";
            }
            {
              leaf = "fadeLayers";
              enabled = true;
              speed = 3;
              bezier = "fade";
            }
            {
              leaf = "fadeLayersOut";
              enabled = true;
              speed = 2;
              bezier = "easeIn";
            }
            {
              leaf = "workspaces";
              enabled = true;
              speed = 4;
              bezier = "woosh";
              style = "slide";
            }
            {
              leaf = "layers";
              enabled = true;
              speed = 3;
              bezier = "fade";
              style = "popin 90%";
            }
            {
              leaf = "layersOut";
              enabled = true;
              speed = 2;
              bezier = "easeIn";
              style = "popin 90%";
            }
          ];
          config = {
            xwayland.force_zero_scaling = true;
            plugin = mkIf cfg.enable-plugins {
              split_monitor_workspaces.enable_persistent_workspaces = 0;
              #hyprexpo = {
              #  columns = 3;
              #  gap_size = 5;
              #  bg_col = "rgb(111111)";
              #  workspace_method = "first 1";
              #  enable_gesture = true;
              #  gesture_distance = 300;
              #  gesture_positive = true;
              #};
              #dynamic-cursors = {
              #  enabled = false;
              #  mode = "tilt";
              #  shake.enabled = false;
              #  stretch.function = "negative_quadratic";
              #};
              #hyprtrails = {
              #  color = "rgba(bbddffff)";
              #  bezier_step = 0.001;
              #  history_points = 6;
              #  points_per_step = 4;
              #  histoty_step = 1;
              #};
            };
            input = {
              kb_layout = "us,ru";
              kb_options = "grp:alt_shift_toggle";
              repeat_delay = 150;
              repeat_rate = 35;
              follow_mouse = 1;
              touchpad = {
                natural_scroll = true;
                scroll_factor = 0.5;
                clickfinger_behavior = true;
                tap_to_click = true;
                disable_while_typing = false;
              };
              touchdevice.enabled = true;
              sensitivity = 1;
              accel_profile = "flat";
            };
            gestures = {
              workspace_swipe_distance = 1000;
              workspace_swipe_invert = true;
              workspace_swipe_cancel_ratio = 0.1;
              workspace_swipe_forever = true;
              workspace_swipe_create_new = true;
              workspace_swipe_direction_lock = false;
            };
            general = {
              gaps_in = 5;
              gaps_out = 5;
              border_size = 0;
              #"col.active_border" = "rgb(4575da) rgb(6804b5)";
              #"col.inactive_border" = "rgb(595959)";
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
            };
            debug = {
              enable_stdout_logs = false;
              disable_logs = true;
            };
            dwindle = {
              preserve_split = true;
            };
            misc = {
              vrr = 1;
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
          };
          bind =
            let
              rofi = pkgs.writers.writeDash "rofi" ''
                pkill rofi || rofi \
                  -show drun \
                  -show-icons \
                  -hover-select \
                  -me-select-entry ''' \
                  -me-accept-entry MousePrimary \
                  -run-command '${pkgs.dash}/bin/dash -c '\'''
                      for arg do
                          case "$arg" in
                              *=*) 
                                  ;;
                              *) 
                                  exec_path="$arg"
                                  break
                                  ;;
                          esac
                      done

                      n=$(basename "$exec_path" | sed "s/\\\\x2d/-/g" | tr -cd "[:alnum:]. _-")
                      exec app2unit -a "$n" -- "$@"
                  '\''' -- {cmd}'
              '';
              rofi_cmd = pkgs.writers.writeDash "rofi_cmd" ''
                pkill rofi || rofi \
                  -show run \
                  -hover-select \
                  -me-select-entry ''' \
                  -me-accept-entry MousePrimary \
                  -run-command 'app2unit -- {cmd}'
              '';
            in
            bind-exec [
              [
                "code:122"
                "pactl set-sink-volume @DEFAULT_SINK@ -4096"
              ]
              [
                "code:123"
                "pactl set-sink-volume @DEFAULT_SINK@ +4096"
              ]
              [
                "Print"
                "app2unit -- env XDG_PICTURES_DIR=${config.xdg.userDirs.pictures} hyprshot -m region -z"
              ]
              [
                "${mod} + Print"
                "app2unit -- env XDG_PICTURES_DIR=${config.xdg.userDirs.pictures} hyprshot -m window -z"
              ]
              [
                "SHIFT + Print"
                "app2unit -- env XDG_PICTURES_DIR=${config.xdg.userDirs.pictures} hyprshot -m output -z"
              ]
              [
                "${mod} + O"
                "app2unit -- env XDG_PICTURES_DIR=${config.xdg.userDirs.pictures} hyprshot -m region -z"
              ]
              [
                "${mod} + ALT + O"
                "app2unit -- env XDG_PICTURES_DIR=${config.xdg.userDirs.pictures} hyprshot -m window -z"
              ]
              [
                "${mod} + SHIFT + O"
                "app2unit -- env XDG_PICTURES_DIR=${config.xdg.userDirs.pictures} hyprshot -m output -z"
              ]
              [
                "MENU"
                "app2unit -- ${read-text} region eng+osd"
              ]
              [
                "${mod} + MENU"
                "app2unit -- ${read-text} window eng+osd"
              ]
              [
                "SHIFT + MENU"
                "app2unit -- ${read-text} output eng+osd"
              ]
              [
                "CTRL + MENU"
                "app2unit -- ${read-text} region rus+osd"
              ]
              [
                "${mod} + MENU"
                "app2unit -- ${read-text} window rus+osd"
              ]
              [
                "SHIFT + MENU"
                "app2unit -- ${read-text} output rus+osd"
              ]
              [
                "CTRL + Print"
                "app2unit -- env XDG_PICTURES_DIR=${config.xdg.userDirs.pictures} hyprshot -z -m region -r d | swappy -f -"
              ]
              [
                "CTRL + ${mod} + Print"
                "app2unit -- env XDG_PICTURES_DIR=${config.xdg.userDirs.pictures} hyprshot -z -m window -r d | swappy -f -"
              ]
              [
                "CTRL + SHIFT + Print"
                "app2unit -- env XDG_PICTURES_DIR=${config.xdg.userDirs.pictures} hyprshot -z -m output -r d | swappy -f -"
              ] # change later to "Satty" https://github.com/gabm/Satty
              [
                "CTRL + ${mod} + O"
                "app2unit -- env XDG_PICTURES_DIR=${config.xdg.userDirs.pictures} hyprshot -z -m region -r d | swappy -f -"
              ]
              [
                "CTRL + ALT + ${mod} + O"
                "app2unit -- env XDG_PICTURES_DIR=${config.xdg.userDirs.pictures} hyprshot -z -m window -r d | swappy -f -"
              ]
              [
                "CTRL + SHIFT + ${mod} + O"
                "app2unit -- env XDG_PICTURES_DIR=${config.xdg.userDirs.pictures} hyprshot -z -m output -r d | swappy -f -"
              ] # change later to "Satty" https://github.com/gabm/Satty
              [
                "${mod} + CTRL + Q"
                "app2unit -- neovide --frame none +term +startinsert '+set laststatus=0 ruler' '+set cmdheight=0' '+map <c-t> :tabnew +term<enter>'"
              ]
              [
                "${mod} + CTRL + R"
                "app2unit -- killall -SIGUSR1 gpu-screen-recorder && notify-send 'GPU-Screen-Recorder' 'Повтор успешно сохранён'"
              ]
              [
                "${mod} + CTRL + U"
                "app2unit -- update-damn-nixos"
              ]
              [
                "${mod} + CTRL + V"
                "rofi -modi clipboard:cliphist-rofi -show clipboard -show-icons -hover-select -me-select-entry '' -me-accept-entry MousePrimary"
              ]
              [
                "${mod} + ALT + mouse_down"
                "hyprctl eval \"hl.config({ cursor = { zoom_factor = $(hyprctl getoption cursor:zoom_factor | grep float | awk '{print $2 + 1}') } })\""
              ]
              [
                "${mod} + ALT + mouse_up"
                "hyprctl eval \"hl.config({ cursor = { zoom_factor = $(hyprctl getoption cursor:zoom_factor | grep float | awk '{if ($2 >= 2) {print $2 - 1} else {print 1}}') } })\""
              ]
              [
                "${mod} + CTRL + mouse_down"
                "hyprctl eval \"hl.config({ cursor = { zoom_factor = $(hyprctl getoption cursor:zoom_factor | grep float | awk '{print $2 + 100}') } })\""
              ]
              [
                "${mod} + CTRL + mouse_up"
                "hyprctl eval \"hl.config({ cursor = { zoom_factor = $(hyprctl getoption cursor:zoom_factor | grep float | awk '{if ($2 >= 101) {print $2 - 100} else {print 1}}') } })\""
              ]
              [
                "${mod} + CTRL + C"
                "hyprctl kill"
              ]
              [
                "${mod} + I"
                "app2unit -- toggle-restriction"
              ]
              [
                "${mod} + F1"
                "app2unit -- gamemode.sh"
              ]
              [
                "${mod} + F2"
                "app2unit -- sheesh.sh"
              ]
              [
                "${mod} + H"
                "killall -SIGUSR1 .waybar-wrapped"
              ]
              [
                "${mod} + L"
                "hyprlock"
              ]
              [
                "${mod} + Q"
                "app2unit -- kitty"
              ]
              [
                "${mod} + Z"
                "app2unit -- zen-twilight"
              ]
              [
                "${mod} + B"
                "uuctl"
              ]
              [
                "${mod} + M"
                "app2unit -- wlogout -b 2 -L 500px -R 500px -c 30px -r 30px"
              ]
              [
                "${mod} + E"
                "app2unit -- pkill nautilus-listen; ${nautilus-listener}/bin/nautilus-listener & env NAUTILUS_4_EXTENSION_DIR='${pkgs.nautilus-python}/lib/nautilus/extensions-4' nautilus -w"
              ]
            ]
            ++ bind [
              [
                "ALT + R"
                "hl.dsp.submap 'passthrough'"
              ]
              [
                "${mod} + C"
                "hl.dsp.window.close()"
              ]
              [
                "${mod} + CTRL + F"
                "hl.dsp.window.fullscreen_state {internal = 0, client = 3}"
              ]
              [
                "${mod} + V"
                "hl.dsp.window.float()"
              ]
              [
                "${mod} + P"
                "hl.dsp.window.pseudo()"
              ]
              [
                "${mod} + J"
                "hl.dsp.layout 'togglesplit'"
              ]
              [
                "${mod} + F"
                "hl.dsp.window.fullscreen()"
              ]
              [
                "${mod} + left"
                "hl.dsp.focus { direction = 'l' }"
              ]
              [
                "${mod} + right"
                "hl.dsp.focus { direction = 'r' }"
              ]
              [
                "${mod} + up"
                "hl.dsp.focus { direction = 'u' }"
              ]
              [
                "${mod} + down"
                "hl.dsp.focus { direction = 'd' }"
              ]
              [
                "${mod} + 1"
                "function() hl.plugin.split_monitor_workspaces.workspace(1) end"
              ]
              [
                "${mod} + 2"
                "function() hl.plugin.split_monitor_workspaces.workspace(2) end"
              ]
              [
                "${mod} + 3"
                "function() hl.plugin.split_monitor_workspaces.workspace(3) end"
              ]
              [
                "${mod} + 4"
                "function() hl.plugin.split_monitor_workspaces.workspace(4) end"
              ]
              [
                "${mod} + 5"
                "function() hl.plugin.split_monitor_workspaces.workspace(5) end"
              ]
              [
                "${mod} + 6"
                "function() hl.plugin.split_monitor_workspaces.workspace(6) end"
              ]
              [
                "${mod} + 7"
                "function() hl.plugin.split_monitor_workspaces.workspace(7) end"
              ]
              [
                "${mod} + 8"
                "function() hl.plugin.split_monitor_workspaces.workspace(8) end"
              ]
              [
                "${mod} + 9"
                "function() hl.plugin.split_monitor_workspaces.workspace(9) end"
              ]
              [
                "${mod} + 0"
                "function() hl.plugin.split_monitor_workspaces.workspace(10) end"
              ]
              [
                "${mod} + SHIFT + 1"
                "function() hl.plugin.split_monitor_workspaces.move_to_workspace(1) end"
              ]
              [
                "${mod} + SHIFT + 2"
                "function() hl.plugin.split_monitor_workspaces.move_to_workspace(2) end"
              ]
              [
                "${mod} + SHIFT + 3"
                "function() hl.plugin.split_monitor_workspaces.move_to_workspace(3) end"
              ]
              [
                "${mod} + SHIFT + 4"
                "function() hl.plugin.split_monitor_workspaces.move_to_workspace(4) end"
              ]
              [
                "${mod} + SHIFT + 5"
                "function() hl.plugin.split_monitor_workspaces.move_to_workspace(5) end"
              ]
              [
                "${mod} + SHIFT + 6"
                "function() hl.plugin.split_monitor_workspaces.move_to_workspace(6) end"
              ]
              [
                "${mod} + SHIFT + 7"
                "function() hl.plugin.split_monitor_workspaces.move_to_workspace(7) end"
              ]
              [
                "${mod} + SHIFT + 8"
                "function() hl.plugin.split_monitor_workspaces.move_to_workspace(8) end"
              ]
              [
                "${mod} + SHIFT + 9"
                "function() hl.plugin.split_monitor_workspaces.move_to_workspace(9) end"
              ]
              [
                "${mod} + SHIFT + 0"
                "function() hl.plugin.split_monitor_workspaces.move_to_workspace(10) end"
              ]
              [
                "${mod} + S"
                "hl.dsp.workspace.toggle_special 'magic'"
              ]
              [
                "${mod} + SHIFT + S"
                "function() hl.plugin.split_monitor_workspaces.move_to_workspace 'special:magic' end"
              ]
              [
                "${mod} + mouse_down"
                "function() hl.plugin.split_monitor_workspaces.workspace 'e+1' end"
              ]
              [
                "${mod} + mouse_up"
                "function() hl.plugin.split_monitor_workspaces.workspace 'e-1' end"
              ]
              [
                "${mod} + CTRL + ${mod}_L "
                "hl.dsp.exec_raw [[${rofi_cmd}]]"
                { release = true; }
              ]
              [
                "${mod} + ${mod}_L"
                "hl.dsp.exec_raw [[${rofi}]]"
                { release = true; }
              ]
              [
                "${mod} + mouse:272"
                "hl.dsp.window.drag()"
                { mouse = true; }
              ]
              [
                "${mod} + mouse:273"
                "hl.dsp.window.resize()"
                { mouse = true; }
              ]
            ];
          window_rule = [
            {
              float = true;
              match.title = "Извлечённый текст";
            }
            {
              no_max_size = true;
              pin = true;
              match.class = "polkit-mate-authentication-agent-1";
            }
            {
              opacity = "0.99 override 0.99 override";
              match.title = "^(QDiskInfo|MainPicker)$";
            }
            {
              opacity = "0.99 override 0.99 override";
              match.class = "^(thunderbird|spotify|org.prismlauncher.PrismLauncher|mpv|org.qbittorrent.qBittorrent|die)$";
            }
            {
              float = true;
              match = {
                class = "steam";
                title = "negative:Steam";
              };
            }
            {
              fullscreen_state = "0 3";
              match = {
                class = "firefox";
                title = "^(.*Discord.* — Mozilla Firefox.*)$";
              };
            }
          ];
          permission = [
            {
              binary = "${lib.escapeRegex (lib.getExe pkgs.hyprpicker)}";
              type = "screencopy";
              mode = "allow";
            }
            {
              binary = "${lib.escapeRegex (lib.getExe pkgs.wayvr)}";
              type = "screencopy";
              mode = "allow";
            }
            {
              binary = "${lib.escapeRegex (lib.getExe pkgs.grim)}";
              type = "screencopy";
              mode = "allow";
            }
            {
              binary = "${lib.escapeRegex (lib.getExe config.programs.hyprlock.package)}";
              type = "screencopy";
              mode = "allow";
            }
            {
              binary = "${lib.escapeRegex "${config.wayland.windowManager.hyprland.portalPackage}"}/libexec/.xdg-desktop-portal-hyprland-wrapped";
              type = "screencopy";
              mode = "allow";
            }
          ]
          ++ mkPluginPermissionEntries plugins;
          layer_rule = [
            {
              blur = true;
              match.namespace = ".*";
            }
            {
              blur_popups = true;
              match.namespace = ".*";
            }
            {
              ignore_alpha = 0.9;
              no_anim = true;
              match.namespace = "selection";
            }
            {
              no_anim = true;
              match.namespace = "hyprpicker";
            }
            {
              ignore_alpha = 0;
              match.namespace = "^(corner0|overview|indicator0|launcher|quicksettings|swaync-control-center|rofi|waybar|swaync-notification-window)$";
            }
            {
              animation = "popin 90%";
              match.namespace = "^(rofi|logout_dialog)$";
            }
            {
              ignore_alpha = 0.02;
              animation = "slide left";
              match.namespace = "swaync-control-center";
            }
            {
              ignore_alpha = 0.02;
              match.namespace = "swaync-notification-window";
            }
          ];
          on = [
            {
              _args = [
                "hyprland.start"
                (lib.generators.mkLuaInline ''
                  function () 
                    ${mkPluginExecEntries plugins}
                    hl.exec_cmd [[kbuildsycoca6]]
                    hl.exec_cmd [[${nautilus-listener}/bin/nautilis-listener]]
                    hl.exec_cmd [[app2unit -- wl-paste --watch cliphist store]]
                    hl.exec_cmd [[fumon]]
                  end
                '')
              ];
            }
          ];
        };
      #extraConfig = ''
      #  hl.submap({
      #    name = "passthrough",
      #    binds = {
      #      { mods = {}, key = "escape", dispatcher = "submap", args = "reset" }
      #    }
      #  })
      #'';
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
    xdg = {
      dataFile.nautilus-python = {
        source = "${nautilus-extensions}/share/nautilus-python";
        recursive = true;
      };
      portal = {
        enable = true;
        extraPortals = [
          pkgs.xdg-desktop-portal-gtk
        ];
        config.common.default = "*";
      };
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
    services = {
      hypridle = {
        enable = true;
        settings = {
          listener = [
            {
              timeout = 300;
              on-timeout = ''hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })' '';
              on-resume = ''hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })' '';
            }
            {
              timeout = 10;
              on-timeout = ''pidof hyprlock && hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })' '';
              on-resume = ''hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })' '';
            }
          ];
        };
      };
    };
    systemd.user.services = {
      swaybg = {
        Service = {
          ExecStart = "${pkgs.swaybg}/bin/swaybg -m fill -i ${../../../stuff/wallpaper.png}";
          Restart = "on-failure";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
      mpvpaper = mkIf (!cfg.wallpaper && cfg.mpvpaper) {
        Install.WantedBy = [ "graphical-session.target" ];
        Service = {
          ExecStart = "${pkgs.mpvpaper}/bin/mpvpaper -s -o 'no-audio loop input-ipc-server=/tmp/mpvpaper-socket hwdec=auto' '*' ${../../../stuff/wallpaper.mp4}";
          Restart = "on-failure";
        };
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
          action = "uwsm stop";
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
