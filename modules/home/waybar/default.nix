{
  config,
  inputs,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.waybar;
in
{
  options.waybar = {
    enable = mkEnableOption "waybar panel";
  };

  config = mkIf cfg.enable {
    programs.waybar = {
      enable = true;
      package = inputs.waybar.packages.${pkgs.stdenv.hostPlatform.system}.default;
      systemd.enable = true;
      style = ''
        @define-color accent #2362ba;

        * {
          font-family: "Noto Sans", "JetBrainsMono NF";
          font-size: 13px;
          font-weight: 600;
          color: #DDDDDD;
          min-height: 0px;
          min-width: 0px;
        }

        #waybar {
          background: none;
        }
        tooltip {
          background-color: rgba(0,0,0,0.1);
          text-shadow: none;
        }
        .modules-left {
          background: rgba(0,0,0,0.2);
          border-radius: 0 0 15px 0;
          padding: 0 10px 0 0;
        }
        .modules-center {
          background: rgba(0,0,0,0.2);
          border-radius: 0 0 15px 15px;
          padding: 0 20px;
        }
        .modules-right {
          background: rgba(0,0,0,0.2);
          border-radius: 0 0 0 15px;
          padding: 0 0 0 10px;
        }
        window#waybar.empty .modules-center {
          background: none;
        }

        #scroll, #cava, #clock, #hardware, #scripts, #window, 
        #cpu, #custom-amd-gpu, #custom-nvidia-gpu, #network, 
        #pulseaudio, #pulseaudio-mic, #custom-lock, #custom-reboot, 
        #custom-logout, #custom-shutdown, #custom-notification, 
        #custom-weather, #batteries, #tray {
          border-radius: 8px;
        }
        #batteries {
          margin-right: 0;
          margin-left: 6px;
          border-radius: 8px 0px 0px 8px;
        }

        #custom-nixos {
          border-radius: 0px;
          padding: 0px;
          margin-left: 8px;
        }

        #cava { padding: 5px 10px 0px 10px; color: #4575DA; }
        #custom-notification { padding: 0px 10px 0px 8px; margin-left: 6px; }
        #tray { padding: 0px 8px 0px 8px; }
        #custom-shutdown { padding: 0 13px 0 8px; margin-left: 4px; }
        #custom-lock { padding: 0 13px 0 8px; }
        #custom-logout { padding: 0 10px 0 10px; }
        #custom-reboot { padding: 0 12px 0 8px; }
        #custom-github { padding-right: 6px; }
        #clock { padding: 0px 5px; }

        #cpu, #network, #custom-vpn, #battery, #custom-cputemp, 
        #bluetooth, #submap, #idle_inhibitor, #gamemode, #custom-camera, 
        #custom-recorder, #custom-batterysaver, #disk, #memory, 
        #pulseaudio, #pulseaudio.mic, #backlight {
          padding: 0px 6px 0px 3px;
        }

        #custom-nixos label { font-size: 20px; }
        #custom-shutdown label,
        #custom-lock label,
        #custom-logout label,
        #custom-reboot label { font-size: 18px; }
        #custom-notification label, 
        #custom-cog label { font-size: 16px; }

        #window {
          font-size: 14px;
          opacity: 100;
          transition: opacity 1s ease-in-out;
        }
        window#waybar.empty #window {
          opacity: 0;
        }

        #custom-notification, #cpu, #network, #custom-nvidia-gpu, 
        #custom-amd-gpu, #pulseaudio, #pulseaudio-mic, #custom-logout, 
        #custom-reboot, #custom-shutdown, #custom-lock {
          margin-top: 2px;
          margin-bottom: 2px;
          transition: background-color 200ms;
        }
        #custom-notification:hover, #cpu:hover, #network:hover, 
        #custom-amd-gpu:hover, #custom-nvidia-gpu:hover, 
        #pulseaudio:hover, #pulseaudio-mic:hover, #custom-logout:hover, 
        #custom-reboot:hover, #custom-shutdown:hover, #custom-lock:hover {
          transition: background-color 200ms;
          background-color: rgba(255,255,255,0.2);
        }

        #gamemode, #submap, #custom-recorder, #custom-vpn, 
        #custom-github, #bluetooth.connected {
          background: shade(alpha(@foreground, 0.1), 0.8);
          border-radius: 8px;
        }

        #language { color: #7aa2f7; margin-top: 3px; }
        #idle_inhibitor, #pulseaudio, #pulseaudio.mic { color: #7aa2f7; }
        #backlight { color: #fab387; }
        #memory { color: shade(#cca0e4, 0.8); }
        #disk { color: shade(#7aa2f7, 0.8); }
        #cpu { color: shade(#a6e3a1, 0.8); }
        #network { color: #a6e3a1; }
        #network.disabled, #network.disconnected { color: #d78787; }

        #custom-recorder label { color: #d78787; }
        #custom-batterysaver.powersave label,
        #custom-batterysaver.power label {
          color: #a6e3a1;
        }
        #custom-batterysaver.default label,
        #custom-batterysaver.normal label {
          color: #7aa2f7;
        }
        #custom-batterysaver.performance label {
          color: #d78787;
        }

        @keyframes workspacesanim {
          0% { background: linear-gradient(to bottom, rgba(0,0,0,0) 20px, @accent 20px); }
          10% { background: linear-gradient(to bottom, rgba(0,0,0,0) 18px, @accent 18px); }
          20% { background: linear-gradient(to bottom, rgba(0,0,0,0) 16px, @accent 16px); }
          30% { background: linear-gradient(to bottom, rgba(0,0,0,0) 14px, @accent 14px); }
          40% { background: linear-gradient(to bottom, rgba(0,0,0,0) 12px, @accent 12px); }
          50% { background: linear-gradient(to bottom, rgba(0,0,0,0) 10px, @accent 10px); }
          60% { background: linear-gradient(to bottom, rgba(0,0,0,0) 8px, @accent 8px); }
          70% { background: linear-gradient(to bottom, rgba(0,0,0,0) 6px, @accent 6px); }
          80% { background: linear-gradient(to bottom, rgba(0,0,0,0) 4px, @accent 4px); }
          90% { background: linear-gradient(to bottom, rgba(0,0,0,0) 2px, @accent 2px); }
          100% { background: linear-gradient(to bottom, rgba(0,0,0,0) 0px, @accent 0px); }
        }
        @keyframes blink {
          to { background-color: alpha(red, 0.6); color: @foreground; }
        }
        @keyframes blink-blue {
          to { background-color: alpha(#7aa2f7, 0.6); color: @foreground; }
        }

        #workspaces button label {
          font-size: 16px;
        }
        #workspaces button {
          padding: 0px 10px 0 4px;
          margin: 4px 0px;
          border-radius: 5px;
        }
        #workspaces button:nth-child(1) { border-radius: 10px 5px 5px 10px; }
        #workspaces button:nth-child(10) { border-radius: 5px 10px 10px 5px; }
        #workspaces button:hover {
          background-color: rgba(255,255,255,0.25);
        }
        #workspaces button.urgent {
          background-color: #3275a8;
        }
        #workspaces button.active {
          animation-name: workspacesanim;
          animation-fill-mode: both;
          animation-duration: 300ms;
          animation-direction: normal;
        }

        #battery.warning:not(.charging),
        #battery.critical:not(.charging) {
          animation: blink 1s linear infinite alternate;
        }
        #bluetooth.discoverable,
        #bluetooth.discovering,
        #bluetooth.pairable {
          animation: blink-blue 1s linear infinite alternate;
        }
      '';

      settings = {
        main = {
          layer = "top";
          position = "top";
          modules-left = [
            "group/powermenu"
            "group/stuff"
          ];
          modules-center = [
            "hyprland/window"
          ];
          modules-right = [
            "tray"
            "bluetooth"
            "group/scroll"
            "group/scripts"
            "group/batteries"
            "group/hardware"
          ];

          "group/powermenu" = {
            orientation = "horizontal";
            modules = [
              "custom/nixos"
              "custom/shutdown"
              "custom/reboot"
              "custom/logout"
              "custom/lock"
            ];
            drawer = {
              "children-class" = "power-menu";
              "transition-duration" = 500;
              "transition-left-to-right" = true;
            };
          };
          "group/stuff" = {
            orientation = "horizontal";
            modules = [
              "clock"
              "hyprland/workspaces"
              "custom/notification"
            ];
          };
          "group/scroll" = {
            orientation = "horizontal";
            modules = [
              "pulseaudio#mic"
              "pulseaudio"
              "backlight"
            ];
          };
          "group/batteries" = {
            orientation = "horizontal";
            modules = [
              "custom/batterysaver"
              "battery"
            ];
          };
          "group/scripts" = {
            orientation = "horizontal";
            modules = [
              "hyprland/submap"
              "idle_inhibitor"
              "gamemode"
            ];
          };
          "group/hardware" = {
            orientation = "horizontal";
            modules = [
              "custom/cog"
              "network"
              "memory"
              "custom/cputemp"
              "cpu"
              "custom/amd-gpu"
              "custom/nvidia-gpu"
            ];
            drawer = {
              "children-class" = "fancy-stuff";
              "transition-duration" = 500;
              "transition-left-to-right" = false;
            };
          };

          "hyprland/window" = {
            format = "{}";
            icon = true;
            icon-size = 18;
            rewrite = {
              "(.*)Mozilla Firefox" = "Mozilla Firefox";
              "(.*)Ablaze Floorp" = "Ablaze Floorp";
            };
          };
          "hyprland/workspaces" = {
            format = "{icon}";
            on-click = "activate";
            all-outputs = true;
            persistent-workspaces = {
              "1" = [ ];
              "2" = [ ];
              "3" = [ ];
              "4" = [ ];
              "5" = [ ];
              "6" = [ ];
              "7" = [ ];
              "8" = [ ];
              "9" = [ ];
              "10" = [ ];
            };
            format-icons = {
              "empty" = "";
              "default" = "";
            };
          };
          "hyprland/submap" = {
            format = "{}";
            tooltip = false;
          };

          "custom/nixos" = {
            exec = "nixos";
            return-type = "json";
            on-click = "rofi -show drun -show-icons -hover-select -me-select-entry '' -me-accept-entry MousePrimary";
            format = "{}";
            tooltip = true;
          };
          "custom/shutdown" = {
            format = "<span color='#ff5e5e'></span>";
            on-click = "systemctl poweroff";
            tooltip = false;
          };
          "custom/reboot" = {
            format = "<span color='#79b4fc'>󰑓</span>";
            on-click = "systemctl reboot";
            tooltip = false;
          };
          "custom/logout" = {
            format = "<span color='#63c773'>󰍃</span>";
            on-click = "uwsm stop; loginctl terminate-user \"\"";
            tooltip = false;
          };
          "custom/lock" = {
            format = "<span color='#787878'></span>";
            on-click = "hyprlock";
            tooltip = false;
          };

          "custom/cog" = {
            format = "  ";
            tooltip = false;
          };
          "custom/notification" = {
            tooltip = false;
            format = "{icon}";
            format-icons = {
              "notification" = "󱅫";
              "none" = "󰂚";
              "dnd-notification" = "󰂛";
              "dnd-none" = "󰂛";
              "inhibited-notification" = "󱅫";
              "inhibited-none" = "󰂚";
              "dnd-inhibited-notification" = "󰂛";
              "dnd-inhibited-none" = "󰂛";
            };
            return-type = "json";
            exec-if = "which swaync-client";
            exec = "swaync-client -swb";
            on-click = "sleep 0.1 && swaync-client -t -sw";
            on-click-right = "sleep 0.1 && swaync-client -d -sw";
            escape = false;
          };
          "custom/cputemp" = {
            interval = 3;
            tooltip = true;
            return-type = "json";
            exec = "cpu-temp";
            format = "<span color='#7AA2F7'>{}</span>";
          };
          "custom/batterysaver" = {
            format = "{}";
            exec = "power-menu getdata";
            on-click = "power-menu menu";
            interval = "once";
            return-type = "json";
            signal = 5;
          };
          "custom/nvidia-gpu" = {
            interval = 1;
            exec = "nvidia-gpu";
            on-click = "kitty nvtop";
            return-type = "json";
            format = "{}";
            tooltip = true;
          };
          "custom/amd-gpu" = {
            interval = 2;
            exec = "amd-gpu";
            on-click = "kitty nvtop";
            return-type = "json";
            format = "{}";
            tooltip = true;
          };
          "custom/vpn" = {
            format = " 󰖂";
            exec = "echo '{\"class\": \"connected\"}'";
            exec-if = "test -d /proc/sys/net/ipv4/conf/tun0";
            return-type = "json";
            interval = 5;
          };
          "custom/weather" = {
            format = "{}°";
            tooltip = true;
            interval = 3600;
            exec = "wttrbar";
            return-type = "json";
          };
          "custom/camera" = {
            format = "{} ";
            interval = "once";
            exec = "[ -z \"$(lsmod | grep uvcvideo)\" ] && echo \"\nКамера отключена\" || echo \"\"";
            on-click = "~/.config/hypr/bin/camera-toggle";
            signal = 3;
          };
          "custom/recorder" = {
            format = "{}";
            interval = "once";
            exec = "echo ''";
            tooltip = "false";
            exec-if = "pgrep 'wl-screenrec'";
            on-click = "exec $HOME/.config/waybar/bin/recorder";
            signal = 4;
          };

          "clock" = {
            format = "{:%H:%M}";
            format-alt = "{:%A, %B %d, %Y (%R)}";
            tooltip-format = "<tt><small>{calendar}</small></tt>";
            calendar = {
              "mode" = "month";
              "mode-mon-col" = 3;
              "weeks-pos" = "right";
              "on-scroll" = 1;
              "on-click-right" = "mode";
              "format" = {
                "today" = "<span color='#a6e3a1'><b><u>{}</u></b></span>";
              };
            };
          };
          "tray" = {
            spacing = 8;
            icon-size = 12;
          };
          "idle_inhibitor" = {
            format = "{icon}";
            tooltip-format-activated = "Idle Inhibitor is active";
            tooltip-format-deactivated = "Idle Inhibitor is not active";
            format-icons = {
              "activated" = "";
              "deactivated" = "";
            };
          };
          "gamemode" = {
            hide-not-running = true;
            icon-spacing = 4;
            icon-size = 13;
            tooltip = true;
            tooltip-format = "Игр запущено: {count}";
          };
          "memory" = {
            format = "{}% ";
            interval = 5;
          };
          "cpu" = {
            interval = 2;
            format = "{usage}%  ";
            on-click = "kitty btop";
          };
          "disk" = {
            interval = 600;
            format = "{percentage_used}% ";
            path = "/";
          };
          "backlight" = {
            device = "intel_backlight";
            format = "{percent}% {icon}";
            format-icons = [
              ""
              ""
              ""
              ""
              ""
              ""
              ""
              ""
              ""
              ""
              ""
              ""
              ""
              ""
              ""
            ];
            on-scroll-down = "brightnessctl s 5%-";
            on-scroll-up = "brightnessctl s +5%";
            tooltip = false;
            smooth-scrolling-threshold = 1;
          };
          "battery" = {
            interval = 120;
            states = {
              "good" = 95;
              "warning" = 30;
              "critical" = 15;
            };
            format = "{capacity}% {icon}";
            format-charging = "<b>{icon} </b>";
            format-full = "<span color='#00ff00'><b>{icon}</b></span> {capacity}%";
            format-icons = [
              "󰂃"
              "󰁺"
              "󰁻"
              "󰁼"
              "󰁽"
              "󰁾"
              "󰁿"
              "󰂀"
              "󰂁"
              "󰂂"
              "󰁹"
            ];
            tooltip-format = "{timeTo}\n{capacity} % | {power} W";
          };
          "network" = {
            interval = 2;
            format-wifi = "    {bandwidthDownBits}";
            format-ethernet = " 󰈀  {bandwidthDownBits}";
            format-disconnected = "󰈂";
            format-linked = "";
            tooltip-format = "{ipaddr}";
            tooltip-format-wifi = "{essid} ({signalStrength}%)   \n{ipaddr} | {frequency} MHz{icon} \n {bandwidthDownBits}  {bandwidthUpBits} ";
            tooltip-format-ethernet = "{ifname} 󰈀 \n{ipaddr} | {frequency} MHz{icon} \n󰈀 {bandwidthDownBits}  {bandwidthUpBits} ";
            tooltip-format-disconnected = "Нет подключения";
            on-click = "networkmanager_dmenu";
          };
          "bluetooth" = {
            format-on = "";
            format-off = "󰂲";
            format-disabled = "";
            format-connected = "<b>󰂰 {num_connections}</b>";
            format-connected-battery = "󰂱 {device_alias} {device_battery_percentage}%";
            tooltip-format = "{controller_alias}\t{controller_address}\n\n{num_connections} connected";
            tooltip-format-connected = "{controller_alias}\t{controller_address}\n\n{num_connections} connected\n\n{device_enumerate}";
            tooltip-format-enumerate-connected = "{device_alias}\t{device_address}";
            tooltip-format-enumerate-connected-battery = "{device_alias}\t{device_address}\t{device_battery_percentage}%";
            on-click = "rofi-bluetooth -i";
          };
          "pulseaudio#mic" = {
            format = "{format_source}";
            format-source = "{volume}%  ";
            format-source-muted = "";
            on-click = "pactl set-source-mute @DEFAULT_SOURCE@ toggle";
            on-scroll-down = "pactl set-source-volume @DEFAULT_SOURCE@ -5%";
            on-scroll-up = "pactl set-source-volume @DEFAULT_SOURCE@ +5%";
          };
          "pulseaudio" = {
            format = "{volume}% {icon}";
            format-bluetooth = "{volume}% {icon}";
            format-muted = "󰝟 ";
            format-icons = {
              "headphones" = "  ";
              "handsfree" = "  ";
              "headset" = "  ";
              "phone" = "  ";
              "portable" = "  ";
              "car" = "  ";
              "default" = [
                " "
                " "
              ];
            };
            on-click = "pgrep -x myxer && killall -q myxer || myxer";
            on-click-middle = "pavucontrol";
            on-scroll-up = "pactl set-sink-volume @DEFAULT_SINK@ +4096";
            on-scroll-down = "pactl set-sink-volume @DEFAULT_SINK@ -4096";
            smooth-scrolling-threshold = 1;
          };
          "cava" = {
            framerate = 60;
            format-icons = [
              "▁"
              "▂"
              "▃"
              "▄"
              "▅"
              "▆"
              "▆"
              "▇"
              "█"
            ];
            bar_delimiter = 0;
            bars = 30;
            input_delay = 0;
            sleep_timer = 300;
          };
        };
      };
    };
  };
}
