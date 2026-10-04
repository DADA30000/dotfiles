{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.replays;
in
{
  options.replays = {
    enable = mkEnableOption "replays";
  };

  config = mkIf cfg.enable {
    systemd.user.services.replays = {
      wantedBy = [ "graphical-session.target" ];
      path = [
        pkgs.gpu-screen-recorder
        pkgs.inotify-tools
        pkgs.findutils
        pkgs.gawk
        pkgs.gnused
        pkgs.gnugrep
      ];
      script = builtins.readFile ../../../stuff/system/replays/replays.sh;
      serviceConfig = {
        Restart = "always";
        RestartSec = "5s";
        KillMode = "control-group";
      };
      unitConfig = {
        StartLimitBurst = 5;
        StartLimitIntervalSec = 60;
      };
    };
    programs.gpu-screen-recorder.enable = true;
  };
}
