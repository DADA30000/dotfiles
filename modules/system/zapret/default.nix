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
	zapret
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
          MODE_HTTP_KEEPALIVE=1
          MODE_HTTPS=1
          MODE_QUIC=0
          MODE_FILTER=none
          DISABLE_IPV6=1
          INIT_APPLY_FW=1
          TPWS_OPT="--hostspell=HOST --split-http-req=method --split-pos=3 --hostcase --oob"
          NFQWS_OPT_DESYNC="--dpi-desync=fake,split2 --dpi-desync-fooling=datanoack"
          #NFQWS_OPT_DESYNC="--dpi-desync=split2"
          #NFQWS_OPT_DESYNC="--dpi-desync=fake,split2 --dpi-desync-ttl=9 --dpi-desync-fooling=md5sig"
          TMPDIR=/tmp
          SET_MAXELEM=522288
          IPSET_OPT="hashsize 262144 maxelem $SEX_MAXELEM"
          IP2NET_OPT4="--prefix-length=22-30 --v4-threshold=3/4"
          IP2NET_OPT6="--prefix-length=56-64 --v6-threshold=5"
          AUTOHOSTLIST_RETRANS_THRESHOLD=3
          AUTOHOSTLIST_FAIL_THRESHOLD=3
          AUTOHOSTLIST_FAIL_TIME=60
          AUTOHOSTLIST_DEBUGLOG=0
          MDIG_THREADS=30
          GZIP_LISTS=1
          DESYNC_MARK=0x40000000
          DESYNC_MARK_POSTNAT=0x20000000
          FLOWOFFLOAD=donttouch
          GETLIST=get_antifilter_ipsmart.sh
        '';
      };
    };
    services = {
      resolved.enable = true;
      dnscrypt-proxy2 = {
        enable = true;
        settings = {
          server_names = [ "cloudflare" "scaleway-fr" "yandex" "google" ];
          listen_addresses = [ "127.0.0.1:53" "[::1]:53" ];
        };
      };
    };
    networking = {
      nameservers = [ "::1" "127.0.0.1" ];
      resolvconf.dnsSingleRequest = true;
      firewall = {
        enable = true;
        allowedTCPPorts = [ 22 80 9993 51820 8080 443 ];
        allowedUDPPorts = [ 22 80 9993 51820 8080 443 ];
      };
    };
  };
}
