{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.singbox;
  dns = "1.1.1.1";
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
in
{
  options.singbox = {
    enable = mkEnableOption "Enable singbox";
  };

  config = mkIf cfg.enable {
    systemd.services.singbox = {
      preStart = ''
        # Cleanup old remains if service crashed
        ip netns del vpn_wrapper 2>/dev/null || true
        ip link del veth_host 2>/dev/null || true
        ip rule delete iif veth_host lookup 2022 priority 2 || true
      '';

      postStart = ''
        PATH=$PATH:${pkgs.procps}/bin:${pkgs.iptables}/bin
        # 1. Create Namespace & Veth
        ip netns add vpn_wrapper
        ip link add veth_host mtu 1400 type veth peer name veth_peer mtu 1400
        ip link set veth_peer netns vpn_wrapper
        ip addr add 10.200.0.1/24 dev veth_host
        ip link set veth_host up

        # 2. Configure Namespace
        ip netns exec vpn_wrapper ip addr add 10.200.0.2/24 dev veth_peer
        ip netns exec vpn_wrapper ip link set veth_peer up
        ip netns exec vpn_wrapper ip link set lo up
        ip netns exec vpn_wrapper ip route add default via 10.200.0.1
        ip netns exec vpn_wrapper sysctl -w net.ipv4.ping_group_range="0 2147483647"

        # 3. Routing Rules (The persistent part)
        ip rule add iif veth_host lookup 2022 priority 2
        ip route add 10.200.0.0/24 dev veth_host table 2022
        
        # 4. Point DNS to the Host (Gateway IP)
        mkdir -p /etc/netns/vpn_wrapper
        echo "nameserver 10.200.0.1" > /etc/netns/vpn_wrapper/resolv.conf

        # 5. Ensure the host allows input to DNS from this subnet
        # (NixOS firewall often blocks this by default)
        iptables -I INPUT -i veth_host -p udp --dport 53 -j ACCEPT
        iptables -I INPUT -i veth_host -p tcp --dport 53 -j ACCEPT
      '';
      path = [ pkgs.iproute2 ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.sing-box}/bin/sing-box -c /config.json run";
        ExecStopPost = ''
          ${pkgs.iproute2}/bin/ip netns del vpn_wrapper || true
          ${pkgs.iproute2}/bin/ip link del veth_host || true
          ${pkgs.iproute2}/bin/ip rule delete iif veth_host lookup 2022 priority 2 || true
        '';
      };
    };
    boot.kernel.sysctl = {
      "net.ipv4.ping_group_range" = "0 2147483647";
      "net.ipv4.ip_forward" = 1;
    };
    #services.resolved = {
    #  enable = true;
    #  settings.Resolve.DNSStubListenerExtra = "127.0.0.1";
    #};
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
          port = 53;
          server = [ dns ];
          neg-ttl = 1;
          cache-size = 10000;
          interface = [ "lo" "veth_host" ];
          bind-interfaces = true;
        };
      };
    };
    networking = {
      nameservers = [ "127.0.0.1" ];
      networkmanager.dns = "none";
    };
  };
}
