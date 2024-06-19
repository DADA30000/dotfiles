{ pkgs, config, ... }:
{
  programs.btop = {
    enable = true;
    settings = {
      color_theme = "${pkgs.btop}/share/btop/themes/dracula.theme";
      update_ms = 200;
      theme_background = false;
    };
  };
}
