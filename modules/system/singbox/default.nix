{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib;
let
  cfg = config.singbox;
  dns = "94.140.14.14";
  zapret-qnum = "210";
  zapret-mark = 707;
  zapret-flags = concatStringsSep " " [
    "--filter-tcp=80,443,853,2053,2083,2087,2096,8443"
    "--filter-udp=53-65535"
    "--filter-udp=1400"
    "--filter-l7=stun"
    "--dpi-desync=fake"
    "--dpi-desync-fake-stun=0x00"
    "--new"
    "--filter-udp=3478-3482,3484,3488,3489,3491-3493,3495-3497"
    "--filter-l7=stun"
    "--dpi-desync=fake"
    "--dpi-desync-fake-stun=0x00"
    "--dpi-desync-repeats=6"
    "--new"
    "--filter-udp=19294-19344,50000-50032"
    "--filter-l7=discord,stun"
    "--dpi-desync=fake"
    "--dpi-desync-fake-discord='${pkgs.zapret}/usr/share/zapret/files/fake/quic_initial_www_google_com.bin'"
    "--dpi-desync-fake-stun='${pkgs.zapret}/usr/share/zapret/files/fake/quic_initial_www_google_com.bin'"
    "--dpi-desync-repeats=6"
    "--new"
    "--filter-tcp=443,2053,2083,2087,2096,8443"
    "--hostlist-domains=dis.gd,discord-attachments-uploads-prd.storage.googleapis.com,discord.app,discord.co,discord.com,discord.design,discord.dev,discord.gift,discord.gifts,discord.gg,gateway.discord.gg,discord.media,discord.new,discord.store,discord.status,discord-activities.com,discordactivities.com,discordapp.com,cdn.discordapp.com,discordapp.net,media.discordapp.net,images-ext-1.discordapp.net,updates.discord.com,stable.dl2.discordapp.net,discordcdn.com,discordmerch.com,discordpartygames.com,discordsays.com,discordsez.com,discordstatus.com"
    "--dpi-desync=fake"
    "--dpi-desync-fake-tls-mod=sni=vk.me"
    "--dpi-desync-fooling=badseq"
    "--dpi-desync-badseq-increment=0"
    "--dpi-desync-badack-increment=1"
    "--dpi-desync-repeats=6"
    "--new"
    "--filter-udp=443"
    "--dpi-desync=fake"
    "--dpi-desync-fake-quic='${pkgs.zapret}/usr/share/zapret/files/fake/quic_initial_www_google_com.bin'"
    "--dpi-desync-repeats=11"
    "--new"
    "--filter-tcp=80"
    "--dpi-desync=fake"
    "--dpi-desync-fake-http='${pkgs.zapret}/usr/share/zapret/files/fake/tls_clienthello_www_google_com.bin'"
    "--dpi-desync-fooling=badseq"
    "--new"
    "--filter-tcp=443"
    "--hostlist-exclude-domains=stable.dl2.discordapp.net"
    "--hostlist='${inputs.zapret-flowseal}/lists/list-google.txt'"
    "--dpi-desync=multidisorder"
    "--dpi-desync-split-pos=1,midsld"
    "--dpi-desync-split-seqovl=681"
    "--dpi-desync-split-seqovl-pattern='${pkgs.zapret}/usr/share/zapret/files/fake/tls_clienthello_www_google_com.bin'"
    "--new"
    "--filter-tcp=443"
    "--hostlist-exclude-domains=dis.gd,discord-attachments-uploads-prd.storage.googleapis.com,discord.app,discord.co,discord.com,updates.discord.com,discord.design,discord.dev,discord.gift,discord.gifts,discord.gg,gateway.discord.gg,discord.media,discord.new,discord.store,discord.status,discord-activities.com,discordactivities.com,discordapp.com,cdn.discordapp.com,discordapp.net,media.discordapp.net,images-ext-1.discordapp.net,discordcdn.com,discordmerch.com,discordpartygames.com,discordsays.com,discordsez.com,discordstatus.com"
    "--dpi-desync=fake,multisplit"
    "--dpi-desync-fake-tls-mod=rnd,dupsid,sni=vk.me"
    "--dpi-desync-split-pos=1,host"
    "--dpi-desync-fooling=badseq"
    "--dpi-desync-badseq-increment=0"
    "--dpi-desync-badack-increment=1"
    "--dpi-desync-repeats=6"
    "--new"
    "--filter-tcp=443,853"
    "--ipset-ip=162.159.36.1,162.159.46.1,2606:4700:4700::1111,2606:4700:4700::1001"
    "--dpi-desync=syndata"
    "--dpi-desync-fake-syndata=0x00"
    "--dpi-desync-cutoff=n2"
    "--new"
    "--filter-udp=53-65535"
    "--filter-l7=wireguard"
    "--dpi-desync=fake"
    "--dpi-desync-fake-wireguard='${pkgs.zapret}/usr/share/zapret/files/fake/quic_initial_www_google_com.bin'"
    "--dpi-desync-cutoff=n2"
    "--dpi-desync-repeats=4"
    "--new"
    "--filter-udp=49152-65535"
    "--ipset-ip=103.140.28.0/23,128.116.0.0/17,141.193.3.0/24,205.201.62.0/24,2620:2b:e000::/48,2620:135:6000::/40,2620:135:6004::/48,2620:135:6007::/48,2620:135:6008::/48,2620:135:6009::/48,2620:135:600a::/48,2620:135:600b::/48,2620:135:600c::/48,2620:135:600d::/48,2620:135:600e::/48,2620:135:6041::/48"
    "--dpi-desync=fake"
    "--dpi-desync-fake-unknown-udp=0x00"
    "--dpi-desync-any-protocol"
    "--dpi-desync-cutoff=n2"
    "--new"
    "--filter-tcp=80"
    "--ipset='${inputs.zapret-flowseal}/lists/ipset-all.txt'"
    "--dpi-desync=fake"
    "--dpi-desync-fake-http='${pkgs.zapret}/usr/share/zapret/files/fake/tls_clienthello_www_google_com.bin'"
    "--dpi-desync-fooling=badseq"
    "--new"
    "--filter-tcp=443"
    "--ipset='${inputs.zapret-flowseal}/lists/ipset-all.txt'"
    "--dpi-desync=fake,multisplit"
    "--dpi-desync-fake-tls-mod=none"
    "--dpi-desync-fooling=badseq"
    "--dpi-desync-badseq-increment=0"
    "--dpi-desync-badack-increment=1"
    "--dpi-desync-split-pos=1"
    "--dpi-desync-repeats=6"
    "--new"
    "--filter-udp=443"
    "--ipset='${inputs.zapret-flowseal}/lists/ipset-all.txt'"
    "--dpi-desync=fake"
    "--dpi-desync-repeats=6"
    "--new"
    "--ipset='${inputs.zapret-flowseal}/lists/ipset-all.txt'"
    "--dpi-desync-any-protocol"
    "--dpi-desync=fakeknown,multisplit"
    "--dpi-desync-fake-tls-mod=none"
    "--dpi-desync-fooling=badseq"
    "--dpi-desync-badseq-increment=0"
    "--dpi-desync-badack-increment=1"
    "--dpi-desync-split-pos=1"
    "--dpi-desync-split-seqovl=681"
    "--dpi-desync-split-seqovl-pattern='${pkgs.zapret}/usr/share/zapret/files/fake/tls_clienthello_www_google_com.bin'"
    "--dpi-desync-cutoff=n3"
    "--dpi-desync-repeats=6"
    "--new"
    "--ipset='${inputs.zapret-flowseal}/lists/ipset-all.txt'"
    "--dpi-desync=fake"
    "--dpi-desync-any-protocol"
    "--dpi-desync-cutoff=n3"
    "--dpi-desync-repeats=12"
  ];
  proxy-dummy = (pkgs.formats.json { }).generate "proxy-dummy" {
    outbounds = [
      {
        tag = "proxy-server";
        type = "selector";
        outbounds = [ "zapret" ];
      }
    ];
  };
  start-singbox = pkgs.writeShellScript "start-singbox" ''
    if [[ -s /config.json ]]; then
      ${pkgs.sing-box}/bin/sing-box -c ${singbox-config} -c /config.json run
    else
      ${pkgs.sing-box}/bin/sing-box -c ${singbox-config} -c "${proxy-dummy}" run
    fi
  '';
  singbox-config = (pkgs.formats.json { }).generate "singbox-config" {
    log = {
      level = "debug";
    };
    route = {
      rules = [
        {
          action = "sniff";
        }
        {
          inbound = [
            "mixed-in"
          ];
          outbound = "proxy";
        }
        {
          outbound = "proxy";
          source_ip_cidr = [
            "10.200.0.0/24"
          ];
        }
        {
          outbound = "proxy";
          process_name = [
            "Battle.net.exe"
            ".AyuGram-wrapped"
            ".Discord-wrapped"
            ".spotify-wrapped"
            ".DiscordCanary-wrapped"
            "TeamSpeak"
            "electron"
            "prismlauncher"
          ];
        }
        {
          outbound = "proxy";
          domain_suffix = [
            "dis.gd"
            "discord.co"
            "discord.com"
            "discord.design"
            "discord.dev"
            "discord.gg"
            "discord.gift"
            "discord.gifts"
            "discord.media"
            "discord.new"
            "discord.store"
            "discord.tools"
            "discordapp.com"
            "discordapp.net"
            "discordmerch.com"
            "discordpartygames.com"
            "discord-activities.com"
            "discordactivities.com"
            "discordsays.com"
            "discordstatus.com"
            "googlevideo.com"
            "youtu.be"
            "youtube.com"
            "ytimg.com"
            "ggpht.com"
            "animego.org"
            "animego.one"
            "animego.bz"
            "aniboom.one"
            "ya-ligh.com"
            "jut.su"
            "aistudio.google.com"
            "chatgpt.com"
            "ai.google.dev"
            "generativelanguage.googleapis.com"
            "content-generativelanguage.googleapis.com"
            "makersuite.google.com"
            "alkalimakersuite-pa.clients6.google.com"
            "cachix.org"
            "garnix.io"
            "xuyh0120.win"
            "s3.dualstack.us-east-2.amazonaws.com"
            "beatsaver.com"
            "gemini.google.com"
            "sagernet.com"
            "cloudflare-ech.com"
            "aiplatform.googleapis.com"
            "oauth2.googleapis.com"
            "apis.google.com"
            "googleapis.com"
            "cloudfront.net"
            "flakehub.com"
            "votv.dev"
            "itch.io"
            "itch.zone"
            "spotify.com"
            "quora.com"
          ];
        }
        {
          outbound = "zen-toggle";
          process_name = [
            "zen"
            ".zen-wrapped"
            "zen-bin"
            "zen.bin"
            ".zen-twilight-wrapped"
            "zen-twilight"
            ".zen-beta-wrapper"
            "zen-beta"
          ];
        }
      ];
      auto_detect_interface = true;
      final = "direct";
    };
    inbounds = [
      {
        listen = "127.0.0.1";
        tag = "mixed-in";
        listen_port = 2080;
        type = "mixed";
      }
      {
        strict_route = true;
        stack = "system";
        interface_name = "tun0";
        auto_route = true;
        mtu = 1400;
        tag = "tun-in";
        address = "172.19.0.1/30";
        type = "tun";
        route_exclude_address = [
          "127.0.0.1/32"
          "192.168.0.0/16"
        ];
      }
    ];
    outbounds = [
      {
        outbounds = [
          "direct"
          "proxy"
        ];
        tag = "zen-toggle";
        type = "selector";
      }
      {
        type = "direct";
        tag = "zapret";
        routing_mark = zapret-mark;
      }
      {
        type = "selector";
        tag = "proxy";
        outbounds = [
          "proxy-server"
          "zapret"
        ];
      }
      {
        tag = "direct";
        type = "direct";
      }
    ];
    experimental = {
      clash_api = {
        external_controller = "127.0.0.1:9090";
      };
    };
  };
  vpnifyBin = pkgs.stdenv.mkDerivation {
    pname = "vpnify";
    version = "1.0";

    src = pkgs.writeText "vpnify.c" ''
      #define _GNU_SOURCE
      #include <sched.h>
      #include <sys/mount.h>
      #include <sys/stat.h>
      #include <unistd.h>
      #include <stdio.h>
      #include <fcntl.h>
      #include <sys/types.h>
      #include <stdlib.h>

      extern char **environ;

      int main(int argc, char **argv) {
        if (argc < 2) {
            fprintf(stderr, "usage: vpnify <cmd> [args...]\n");
            return 1;
        }

        char **saved_env = environ;

        int fd = open("/var/run/netns/vpn_wrapper", O_RDONLY);
        if (fd < 0) {
            perror("open netns");
            return 1;
        }

        if (setns(fd, CLONE_NEWNET) != 0) {
            perror("setns(net)");
            return 1;
        }

        if (unshare(CLONE_NEWNS) != 0) {
            perror("unshare mount ns");
            return 1;
        }

        if (mount(NULL, "/", NULL, MS_REC | MS_PRIVATE, NULL) != 0) {
            perror("mount private");
            return 1;
        }

        const char *ns_resolv = "/etc/netns/vpn_wrapper/resolv.conf";
        struct stat st;
        if (stat(ns_resolv, &st) == 0) {
            if (mount(ns_resolv, "/etc/resolv.conf", NULL, MS_BIND, NULL) != 0) {
                perror("bind resolv.conf");
                return 1;
            }
        }

        if (setuid(getuid()) != 0) {
            perror("setuid");
            return 1;
        }

        environ = saved_env;

        execvp(argv[1], &argv[1]);
        perror("execvp");
        return 1;
      }
    '';

    dontUnpack = true;

    buildPhase = ''
      gcc -O2 -Wall $src -o vpnify
    '';

    installPhase = ''
      mkdir -p $out/bin
      install -m 0755 vpnify $out/bin/vpnify
    '';
  };
  FIX_INCOMING_PACKETS_TABLE = "1212";
  FIX_INCOMING_PACKETS_MARK = "0x1";
  VPNIFY_TABLE = "2022";
  GAME_PEERS_TABLE = "1213";
  fix_incoming_packets_script = pkgs.writeShellScript "fix_incoming_packets_script" ''
    PATH=$PATH:${pkgs.iptables}/bin:${pkgs.gawk}/bin:${pkgs.iproute2}/bin:${pkgs.ipset}/bin
    FIX_INCOMING_PACKETS_TABLE=${FIX_INCOMING_PACKETS_TABLE}
    FIX_INCOMING_PACKETS_MARK=${FIX_INCOMING_PACKETS_MARK}
    GAME_PEERS_TABLE=${GAME_PEERS_TABLE}
    COUNT=0

    while true; do
      GW_IP=$(ip route show default table main | awk '/default/ {print $3}' | head -n 1)
      GW_DEV=$(ip route show default table main | awk '/default/ {print $5}' | head -n 1)

      if [[ -n "$GW_IP" ]] && [[ -n "$GW_DEV" ]]; then
        PHYSICAL_IP=$(ip -4 addr show dev $GW_DEV | awk '/inet / {print $2}' | cut -d/ -f1)

        ip route replace default via $GW_IP dev $GW_DEV table $FIX_INCOMING_PACKETS_TABLE 2>/dev/null

        iptables -t mangle -N BYPASS_CHECK || true
        
        if ip link show tun0 >/dev/null 2>&1; then
           iptables -t mangle -C BYPASS_CHECK -i tun0 -j RETURN 2>/dev/null || \
             iptables -t mangle -A BYPASS_CHECK -i tun0 -j RETURN
        fi

        iptables -t mangle -C BYPASS_CHECK -i lo -j RETURN 2>/dev/null || \
          iptables -t mangle -A BYPASS_CHECK -i lo -j RETURN 2>/dev/null || true
        
        iptables -t mangle -C BYPASS_CHECK -j CONNMARK --set-mark $FIX_INCOMING_PACKETS_MARK 2>/dev/null || \
          iptables -t mangle -A BYPASS_CHECK -j CONNMARK --set-mark $FIX_INCOMING_PACKETS_MARK

        iptables -t mangle -C PREROUTING -m conntrack --ctstate NEW -j BYPASS_CHECK 2>/dev/null || \
          iptables -t mangle -A PREROUTING -m conntrack --ctstate NEW -j BYPASS_CHECK

        iptables -t mangle -C OUTPUT -m connmark --mark $FIX_INCOMING_PACKETS_MARK -j CONNMARK --restore-mark 2>/dev/null || \
          iptables -t mangle -A OUTPUT -m connmark --mark $FIX_INCOMING_PACKETS_MARK -j CONNMARK --restore-mark

        ip rule show | grep -q "lookup $FIX_INCOMING_PACKETS_TABLE" || \
          ip rule add fwmark $FIX_INCOMING_PACKETS_MARK lookup $FIX_INCOMING_PACKETS_TABLE priority 50 2>/dev/null

        if [[ -n "$PHYSICAL_IP" ]]; then
          ipset create bypass_peers hash:ip 2>/dev/null || true

          iptables -t mangle -C PREROUTING -i $GW_DEV -m conntrack --ctstate NEW -j SET --add-set bypass_peers src 2>/dev/null || \
            iptables -t mangle -A PREROUTING -i $GW_DEV -m conntrack --ctstate NEW -j SET --add-set bypass_peers src

          ip rule show | grep -q "lookup $GAME_PEERS_TABLE" || \
            ip rule add lookup $GAME_PEERS_TABLE priority 5000 2>/dev/null

          current_peers=$(ipset list bypass_peers 2>/dev/null | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ {print $1}')
          existing_routes=$(ip route show table $GAME_PEERS_TABLE 2>/dev/null | awk '{print $1}')

          for peer in $current_peers; do
            echo "$existing_routes" | grep -q "^$peer$" || \
              ip route add $peer via $GW_IP dev $GW_DEV src $PHYSICAL_IP table $GAME_PEERS_TABLE 2>/dev/null
          done

          for route_ip in $existing_routes; do
            echo "$current_peers" | grep -q "^$route_ip$" || \
              ip route del $route_ip table $GAME_PEERS_TABLE 2>/dev/null
          done
        fi
      fi
      # Something needs to init first, and I don't know what exactly, I'll figure out later
      if [[ $COUNT -gt 100 ]]; then
        sleep 180
      fi
      sleep 2
      (( COUNT++ ))
    done
  '';
  cleanup_script = pkgs.writeShellScript "singbox_cleanup_script" ''
    PATH=$PATH:${pkgs.iptables}/bin:${pkgs.iproute2}/bin:${pkgs.ipset}/bin:${pkgs.gawk}/bin
    FIX_INCOMING_PACKETS_TABLE=${FIX_INCOMING_PACKETS_TABLE}
    FIX_INCOMING_PACKETS_MARK=${FIX_INCOMING_PACKETS_MARK}
    VPNIFY_TABLE=${VPNIFY_TABLE}
    GAME_PEERS_TABLE=${GAME_PEERS_TABLE}
    
    rm -rf /etc/netns/vpn_wrapper

    ip netns del vpn_wrapper 2>/dev/null || true
    ip link del veth_host 2>/dev/null || true
    ip route flush table $VPNIFY_TABLE 2>/dev/null || true

    for prio in 1 2; do
      while ip rule del priority $prio 2>/dev/null; do :; done
    done

    iptables -t mangle -D PREROUTING -j CONNMARK --restore-mark --mask 0xFFFE 2>/dev/null || true
    iptables -t mangle -D OUTPUT -m mark --mark ${toString zapret-mark} -j CONNMARK --save-mark --mask 0xFFFE 2>/dev/null || true
    iptables -t mangle -D OUTPUT -m mark --mark ${toString zapret-mark} -j NFQUEUE --queue-num ${zapret-qnum} --queue-bypass 2>/dev/null || true
    
    iptables -t mangle -D PREROUTING -m conntrack --ctstate NEW -j BYPASS_CHECK 2>/dev/null || true
    iptables -t mangle -D OUTPUT -m connmark --mark $FIX_INCOMING_PACKETS_MARK -j CONNMARK --restore-mark 2>/dev/null || true
    iptables -t mangle -F BYPASS_CHECK 2>/dev/null || true
    iptables -t mangle -X BYPASS_CHECK 2>/dev/null || true
    ip rule del fwmark $FIX_INCOMING_PACKETS_MARK lookup $FIX_INCOMING_PACKETS_TABLE priority 50 2>/dev/null || true
    ip route flush table $FIX_INCOMING_PACKETS_TABLE 2>/dev/null || true

    iptables-save -t mangle | grep -e "-j SET --add-set bypass_peers src" | sed 's/-A /-D /' | while read -r cmd; do
      iptables -t mangle $cmd 2>/dev/null || true
    done
    ip rule del lookup $GAME_PEERS_TABLE priority 5000 2>/dev/null || true
    ip route flush table $GAME_PEERS_TABLE 2>/dev/null || true
    ipset destroy bypass_peers 2>/dev/null || true
  '';
in
{
  options.singbox = {
    enable = mkEnableOption "singbox";
  };

  config = mkIf cfg.enable {
    systemd.services = {
      singbox-fix-incoming-packets = {
        bindsTo = [ "singbox.service" ];
        after = [ "singbox.service" ];
        wantedBy = [ "singbox.service" ];
        serviceConfig.ExecStart = fix_incoming_packets_script;
      };
      zapret = {
        bindsTo = [ "singbox.service" ];
        after = [ "singbox.service" ];
        wantedBy = [ "singbox.service" ];
        serviceConfig.ExecStart = "${pkgs.zapret}/bin/nfqws --qnum=${zapret-qnum} ${zapret-flags}";
      };
      singbox = {
        postStart = ''
          PATH=$PATH:${pkgs.iptables}/bin
          FIX_INCOMING_PACKETS_TABLE=${FIX_INCOMING_PACKETS_TABLE}
          FIX_INCOMING_PACKETS_MARK=${FIX_INCOMING_PACKETS_MARK}
          VPNIFY_TABLE=${VPNIFY_TABLE}

          ${cleanup_script}

          ip rule add fwmark ${toString zapret-mark}/${toString zapret-mark} lookup main priority 1
          ip rule add fwmark 0x40000000/0x40000000 lookup main priority 2
          iptables -t mangle -I PREROUTING -j CONNMARK --restore-mark --mask 0xFFFE
          iptables -t mangle -I OUTPUT -m mark --mark ${toString zapret-mark} -j CONNMARK --save-mark --mask 0xFFFE
          iptables -t mangle -A OUTPUT -m mark --mark ${toString zapret-mark} -j NFQUEUE --queue-num ${zapret-qnum} --queue-bypass

          ip netns add vpn_wrapper
          ip link add veth_host mtu 1400 type veth peer name veth_peer mtu 1400
          ip link set veth_peer netns vpn_wrapper
          ip addr add 10.200.0.1/24 dev veth_host
          ip link set veth_host up

          ip netns exec vpn_wrapper ip addr add 10.200.0.2/24 dev veth_peer
          ip netns exec vpn_wrapper ip link set veth_peer up
          ip netns exec vpn_wrapper ip link set lo up
          ip netns exec vpn_wrapper ip route add default via 10.200.0.1

          ip rule add iif veth_host lookup $VPNIFY_TABLE priority 2
          ip route add 10.200.0.0/24 dev veth_host table $VPNIFY_TABLE

          mkdir -p /etc/netns/vpn_wrapper
          echo "nameserver 10.200.0.1" > /etc/netns/vpn_wrapper/resolv.conf
        '';
        path = [ pkgs.iproute2 ];
        after = [ "graphical.target" ];
        wantedBy = [ "graphical.target" ];
        serviceConfig = {
          ExecStart = start-singbox;
          ExecStopPost = cleanup_script;
        };
      };
    };
    boot.kernel.sysctl = {
      "net.ipv4.conf.all.rp_filter" = 0;
      "net.ipv4.conf.default.rp_filter" = 0;
      "net.ipv4.ping_group_range" = "0 2147483647";
      "net.ipv4.ip_forward" = 1;
    };
    security.wrappers.vpnify = {
      setuid = true;
      owner = "root";
      group = "root";
      source = "${vpnifyBin}/bin/vpnify";
    };
    programs.firejail.enable = true;
    services = {
      resolved.enable = false;
      dnsmasq = {
        enable = true;
        resolveLocalQueries = false;
        settings = {
          bind-dynamic = true;
          except-interface = "waydroid0";
          server = [ dns ];
          neg-ttl = 1;
          cache-size = 10000;
        };
      };
    };
    networking = {
      firewall.enable = false;
      nameservers = [ "127.0.0.1" ];
      networkmanager.dns = "none";
    };
  };
}
