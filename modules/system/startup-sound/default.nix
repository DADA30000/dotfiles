{ config, lib, pkgs, ... }:
with lib;
let
  long-script = "${pkgs.beep}/bin/beep -f 130 -l 100 -n -f 262 -l 100 -n -f 330 -l 100 -n -f 392 -l 100 -n -f 523 -l 100 -n -f 660 -l 100 -n -f 784 -l 300 -n -f 660 -l 300 -n -f 146 -l 100 -n -f 262 -l 100 -n -f 311 -l 100 -n -f 415 -l 100 -n -f 523 -l 100 -n -f 622 -l 100 -n -f 831 -l 300 -n -f 622 -l 300 -n -f 155 -l 100 -n -f 294 -l 100 -n -f 349 -l 100 -n -f 466 -l 100 -n -f 588 -l 100 -n -f 699 -l 100 -n -f 933 -l 300 -n -f 933 -l 100 -n -f 933 -l 100 -n -f 933 -l 100 -n -f 1047 -l 400";
  cfg = config.startup-sound;
in
{
  options.startup-sound = {
    enable = mkEnableOption "Enable startup sound on PC speaker (also plays after rebuilds)";
  };
  


  config = mkIf cfg.enable {
    systemd.services.startup-sound = {
      wantedBy = ["sysinit.target"];
      enable = false;
      preStart = "${pkgs.kmod}/bin/modprobe pcspkr";
      serviceConfig = {
        ExecStart = long-script;
      };
    };
  };
}
