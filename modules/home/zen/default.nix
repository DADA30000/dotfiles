{ lib, config, inputs, pkgs, ... }:
with lib;
let 
  cfg_orig = config.programs.zen-browser;
  cfg = config.zen;
  mods_json = (pkgs.formats.json {}).generate "mods.json" {
    Nebula = {
      id = "Nebula";
      js = true;
      homepage = "https://github.com/JustADumbPrsn/Zen-Nebula";
      author = "JustADumbPrsn";
      name = "Nebula";
      description = "A beautiful theme made for Zen Browser :))";
      version = "3.3.3";
      createdAt = "2025-05-31";
      updatedAt = "2025-10-28";
      readme = "https://raw.githubusercontent.com/JustADumbPrsn/Zen-Nebula/main/README.md";
      image = "https://i.ibb.co/Lqk4krw/Screenshot-2025-09-03-232353.png";
      tags = ["content" "chrome" "minimal"];
      fork = ["zen"];
      preferences = "https://raw.githubusercontent.com/CosmoCreeper/Nubulu/main/preferences.json";
      style = {
        chrome = "https://raw.githubusercontent.com/CosmoCreeper/Nubulu/main/userChrome.css";
        content = "https://raw.githubusercontent.com/CosmoCreeper/Nubulu/main/userContent.css";
      };
      editable-files = [
        "preferences.json"
        "readme.md"
        "chrome.css"
        "userChrome.css"
        "userContent.css"
        {
          directory = "Nebula";
          contents = [
            "Nebula.css"
            "Nebula-config.css"
            "Nebula-content.css"
            {
              directory = "modules";
              contents = [
                "General-UI.css"
                "Sidebar.css"
                "URLbar.css"
                "Pinned-extensions.css"
                "Topbar-buttons.css"
                "Tabstyles.css"
                "Essentials.css"
                "Sound-icon.css"
                "Toolbar.css"
                "Miniplayer.css"
                "BetterPiP.css"
                "Animations(tabs).css"
                "Tabfolders.css"
                "Workspace-buttons.css"
              ];
            }
            {
              directory = "content";
              contents = ["Better-pdf.css" "Transparent-settings.css"];
            }
          ];
        }
        { directory = "js"; contents = ["Nebula.uc.js"]; }
      ];
      no-updates = false;
      enabled = true;
    };
  };
  combined_chrome = pkgs.stdenv.mkDerivation {
    pname = "chrome-zen";
    version = "1.0";

    src = inputs.fx-autoconfig;
    src_1 = inputs.sine;
    src_2 = inputs.nebula-zen;
    mods_json = mods_json;

    installPhase = ''
      cp -r $src/profile/chrome $out
      chmod -R +w $out
      cp -r $src_1/{sine.uc.mjs,engine} $out/JS
      chmod -R +w $out
      mkdir -p $out/sine-mods/Nebula
      cp $mods_json $out/sine-mods/mods.json
      cp $src_2/JS/Nebula.uc.js $out/JS/Nebula_Nebula.uc.js
      cp $src_2/README.md $out/sine-mods/Nebula/readme.md
      cp -r $src_2/{Nebula,userChrome.css,userContent.css,preferences.json} $out/sine-mods/Nebula
    '';
  };
  zen-package = (inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.twilight-unwrapped.override {
    policies = cfg_orig.policies;
  }).overrideAttrs (prev: {
    postInstall = prev.postInstall or "" + ''
      chmod -R u+w "$out/lib/zen-bin-${prev.version}"
      cp -r "${inputs.fx-autoconfig}/program/"* "$out/lib/zen-bin-${prev.version}"
    '';
  });
in
{
  options.zen = {
    enable = mkEnableOption "Enable zen-browser with declarative customization";
  };
  
  config = mkIf cfg.enable {
    home.file.".zen/default/chrome" = {
      source = combined_chrome;
      recursive = true;
    };
    programs.zen-browser = {
      enable = true;
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
          "nebula-nogaps-mod" = true;
          "nebula-tab-loading-animation" = 0;
          "browser.tabs.allow_transparent_browser" = true;
          "zen.widget.linux.transparency" = true;
          # "nebula-tab-switch-animation" = 0;
        };
        extensions = {
          packages = with inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}; [
            adnauseam
            darkreader
            bitwarden
            foxyproxy-standard
            user-agent-string-switcher
            enhanced-h264ify
            github-file-icons
            redirector
            return-youtube-dislikes
            sponsorblock
            # No Internet Zen extension yet :(
          ];
        };
      };
    };
  };
} 
