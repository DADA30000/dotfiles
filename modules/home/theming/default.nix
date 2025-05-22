{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.theming;
in
{
  options.theming = {
    enable = mkEnableOption "Enable theming stuff like cursor theme, icon theme and etc";
  };

  config = mkIf cfg.enable {

    home.activation = {
      gimpTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [[ ! -z DRY_RUN ]]; then
          if [[ ! -d ${config.xdg.configHome}/GIMP ]]; then 
              mkdir -p $VERBOSE_ARG "${config.xdg.configHome}/GIMP"
              cp -r $VERBOSE_ARG ${builtins.toPath ../../../stuff/GIMP/3.0} "${config.xdg.configHome}/GIMP/3.0"
              find ${config.xdg.configHome}/GIMP -type f -exec chmod 644 {} \;
              find ${config.xdg.configHome}/GIMP -type d -exec chmod 755 {} \;
          fi
        fi
      '';
    };

    home.file = {
      ".themes".source = ../../../stuff/.themes;
      ".config/gtk-4.0/assets".source = ../../../stuff/.themes/Fluent-Dark/gtk-4.0/assets;
      ".config/gtk-4.0/gtk.css".source = ../../../stuff/.themes/Fluent-Dark/gtk-4.0/gtk.css;
      ".config/gtk-4.0/icons".source = ../../../stuff/.themes/Fluent-Dark/gtk-4.0/gtk-dark.css;
      ".config/vesktop/settings".source = ../../../stuff/vesktop/settings;
      ".config/vesktop/settings.json".source = ../../../stuff/vesktop/settings.json;
      ".config/vesktop/themes".source = ../../../stuff/vesktop/themes;
      ".config/Vencord/settings".source = ../../../stuff/vesktop/settings;
      ".config/Vencord/themes".source = ../../../stuff/vesktop/themes;
    };
    xdg.desktopEntries.discord.settings = {
      Exec = "discord --ozone-platform-hint=auto %U";
      Categories = "Network;InstantMessaging;Chat";
      GenericName = "All-in-one cross-platform voice and text chat for gamers";
      Icon = "discord";
      MimeType = "x-scheme-handler/discord";
      Keywords = "discord;vencord;electron;chat";
      Name = "Discord";
      StartupWMClass = "discord";
      Type = "Application";
    };
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
      package = pkgs.runCommand "moveUp" { } ''
        mkdir -p $out/share/icons
        ln -s ${../../../stuff/Bibata-Modern} $out/share/icons/Bibata-Modern
      '';
      name = "Bibata-Modern";
      size = 24;
    };
    gtk = {
      enable = true;
      gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
      gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
      iconTheme = {
        name = "Papirus-Dark";
        package = pkgs.papirus-icon-theme;
      };
      theme.name = "Fluent-Dark";
      font.name = "Noto Sans Medium";
      font.size = 11;
    };
  };
}
