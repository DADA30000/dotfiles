{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.singbox;
  dns = "94.140.14.14";
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

        /* save environment early */
        char **saved_env = environ;

        int fd = open("/var/run/netns/vpn_wrapper", O_RDONLY);
        if (fd < 0) {
            perror("open netns");
            return 1;
        }

        /* enter network namespace */
        if (setns(fd, CLONE_NEWNET) != 0) {
            perror("setns(net)");
            return 1;
        }

        /* private mount namespace */
        if (unshare(CLONE_NEWNS) != 0) {
            perror("unshare mount ns");
            return 1;
        }

        /* stop mount propagation */
        if (mount(NULL, "/", NULL, MS_REC | MS_PRIVATE, NULL) != 0) {
            perror("mount private");
            return 1;
        }

        /* optional per-netns resolv.conf */
        const char *ns_resolv = "/etc/netns/vpn_wrapper/resolv.conf";
        struct stat st;
        if (stat(ns_resolv, &st) == 0) {
            if (mount(ns_resolv, "/etc/resolv.conf", NULL, MS_BIND, NULL) != 0) {
                perror("bind resolv.conf");
                return 1;
            }
        }

        /* drop privileges LAST */
        if (setuid(getuid()) != 0) {
            perror("setuid");
            return 1;
        }

        /* restore user environment */
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

    while true; do
      GW_IP=$(ip route show default table main | awk '/default/ {print $3}' | head -n 1)
      GW_DEV=$(ip route show default table main | awk '/default/ {print $5}' | head -n 1)

      if [[ -n "$GW_IP" ]] && [[ -n "$GW_DEV" ]]; then
        PHYSICAL_IP=$(ip -4 addr show dev $GW_DEV | awk '/inet / {print $2}' | cut -d/ -f1)

        ip route show table $FIX_INCOMING_PACKETS_TABLE | grep -q "default via $GW_IP" || \
          ip route add default via $GW_IP dev $GW_DEV table $FIX_INCOMING_PACKETS_TABLE 2>/dev/null

        iptables -t mangle -L BYPASS_CHECK >/dev/null 2>&1 || iptables -t mangle -N BYPASS_CHECK
        
        if ip link show tun0 >/dev/null 2>&1; then
           iptables -t mangle -C BYPASS_CHECK -i tun0 -j RETURN 2>/dev/null || \
             iptables -t mangle -A BYPASS_CHECK -i tun0 -j RETURN
        fi

        iptables -t mangle -C BYPASS_CHECK -i lo -j RETURN 2>/dev/null || \
          iptables -t mangle -A BYPASS_CHECK -i lo -j RETURN
        
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

      sleep 2
    done
  '';
  cleanup_script = pkgs.writeShellScript "singbox_cleanup_script" ''
    PATH=$PATH:${pkgs.iptables}/bin:${pkgs.iproute2}/bin:${pkgs.ipset}/bin:${pkgs.gawk}/bin
    FIX_INCOMING_PACKETS_TABLE=${FIX_INCOMING_PACKETS_TABLE}
    FIX_INCOMING_PACKETS_MARK=${FIX_INCOMING_PACKETS_MARK}
    VPNIFY_TABLE=${VPNIFY_TABLE}
    GAME_PEERS_TABLE=${GAME_PEERS_TABLE}

    ip netns del vpn_wrapper 2>/dev/null || true
    ip link del veth_host 2>/dev/null || true
    ip rule delete iif veth_host lookup $VPNIFY_TABLE priority 2 2>/dev/null || true
    ip route flush table $VPNIFY_TABLE 2>/dev/null || true

    iptables -t mangle -D PREROUTING -m conntrack --ctstate NEW -j BYPASS_CHECK 2>/dev/null || true
    iptables -t mangle -D OUTPUT -m connmark --mark $FIX_INCOMING_PACKETS_MARK -j CONNMARK --restore-mark 2>/dev/null || true
    iptables -t mangle -F BYPASS_CHECK 2>/dev/null || true
    iptables -t mangle -X BYPASS_CHECK 2>/dev/null || true
    ip rule del fwmark $FIX_INCOMING_PACKETS_MARK lookup $FIX_INCOMING_PACKETS_TABLE priority 50 2>/dev/null || true
    ip route flush table $FIX_INCOMING_PACKETS_TABLE 2>/dev/null || true

    GW_DEV=$(ip route show default table main | awk '/default/ {print $5}' | head -n 1)
    if [[ -n "$GW_DEV" ]]; then
      iptables -t mangle -D PREROUTING -i $GW_DEV -m conntrack --ctstate NEW -j SET --add-set bypass_peers src 2>/dev/null || true
    fi
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
      singbox = {
        postStart = ''
          PATH=$PATH:${pkgs.iptables}/bin
          FIX_INCOMING_PACKETS_TABLE=${FIX_INCOMING_PACKETS_TABLE}
          FIX_INCOMING_PACKETS_MARK=${FIX_INCOMING_PACKETS_MARK}
          VPNIFY_TABLE=${VPNIFY_TABLE}

          ${cleanup_script}

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
          ExecStart = "${pkgs.sing-box}/bin/sing-box -c /config.json run";
          ExecStopPost = cleanup_script;
        };
      };
    };
    boot.kernel.sysctl = {
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
          server = [ dns ];
          neg-ttl = 1;
          cache-size = 10000;
        };
      };
    };
    networking = {
      nameservers = [ "127.0.0.1" ];
      networkmanager.dns = "none";
    };
  };
}
