{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.theming;
  mkSourcePrefix = prefix: attrs:
    builtins.listToAttrs (
      lib.mapAttrsToList (name: value:
        {
          name  = "${prefix}/${name}";
          value = { source = value; };
        }
      )
      attrs
    );
in
{
  options.theming = {
    enable = mkEnableOption "Enable theming stuff like cursor theme, icon theme and etc";
  };

  config = mkIf cfg.enable {

    home.activation = {
      gimpTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [[ ! -z DRY_RUN ]]; then
          if [[ ! -f ${config.xdg.configHome}/GIMP/3.0/check-do_not_delete_this ]]; then 
            mkdir -p $VERBOSE_ARG "${config.xdg.configHome}/GIMP"
            cp -r $VERBOSE_ARG "${config.xdg.configHome}/GIMP_fake/3.0" "${config.xdg.configHome}/GIMP/3.0"
            find ${config.xdg.configHome}/GIMP -type f -exec chmod 644 {} \;
            find ${config.xdg.configHome}/GIMP -type d -exec chmod 755 {} \;
          fi
        fi
      '';
      prismLauncher = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [[ ! -z DRY_RUN ]]; then
          if [[ ! -f ${config.home.homeDirectory}/.local/share/PrismLauncher/accounts.json ]]; then
            mkdir -p $VERBOSE_ARG "${config.home.homeDirectory}/.local/share/PrismLauncher"
            echo '{"accounts": [{"entitlement": {"canPlayMinecraft": true,"ownsMinecraft": true},"type": "MSA"}],"formatVersion": 3}' > ${config.home.homeDirectory}/.local/share/PrismLauncher/accounts.json
          fi
        fi
      '';
    };

    home.file.".themes".source = ../../../stuff/.themes;
    xdg.configFile = {
        "Kvantum".source = ../../../stuff/Kvantum;
        "qt5ct".source = ../../../stuff/qt5ct;
        "qt6ct".source = ../../../stuff/qt6ct;
        "GIMP_fake".source = ../../../stuff/GIMP;
      } 
      //
      (mkSourcePrefix "gtk-4.0" { 
        "assets" = ../../../stuff/.themes/Fluent-Dark/gtk-4.0/assets;
        "gtk.css" = ../../../stuff/.themes/Fluent-Dark/gtk-4.0/gtk.css;
        "icons" = ../../../stuff/.themes/Fluent-Dark/gtk-4.0/gtk-dark.css;
      })
      //
      (mkSourcePrefix "vesktop" {
        "settings" = ../../../stuff/vesktop/settings;
        "settings.json" = ../../../stuff/vesktop/settings.json;
        "themes" = ../../../stuff/vesktop/themes;
      })
      //
      (mkSourcePrefix "Vencord" {
        "settings" = ../../../stuff/vesktop/settings;
        "themes" = ../../../stuff/vesktop/themes;
    });
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
      platformTheme.name = "qtct";
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
