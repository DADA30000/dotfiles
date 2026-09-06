{
  config,
  lib,
  ...
}:
{

  xdg.configFile = {
    "openxr/1/active_runtime.i686.json".source =
      config.lib.file.mkOutOfStoreSymlink "/etc/xdg/openxr/1/active_runtime.i686.json";
    "bookmarks.html".source = ../../../stuff/bookmarks.html;
    "uwsm/env".source = "${config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh";
    "libvirt/qemu.conf".text = "max_core = 0";
    "containers/registries.conf".text = ''unqualified-search-registries = ["docker.io", "quay.io"]'';
    "gamemode.ini".text = ''
      [general]
      renice=0
      inhibit_screensaver=1

      [cpu]
      pin_cores=no
      park_cores=no

      [gpu]
      apply_gpu_optimisations=0 
    '';
  };

  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    CUDA_CACHE_PATH = "${config.xdg.dataHome}/nv";
    GNUPGHOME = "${config.xdg.dataHome}/gnupg";
    RUSTUP_HOME = "${config.xdg.dataHome}/rustup";
    PI_CODING_AGENT_DIR = "${config.xdg.configHome}/pi/agent";
  };

  systemd.user.services.easyeffects.Service.TimeoutStopSec = lib.mkForce 1;

  manual.manpages.enable = false;

  sandboxing.enable = true;

  umu.enable = true;

  thunderbird.enable = true;

  zen.enable = true;

  spicetify.enable = true;

  home.file.".config/mpv".source = ../../../stuff/mpv;

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
