{
  lib,
  config,
  inputs,
  pkgs,
  ...
}:
with lib;
let
  cfg_orig = config.programs.zen-browser;
  cfg = config.zen;
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
        --replace-fail "scale: 1.7;" "scale: 1.5;" \
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
    enable = mkEnableOption "Enable zen-browser with declarative customization";
  };

  config = mkIf cfg.enable {
    xdg.configFile = {
      ".zen".source = config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/zen";
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
          "sine.engine.auto-update" = false;
          "zen.welcome-screen.seen" = true;
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
            zen-internet
          ];
        };
      };
    };
  };
}
