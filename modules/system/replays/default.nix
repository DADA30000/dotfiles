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
      script = ''
        set -x
        export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"
        mkdir -p "$HOME/Documents/Replays"
        rm_nv() {
          local tmp=$(mktemp -u ~/.nv.XXXXXX)
          mv ~/.nv "$tmp" && rm -rf "$tmp"
        }
        # gpu-screen-recorder -w screen -s 1920x1080 -k hevc -q high -a default_output -a default_input -f 60 -r 300 -c mkv -o "$HOME/Documents/Replays"
        MONITORS=$(ls /sys/class/drm/*/status | xargs grep -l '^connected' | awk -F'/' '{print $5}' | sed -E 's/card[0-9]+-//')

        for mon in $MONITORS; do
          if [ -n "$mon" ]; then
            mkdir -p "$HOME/Documents/Replays/$mon"
            # gpu-screen-recorder -w "$mon" -s 1920x1080 -k h264 -q ultra -a default_output -a default_input -f 60 -r 300 -c mkv -o "$HOME/Documents/Replays/$mon" -encoder cpu &
            gpu-screen-recorder -w "$mon" -s 1920x1080 -k hevc -q ultra -a default_output -a default_input -f 60 -r 300 -c mkv -o "$HOME/Documents/Replays/$mon" &
            if ! rm_nv; then
              inotifywait -q -e create --format '%f' ~ | grep -q '^.nv$'
              rm_nv
            fi
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
