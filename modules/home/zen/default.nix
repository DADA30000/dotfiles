{
  lib,
  config,
  inputs,
  pkgs,
  ...
}:
with lib;
let
  initial_adnauseam_settings = toJSON {
    selectedFilterLists = [
      "user-filters"
      "adnauseam-filters"
      "eff-dnt-whitelist"
      "ublock-filters"
      "ublock-badware"
      "ublock-privacy"
      "ublock-quick-fixes"
      "ublock-unbreak"
      "easylist"
      "easyprivacy"
      "urlhaus-1"
      "RUS-0"
      "RUS-1"
    ];
    hidingAds = true;
    disableClickingForDNT = true;
    blockingMalware = true;
    clickingAds = true;
    firstInstall = false;
    disableHidingForDNT = false;
    user-filters = "! 5 янв. 2026 г. https://mangalib.org\nmangalib.org##.size-lg.variant-primary.is-glow.is-outline.is-full-width.is-filled.btn\nmangalib.org###\\30 7cecdc2-bda5-46a6-ab11-4b098ffd8489\nmangalib.org##div.mx_b:nth-of-type(2)";
  };
  initial_redirector_settings = toJSON {
    redirects = [
      {
        processMatches = "noProcessing";
        includePattern = "http(s?)://nixos.wiki/wiki/(.*)";
        redirectUrl = "http$1://wiki.nixos.org/wiki/$2";
        excludePattern = "";
        error = null;
        grouped = false;
        patternType = "R";
        disabled = false;
        patternDesc = "";
        description = "NixOS Wiki";
        exampleUrl = "http://nixos.wiki/wiki/Main_Page";
        appliesTo = [
          "main_frame"
        ];
        exampleResult = "http://wiki.nixos.org/wiki/Main_Page";
      }
    ];
  };
  zen-internet-settings = toJSON {
    transparentZenSettings = {
      forceStyling = true;
      autoUpdate = true;
      enableStyling = true;
      welcomeShown = true;
    };
  };
  zen-internet-storage = pkgs.stdenv.mkDerivation {
    pname = "zen-internet-storage";
    version = "1.0.0";
    src = inputs.my-internet;
  
    nativeBuildInputs = [
      pkgs.nodejs
      pkgs.nodePackages.postcss
      pkgs.jq
    ];
  
    buildPhase = ''
      runHook preBuild
      export HOME=$(mktemp -d)
      mkdir -p node_modules
      ln -s ${pkgs.nodePackages.postcss}/lib/node_modules/postcss ./node_modules/postcss
      echo '${zen-internet-settings}' > settings.json
      node update-styles-json.mjs
      jq -n \
        --slurpfile generated styles.json \
        --slurpfile settings settings.json \
        '$settings[0] + {styles: $generated[0]} + {stylesMapping: {mapping: $generated[0].mapping}}' \
        > storage.json
      runHook postBuild
    '';
  
    installPhase = ''
      runHook preInstall
      install -Dm644 storage.json $out
      runHook postInstall
    '';
  };
  extensions_json = pkgs.stdenv.mkDerivation {
    name = "extensions.json";
    version = "miha_gay_furry";

    src = inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}.darkreader;

    buildInputs = [ pkgs.python3 ];

    buildPhase = ''
      shopt -s globstar
      python3 ${./generate_extensions_json.py} \
        --profile-path ${config.xdg.configHome}/zen/default \
        --extension "$src"/**/*.xpi \
        --extension "${inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}.return-youtube-dislikes}"/**/*.xpi
    '';
    
    installPhase = ''
      cp ./generated_extensions.json $out
    '';

  };
  shortcuts = pkgs.writeText "zen-keyboard-shortcuts.json" (toJSON {
    shortcuts = [
      {
        keycode = "";
        disabled = false;
        internal = false;
        l10nId = "zen-close-all-unpinned-tabs-shortcut";
        modifiers = {
          accel = false;
          alt = true;
          control = false;
          shift = false;
          meta = false;
        };
        action = "cmd_zenCloseUnpinnedTabs";
        id = "zen-close-all-unpinned-tabs";
        key = "w";
        group = "zen-workspace";
        reserved = false;
      }
    ];
  });
  vpn-toggler-extId = "zen-toggle@nixos.org";
  vpn-toggler =
    pkgs.runCommand "vpn-toggler-xpi"
      {
        buildInputs = [ pkgs.zip ];
      }
      ''
        mkdir -p $out
        cp --no-preserve=mode -r ${../../../stuff/vpn-toggler}/* .
        echo '<svg viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg"><circle cx="24" cy="24" r="20" fill="#EF4444"/></svg>' > icon-direct.svg
        echo '<svg viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg"><circle cx="24" cy="24" r="20" fill="#22C55E"/></svg>' > icon-proxy.svg
        zip -r $out/${vpn-toggler-extId}.xpi *
      '';
  cfg_orig = config.programs.zen-browser;
  cfg = config.zen;
  xulstore_json = pkgs.writeText "xulstore.json" (toJSON {
    "chrome://browser/content/browser.xhtml" = {
      navigator-toolbox = {
        style = "width: 300px; max-width: 500px; --actual-zen-sidebar-width: 321px; --zen-sidebar-width: 300px;";
        width = "280px";
      };
    };
  });
  combined_chrome = pkgs.stdenv.mkDerivation {
    pname = "chrome-zen";
    version = "1.0";

    src = inputs.sine;
    src_1 = inputs.nebula-zen;
    src_2 = inputs.sine-bootloader;

    buildInputs = [ pkgs.jq ];

    installPhase = ''
      # Installing Sine
      mkdir -p $out/JS
      cp --no-preserve=mode -r $src/{sine.sys.mjs,engine} $out/JS
      cp --no-preserve=mode -r $src_2/profile/utils $src/locales $out
      # Installing Nebula
      mkdir -p $out/sine-mods
      cp --no-preserve=mode -r $src_1 $out/sine-mods/Nebula
      echo "{}" > $out/sine-mods/mods.json
      jq --arg key "Nebula" --slurpfile new $src_1/theme.json  \
        '.[$key] = ($new[0] + {
          "stars": 1233,
          "origin": "store",
          "preferences": "preferences.json",
          "no-updates": false,
          "enabled": true
        })' $out/sine-mods/mods.json > $out/sine-mods/mods.json.tmp && mv $out/sine-mods/mods.json.tmp $out/sine-mods/mods.json
      ln -s $out/sine-mods/Nebula/README.md $out/sine-mods/Nebula/readme.md
      # Modifying Nebula
      cp --no-preserve=mode ${pkgs.nixos-icons}/share/icons/hicolor/1024x1024/apps/nix-snowflake.png $out/sine-mods/Nebula/Nebula/modules
      substituteInPlace $out/sine-mods/Nebula/Nebula/modules/Topbar-buttons.css \
        --replace-fail "url(\"chrome://branding/content/about-logo.svg\")" "url(\"nix-snowflake.png\")" \
        --replace-fail "scale: 1.7;" "scale: 1.5;"
      TRANSPARENCY_PATCH="
        panelmultiview, 
        .panel-subview-body, 
        .panel-arrowcontent,
        #appMenu-popup {
          --panel-background: rgba(0, 0, 0, 0.01) !important;
          background-color: rgba(0, 0, 0, 0.01) !important;
          background: rgba(0, 0, 0, 0.01) !important;
          --panel-shadow: none !important;
          --panel-shadow-margin: 0px !important;
          box-shadow: none !important;
          border: none !important;
          --panel-border-radius: 12px !important;
          border-radius: 12px !important;
          overflow: hidden !important;
        }
        #full-page-translations-panel,
        #full-page-translations-panel-multiview,
        #full-page-translations-panel .panel-viewcontainer,
        #full-page-translations-panel .panel-viewstack,
        .translations-panel-header-wrapper,
        .translations-panel-footer {
          background-color: rgba(0, 0, 0, 0.01) !important;
          background: rgba(0, 0, 0, 0.01) !important;
          --panel-background: rgba(0, 0, 0, 0.01) !important;
          box-shadow: none !important;
          --panel-shadow: none !important;
          --panel-shadow-margin: 0px !important;
          border: none !important;
          filter: none !important; 
          border-radius: 12px !important;
        }
      "
      echo "$TRANSPARENCY_PATCH" | sed 's/^[[:space:]]*//' | sed '/^$/d' >> "$out/sine-mods/Nebula/userChrome.css"
    '';
  };
  zen-package =
    (inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.twilight-unwrapped.override {
      policies = cfg_orig.policies;
    }).overrideAttrs
      (prev: {
        postInstall = prev.postInstall or "" + ''
          chmod -R u+w "$out/lib/zen-bin-${prev.version}"
          cp -r "${inputs.sine-bootloader}/program/"* "$out/lib/zen-bin-${prev.version}"
        '';
      });
