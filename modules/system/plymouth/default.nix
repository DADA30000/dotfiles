{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.plymouth;
in
{
  options.plymouth = {
    enable = mkEnableOption "Enable plymouth";
  };

  config = mkIf cfg.enable {
    security.sudo.extraRules = [ { groups = [ "wheel" ]; commands = [ { command = "${pkgs.plymouth}/bin/plymouth quit"; options = [ "NOPASSWD" ]; } ]; } ];

    systemd.services = {
      plymouth-quit.enable = false;
      plymouth-quit-wait.enable = false;
    };

    boot.plymouth = {
      enable = true;
      theme = "logo";
      themePackages = [ (pkgs.callPackage ./logo.nix {}) ];
    };
  };
}
