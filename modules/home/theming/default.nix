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
    xresources.properties = lib.mkForce null;
    xdg = {
      dataFile = {
        "color-schemes/Transparent.colors".source = ../../../stuff/Transparent.colors;
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
              cp -r $VERBOSE_ARG "${config.xdg.configHome}/GIMP_fake/3.0" "${config.xdg.configHome}/GIMP/3.0"
              find ${config.xdg.configHome}/GIMP -type f -exec chmod 644 {} \;
              find ${config.xdg.configHome}/GIMP -type d -exec chmod 755 {} \;
            fi
          fi
        '';
        bookmarks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if [[ -z "''${DRY_RUN:-}" ]]; then
            if [[ ! -f ${config.xdg.configHome}/gtk-3.0/bookmarks ]]; then
              mkdir -p $VERBOSE_ARG ${config.xdg.configHome}/gtk-3.0
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

          postPatch = ''
            cat << 'EOF' > build_themes.py
            import glob
            import json
            import os
            import shutil
            import tomllib

            colors = [
                ("#00FF00", "#000000"),
                ("#0000FF", "#0057d1"),
                ("#FF0000", "#000000"),
            ]

            hotspots = {
                "bottom_left_corner": (0.06, 0.88),
                "bottom_right_corner": (0.88, 0.88),
                "bottom_side": (0.50, 0.88),
                "bottom_tee": (0.50, 0.88),
                "center_ptr": (0.44, 0.06),
                "circle": (0.19, 0.06),
                "context-menu": (0.19, 0.06),
                "copy": (0.19, 0.06),
                "dnd-ask": (0.38, 0.25),
                "dnd-copy": (0.38, 0.25),
                "dnd-link": (0.38, 0.25),
                "dnd_no_drop": (0.38, 0.25),
                "grabbing": (0.50, 0.25),
                "hand1": (0.56, 0.25),
                "hand2": (0.44, 0.06),
                "left_ptr": (0.19, 0.06),
                "left_ptr_watch": (0.19, 0.06),
                "left_side": (0.06, 0.50),
                "left_tee": (0.88, 0.50),
                "link": (0.19, 0.06),
                "ll_angle": (0.06, 0.81),
                "lr_angle": (0.88, 0.88),
                "pencil": (0.12, 0.81),
                "pointer-move": (0.19, 0.06),
                "question_arrow": (0.12, 0.31),
                "right_ptr": (0.75, 0.06),
                "right_side": (0.88, 0.50),
                "right_tee": (0.06, 0.50),
                "sb_down_arrow": (0.50, 0.81),
                "sb_left_arrow": (0.12, 0.50),
                "sb_right_arrow": (0.81, 0.50),
                "sb_up_arrow": (0.50, 0.12),
                "top_left_corner": (0.06, 0.06),
                "top_right_corner": (0.88, 0.06),
                "top_side": (0.50, 0.06),
                "top_tee": (0.50, 0.06),
                "ul_angle": (0.12, 0.12),
                "ur_angle": (0.88, 0.12),
                "zoom-in": (0.44, 0.44),
                "zoom-out": (0.44, 0.44)
            }

            with open("build.toml", "rb") as f_toml:
                config = tomllib.load(f_toml)

            cursors = config["cursors"]
            fallback = cursors["fallback_settings"]
            default_x = fallback.get("x_hotspot", 128)
            default_y = fallback.get("y_hotspot", 128)

            bitmaps_dir = "bitmaps/Bibata-Modern-Ice"
            os.makedirs(bitmaps_dir, exist_ok=True)

            out_dir = "hyprcursor-build/theme_Bibata-Modern-Ice"
            hyprcursors_dir = os.path.join(out_dir, "hyprcursors")
            os.makedirs(hyprcursors_dir, exist_ok=True)

            for key, cursor in cursors.items():
                if key == "fallback_settings":
                    continue
                
                png_pattern = cursor["png"]
                svgs = []
                if "*" in png_pattern:
                    base_name = png_pattern.split("-*")[0]
                    svgs = sorted(glob.glob(os.path.join("svg/modern", base_name, "*.svg")))
                else:
                    base_name = png_pattern.replace(".png", ".svg")
                    svg_path = os.path.join("svg/modern", base_name)
                    if os.path.exists(svg_path):
                        svgs = [svg_path]
                
                if "x11_name" in cursor:
                    x11_name = cursor["x11_name"]
                    hotspot_x, hotspot_y = hotspots.get(x11_name, (0.50, 0.50))
                    shape_dir = os.path.join(hyprcursors_dir, x11_name)
                    os.makedirs(shape_dir, exist_ok=True)
                
                for svg_path in svgs:
                    name = os.path.basename(svg_path)
                    png_name = name.replace(".svg", ".png")
                    dst_png_path = os.path.join(bitmaps_dir, png_name)
                    
                    with open(svg_path, "r") as f_in:
                        content = f_in.read()
                    for match, replace in colors:
                        content = content.replace(match, replace)
                    
                    if "x11_name" in cursor:
                        dst_svg_path = os.path.join(shape_dir, name)
                        with open(dst_svg_path, "w") as f_out:
                            f_out.write(content)
                        os.system(f"resvg -w 256 -h 256 {dst_svg_path} {dst_png_path}")
                    else:
                        tmp_svg_path = os.path.join(bitmaps_dir, name)
                        with open(tmp_svg_path, "w") as f_out:
                            f_out.write(content)
                        os.system(f"resvg -w 256 -h 256 {tmp_svg_path} {dst_png_path}")
                        os.remove(tmp_svg_path)
                
                if "x11_name" in cursor:
                    meta_path = os.path.join(shape_dir, "meta.hl")
                    meta_content = "resize_algorithm = none\n"
                    meta_content += f"hotspot_x = {hotspot_x:.2f}\n"
                    meta_content += f"hotspot_y = {hotspot_y:.2f}\n\n"
                    
                    for svg_path in svgs:
                        name = os.path.basename(svg_path)
                        meta_content += f"define_size = 0, {name}\n"
                        
                    for symlink in cursor.get("x11_symlinks", []):
                        meta_content += f"define_override = {symlink}\n"
                    
                    meta_content += "\n"
                    
                    with open(meta_path, "w") as f_meta:
                        f_meta.write(meta_content)

            manifest_path = os.path.join(out_dir, "manifest.hl")
            manifest_content = (
                "name = Bibata-Modern\n"
                "description = Custom Black and Blue Bibata cursors\n"
                "version = 0.1\n"
                "cursors_directory = hyprcursors\n"
            )
            with open(manifest_path, "w") as f_manifest:
                f_manifest.write(manifest_content)
            EOF
          '';

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
