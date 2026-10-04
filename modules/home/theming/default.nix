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
  fluent-dark = pkgs.stdenvNoCC.mkDerivation {
    pname = "fluent-dark";
    version = "2025-04-17";

    src = inputs.fluent-gtk-theme;

    patches = [
      ../../../stuff/patches/fluent.patch
    ];

    nativeBuildInputs = [
      pkgs.jdupes
      pkgs.sassc
      pkgs.findutils
    ];

    postPatch = ''
      patchShebangs install.sh
    '';

    installPhase = ''
      runHook preInstall

      HOME="$TMPDIR" ./install.sh \
        --color dark \
        --tweaks noborder round blur \
        --icon nixos \
        --dest "$TMPDIR/themes"

      cp -rL "$TMPDIR/themes/fluent-dark-2025-04-17-round-Dark" "$out"

      runHook postInstall
    '';
  };
  customMoreWaita = pkgs.morewaita-icon-theme.overrideAttrs (oldAttrs: {
    propagatedBuildInputs = (oldAttrs.propagatedBuildInputs or [ ]) ++ [
      pkgs.adwaita-icon-theme
      pkgs.adwaita-icon-theme-legacy
      pkgs.papirus-icon-theme
    ];

    dontWrapQtApps = true;

    postInstall = (oldAttrs.postInstall or "") + ''
      substituteInPlace "$out/share/icons/MoreWaita/index.theme" \
        --replace-fail "Inherits=Adwaita,AdwaitaLegacy,hicolor" "Inherits=Adwaita,AdwaitaLegacy,Papirus-Dark,hicolor"
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
    discordBranch = "canary";
    minimizeToTray = true;
    arRPC = true;
    splashColor = "rgb(255, 255, 255)";
    splashBackground = "rgba(0, 0, 0, 0.05)";
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
    wallpaper = mkOption {
      description = "Wallpaper path";
      type = lib.types.path;
      defaultText = "../../../stuff/home/theming/wallpaper.png";
      default = ../../../stuff/home/theming/wallpaper.png;
      example = "../../../stuff/home/theming/wallpaper.jpg";
    };
    cursor_size = mkOption {
      description = "XCURSOR size";
      type = lib.types.int;
      default = 24;
    };
  };

  config = mkIf cfg.enable {
    xresources.properties = lib.mkForce null;
    programs.hyprtoolkit = {
      enable = true;
      settings = {
        background = "0x00000000";
        base = "0x30000000";
        alternate_base = "0x00000000";
        text = "0xFFFFFFFF";
        bright_text = "0xFFFFFFFF";
        accent = "0x00000000";
        accent_secondary = "0x00000000";
        font_family = "Noto Sans";
        font_family_monospace = "JetBrainsMono Nerd Font";
        font_size = 11;
        small_font_size = 10;
        h1_size = 18;
        h2_size = 15;
        h3_size = 13;
        rounding_large = 14;
        rounding_small = 8;
        icon_theme = "Papirus-Dark";
      };
    };
    xdg = {
      dataFile = {
        "color-schemes/Transparent.colors".source = ../../../stuff/home/theming/Transparent.colors;
        "themes/Fluent-Dark".source = fluent-dark;
      };
      userDirs = {
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
      configFile = {
        "Vencord/settings/settings.json".source = vencord_settings;
        "menus/applications.menu".source = ../../../stuff/home/theming/plasma-applications.menu;
        "GIMP_fake".source = "${inputs.photogimp}/.config/GIMP";
        "Kvantum".source = ../../../stuff/home/theming/Kvantum;
        "qt5ct".source = pkgs.runCommand "qt5ct.conf" { conf = ../../../stuff/home/theming/qt5ct; } ''
          mkdir -p $out
          cp -r $conf/* $out
          chmod u+w $out/qt5ct.conf
          ${pkgs.crudini}/bin/crudini --ini-options=nospace --set $out/qt5ct.conf Interface stylesheets "${config.xdg.configHome}/qt5ct/qss/kek.qss"
          ${pkgs.crudini}/bin/crudini --ini-options=nospace --set $out/qt6ct.conf Appearance color_scheme_path "${config.xdg.dataHome}/color-schemes/Transparent.colors"
        '';
        "qt6ct".source = pkgs.runCommand "qt6ct.conf" { conf = ../../../stuff/home/theming/qt6ct; } ''
          mkdir -p $out
          cp -r $conf/* $out
          chmod u+w $out/qt6ct.conf
          ${pkgs.crudini}/bin/crudini --ini-options=nospace --set $out/qt6ct.conf Interface stylesheets "${config.xdg.configHome}/qt6ct/qss/kek.qss"
          ${pkgs.crudini}/bin/crudini --ini-options=nospace --set $out/qt6ct.conf Appearance color_scheme_path "${config.xdg.dataHome}/color-schemes/Transparent.colors"
        '';
      }
      // (mkSourcePrefix "easyeffects/db" {
        "graphrc" = ../../../stuff/home/theming/graphrc;
      })
      // (mkSourcePrefix "qimgv" {
        "qimgv.conf" = ../../../stuff/home/theming/qimgv/qimgv.conf;
        "theme.conf" = ../../../stuff/home/theming/qimgv/theme.conf;
      })
      // (mkSourcePrefix "vesktop" {
        "settings/settings.json" = vencord_settings;
        "settings.json" = vesktop_settings;
      })
      // (mkSourcePrefix "gtk-4.0" {
        assets = "${fluent-dark}/gtk-4.0/assets";
        "gtk-dark.css" = "${fluent-dark}/gtk-4.0/gtk-dark.css";
        "gtk.css" = "${fluent-dark}/gtk-4.0/gtk-dark.css";
      });
      # // (mkSourcePrefix "gtk-3.0" {
      #   assets = "${fluent-dark}/share/themes/Fluent-round/gtk-3.0/assets";
      #   "gtk-dark.css" = "${fluent-dark}/share/themes/Fluent-round/gtk-3.0/gtk-dark.css";
      #   "gtk.css" = "${fluent-dark}/share/themes/Fluent-round/gtk-3.0/gtk-dark.css";
      # })
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
        recursive-search = "always";
        show-create-link = true;
        show-delete-permanently = true;
        show-directory-item-counts = "always";
        show-image-thumbnails = "always";
      };
      "org/gtk/gtk4/settings/file-chooser".showhidden = true;
      "org/gnome/desktop/interface".color-scheme = "prefer-dark";
      "com/github/stunkymonkey/nautilus-open-any-terminal".terminal = "app2unit-term";
    };
    qt.enable = true;
    home = {
      preferXdgDirectories = true;
      file = {
        ".icons/default/index.theme".enable = false;
        ".icons/${config.home.pointerCursor.name}".enable = false;
      };
      sessionVariables = {
        HYPRCURSOR_THEME = "Bibata-Modern";
        HYPRCURSOR_SIZE = cfg.cursor_size;
      };
      activation = {
        gimpTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if [[ -z "''${DRY_RUN:-}" ]]; then
            if [[ ! -f ${config.xdg.configHome}/GIMP/3.0/check-do_not_delete_this ]]; then 
              mkdir -p $VERBOSE_ARG "${config.xdg.configHome}/GIMP"
              cp -r --no-preserve=mode $VERBOSE_ARG "${config.xdg.configHome}/GIMP_fake/3.0" "${config.xdg.configHome}/GIMP/3.0"
              touch "${config.xdg.configHome}/GIMP/3.0/check-do_not_delete_this"
            fi
          fi
        '';
        bookmarks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if [[ -z "''${DRY_RUN:-}" ]]; then
            if [[ ! -f ${config.xdg.configHome}/gtk-3.0/bookmarks ]]; then
              mkdir -p $VERBOSE_ARG ${config.xdg.configHome}/gtk-3.0
              BOOKMARKS="
                file://${config.xdg.userDirs.pictures} Изображения
                File://${config.xdg.userDirs.music} Музыка
                file://${config.xdg.userDirs.documents} Документы
                file://${config.xdg.userDirs.download} Загрузки
                file://${config.xdg.userDirs.videos} Видео
                file://${config.home.homeDirectory}/.umu .umu
                admin:/// / (корень, от рута)
                file:/// / (корень)
              "
              echo "$BOOKMARKS" | sed 's/^[[:space:]]*//' | sed '/^$/d' > "${config.xdg.configHome}/gtk-3.0/bookmarks"
            fi
          fi
        '';
      };
      pointerCursor = {
        enable = true;
        gtk.enable = true;
        x11.enable = true;
        package = pkgs.stdenv.mkDerivation {
          pname = "bibata-modern-hyprcursor";
          version = "2.0.6";

          src = inputs.bibata-modern-hyprcursor;

          nativeBuildInputs = with pkgs; [
            python3
            clickgen
            resvg
          ];

          postPatch = "cp ${../../../stuff/home/theming/build_themes.py} build_themes.py";

          buildPhase = ''
            cd svg
            python3 link.py
            cd ..

            python3 build_themes.py

            ctgen build.toml -p x11 -d "bitmaps/Bibata-Modern-Ice" -n "Bibata-Modern-Ice" -c "Custom Cursors"
          '';

          installPhase = ''
            mkdir -p $out/share/icons/Bibata-Modern
            cp -r themes/Bibata-Modern-Ice/* $out/share/icons/Bibata-Modern/
            cp -r hyprcursor-build/theme_Bibata-Modern-Ice/* $out/share/icons/Bibata-Modern/
          '';
        };
        name = "Bibata-Modern";
        size = cfg.cursor_size;
      };
    };
    gtk = {
      enable = true;
      gtk2.theme.name = "Fluent-Dark";
      gtk3.theme.name = "Fluent-Dark";
      gtk4.theme.name = "Fluent-Dark";
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
