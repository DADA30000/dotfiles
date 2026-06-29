{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib;
let
  cfg = config.theming;
  fluent-dark-pre =
    (pkgs.fluent-gtk-theme.overrideAttrs (prev: {
      src = inputs.fluent-gtk-theme;
      patches = (prev.patches or [ ]) ++ [ ../../../stuff/patches/fluent.patch ];
    })).override
      {
        tweaks = [
          "noborder"
          "round"
          "blur"
        ];
      };
  fluent-dark = pkgs.runCommand "fluent-dark" { } ''
    cp -rL "${fluent-dark-pre}/share/themes/Fluent-round-Dark" "$out"
  '';
  customMoreWaita = pkgs.morewaita-icon-theme.overrideAttrs (oldAttrs: {
    # 1. Propagate the Papirus theme to make it a runtime dependency.
    propagatedBuildInputs = (oldAttrs.propagatedBuildInputs or [ ]) ++ [ pkgs.papirus-icon-theme ];

    # 2. Tell the Qt build hooks not to look for binaries to wrap.
    dontWrapQtApps = true;

    postInstall = (oldAttrs.postInstall or "") + ''
      theme_file="$out/share/icons/MoreWaita/index.theme"
      if [ -f "$theme_file" ]; then
        substituteInPlace "$theme_file" \
          --replace "Inherits=Adwaita,hicolor" "Inherits=Papirus-Dark,Adwaita,hicolor"
      fi

      # 3. Create absolute symlinks so the fallback theme resolves correctly in the Nix store.
      ln -sf ${pkgs.papirus-icon-theme}/share/icons/Papirus $out/share/icons/Papirus
      ln -sf ${pkgs.papirus-icon-theme}/share/icons/Papirus-Dark $out/share/icons/Papirus-Dark
    '';
  });
  # https://github.com/Vendicated/Vencord/tree/main/src/plugins
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
      SpotifyShareCommands.enabled = true;
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
    enable = mkEnableOption "theming stuff like cursor theme, icon theme and etc";
    cursor_size = mkOption {
      description = "XCURSOR size";
      type = lib.types.int;
      default = 24;
    };
  };

  config = mkIf cfg.enable {

    home = {
      packages = with pkgs; [
        papirus-icon-theme
        adwaita-icon-theme
      ];
      activation = {
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
                file://${config.home.homeDirectory}/.umu/drive_c Диск C: от UMU
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
      };
      file = {
        ".themes/Fluent-Dark" = {
          recursive = true;
          source = fluent-dark;
        };
        "Templates" = {
          recursive = true;
          source = pkgs.runCommand "templates" { } ''
            mkdir -p $out
            touch $out/new_file.{py,txt,sh}
          '';
        };
      };
    };
    xdg.userDirs = {
      setSessionVariables = false;
      createDirectories = true;
      enable = true;
      documents = "${config.home.homeDirectory}/Documents";
      download = "${config.home.homeDirectory}/Downloads";
      music = "${config.home.homeDirectory}/Music";
      pictures = "${config.home.homeDirectory}/Pictures";
      videos = "${config.home.homeDirectory}/Videos";
      templates = "${config.home.homeDirectory}/Templates";
    };
    xdg = {
      dataFile."color-schemes/Transparent.colors".source = ../../../stuff/Transparent.colors;
      configFile = {
        "menus/applications.menu".source = ../../../stuff/plasma-applications.menu;
        "GIMP_fake".source = ../../../stuff/GIMP;
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
      }
      // (mkSourcePrefix "easyeffects/db" {
        "graphrc" = ../../../stuff/graphrc;
      })
      // (mkSourcePrefix "qimgv" {
        "qimgv.conf" = ../../../stuff/qimgv/qimgv.conf;
        "theme.conf" = ../../../stuff/qimgv/theme.conf;
      })
      // (mkSourcePrefix "vesktop" {
        themes = ./themes;
        "settings/settings.json" = vencord_settings;
        "settings.json" = vesktop_settings;
      })
      // (mkSourcePrefix "gtk-4.0" {
        assets = "${fluent-dark}/gtk-4.0/assets";
        "gtk-dark.css" = "${fluent-dark}/gtk-4.0/gtk-dark.css";
        "gtk.css" = "${fluent-dark}/gtk-4.0/gtk-dark.css";
      })
      # // (mkSourcePrefix "gtk-3.0" {
      #   assets = "${fluent-dark}/share/themes/Fluent-round/gtk-3.0/assets";
      #   "gtk-dark.css" = "${fluent-dark}/share/themes/Fluent-round/gtk-3.0/gtk-dark.css";
      #   "gtk.css" = "${fluent-dark}/share/themes/Fluent-round/gtk-3.0/gtk-dark.css";
      # })
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
      desktopEntries."com.discordapp.DiscordCanary".settings = {
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
      "com/github/stunkymonkey/nautilus-open-any-terminal" = {
        terminal = "kitty";
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
        size = cfg.cursor_size;
      };
    };
    gtk = {
      enable = true;
      gtk2.theme.name = "Fluent-Dark";
      gtk4 = {
        extraConfig.gtk-application-prefer-dark-theme = 1;
        theme.name = "Fluent-Dark";
      };
      gtk3 = {
        extraConfig.gtk-application-prefer-dark-theme = 1;
        theme.name = "Fluent-Dark";
      };
      iconTheme = {
        name = "MoreWaita";
        package = customMoreWaita;
      };
      font = {
        name = "Noto Sans Medium";
        size = 11;
      };
    };

  };
}
