{
  config,
  lib,
  pkgs,
  ...
}:
{

  xdg.configFile = {
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

  home.sessionVariables = {
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
    ENVFS_RESOLVE_ALWAYS = "1";
    MOZ_ENABLE_WAYLAND = "1";
    TERMINAL = "neovide-term";
    EGL_PLATFORM = "wayland";
    MOZ_DISABLE_RDD_SANDBOX = "1";
    NIXPKGS_ALLOW_UNFREE = "1";
  };

  systemd.user = {
    services.easyeffects.Service.TimeoutStopSec = lib.mkForce 1;
    packages = [ pkgs.gamemode ];
  };

  manual.manpages.enable = false;

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

    git = {
      enable = true;
      settings = {
        color.ui = "auto";
        credential.helper = "store --file=${config.xdg.configHome}/git/credentials";
      };
      includes = [
        {
          path = "${config.xdg.configHome}/git/config-mutable";
        }
      ];
    };

    mcp = {
      enable = true;
      servers.context7 = {
        url = "https://mcp.context7.com/mcp";
        headers = {
          CONTEXT7_API_KEY = "{env:CONTEXT7_API_KEY}";
        };
      };
    };

  };

  services = {

    easyeffects.enable = true;

    kdeconnect = {
      enable = true;
      indicator = true;
    };

  };

  hyprland = {

    enable = true;

    from-unstable = false;

    stable = true;

    enable-plugins = true;

  };

  fastfetch = {

    enable = true;

    zsh-start = true;

  };
}