in
{
  options.zen = {
    enable = mkEnableOption "zen-browser with declarative customization";
  };

  config = mkIf cfg.enable {
    xdg.configFile = {
      ".zen".source = config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/zen";
      "zen/default/zen-keyboard-shortcuts.json".source = shortcuts;
      "zen/default/xulstore.json".source = xulstore_json;
      "zen/default/chrome" = {
        source = combined_chrome;
        recursive = true;
      };
    };

    home = {
      file.".zen".source = config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/zen";
      activation.zenTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [[ -z "''${DRY_RUN:-}" ]]; then
          echo "@import \"file://${config.xdg.configHome}/zen/default/chrome/sine-mods/Nebula/userChrome.css\";" > ${config.xdg.configHome}/zen/default/chrome/sine-mods/chrome.css
          echo "@import \"file://${config.xdg.configHome}/zen/default/chrome/sine-mods/Nebula/userContent.css\";" > ${config.xdg.configHome}/zen/default/chrome/sine-mods/content.css
          if [[ ! -f "${config.xdg.configHome}/zen/default/extensions.json" ]]; then
            cp --no-preserve=mode ${extensions_json} "${config.xdg.configHome}/zen/default/extensions.json"
          fi
          if [[ ! -f '${config.xdg.configHome}/zen/default/browser-extension-data/{446900e4-71c2-419f-a6a7-df9c091e268b}/storage.js' ]]; then
            rm -rf '${config.xdg.configHome}/zen/default/browser-extension-data/{446900e4-71c2-419f-a6a7-df9c091e268b}'
            mkdir -p '${config.xdg.configHome}/zen/default/browser-extension-data/{446900e4-71c2-419f-a6a7-df9c091e268b}'
            echo '{ "global_extensionInitialInstall_extensionInstalled": { "__json__": true, "value": "true" } }' > '${config.xdg.configHome}/zen/default/browser-extension-data/{446900e4-71c2-419f-a6a7-df9c091e268b}/storage.js'
          fi
          if [[ ! -f '${config.xdg.configHome}/zen/default/browser-extension-data/sponsorBlocker@ajay.app/storage.js' ]]; then
            rm -rf '${config.xdg.configHome}/zen/default/browser-extension-data/sponsorBlocker@ajay.app'
            mkdir -p '${config.xdg.configHome}/zen/default/browser-extension-data/sponsorBlocker@ajay.app'
            echo '{ "alreadyInstalled": true }' > '${config.xdg.configHome}/zen/default/browser-extension-data/sponsorBlocker@ajay.app/storage.js'
          fi
          if [[ ! -f '${config.xdg.configHome}/zen/default/browser-extension-data/adnauseam@rednoise.org/storage.js' ]]; then
            rm -rf '${config.xdg.configHome}/zen/default/browser-extension-data/adnauseam@rednoise.org'
            mkdir -p '${config.xdg.configHome}/zen/default/browser-extension-data/adnauseam@rednoise.org'
            echo '${initial_adnauseam_settings}' > '${config.xdg.configHome}/zen/default/browser-extension-data/adnauseam@rednoise.org/storage.js'
          fi
          if [[ ! -f '${config.xdg.configHome}/zen/default/browser-extension-data/{91aa3897-2634-4a8a-9092-279db23a7689}/storage.js' ]]; then
            rm -rf '${config.xdg.configHome}/zen/default/browser-extension-data/{91aa3897-2634-4a8a-9092-279db23a7689}'
            mkdir -p '${config.xdg.configHome}/zen/default/browser-extension-data/{91aa3897-2634-4a8a-9092-279db23a7689}'
            cp '${zen-internet-storage}' '${config.xdg.configHome}/zen/default/browser-extension-data/{91aa3897-2634-4a8a-9092-279db23a7689}/storage.js'
          fi
          if [[ ! -f '${config.xdg.configHome}/zen/default/browser-extension-data/redirector@einaregilsson.com/storage.js' ]]; then
            rm -rf '${config.xdg.configHome}/zen/default/browser-extension-data/redirector@einaregilsson.com'
            mkdir -p '${config.xdg.configHome}/zen/default/browser-extension-data/redirector@einaregilsson.com'
            echo '${initial_redirector_settings}' > '${config.xdg.configHome}/zen/default/browser-extension-data/redirector@einaregilsson.com/storage.js'
          fi
        fi
      '';
    };
    programs.zen-browser = {
      enable = true;
      suppressXdgMigrationWarning = true;
      package = (pkgs.wrapFirefox zen-package { icon = "zen-twilight"; }).override {
        extraPrefs = cfg_orig.extraPrefs;
        extraPrefsFiles = cfg_orig.extraPrefsFiles;
        nativeMessagingHosts = cfg_orig.nativeMessagingHosts;
      };
      nativeMessagingHosts = [
        inputs.pipewire-screenaudio.packages.${pkgs.stdenv.hostPlatform.system}.default
      ];
      policies = {
        AutofillAddressEnabled = true;
        AutofillCreditCardEnabled = false;
        DisableFeedbackCommands = true;
        DisableFirefoxStudies = true;
        DisablePocket = true;
        DisableTelemetry = true;
        DontCheckDefaultBrowser = true;
        NoDefaultBookmarks = true;
        OfferToSaveLogins = false;
        DisableAppUpdate = true;
        ExtensionSettings = {
          "*" = {
            installation_mode = "allowed";
          };
          "{762f9885-5a13-4abd-9c77-433dcd38b8fd}" = {
            installation_mode = "allowed";
            managed_storage.showGreetings = false;
          };
          "{7b1bf0b6-a1b9-42b0-b75d-252036438bdc}" = {
            installation_mode = "allowed";
            managed_storage = {
              showChangeLog = false;
              firstRun = false;
            };
          };
          "sponsorBlocker@ajay.app" = {
            installation_mode = "allowed";
            default_area = "menupanel";
          };
          "adnauseam@rednoise.org" = {
            installation_mode = "allowed";
            default_area = "navbar";
          };
          "addon@darkreader.org" = {
            installation_mode = "allowed";
            default_area = "navbar";
          };
          "{91aa3897-2634-4a8a-9092-279db23a7689}" = {
            installation_mode = "allowed";
            default_area = "navbar";
          };
          ${vpn-toggler-extId} = {
            installation_mode = "force_installed";
            install_url = "file://${vpn-toggler}/${vpn-toggler-extId}.xpi";
            default_area = "navbar";
          };
        };
        EnableTrackingProtection = {
          Value = true;
          Locked = true;
          Cryptomining = true;
          Fingerprinting = true;
        };
        FirefoxHome = {
          Pocket = false;
          Snippets = false;
        };
      };
      profiles.default = {
        isDefault = true;
        search.default = "google";
        settings = {
          gfx.webrender.all = true;
          sine.engine.auto-update = false;
          nebula-nogaps-mod = true;
          nebula-tab-loading-animation = 0;
          var-nebula-border-radius = "13px";
          var-nebula-color-glass-dark = "rgba(0, 0, 0, 0.4)";
          var-nebula-color-glass-light = "rgba(255, 255, 255, 0.4)";
          var-nebula-color-shadow-dark = "rgba(0, 0, 0, 0.55)";
          var-nebula-color-shadow-light = "rgba(255, 255, 255, 0.055)";
          var-nebula-essentials-width = "60px";
          var-nebula-glass-blur = "32px";
          var-nebula-glass-saturation = "140%";
          var-nebula-tabs-default-dark = "rgba(0,0,0,0.35)";
          var-nebula-tabs-default-light = "rgba(255,255,255,0.25)";
          var-nebula-tabs-hover-dark = "rgba(0,0,0,0.45)";
          var-nebula-tabs-hover-light = "rgba(255,255,255,0.35)";
          var-nebula-tabs-minimum-dark = "rgba(0, 0, 0, 0.2)";
          var-nebula-tabs-minimum-light = "rgba(255, 255, 255, 0.1)";
          var-nebula-tabs-selected-dark = "rgba(0,0,0,0.55)";
          var-nebula-tabs-selected-light = "rgba(255,255,255,0.45)";
          var-nebula-ui-tint-dark = "rgba(0,0,0,0.2)";
          var-nebula-ui-tint-light = "rgba(255,255,255,0.2)";
          var-nebula-website-tint-dark = "rgba(0,0,0,0)";
          var-nebula-website-tint-light = "rgba(255,255,255,0)";
          var-nebula-workspace-grayscale = "100%";
          nebula-active-tab-glow = 0;
          nebula-bookmarks-autohide = 0;
          nebula-default-sound-style = 1;
          nebula-glow-gradient = 1;
          nebula-tab-switch-animation = 1;
          nebula-urlbar-animation = 1;
          nebula-workspace-style = 1;
          "extensions.webextensions.ExtensionStorageIDB.enabled" = false;
          "intl.locale.requested" = "ru,en-US";
          "extensions.postDownloadThirdPartyPrompt" = false;
          "extensions.autoDisableScopes" = 0;
          "xpinstall.signatures.required" = false;
          "browser.tabs.allow_transparent_browser" = true;
          "browser.tabs.unloadOnLowMemory" = true;
          "zen.widget.linux.transparency" = true;
          "zen.welcome-screen.seen" = true;
          "zen.view.use-single-toolbar" = true;
          "zen.view.compact.enable-at-startup" = true;
        };
        extensions = {
          packages = with inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}; [
            youtube-auto-hd-fps
            adnauseam
            darkreader
            bitwarden
            user-agent-string-switcher
            enhanced-h264ify
            github-file-icons
            redirector
            return-youtube-dislikes
            sponsorblock
            zen-internet
          ];
        };
      };
    };
  };
}
