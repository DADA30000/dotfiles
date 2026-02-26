{
  min-flag,
  avg-flag,
  home-modules,
  pkgs,
  inputs,
  ...
}:
{

  imports = home-modules;

  xdg.configFile."bookmarks.html".source = ../../stuff/bookmarks.html;

  manual.manpages.enable = false;

  umu.enable = true;

  thunderbird.enable = true;

  zen.enable = true;

  home.stateVersion = "25.05";

  spicetify.enable = true;

  home.file.".config/mpv".source = ../../stuff/mpv;

  neovim.enable = true;

  theming.enable = true;

  cava.enable = true;

  swaync.enable = true;

  kitty.enable = true;

  zsh.enable = true;

  file-associations.enable = true;

  waybar.enable = true;

  btop.enable = true;

  programs = {

    opencode = {
      enable = true;
      enableMcpIntegration = true;
      package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode;
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

    ollama = {
      enable = true;
      package = pkgs.ollama-vulkan;
    };

  };

  mpd = {
    enable = false;
    ncmpcpp = false;
  };

  flatpak =
    if !(avg-flag || min-flag) then
      {
        enable = true;
        packages = [
          "io.github.Soundux"
        ];
      }
    else
      { };

  hyprland = {
    enable = true;
    from-unstable = false;
    stable = false;
    enable-plugins = false;
    mpvpaper = false;
    hyprpaper = true;
    wlogout = true;
    hyprlock = true;
    rofi = true;
  };

  fastfetch = {

    enable = true;
    zsh-start = true;
    logo-path = ../../stuff/logo.png;

  };
}
