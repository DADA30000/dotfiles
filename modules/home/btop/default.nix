{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  package = pkgs.btop.overrideAttrs {
    src = pkgs.fetchFromGitHub {
      owner = "aristocratos";
      repo = "btop";
      rev = "main";
      hash = "sha256-i7FYWqhTisX4P/DpLaN/hRXjwZSN+/QJEX0HnA613Uo=";
    };
  };
  cfg = config.btop;
in
{
  options.btop = {
    enable = mkEnableOption "Enable btop process manager";
  };

  config = mkIf cfg.enable {
    programs.btop = {
      enable = true;
      package = package;
      settings = {
        color_theme = "${package}/share/btop/themes/dracula.theme";
        update_ms = 200;
        theme_background = false;
      };
    };
  };
}
