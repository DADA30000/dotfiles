{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.zapret;
in
{
  options.zapret = {
    enable = mkEnableOption "Enable DPI (Deep packet inspection) bypass";
  };
  


  config = mkIf cfg.enable {
    users.users.tpws = {
      isSystemUser = true;
      group = "tpws";
    };
    users.groups.tpws = {};
    systemd.services.zapret = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [
        iptables
        nftables
        ipset
        curl
	(zapret.overrideAttrs (finalAttrs: previousAttrs: {
	  src = pkgs.fetchFromGitHub {
	    owner = "bol-van";
	    repo = "zapret";
	    rev = "29c8aec1116d504692bebc16420d0e3ad65c030b";
	    hash = "sha256-diWPEakHgYytBknng1Opfr7XZbf58JqzwPz8KbmNcBQ=";
	  };
	}))
        gawk
      ];
      serviceConfig = {
        Type = "forking";
        Restart = "no";
        TimeoutSec = "30sec";
        IgnoreSIGPIPE = "no";
        KillMode = "none";
        GuessMainPID = "no";
        ExecStart = "${pkgs.bash}/bin/bash -c 'zapret start'";
        ExecStop = "${pkgs.bash}/bin/bash -c 'zapret stop'";
        EnvironmentFile = pkgs.writeText "zapret-environment" ''
          MODE="nfqws"
          FWTYPE="iptables"
          MODE_HTTP=1
          MODE_HTTP_KEEPALIVE=0
          MODE_HTTPS=1
          MODE_QUIC=1
	  QUIC_PORTS=50000-65535
          MODE_FILTER=none
          DISABLE_IPV6=1
          INIT_APPLY_FW=1
          NFQWS_OPT_DESYNC="--dpi-desync=syndata,fake,split2 --dpi-desync-fooling=md5sig --dpi-desync-repeats=6"
	  NFQWS_OPT_DESYNC_QUIC="--dpi-desync=fake,tamper --dpi-desync-any-protocol"
          TMPDIR=/tmp
        '';
      };
    };
    services = {
      resolved.enable = true;
      dnscrypt-proxy2 = {
        enable = true;
        settings = {
          server_names = [ "cloudflare" "scaleway-fr" "google" "yandex" ];
          listen_addresses = [ "127.0.0.1:53" "[::1]:53" ];
        };
      };
    };
    networking = {
      nameservers = [ "::1" "127.0.0.1" ];
      resolvconf.dnsSingleRequest = true;
      firewall = {
        enable = true;
        allowedTCPPorts = [ 22 80 9993 51820 8080 443 1935 49152 8125 ];
        allowedUDPPorts = [ 22 80 9993 51820 8080 443 1935 49152 8125 ];
      };
    };
  };
}
