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
	    rev = "171ae7ccdc4789f889cc95844c1e5aaef41f9bcd";
	    hash = "sha256-clO4hbvNPaIipiG5ujThSYfaWQ6M3DU24niUJjVdhPw=";
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
          #NFQWS_OPT_DESYNC="--dpi-desync=fake --dpi-desync-ttl=11 --dpi-desync-fake-http=0x00000000"
          #NFQWS_OPT_DESYNC="--dpi-desync=split2"
	  #NFQWS_OPT_DESYNC="--dpi-desync=split2 --dpi-desync-split-pos=1 --dpi-desync-ttl=0 --dpi-desync-fooling=md5sig,badsum --dpi-desync-repeats=6 --dpi-desync-any-protocol --dpi-desync-cutoff=d4"
          NFQWS_OPT_DESYNC="--dpi-desync=split2 --dpi-desync-any-protocol --hostlist=${../../../stuff/youtube-hosts} --new --dpi-desync-any-protocol --dpi-desync=fake,split2 --dpi-desync-ttl=9 --dpi-desync-fooling=md5sig"
	  #NFQWS_OPT_DESYNC="--dpi-desync=fake,disorder2 --dpi-desync-split-pos=1 --dpi-desync-ttl=0 --dpi-desync-fooling=md5sig,badsum --dpi-desync-repeats=6 --dpi-desync-any-protocol --dpi-desync-cutoff=d4 --dpi-desync-fake-tls=${../../../stuff/tls_clienthello_www_google_com.bin} "
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
          server_names = [ "cloudflare" "scaleway-fr" "google" ];
          listen_addresses = [ "127.0.0.1:53" "[::1]:53" ];
        };
      };
    };
    networking = {
      nameservers = [ "::1" "127.0.0.1" ];
      resolvconf.dnsSingleRequest = true;
      firewall = {
        enable = true;
        allowedTCPPorts = [ 22 80 9993 51820 8080 443 1935 ];
        allowedUDPPorts = [ 22 80 9993 51820 8080 443 1935 ];
      };
    };
  };
}
