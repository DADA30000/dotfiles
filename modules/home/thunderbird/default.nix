{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.thunderbird;
in
{
  options.thunderbird = {
    enable = mkEnableOption "thunderbird customization";
  };

  config = mkIf cfg.enable {
    programs.thunderbird = {
      enable = true;
      profiles.kek = {
        isDefault = true;
        userChrome = builtins.readFile ../../../stuff/modules/home/thunderbird/userChrome.css;
        settings = {
          # UI / Custom Styling
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true; # Required for userChrome.css / userContent.css
          "svg.context-properties.content.enabled" = true;
          "widget.gtk.rounded-bottom-corners.enabled" = true;
          "mail.density" = 0; # 0 = Compact, 1 = Normal, 2 = Relaxed (Thunderbird Supernova)
          "layout.css.prefers-color-scheme.content-override" = 2; # 0=Dark, 1=Light, 2=System
          "browser.aboutConfig.showWarning" = false;
          "browser.display.focus_ring_on_anything" = true;
          "browser.display.focus_ring_style" = 0;
          "browser.display.focus_ring_width" = 0;

          # Privacy & Telemetry
          "datareporting.policy.dataSubmissionEnabled" = false;
          "datareporting.healthreport.uploadEnabled" = false;
          "toolkit.telemetry.enabled" = false;
          "toolkit.telemetry.unified" = false;
          "toolkit.telemetry.server" = "data:,";
          "breakpad.reportURL" = "";
          "network.captive-portal-service.enabled" = false;
          "network.connectivity-service.enabled" = false;
          "privacy.globalprivacycontrol.enabled" = true;

          # Security & Anti-Phishing
          "network.IDN_show_punycode" = true; # Shows actual punycode to prevent spoofing
          "pdfjs.enableScripting" = false; # Disables JS in embedded PDF preview
          "security.ssl.treat_unsafe_negotiation_as_broken" = true;
          "security.tls.enable_0rtt_data" = false;

          # Editor & Interaction
          "editor.truncate_user_pastes" = false;
          "findbar.highlightAll" = true;
          "general.autoScroll" = true;
          "layout.word_select.eat_space_to_next_word" = false;

          # Custom Scrolling Physics
          "general.smoothScroll" = true;
          "general.smoothScroll.msdPhysics.enabled" = true;
          "general.smoothScroll.msdPhysics.continuousMotionMaxDeltaMS" = 12;
          "general.smoothScroll.msdPhysics.motionBeginSpringConstant" = 600;
          "general.smoothScroll.msdPhysics.regularSpringConstant" = 650;
          "general.smoothScroll.msdPhysics.slowdownMinDeltaMS" = 25;
          "general.smoothScroll.msdPhysics.slowdownMinDeltaRatio" = 2.0;
          "general.smoothScroll.msdPhysics.slowdownSpringConstant" = 250;
          "general.smoothScroll.currentVelocityWeighting" = 1.0;
          "general.smoothScroll.stopDecelerationWeighting" = 1.0;
          "general.smoothScroll.mouseWheel.durationMinMS" = 80;
          "mousewheel.min_line_scroll_amount" = 10;
          "mousewheel.default.delta_multiplier_y" = 300;
          "apz.overscroll.enabled" = true;

          # Extensions & Localization
          "extensions.autoDisableScopes" = 0;
          "extensions.webextensions.restrictedDomains" = "";
          "intl.accept_languages" = "ru,en-us";
          "intl.locale.requested" = "ru,en-US";
          "intl.regional_prefs.use_os_locales" = true;
        };
      };
    };
  };
}
