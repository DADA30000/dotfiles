{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.replays;

  replaysScript = pkgs.writeShellApplication {
    name = "replays";
    runtimeInputs = [
      pkgs.gpu-screen-recorder
      pkgs.inotify-tools
      pkgs.findutils
      pkgs.gawk
      pkgs.gnused
      pkgs.gnugrep
    ];
    text = builtins.readFile ../../../stuff/home/replays/replays.sh;
  };
in
{
  options.replays = {
    enable = lib.mkEnableOption "replays";
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.replays = {
      Install.WantedBy = [ "graphical-session.target" ];
      Unit = {
        Description = "Replays recording service";
        StartLimitBurst = 5;
        StartLimitIntervalSec = 60;
      };
      Service = {
        ExecStart = "${replaysScript}/bin/replays";
        Restart = "always";
        RestartSec = "5s";
        KillMode = "control-group";
      };
    };
  };
}
