{
  config,
  lib,
  pkgs,
  ...
}:
{
  xdg = {
    terminal-exec = {
      enable = true;
      settings.default = [ "neovide-term.desktop" ];
    };
    configFile = {
      texinfo.source = pkgs.texinfo;
      stdenvNoCC.source = pkgs.stdenvNoCC;
      bashInteractive.source = pkgs.bashInteractive;
      "openxr/1/active_runtime.i686.json".source =
        config.lib.file.mkOutOfStoreSymlink "/etc/xdg/openxr/1/active_runtime.i686.json";
      "uwsm/env".source = "${config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh";
      "libvirt/qemu.conf".text = "max_core = 0";
      "containers/registries.conf".text = ''unqualified-search-registries = ["docker.io", "quay.io"]'';
      "gamemode.ini".text = ''
        [general]
        inhibit_screensaver=1

        [cpu]
        pin_cores=no
        park_cores=no
      '';
    };
  };

  home.sessionVariables = {
    __GL_SHADER_DISK_CACHE_PATH = "${config.xdg.cacheHome}/nvidia";
    __GL_SHADER_DISK_CACHE_SIZE = 107374182400;
    __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = 1;
    NIXOS_OZONE_WL = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    CUDA_CACHE_PATH = "${config.xdg.dataHome}/nv";
    GNUPGHOME = "${config.xdg.dataHome}/gnupg";
    RUSTUP_HOME = "${config.xdg.dataHome}/rustup";
    PI_CODING_AGENT_DIR = "${config.xdg.configHome}/pi/agent";
    GDK_PIXBUF_MODULE_FILE = "${pkgs.librsvg}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache";
    MANGOHUD_CONFIG = "fps_limit_method=early,fps_limit=0+165+144+120+90+60,no_display,toggle_hud=Delete,toggle_fps_limit=Shift_R+backslash,ram,vram,cpu_temp,gpu_temp,cpu_stats,gpu_stats,frame_timing,fps_metrics=avg+0.001+0.01+0.97";
    ALSOFT_DRIVERS = "pulse";
    APP2UNIT_SLICES = "a=app-graphical.slice b=background-graphical.slice s=session-graphical.slice";
    QT_QPA_PLATFORMTHEME = "qt5ct";
    QT_QPA_TRANSPARENT_BACKGROUND = "1";
    GTK_THEME = "Fluent-Dark";
    GDK_WAYLAND_DISABLE = "ext_background_effect_manager_v1";
    ENVFS_RESOLVE_ALWAYS = "1";
    MOZ_ENABLE_WAYLAND = "1";
    TERMINAL = "neovide-term";
    EGL_PLATFORM = "wayland";
    NIXPKGS_ALLOW_UNFREE = "1";
  };

  systemd.user.dbusProxy.services.usbguard-notifier = {
    talk = [ "org.freedesktop.Notifications" ];
  };

  systemd.user.services = {
    easyeffects.Service.TimeoutStopSec = lib.mkForce 1;
    cgroup-executioner = {
      Install.WantedBy = [ "graphical-session.target" ];
      Unit = {
        Description = "Automatically terminate any application scope that hits TasksMax";
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "/run/current-system/sw/bin/cgroup-executioner";
        Restart = "always";
        RestartSec = "2s";

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateTmp = true;
        PrivateDevices = true;
        DevicePolicy = "closed";
        PrivateNetwork = true;
        PrivateUsers = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = false;
        ProtectProc = "default";
        ProcSubset = "all";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        KeyringMode = "private";
        InaccessiblePaths = [
          "%h"
          "-/run/dbus/system_bus_socket"
        ];
        RestrictAddressFamilies = [ "AF_UNIX" ];
        SystemCallArchitectures = "native";
        SystemCallErrorNumber = "EPERM";
        SystemCallFilter = [
          "@system-service"
          "~@mount"
          "~@module"
          "~@raw-io"
          "~@reboot"
          "~@swap"
          "~@clock"
          "~@debug"
          "~@obsolete"
          "~@cpu-emulation"
        ];
        UMask = "0077";
      };
    };
    usbguard-notifier = {
      Install.WantedBy = [ "graphical-session.target" ];
      Service = {
        ExecStart = "${pkgs.usbguard-notifier}/bin/usbguard-notifier";
        Restart = "on-failure";

        # libqb IPC needs host netns for @usbguard abstract socket + /dev/shm/qb-*
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateTmp = true;
        PrivateDevices = true;
        DevicePolicy = "closed";
        PrivateNetwork = false;
        PrivateUsers = false;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        ProtectProc = "invisible";
        ProcSubset = "pid";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        KeyringMode = "private";
        ReadWritePaths = [
          "%t"
          "/dev/shm"
        ];
        InaccessiblePaths = [ "-/run/dbus/system_bus_socket" ];
        RestrictAddressFamilies = [ "AF_UNIX" ];
        SystemCallArchitectures = "native";
        SystemCallErrorNumber = "EPERM";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        UMask = "0077";
      };
      Unit = {
        Description = "USBGuard desktop notification service";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
    };
    sunshine = {
      #Install.WantedBy = [ "graphical-session.target" ];
      Unit = {
        Description = "Sunshine Game Streaming Host";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "3s";
        ExecStartPre = pkgs.writeShellScript "sunshine-env-forward" (
          builtins.readFile ../../../stuff/system/shared/sunshine-env-forward.sh
        );
        ExecStart = "${pkgs.systemd}/bin/systemctl start --wait sunshine@%u.service";
        ExecStop = "${pkgs.systemd}/bin/systemctl stop sunshine@%u.service";

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateTmp = true;
        PrivateDevices = true;
        DevicePolicy = "closed";
        PrivateNetwork = true;
        PrivateUsers = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        ProtectProc = "invisible";
        ProcSubset = "pid";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        KeyringMode = "private";
        ReadWritePaths = [ "%t" ];
        InaccessiblePaths = [
          "-%t/bus"
          "-%t/systemd/private"
        ];
        RestrictAddressFamilies = [ "AF_UNIX" ];
        SystemCallArchitectures = "native";
        SystemCallErrorNumber = "EPERM";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        UMask = "0077";
      };
    };
    opentabletdriver = {
      #Install.WantedBy = [ "graphical-session.target" ];
      Unit = {
        Description = "OpenTabletDriver User Bridge";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "3s";
        ExecStart = "${pkgs.systemd}/bin/systemctl start --wait opentabletdriver@%u.service";
        ExecStop = "${pkgs.systemd}/bin/systemctl stop opentabletdriver@%u.service";

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateTmp = true;
        PrivateDevices = true;
        DevicePolicy = "closed";
        PrivateNetwork = true;
        PrivateUsers = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        ProtectProc = "invisible";
        ProcSubset = "pid";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        KeyringMode = "private";
        ReadWritePaths = [ "%t" ];
        InaccessiblePaths = [
          "-%t/bus"
          "-%t/systemd/private"
        ];
        RestrictAddressFamilies = [ "AF_UNIX" ];
        SystemCallArchitectures = "native";
        SystemCallErrorNumber = "EPERM";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        UMask = "0077";
      };
    };
  };

  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      emoji = [
        "JetBrainsMono Nerd Font"
        "Noto Emoji"
        "Noto Color Emoji"
      ];
      serif = [
        "Noto Serif"
        "Liberation Serif"
      ];
      sansSerif = [
        "Noto Sans"
        "Arial"
        "Liberation Sans"
      ];
      monospace = [
        "JetBrainsMono Nerd Font"
        "Liberation Mono"
      ];
    };
  };

  replays.enable = true;

  systemd-hardening.enable = true;

  sandboxing.enable = true;

  umu.enable = true;

  thunderbird.enable = true;

  zen.enable = true;

  spicetify.enable = true;

  mpv.enable = true;

  neovim.enable = true;

  theming.enable = true;

  cava.enable = true;

  kitty.enable = true;

  zsh.enable = true;

  file-associations.enable = true;

  btop.enable = true;

  programs = {
    ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings."*" = {
        serverAliveInterval = 60;
        serverAliveCountMax = 3;
      };
    };
    git = {
      enable = true;
      lfs.enable = true;
      settings = {
        safe.directory = "/nix/store/*";
        color.ui = "auto";
        credential.helper = "store --file=${config.xdg.configHome}/git/credentials";
      };
      includes = [
        {
          path = "${config.xdg.configHome}/git/config-mutable";
        }
      ];
    };
  };

  services = {

    ssh-agent.enable = true;

    easyeffects.enable = true;

  };

  hyprland = {

    enable = true;

    enable-plugins = true;

  };

  fastfetch = {

    enable = true;

    zsh-start = true;

  };
}
