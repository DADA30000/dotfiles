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

    systemd.services.plymouth-quit = {
      requires = [ "user@1000.service" "systemd-vconsole-setup.service" "polkit.service" ];
      after = [ "user@1000.service" "systemd-vconsole-setup.service" "polkit.service" ];
      preStart = "${pkgs.coreutils-full}/bin/sleep 5";
    };

    systemd.services.plymouth-quit-wait.enable = false;

    boot.plymouth = {
      enable = true;
      theme = "logo";
      themePackages = [ (pkgs.callPackage ./logo.nix { }) ];
    };
  };
}
