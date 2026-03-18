{
  config,
  lib,
  pkgs,
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
      path = with pkgs; [
        coreutils
        findutils
        gnugrep
        gawk
        gnused
        gpu-screen-recorder
      ];
      script = ''
        export PATH="/run/wrappers/bin:$PATH"
        mkdir -p "$HOME/Games/Replays"
        # gpu-screen-recorder -w screen -s 1920x1080 -k hevc -q high -a default_output -a default_input -f 60 -r 300 -c mkv -o "$HOME/Games/Replays"
        MONITORS=$(ls /sys/class/drm/*/status | xargs grep -l '^connected' | awk -F'/' '{print $5}' | sed -E 's/card[0-9]+-//')

        for mon in $MONITORS; do
          if [ -n "$mon" ]; then
            mkdir -p "$HOME/Games/Replays/$mon"
            # gpu-screen-recorder -w "$mon" -s 1920x1080 -k h264 -q ultra -a default_output -a default_input -f 60 -r 300 -c mkv -o "$HOME/Games/Replays/$mon" -encoder cpu &
            gpu-screen-recorder -w "$mon" -s 1920x1080 -k hevc -q ultra -a default_output -a default_input -f 60 -r 300 -c mkv -o "$HOME/Games/Replays/$mon" &
          fi
        done

        wait
      '';
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
