{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.theming;
  # https://github.com/Vendicated/Vencord/blob/main/src/api/Settings.ts
  vencord_settings = (pkgs.formats.json { }).generate "settings.json" {
    autoUpdate = true;
    autoUpdateNotification = true;
    useQuickCss = true;
    enabledThemes = [ ];
    frameless = true;
    transparent = true;
    disableMinSize = true;
    winNativeTitleBar = true;
    plugins = {
      CommandsAPI.enabled = true;
      MessageAccessoriesAPI.enabled = true;
      UserSettingsAPI.enabled = true;
      CrashHandler.enabled = true;
      FakeNitro.enabled = true;
      MessageLogger.enabled = true;
      RoleColorEverywhere.enabled = true;
      ShowHiddenChannels.enabled = true;
      ShowHiddenThings.enabled = true;
      SpotifyCrack.enabled = true;
      Translate.enabled = true;
      VoiceDownload.enabled = true;
      VoiceMessages.enabled = true;
      VolumeBooster.enabled = true;
      YoutubeAdblock.enabled = true;
      BadgeAPI.enabled = true;
    };
    notifications = {
      timeout = 5000;
      position = "bottom-right";
      useNative = "not-focused";
      logLimit = 50;
    };
    cloud = {
      authenticated = false;
      url = "https://api.vencord.dev/";
      settingsSync = false;
      settingsSyncVersion = 1744986831158;
    };
  };
  # https://github.com/Vencord/Vesktop/blob/main/src/shared/settings.d.ts
  vesktop_settings = (pkgs.formats.json { }).generate "settings.json" {
    discordBranch = "stable";
    minimizeToTray = true;
    arRPC = false;
    splashColor = "rgb(222, 222, 222)";
    splashBackground = "rgba(0, 0, 0, 0.2)";
    splashTheming = true;
    spellCheckLanguages = [
      "en"
      "ru"
      "ru-RU"
      "en-US"
    ];
  };
  mkSourcePrefix =
    prefix: attrs:
    builtins.listToAttrs (
      lib.mapAttrsToList (name: value: {
        name = "${prefix}/${name}";
        value = {
          source = value;
        };
      }) attrs
    );
in
{
  options.theming = {
    enable = mkEnableOption "Enable theming stuff like cursor theme, icon theme and etc";
  };

  config = mkIf cfg.enable {

    home.activation = {
      gimpTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [[ -z "''${DRY_RUN:-}" ]]; then
          if [[ ! -f ${config.xdg.configHome}/GIMP/3.0/check-do_not_delete_this ]]; then 
            mkdir -p $VERBOSE_ARG "${config.xdg.configHome}/GIMP"
            cp -r $VERBOSE_ARG "${config.xdg.configHome}/GIMP_fake/3.0" "${config.xdg.configHome}/GIMP/3.0"
            find ${config.xdg.configHome}/GIMP -type f -exec chmod 644 {} \;
            find ${config.xdg.configHome}/GIMP -type d -exec chmod 755 {} \;
          fi
        fi
      '';
      bookmarks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [[ -z "''${DRY_RUN:-}" ]]; then
          if [[ ! -f ${config.xdg.configHome}/gtk-3.0/check-do_not_delete_this ]]; then
            mkdir -p $VERBOSE_ARG ${config.xdg.configHome}/gtk-3.0
            touch ${config.xdg.configHome}/gtk-3.0/check-do_not_delete_this
            BOOKMARKS="
              file://${config.home.homeDirectory}/bottles/Games/drive_c drive_c
              file://${config.xdg.userDirs.pictures} Изображения
              File://${config.xdg.userDirs.music} Музыка
              file://${config.xdg.userDirs.documents} Документы
              file://${config.xdg.userDirs.download} Загрузки
              file://${config.xdg.userDirs.videos} Видео
              admin:/// / (корень, от рута)
              file:/// / (корень)
            "
            echo "$BOOKMARKS" | sed 's/^[[:space:]]*//' | sed '/^$/d' > "${config.xdg.configHome}/gtk-3.0/bookmarks"
          fi
        fi
      '';
      #prismLauncher = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      #  if [[ ! -z DRY_RUN ]]; then
      #    if [[ ! -f ${config.home.homeDirectory}/.local/share/PrismLauncher/accounts.json ]]; then
      #      mkdir -p $VERBOSE_ARG "${config.home.homeDirectory}/.local/share/PrismLauncher"
      #      echo '{"accounts": [{"entitlement": {"canPlayMinecraft": true,"ownsMinecraft": true},"type": "MSA"}],"formatVersion": 3}' > ${config.home.homeDirectory}/.local/share/PrismLauncher/accounts.json
      #    fi
      #  fi
      #'';
    };
    home.file.".themes".source = ../../../stuff/.themes;
    xdg.userDirs = {
      createDirectories = true;
      enable = true;
      documents = "${config.home.homeDirectory}/Documents";
      download = "${config.home.homeDirectory}/Downloads";
      music = "${config.home.homeDirectory}/Music";
      pictures = "${config.home.homeDirectory}/Pictures";
      videos = "${config.home.homeDirectory}/Videos";
    };
    xdg = {
      dataFile."color-schemes/Transparent.colors".source = ../../../stuff/Transparent.colors;
      configFile = {
        "networkmanager-dmenu".source = ../../../stuff/networkmanager-dmenu;
        "Kvantum".source = ../../../stuff/Kvantum;
        "qt5ct".source = pkgs.runCommand "qt5ct.conf" { conf = ../../../stuff/qt5ct; } ''
          mkdir -p $out
          cp -r $conf/* $out
          chmod u+w $out/qt5ct.conf
          ${pkgs.crudini}/bin/crudini --ini-options=nospace --set $out/qt5ct.conf Interface stylesheets "${config.xdg.configHome}/qt5ct/qss/kek.qss"
          ${pkgs.crudini}/bin/crudini --ini-options=nospace --set $out/qt6ct.conf Appearance color_scheme_path "${config.xdg.dataHome}/color-schemes/Transparent.colors"
        '';
        "qt6ct".source = pkgs.runCommand "qt6ct.conf" { conf = ../../../stuff/qt6ct; } ''
          mkdir -p $out
          cp -r $conf/* $out
          chmod u+w $out/qt6ct.conf
          ${pkgs.crudini}/bin/crudini --ini-options=nospace --set $out/qt6ct.conf Interface stylesheets "${config.xdg.configHome}/qt6ct/qss/kek.qss"
          ${pkgs.crudini}/bin/crudini --ini-options=nospace --set $out/qt6ct.conf Appearance color_scheme_path "${config.xdg.dataHome}/color-schemes/Transparent.colors"
        '';
        "GIMP_fake".source = ../../../stuff/GIMP;
      }
      // (mkSourcePrefix "easyeffects/db" {
        "graphrc" = ../../../stuff/graphrc;
      })
      // (mkSourcePrefix "qimgv" {
        "qimgv.conf" = ../../../stuff/qimgv/qimgv.conf;
        "theme.conf" = ../../../stuff/qimgv/theme.conf;
      })
      // (mkSourcePrefix "gtk-4.0" {
        assets = ../../../stuff/.themes/Fluent-Dark/gtk-4.0/assets;
        icons = ../../../stuff/.themes/Fluent-Dark/gtk-4.0/gtk-dark.css;
        "gtk.css" = ../../../stuff/.themes/Fluent-Dark/gtk-4.0/gtk.css;
      })
      // (mkSourcePrefix "vesktop" {
        themes = ./themes;
        "settings/settings.json" = vencord_settings;
        "settings.json" = vesktop_settings;
      })
      // (mkSourcePrefix "Vencord" {
        themes = ./themes;
        "settings/settings.json" = vencord_settings;
      });
      #desktopEntries.discord.settings = {
      #  Exec = "discord --ozone-platform-hint=auto %U";
      #  Categories = "Network;InstantMessaging;Chat";
      #  GenericName = "All-in-one cross-platform voice and text chat for gamers";
      #  Icon = "discord";
      #  MimeType = "x-scheme-handler/discord";
      #  Keywords = "discord;vencord;electron;chat";
      #  Name = "Discord";
      #  StartupWMClass = "discord";
      #  Type = "Application";
      #};
      desktopEntries.discord-canary.settings = {
        Exec = "DiscordCanary --ozone-platform-hint=auto %U";
        Categories = "Network;InstantMessaging;Chat";
        GenericName = "All-in-one cross-platform voice and text chat for gamers";
        Icon = "discord-canary";
        MimeType = "x-scheme-handler/discord";
        Keywords = "discord;vencord;electron;chat";
        Name = "Discord Canary";
        StartupWMClass = "discord";
        Type = "Application";
      };
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
      #platformTheme.name = "qtct";
    };
    home = {
      pointerCursor = {
        gtk.enable = true;
        x11.enable = true;
        package = pkgs.runCommand "moveUp" { } ''
          mkdir -p $out/share/icons
          ln -s ${../../../stuff/Bibata-Modern} $out/share/icons/Bibata-Modern
        '';
        name = "Bibata-Modern";
        size = 24;
      };
    };
    gtk = {
      enable = true;
      gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
      gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
      iconTheme = {
        name = "MoreWaita";
        package = pkgs.morewaita-icon-theme;
        #name = "Papirus-Dark";
        #package = pkgs.runCommand "Papirus" {} ''
        #  cp -r ${pkgs.papirus-icon-theme} $out
        #  chmod -R +w $out/*
        #  rm $out/share/icons/{breeze,breeze-dark}
        #  ${pkgs.gnused}/bin/sed -i 's/Inherits=breeze,hicolor/Inherits=hicolor/g' $out/share/icons/Papirus-Dark/index.theme
        #'';
      };
      theme.name = "Fluent-Dark";
      font.name = "Noto Sans Medium";
      font.size = 11;
    };

  };
}
