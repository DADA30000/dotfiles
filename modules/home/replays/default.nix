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
    ${pkgs.acl}/bin/setfacl -m g:replays:r "$XDG_RUNTIME_DIR/replays.env"
    for sock in "$wl" "pipewire-0" "pulse/native"; do
      if [ -S "$XDG_RUNTIME_DIR/$sock" ]; then
        ${pkgs.acl}/bin/setfacl -m g:replays:rw "$XDG_RUNTIME_DIR/$sock"
      fi
    done
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

        # Host-userns hardening: ExecStartPre runs setfacl for the `replays` UID
        # which requires host uid_map (no mount/UTS/net namespace directives).
        NoNewPrivileges = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        KeyringMode = "private";
        RestrictAddressFamilies = [ "AF_UNIX" ];
        SystemCallArchitectures = "native";
        SystemCallErrorNumber = "EPERM";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        UMask = "0077";
      };
    };
  };
}
