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
      #inputs.split-monitor-workspaces.packages.${pkgs.stdenv.hostPlatform.system}.split-monitor-workspaces
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
in
{
  options.hyprland = {
    enable = mkEnableOption "my Hyprland configuration";
    from-unstable = mkEnableOption "Use Hyprland package from UNSTABLE nixpkgs";
    stable = mkEnableOption "Use Hyprland from nixpkgs";
    enable-plugins = mkEnableOption "Hyprland plugins";
    additional-monitors = mkOption {
      default = [ ];
      type = lib.types.listOf lib.types.attrs;
    };
  };

  config = mkIf cfg.enable {
    home.sessionVariables.NAUTILUS_4_EXTENSION_DIR = "${pkgs.nautilus-python}/lib/nautilus/extensions-4";

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
      systemd.enable = false;
      configType = "lua";
      extraLuaFiles."00-init" = {
        autoLoad = true;
        content = ''
          smw = require('plugins.split-monitor-workspaces')
          smw.setup({ enable_persistent_workspaces = false })
        '';
      };
      submaps.passthrough.settings.bind = [
        {
          _args = [
            "escape"
            (lib.generators.mkLuaInline "hl.dsp.submap('reset')")
          ];
        }
      ];
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
              leaf = "fadePopups";
              enabled = false;
            }
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
              mouse_refocus = true;
              float_switch_override_focus = 1;
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
              no_update_news = true;
              enforce_permissions = true;
            };
            cursor = {
              no_warps = false;
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
              vrr = 0;
              enable_anr_dialog = false;
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
              scroll_event_delay = 60;
            };
          };
          bind =
            let
              kill-cgroup = pkgs.writeShellScript "hypr-kill-cgroup" ''
                set -euo pipefail

                POS=$(slurp -p)
                X="''${POS%%,*}"
                Y="''${POS#*,}"

                ACTIVE_WS=$(hyprctl monitors -j | jq -c '[.[].activeWorkspace.id]')

                CLIENT_INFO=$(hyprctl clients -j | jq -r --argjson x "$X" --argjson y "$Y" --argjson active_ws "$ACTIVE_WS" '
                  .[] | select(.workspace.id as $w | $active_ws | contains([$w])) |
                  select(.at[0] <= $x and $x <= (.at[0] + .size[0]) and
                         .at[1] <= $y and $y <= (.at[1] + .size[1])) |
                  {pid: .pid, class: .class}
                ' | head -n 1)

                PID=$(echo "$CLIENT_INFO" | jq -r '.pid // empty')
                WM_CLASS=$(echo "$CLIENT_INFO" | jq -r '.class // "Window"')

                if [[ -z "$PID" || "$PID" == "null" || "$PID" == "0" ]]; then
                  notify-send -u low "Cgroup Killer" "No window found at position"
                  exit 1
                fi

                UNIT=$(ps -o unit= -p "$PID" | tr -d ' ')
                PROTECTED_PATTERN="^(hyprland|wayland-wm.*|dbus.*|init\.scope|user@.*|systemd-.*)$"
                KILLED=0

                if [[ -n "$UNIT" && "$UNIT" =~ \.(service|scope)$ ]] && ! [[ "$UNIT" =~ $PROTECTED_PATTERN ]]; then
                  if systemctl --user is-active --quiet "$UNIT" 2>/dev/null; then
                    systemctl --user stop "$UNIT"
                    notify-send -u normal "Cgroup Killer" "Stopped unit: $UNIT ($WM_CLASS)"
                    KILLED=1
                  elif systemctl is-active --quiet "$UNIT" 2>/dev/null; then
                    systemctl stop "$UNIT"
                    notify-send -u normal "Cgroup Killer" "Stopped system unit: $UNIT ($WM_CLASS)"
                    KILLED=1
                  fi
                fi
              '';
              save-replay = pkgs.writers.writeDash "save-replay" ''
                MON_NAME=$(hyprctl activeworkspace -j | ${pkgs.jq}/bin/jq -r '.monitor')
                pkill -SIGUSR1 -f "gpu-screen-recorder.*-w $MON_NAME.*" && \
                notify-send 'GPU-Screen-Recorder' "Повтор с $MON_NAME успешно сохранён"
              '';
            in
            bind-exec [
              [
                "code:122"
                "noctalia msg volume-down"
              ]
              [
                "code:123"
                "noctalia msg volume-up"
              ]
              [
                "code:121"
                "noctalia msg volume-mute"
              ]
              [
                "code:232"
                "noctalia msg brightness-down"
              ]
              [
                "code:233"
                "noctalia msg brightness-up"
              ]
              [
                "Print"
                "noctalia msg screenshot-region"
              ]
              [
                "SHIFT + Print"
                "noctalia msg screenshot-fullscreen"
              ]
              [
                "${mod} + O"
                "noctalia msg screenshot-region"
              ]
              [
                "${mod} + SHIFT + O"
                "noctalia msg screenshot-fullscreen"
              ]
              [
                "CTRL + Print"
                "noctalia msg screenshot-region 'satty -f -'"
              ]
              [
                "CTRL + SHIFT + Print"
                "noctalia msg screenshot-fullscreen 'satty -f -'"
              ]
              [
                "${mod} + CTRL + O"
                "noctalia msg screenshot-region 'satty -f -'"
              ]
              [
                "${mod} + CTRL + SHIFT + O"
                "noctalia msg screenshot-fullscreen 'satty -f -'"
              ]
              [
                "${mod} + CTRL + Q"
                "app2unit -- kitty"
              ]
              [
                "${mod} + CTRL + R"
                "app2unit -- ${save-replay}"
              ]
              [
                "${mod} + CTRL + U"
                "app2unit -- update-damn-nixos"
              ]
              [
                "${mod} + CTRL + V"
                "noctalia msg panel-toggle clipboard"
              ]
              [
                "${mod} + ALT + mouse_up"
                "hyprctl eval \"hl.config({ cursor = { zoom_factor = $(hyprctl getoption cursor:zoom_factor | grep float | awk '{print $2 + 1}') } })\""
              ]
              [
                "${mod} + ALT + mouse_down"
                "hyprctl eval \"hl.config({ cursor = { zoom_factor = $(hyprctl getoption cursor:zoom_factor | grep float | awk '{if ($2 >= 2) {print $2 - 1} else {print 1}}') } })\""
              ]
              [
                "${mod} + CTRL + mouse_up"
                "hyprctl eval \"hl.config({ cursor = { zoom_factor = $(hyprctl getoption cursor:zoom_factor | grep float | awk '{print $2 + 100}') } })\""
              ]
              [
                "${mod} + CTRL + mouse_down"
                "hyprctl eval \"hl.config({ cursor = { zoom_factor = $(hyprctl getoption cursor:zoom_factor | grep float | awk '{if ($2 >= 101) {print $2 - 100} else {print 1}}') } })\""
              ]
              [
                "${mod} + CTRL + C"
                "hyprctl kill"
              ]
              [
                "${mod} + ALT + CTRL + C"
                "${kill-cgroup}"
              ]
              [
                "${mod} + I"
                "app2unit -- toggle-restriction"
              ]
              [
                "${mod} + F2"
                "app2unit -- sheesh.sh"
              ]
              [
                "${mod} + H"
                "noctalia msg bar-toggle"
              ]
              [
                "${mod} + L"
                "noctalia msg session lock"
              ]
              [
                "${mod} + Q"
                "app2unit -- xdg-terminal-exec"
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
                "noctalia msg panel-toggle session"
              ]
              [
                "${mod} + E"
                "app2unit -- nautilus -w"
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
                "smw.workspace('1')"
              ]
              [
                "${mod} + 2"
                "smw.workspace('2')"
              ]
              [
                "${mod} + 3"
                "smw.workspace('3')"
              ]
              [
                "${mod} + 4"
                "smw.workspace('4')"
              ]
              [
                "${mod} + 5"
                "smw.workspace('5')"
              ]
              [
                "${mod} + 6"
                "smw.workspace('6')"
              ]
              [
                "${mod} + 7"
                "smw.workspace('7')"
              ]
              [
                "${mod} + 8"
                "smw.workspace('8')"
              ]
              [
                "${mod} + 9"
                "smw.workspace('9')"
              ]
              [
                "${mod} + 0"
                "smw.workspace('10')"
              ]
              [
                "${mod} + SHIFT + 1"
                "smw.move_to_workspace('1')"
              ]
              [
                "${mod} + SHIFT + 2"
                "smw.move_to_workspace('2')"
              ]
              [
                "${mod} + SHIFT + 3"
                "smw.move_to_workspace('3')"
              ]
              [
                "${mod} + SHIFT + 4"
                "smw.move_to_workspace('4')"
              ]
              [
                "${mod} + SHIFT + 5"
                "smw.move_to_workspace('5')"
              ]
              [
                "${mod} + SHIFT + 6"
                "smw.move_to_workspace('6')"
              ]
              [
                "${mod} + SHIFT + 7"
                "smw.move_to_workspace('7')"
              ]
              [
                "${mod} + SHIFT + 8"
                "smw.move_to_workspace('8')"
              ]
              [
                "${mod} + SHIFT + 9"
                "smw.move_to_workspace('9')"
              ]
              [
                "${mod} + SHIFT + 0"
                "smw.move_to_workspace('10')"
              ]
              [
                "${mod} + S"
                "hl.dsp.workspace.toggle_special 'magic'"
              ]
              [
                "${mod} + SHIFT + S"
                "smw.move_to_workspace 'special:magic'"
              ]
              [
                "${mod} + mouse_up"
                "smw.workspace 'e+1'"
              ]
              [
                "${mod} + mouse_down"
                "smw.workspace 'e-1'"
              ]
              [
                "${mod} + CTRL + ${mod}_L "
                "hl.dsp.exec_raw [[noctalia-run]]"
                { release = true; }
              ]
              [
                "${mod} + ${mod}_L"
                "hl.dsp.exec_raw [[noctalia msg panel-toggle launcher]]"
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
              opacity = "0.99 override 0.99 override";
              match.title = "^(QDiskInfo|MainPicker)$";
            }
            {
              float = true;
              match = {
                class = "steam";
                title = "negative:Steam";
              };
            }
          ];
          permission = [
            {
              binary = "${lib.escapeRegex (lib.getExe pkgs.wayvr)}";
              type = "screencopy";
              mode = "allow";
            }
            {
              binary = "${lib.escapeRegex "${config.programs.noctalia.package}/bin/.noctalia-wrapped"}";
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
              ignore_alpha = 0;
              match.namespace = "^noctalia-.*$";
            }
            {
              no_anim = true;
              match.namespace = "^noctalia-.*$";
            }
          ];
          on = [
            {
              _args = [
                "hyprland.start"
                (lib.generators.mkLuaInline ''
                  function () 
                    ${mkPluginExecEntries plugins}
                    hl.exec_cmd [[app2unit -s b -- kbuildsycoca6]]
                    hl.exec_cmd [[app2unit -s b -- ${nautilus-listener}/bin/nautilus-listener]]
                    hl.exec_cmd [[app2unit -s b -- fumon]]
                    hl.exec_cmd [[app2unit -s b -- xhost +si:localuser:root]]
                    hl.exec_cmd [[app2unit -s b -- dash -c 'echo "Xft.dpi: 96" | xrdb -merge']]
                  end
                '')
              ];
            }
          ];
        };
    };
    xdg = {
      configFile."hypr/plugins/split-monitor-workspaces".source = inputs.split-monitor-workspaces;
      dataFile.nautilus-python.source = "${nautilus-extensions}/share/nautilus-python";
      portal = {
        enable = true;
        extraPortals = [
          pkgs.xdg-desktop-portal-gtk
        ];
        config.common.default = "*";
      };
    };
    programs = {
      noctalia = {
        enable = true;
        systemd.enable = true;
        package = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (prev: {
          patches = (prev.patches or [ ]) ++ [ ../../../stuff/patches/noctalia.patch ];
        });
        customPalettes.transparent-blue = {
          id = "transparent-blue";
          name = "Transparent Blue";
          dark = {
            primary = "#2362ba";
            onPrimary = "#ffffff";
            secondary = "#7aa2f7";
            onSecondary = "#0a1120";
            tertiary = "#4575da";
            onTertiary = "#ffffff";
            error = "#ff5e5e";
            onError = "#ffffff";
            surface = "#00000033";
            onSurface = "#dddddd";
            surfaceVariant = "#00000033";
            onSurfaceVariant = "#9bb0c9";
            outline = "#00000000"; # Disabled static non-hover outlines
            shadow = "#000000";
            hover = "#2362ba55";
            onHover = "#ffffff";
            terminal = {
              foreground = "#dddddd";
              background = "#000000";
              selectionFg = "#ffffff";
              selectionBg = "#2362ba";
              cursorText = "#000000";
              cursor = "#7aa2f7";
              normal = {
                black = "#161a22";
                red = "#d78787";
                green = "#a6e3a1";
                yellow = "#fab387";
                blue = "#2362ba";
                magenta = "#cca0e4";
                cyan = "#7aa2f7";
                white = "#dddddd";
              };
              bright = {
                black = "#525866";
                red = "#ff5e5e";
                green = "#a6e3a1";
                yellow = "#fab387";
                blue = "#79b4fc";
                magenta = "#cca0e4";
                cyan = "#7aa2f7";
                white = "#ffffff";
              };
            };
          };
          light = {
            primary = "#2362ba";
            onPrimary = "#ffffff";
            secondary = "#3275a8";
            onSecondary = "#ffffff";
            tertiary = "#4575da";
            onTertiary = "#ffffff";
            error = "#d78787";
            onError = "#ffffff";
            surface = "#00000033";
            onSurface = "#111827";
            surfaceVariant = "#00000033";
            onSurfaceVariant = "#334155";
            outline = "#00000000";
            shadow = "#000000";
            hover = "#2362ba55";
            onHover = "#ffffff";
            terminal = {
              foreground = "#111827";
              background = "#f5f7fb";
              selectionFg = "#ffffff";
              selectionBg = "#2362ba";
              cursorText = "#ffffff";
              cursor = "#2362ba";
              normal = {
                black = "#1e293b";
                red = "#c01c28";
                green = "#26a269";
                yellow = "#d97706";
                blue = "#2362ba";
                magenta = "#8b5cf6";
                cyan = "#0284c7";
                white = "#cbd5e1";
              };
              bright = {
                black = "#64748b";
                red = "#dc2626";
                green = "#16a34a";
                yellow = "#f59e0b";
                blue = "#3b82f6";
                magenta = "#a855f7";
                cyan = "#38bdf8";
                white = "#f8fafc";
              };
            };
          };
        };

        # Noctalia Settings: Exact merge of your settings.toml + config.toml (filtered non-defaults)
        settings = {
          theme = {
            source = "custom";
            custom_palette = "transparent-blue";
          };

          wallpaper.default.path = ../../../stuff/wallpaper.png;

          audio.enable_overdrive = true;
          control_center.calendar.show_events_card = false;
          location.auto_locate = true;
          osd.background_opacity = 0.25;
          system.monitor.gpu_poll_seconds = 1;

          lockscreen = {
            blurred_desktop = true;
            blur_intensity = 0.6;
          };

          shell = {
            font_family = "Noto Sans";
            setup_wizard_enabled = false;
            card_borders = false;
            settings_window_translucent = true;
            popup_shadows = false;
            launch_apps_custom_command = "app2unit-wrapped $CMD";

            clipboard_history_max_entries = 1000;
            polkit_agent = true;

            screenshot.directory = "~/Pictures/Screenshots";

            panel = {
              control_center_placement = "floating";
              wallpaper_placement = "floating";
              session_placement = "floating";
              open_near_click_control_center = true;
              open_near_click_session = true;
              open_near_click_launcher = true;
              transparency_mode = "glass";
              background_opacity = 0.18;
              card_opacity = 0.30;
              borders = false;
              shadow = false;
            };

            session.actions = [
              { action = "lock"; }
              {
                action = "logout";
                command = "app2unit -- hyprlogout";
              }
              {
                action = "suspend";
                command = "systemctl suspend";
              }
              {
                action = "reboot";
                command = "app2unit -- hyprshutdown -t 'Перезагрузка...' --post-cmd 'systemctl reboot'";
              }
              {
                action = "shutdown";
                command = "app2unit -- hyprshutdown -t 'Выключение...' --post-cmd 'systemctl poweroff'";
                variant = "destructive";
              }
            ];

            animation = {
              scroll_speed = 0.2;
              scroll_step = 160.0;
              tab_switch_speed = 1.5;
              workspace_speed = 1.2;
            };
          };

          notification = {
            position = "top_left";
            background_opacity = 0.25;
          };

          bar.default = {
            position = "top";
            thickness = 32;
            margin_edge = 0;
            margin_ends = 0;
            padding = 0;
            capsule_thickness = 1.0;
            capsule = false;
            background_opacity = 0.0;
            shadow = false;

            start = [ "group:left" ];
            center = [ "group:center" ];
            end = [ "group:right" ];

            capsule_group = [
              {
                id = "left";
                members = [
                  "session"
                  "clock"
                  "workspaces"
                  "notifications"
                  "vpn"
                  "tray"
                ];
                fill = "#00000033";
                padding = 10.0;
                radius_top_left = 0.0;
                radius_top_right = 0.0;
                radius_bottom_right = 15.0;
                radius_bottom_left = 0.0;
              }
              {
                id = "center";
                members = [ "active_window" ];
                fill = "#00000033";
                padding = 18.0;
                radius_top_left = 0.0;
                radius_top_right = 0.0;
                radius_bottom_right = 15.0;
                radius_bottom_left = 15.0;
              }
              {
                id = "right";
                members = [
                  "input_volume"
                  "volume"
                  "bluetooth"
                  "network"
                  "battery"
                  "cpu"
                  "control-center"
                ];
                fill = "#00000033";
                padding = 10.0;
                radius_top_left = 0.0;
                radius_top_right = 0.0;
                radius_bottom_right = 0.0;
                radius_bottom_left = 15.0;
              }
            ];
          };

          widget = {
            workspaces = {
              show_labels = false;
              pill_scale = 0.70;
              active_pill_size = 2.2;
              inactive_pill_size = 0.9;
              persistent_count = 10;
              capsule_radius = 8.0;
              focused_color = "#2362ba";
              occupied_color = "#DDDDDD";
              empty_color = "#555555";
            };

            active_window = {
              icon_size = 18.0;
              min_length = 0.0;
              max_length = 300.0;
            };

            volume.show_label = true;
            battery.show_label = true;
            network.show_label = true;

            cpu = {
              type = "sysmon";
              stat = "cpu_usage";
              show_glyph = true;
              show_value = true;
              glyph_position = "after";
            };
          };
        };
      };
      satty = {
        enable = true;
        settings = {
          general = {
            fullscreen = false;
            resize.mode = "smart";
            floating-hack = true;
            auto-copy = false;
            early-exit = [ "all" ];
            corner-roundness = 12;
            initial-tool = "brush";
            copy-command = "wl-copy --type image/png";
            annotation-size-factor = 2;
            output-filename = "${config.xdg.userDirs.pictures}/satty-%Y-%m-%d_%H:%M:%S.png";
            save-after-copy = true;
            default-hide-toolbars = false;
            focus-toggles-toolbars = false;
            default-fill-shapes = false;
            primary-highlighter = "block";
            disable-notifications = false;
            actions-on-enter = [ "save-to-clipboard" ];
            actions-on-escape = [ "exit" ];
            action-on-enter = "save-to-clipboard";
            right-click-copy = false;
            no-window-decoration = true;
            brush-smooth-history-size = 0;
            pan-step-size = 50.0;
            zoom-factor = 1.1;
            text-move-length = 50.0;
            input-scale = 1.0;
            title = "Satty";
            app-id = "org.satty.satty";
          };
          keybinds = {
            pointer = "p";
            crop = "c";
            brush = "b";
            line = "i";
            arrow = "z";
            rectangle = "r";
            ellipse = "e";
            text = "t";
            marker = "m";
            blur = "u";
            highlight = "g";
          };
          font = {
            family = "JetBrainsMono NF";
            style = "Regular";
            fallback = [ "Noto Sans CJK SC" ];
          };
          color-palette.palette = [
            "#f0932bff"
            "#eb4d4bff"
            "#6ab04cff"
            "#22a6b3ff"
            "#130f40FF"
          ];
        };
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
  };
}
