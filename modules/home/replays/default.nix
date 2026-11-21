{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.replays;

  envPrep = pkgs.writeShellScript "replays-env-forward" ''
    set -euo pipefail
    wl="''${WAYLAND_DISPLAY:-wayland-1}"
    printf 'WAYLAND_DISPLAY=%s\n' "$wl" > "$XDG_RUNTIME_DIR/replays.env"
    if [ -S "$XDG_RUNTIME_DIR/$wl" ]; then
      ${pkgs.acl}/bin/setfacl -m u:replays:rw "$XDG_RUNTIME_DIR/$wl"
    fi
  '';
in
{
  options.replays = {
    enable = lib.mkEnableOption "replays user bridge to isolated replays@ system service";
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.replays = {
      Install.WantedBy = [ "graphical-session.target" ];
      Unit = {
        Description = "Replays Recording Service User Bridge";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
        StartLimitBurst = 5;
        StartLimitIntervalSec = 60;
      };
      Service = {
        Type = "simple";
        ExecStartPre = "${envPrep}";
        ExecStart = "${pkgs.systemd}/bin/systemctl start --wait replays@%U.service";
        ExecStop = "${pkgs.systemd}/bin/systemctl stop replays@%U.service";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
