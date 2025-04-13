{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.replays;
in
{
  options.replays = {
    enable = mkEnableOption "Enable replays";
  };
  


  config = mkIf cfg.enable {
    systemd.user.services.replays = {
      path = with pkgs; [ bash gpu-screen-recorder pulseaudio ];
      wantedBy = [ "graphical-session.target" ];
      script = ''
        export PATH=/run/wrappers/bin:$PATH
        exec gpu-screen-recorder -w screen -q ultra -a $(pactl get-default-sink).monitor -a $(pactl get-default-source) -f 60 -r 300 -c mp4 -o ~/Games/Replays
      '';
      serviceConfig = {
        Restart = "always";
      };
    };
    programs.gpu-screen-recorder.enable = true;
  };
}
