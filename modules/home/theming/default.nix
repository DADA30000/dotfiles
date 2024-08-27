{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.theming;
in
{
  options.theming = {
    enable = mkEnableOption "Enable theming stuff like cursor theme, icon theme and etc";
  };
  


  config = mkIf cfg.enable {
    home.file.".themes".source = ../../../stuff/.themes;
    dconf.settings = {
      "org/nemo/preferences" = {
        default-folder-viewer = "list-view";
        show-hidden-files = true;
        thumbnail-limit = lib.hm.gvariant.mkUint64 68719476736;
      };
      "org/gnome/nautilus/preferences" = {
        default-folder-viewer = "list-view";
        migrated-gtk-settings = true;
      };
      "org/gnome/desktop/interface" = { 
        color-scheme = "prefer-dark"; 
      };
    };
    qt = {
      enable = true;
      platformTheme.name = "gtk3";
    };
    home.pointerCursor = {
      gtk.enable = true;
      x11.enable = true;
      package = pkgs.google-cursor;
      name = "GoogleDot-Black";
      size = 24;
    };
    gtk = {
      enable = true;
      gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
      gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
      cursorTheme.name = "GoogleDot-Black";
      iconTheme = {
        name = "MoreWaita";
        package = pkgs.morewaita-icon-theme;
      };
      theme.name = "Materia-dark";
      font.name = "Noto Sans Medium";
      font.size = 11;
    };
  };
}
