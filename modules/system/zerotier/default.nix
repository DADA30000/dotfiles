{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.zerotier;
in
{
  options.zerotier = {
    enable = mkEnableOption "Enable zerotier";
  };
  


  config = mkIf cfg.enable {
    systemd.services.zerotier = {
      description = "Starts a zerotier-one service";
      serviceConfig.ExecStart = "${pkgs.zerotierone}/bin/zerotier-one";
      wantedBy = [ "multi-user.target" ];
    };
    environment.systemPackages = [ pkgs.zerotierone ];
  };
}
