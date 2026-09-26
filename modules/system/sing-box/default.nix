{
  config,
  lib,
  pkgs,
  inputs,
  evalAndSubstitute,
  ...
}:
with lib;
let
  cfg = config.sing-box;
  dns = "94.140.14.14";
  dns-ipv6 = "2a10:50c0::ad1:ff";
  zapret-qnum = "210";
  zapret-mark = 707;
  MTU = 1480;
  START_FWMARK = 51820;
  START_TABLE = 1234;
  CREDENTIAL_DIR = "/etc/credstore";
  BYPASS_MARK = "0x10000";
  zapret-flags = evalAndSubstitute {
    string = builtins.readFile ../../../stuff/system/sing-box/zapret-flags;
    scope = { inherit pkgs inputs; };
  };

  processes = [
    "Battle.net.exe"
    ".AyuGram-wrapped"
    ".Discord-wrapped"
    ".spotify-wrapped"
    ".DiscordCanary-wrapped"
    "TeamSpeak"
    "electron"
    "prismlauncher"
  ];

  sanitize-awg-py = pkgs.writers.writePython3 "sanitize-awg.py" { } (
    builtins.readFile ../../../stuff/system/sing-box/sanitize-awg.py
  );

  build-config-py = pkgs.writers.writePython3 "build-config.py" { } (
    builtins.readFile ../../../stuff/system/sing-box/build-config.py
  );

  sing-box-config-file = (pkgs.formats.json { }).generate "sing-box-config-base" {
    log = {
      level = "debug";
    };
    route = {
      rules = [
        { action = "sniff"; }
        {
          inbound = [ "vless-in" ];
          outbound = "proxy";
        }
        {
          inbound = [ "mixed-in" ];
          outbound = "proxy";
        }
        {
          outbound = "proxy";
          source_ip_cidr = [
            "10.200.0.0/24"
            "fd00:200::/126"
          ];
        }
        {
          outbound = "proxy";
          process_name = processes;
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
            "gemini.google.com"
            "s3.dualstack.us-east-2.amazonaws.com"
            "beatsaver.com"
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
            "geekbench.com"
            "website-files.com"
            "localizeapi.com"
            "steamcmd.net"
            "tonelib.vip"
            "exa.ai"
            "rutracker.org"
            "rutracker.cc"
            "cache.nixos.org"
            "bitwarden.com"
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
            ".zen-twilight-wrapper"
            "zen-twilight"
          ];
        }
      ];
      auto_detect_interface = true;
      final = "final-toggle";
    };
    inbounds = [
      {
        type = "vless";
        tag = "vless-in";
        listen = "127.0.0.1";
        listen_port = 1919;
        users = [
          {
            uuid = "a1c0d4be-6c12-485c-8515-4451ee91ddc3";
            name = "sandbox-user";
          }
        ];
      }
      {
        tag = "mixed-in";
        listen_port = 2080;
        listen = "127.0.0.1";
        type = "mixed";
      }
      {
        type = "tun";
        interface_name = "tun0";
        mtu = MTU;
        strict_route = true;
        auto_route = true;
        address = [
          "172.19.0.1/30"
          "fd00::1/126"
        ];
        route_exclude_address = [
          "${dns}/32"
          "${dns-ipv6}/128"
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
        tag = "final-toggle";
        type = "selector";
        outbounds = [
          "direct"
          "proxy"
        ];
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
          "zapret"
          "direct"
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
    dontUnpack = true;
    buildPhase = "gcc -O2 -Wall ${../../../stuff/system/sing-box/vpnify.c} -o vpnify";
    installPhase = ''
      mkdir -p $out/bin
      install -m 0755 vpnify $out/bin/vpnify
    '';
  };

  vpnRoutingNft = pkgs.writeText "vpn_routing.nft" ''
    table inet vpn_routing {
      # Dynamic stateful map for inbound UDP sessions (10 minute idle timeout)
      # Key: { client_ip . client_port . server_port } => Value: local_nic_ip
      map inbound_udp_v4 {
        type ipv4_addr . inet_service . inet_service : ipv4_addr
        flags dynamic, timeout
        timeout 10m
      }

      map inbound_udp_v6 {
        type ipv6_addr . inet_service . inet_service : ipv6_addr
        flags dynamic, timeout
        timeout 10m
      }

      chain prerouting {
        type filter hook prerouting priority mangle; policy accept;

        # Ignore traffic on virtual / tunnel / loopback interfaces
        iifname { "tun*", "awg*", "lo", "veth*" } accept

        # 1. TCP and general conntrack mark for inbound connections
        ct state new ct mark set ct mark or ${BYPASS_MARK}

        # 2. Dynamic tracking of inbound UDP sessions across any port
        ip version 4 udp dport != 0 update @inbound_udp_v4 { ip saddr . udp sport . udp dport : ip daddr }
        ip6 version 6 udp dport != 0 update @inbound_udp_v6 { ip6 saddr . udp sport . udp dport : ip6 daddr }
      }

      chain output {
        type route hook output priority mangle; policy accept;

        # TCP replies: Conntrack mark restoration (TCP sockets bind saddr automatically upon accept)
        meta l4proto tcp ct mark and ${BYPASS_MARK} == ${BYPASS_MARK} meta mark set meta mark or ${BYPASS_MARK}

        # UDP replies from 0.0.0.0 wildcard sockets:
        # Match outbound UDP against the active inbound session map.
        # 1) Restore saddr from tun0 IP back to physical interface IP (e.g. 192.168.0.225)
        # 2) Set fwmark to trigger ip_route_me_harder() via table main (eno1 / wlan0)
        ip daddr . udp dport . udp sport @inbound_udp_v4 \
          ip saddr set ip daddr . udp dport . udp sport map @inbound_udp_v4 \
          meta mark set meta mark or ${BYPASS_MARK}

        ip6 daddr . udp dport . udp sport @inbound_udp_v6 \
          ip6 saddr set ip6 daddr . udp dport . udp sport map @inbound_udp_v6 \
          meta mark set meta mark or ${BYPASS_MARK}

        # Zapret NFQWS bypass preservation
        meta mark ${toString zapret-mark} counter queue num ${zapret-qnum} bypass
      }

      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "awg*" masquerade
      }
    }
  '';

  cleanup_script = pkgs.writeShellScript "sing-box-cleanup" ''
    PATH="$PATH:${pkgs.iproute2}/bin:${pkgs.nftables}/bin"

    nft delete table inet vpn_routing 2>/dev/null || true

    rm -rf /etc/netns/vpn_wrapper
    ip netns del vpn_wrapper 2>/dev/null || true
    ip link del veth_host 2>/dev/null || true

    ip rule del fwmark ${toString zapret-mark}/${toString zapret-mark} lookup main priority 1 2>/dev/null || true
    ip -6 rule del fwmark ${toString zapret-mark}/${toString zapret-mark} lookup main priority 1 2>/dev/null || true
    ip rule del fwmark 0x40000000/0x40000000 lookup main priority 2 2>/dev/null || true
    ip -6 rule del fwmark 0x40000000/0x40000000 lookup main priority 2 2>/dev/null || true
    ip rule del fwmark ${BYPASS_MARK}/${BYPASS_MARK} lookup main priority 50 2>/dev/null || true
    ip -6 rule del fwmark ${BYPASS_MARK}/${BYPASS_MARK} lookup main priority 50 2>/dev/null || true
    ip rule del to 10.200.0.0/24 lookup main priority 2 2>/dev/null || true
    ip -6 rule del to fd00:200::/126 lookup main priority 2 2>/dev/null || true
  '';

  setup_script = pkgs.writeShellScript "sing-box-setup" ''
    PATH="$PATH:${pkgs.iproute2}/bin:${pkgs.nftables}/bin"
    ${cleanup_script}
    set -e

    nft -f ${vpnRoutingNft}

    ip rule add fwmark ${toString zapret-mark}/${toString zapret-mark} lookup main priority 1
    ip -6 rule add fwmark ${toString zapret-mark}/${toString zapret-mark} lookup main priority 1 2>/dev/null || true

    ip rule add fwmark 0x40000000/0x40000000 lookup main priority 2
    ip -6 rule add fwmark 0x40000000/0x40000000 lookup main priority 2 2>/dev/null || true

    ip rule add fwmark ${BYPASS_MARK}/${BYPASS_MARK} lookup main priority 50
    ip -6 rule add fwmark ${BYPASS_MARK}/${BYPASS_MARK} lookup main priority 50 2>/dev/null || true

    ip netns add vpn_wrapper
    ip link add veth_host mtu ${toString MTU} type veth peer name veth_peer mtu ${toString MTU}
    ip link set veth_peer netns vpn_wrapper

    ip addr add 10.200.0.1/24 dev veth_host
    ip addr add fd00:200::1/126 dev veth_host
    ip link set veth_host up

    ip netns exec vpn_wrapper ip addr add 10.200.0.2/24 dev veth_peer
    ip netns exec vpn_wrapper ip -6 addr add fd00:200::2/126 dev veth_peer
    ip netns exec vpn_wrapper ip link set veth_peer up
    ip netns exec vpn_wrapper ip link set lo up
    ip netns exec vpn_wrapper ip route add default via 10.200.0.1
    ip netns exec vpn_wrapper ip -6 route add default via fd00:200::1

    ip rule add to 10.200.0.0/24 lookup main priority 2
    ip -6 rule add to fd00:200::/126 lookup main priority 2 2>/dev/null || true

    mkdir -p /etc/netns/vpn_wrapper
    echo "nameserver 10.200.0.1" > /etc/netns/vpn_wrapper/resolv.conf
  '';

  awg_up_script = pkgs.writeShellScript "awg-up" ''
    set -e
    IFACE="$1"
    source "/run/sing-box/$IFACE.state" 2>/dev/null || { echo "Missing state for $IFACE" >&2; exit 1; }
    ${pkgs.amneziawg-tools}/bin/awg-quick up "/run/sing-box/$IFACE.conf"
    ip route replace default dev "$IFACE" table "$TABLE" mtu ${toString MTU}
    ip rule add oif "$IFACE" lookup "$TABLE" priority 1 2>/dev/null || true
    ip rule add fwmark "$FWMARK" lookup main priority 10 2>/dev/null || true
  '';

  awg_down_script = pkgs.writeShellScript "awg-down" ''
    IFACE="$1"
    source "/run/sing-box/$IFACE.state" 2>/dev/null || true
    ip rule del oif "$IFACE" lookup "''${TABLE:-1234}" priority 1 2>/dev/null || true
    ip rule del fwmark "''${FWMARK:-51820}" lookup main priority 10 2>/dev/null || true
    ip route flush table "''${TABLE:-1234}" 2>/dev/null || true
    ${pkgs.amneziawg-tools}/bin/awg-quick down "/run/sing-box/$IFACE.conf" 2>/dev/null || true
  '';

  init_script = pkgs.writeShellScript "sing-box-init" ''
    set -e
    [[ -d "${CREDENTIAL_DIR}" ]] || { echo "Error: CREDENTIAL_DIR (${CREDENTIAL_DIR}) missing!" >&2; exit 1; }

    echo "Initializing base network policies..."
    ${setup_script}

    START_FWMARK=${toString START_FWMARK}
    START_TABLE=${toString START_TABLE}

    find_free_id() {
      local val=$1 type=$2
      while true; do
        if [[ "$type" == "mark" ]]; then
          local hex; hex=$(printf "0x%x" "$val")
          ip rule show | grep -qE "fwmark ($val|$hex)" || grep -rq "FWMARK=$val" /run/sing-box/*.state 2>/dev/null || { echo "$val"; return; }
        else
          ip rule show | grep -q "lookup $val" || ip route show table "$val" >/dev/null 2>&1 || grep -rq "TABLE=$val" /run/sing-box/*.state 2>/dev/null || { echo "$val"; return; }
        fi
        (( val++ ))
      done
    }

    AWG_SERVICES=()
    AWG_OUTBOUNDS="[]"
    ALL_NEW_TAGS="[]"

    while IFS= read -r -d "" conf_file; do
      iface_name="$(basename "$conf_file" .conf)"
      FWMARK=$(find_free_id "$START_FWMARK" "mark")
      TABLE=$(find_free_id "$START_TABLE" "table")
      START_FWMARK=$((FWMARK + 1))
      START_TABLE=$((TABLE + 1))

      python3 ${sanitize-awg-py} "$conf_file" "/run/sing-box/$iface_name.conf" "$FWMARK"
      printf "FWMARK=%s\nTABLE=%s\nINTERFACE=%s\n" "$FWMARK" "$TABLE" "$iface_name" > "/run/sing-box/$iface_name.state"

      tag=$(grep -oP '(?<=# tag=")[^"]+' "$conf_file" || echo "$iface_name")
      AWG_OUTBOUNDS=$(jq -n --argjson list "$AWG_OUTBOUNDS" --arg tag "$tag" --arg iface "$iface_name" \
        '$list + [{tag: $tag, type: "direct", bind_interface: $iface}]')
      ALL_NEW_TAGS=$(jq -n --argjson list "$ALL_NEW_TAGS" --arg tag "$tag" '[$tag] + $list')

      systemctl start "awg-interface@$iface_name.service"
      AWG_SERVICES+=("awg-interface@$iface_name.service")
    done < <(find "${CREDENTIAL_DIR}" -maxdepth 1 -name "awg*.conf" -print0 2>/dev/null | sort -z)

    for svc in "''${AWG_SERVICES[@]}"; do
      count=0
      while ! systemctl is-active --quiet "$svc"; do
        sleep 0.5
        (( ++count > 25 )) && {
          echo "Error: $svc failed to start!" >&2
          journalctl -u "$svc" -n 20 --no-pager >&2
          exit 1
        }
      done
    done

    CRED_CONF="${CREDENTIAL_DIR}/config.json"
    if [[ -f "$CRED_CONF" ]]; then
      EXTRA_TAGS=$(jq -r '[.outbounds[]?.tag // empty, .endpoints[]?.tag // empty] | reverse | .[]' "$CRED_CONF" 2>/dev/null || true)
      for tag in $EXTRA_TAGS; do
        ALL_NEW_TAGS=$(jq -n --argjson list "$ALL_NEW_TAGS" --arg tag "$tag" '[$tag] + $list')
      done
    else
      CRED_CONF="none"
    fi

    echo "Assembling unified sing-box config..."
    python3 ${build-config-py} \
      "${sing-box-config-file}" \
      "$CRED_CONF" \
      "/run/sing-box/config.json" \
      "$AWG_OUTBOUNDS" \
      "$ALL_NEW_TAGS"

    chmod 600 /run/sing-box/config.json
    echo "sing-box initialization complete."
  '';

  stop_script = pkgs.writeShellScript "sing-box-stop" ''
    for svc in $(systemctl list-units --type=service --state=active --no-legend "awg-interface@*" | awk '{print $1}'); do
      systemctl stop "$svc" || true
    done
    ${cleanup_script}
  '';

  sing-box-watcher-src = pkgs.writeText "sing-box-watcher.c" ''
    #define _GNU_SOURCE
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <unistd.h>
    #include <dirent.h>
    #include <fcntl.h>
    #include <signal.h>
    #include <poll.h>
    #include <sys/socket.h>
    #include <linux/rtnetlink.h>
    #include <sys/wait.h>

    static volatile sig_atomic_t g_running = 1;

    static void handle_signal(int sig) {
        (void)sig;
        g_running = 0;
    }

    static void run_systemctl(const char *action) {
        pid_t pid = fork();
        if (pid == 0) {
            execl("${pkgs.systemd}/bin/systemctl", "systemctl", action, "sing-box-init.service", NULL);
            _exit(1);
        } else if (pid > 0) {
            int status;
            waitpid(pid, &status, 0);
        }
    }

    static int has_physical_carrier(void) {
        DIR *dir = opendir("/sys/class/net");
        if (!dir) return 0;

        struct dirent *de;
        int connected = 0;

        while ((de = readdir(dir)) != NULL) {
            if (de->d_name[0] == '.') continue;

            char path[512];
            snprintf(path, sizeof(path), "/sys/class/net/%s/device", de->d_name);
            if (access(path, F_OK) != 0) {
                // Ignore virtual network devices (tun0, lo, veth, etc.)
                continue;
            }

            // Check carrier
            snprintf(path, sizeof(path), "/sys/class/net/%s/carrier", de->d_name);
            int fd = open(path, O_RDONLY | O_CLOEXEC);
            if (fd >= 0) {
                char ch = 0;
                if (read(fd, &ch, 1) == 1 && ch == '1') {
                    connected = 1;
                    close(fd);
                    break;
                }
                close(fd);
            }

            // Check operstate fallback
            snprintf(path, sizeof(path), "/sys/class/net/%s/operstate", de->d_name);
            fd = open(path, O_RDONLY | O_CLOEXEC);
            if (fd >= 0) {
                char buf[8];
                ssize_t n = read(fd, buf, sizeof(buf) - 1);
                if (n >= 2 && strncmp(buf, "up", 2) == 0) {
                    connected = 1;
                    close(fd);
                    break;
                }
                close(fd);
            }
        }

        closedir(dir);
        return connected;
    }

    int main(void) {
        struct sigaction sa;
        memset(&sa, 0, sizeof(sa));
        sa.sa_handler = handle_signal;
        sigaction(SIGTERM, &sa, NULL);
        sigaction(SIGINT, &sa, NULL);

        int nl_fd = socket(AF_NETLINK, SOCK_RAW | SOCK_CLOEXEC | SOCK_NONBLOCK, NETLINK_ROUTE);
        if (nl_fd < 0) {
            perror("socket(AF_NETLINK)");
            return 1;
        }

        struct sockaddr_nl sa_nl;
        memset(&sa_nl, 0, sizeof(sa_nl));
        sa_nl.nl_family = AF_NETLINK;
        sa_nl.nl_groups = RTMGRP_LINK;

        if (bind(nl_fd, (struct sockaddr *)&sa_nl, sizeof(sa_nl)) < 0) {
            perror("bind(AF_NETLINK)");
            close(nl_fd);
            return 1;
        }

        int last_state = -1;

        while (g_running) {
            int connected = has_physical_carrier();

            if (connected != last_state) {
                last_state = connected;
                if (connected) {
                    fprintf(stderr, "[sing-box-watcher] Physical link UP. Starting sing-box-init...\n");
                    run_systemctl("start");
                } else {
                    fprintf(stderr, "[sing-box-watcher] Physical link DOWN. Stopping sing-box-init...\n");
                    run_systemctl("stop");
                }
            }

            struct pollfd pfd;
            memset(&pfd, 0, sizeof(pfd));
            pfd.fd = nl_fd;
            pfd.events = POLLIN;

            int ret = poll(&pfd, 1, -1);
            if (ret > 0 && (pfd.revents & POLLIN)) {
                char buf[4096];
                while (recv(nl_fd, buf, sizeof(buf), MSG_DONTWAIT) > 0) {}

                // Debounce 1.5s to absorb link flapping / DHCP negotiation
                int remaining_ms = 1500;
                while (g_running && remaining_ms > 0) {
                    struct pollfd pfd_db = { .fd = nl_fd, .events = POLLIN, .revents = 0 };
                    int db_ret = poll(&pfd_db, 1, (remaining_ms > 200) ? 200 : remaining_ms);
                    if (db_ret > 0 && (pfd_db.revents & POLLIN)) {
                        while (recv(nl_fd, buf, sizeof(buf), MSG_DONTWAIT) > 0) {}
                    }
                    remaining_ms -= 200;
                }
            }
        }

        fprintf(stderr, "[sing-box-watcher] Exiting, stopping sing-box-init...\n");
        run_systemctl("stop");
        close(nl_fd);
        return 0;
    }
  '';

  sing-box-watcher = pkgs.stdenv.mkDerivation {
    pname = "sing-box-watcher";
    version = "1.0";
    dontUnpack = true;
    src = sing-box-watcher-src;
    buildPhase = "$CC -O2 -Wall $src -o sing-box-watcher";
    installPhase = ''
      mkdir -p $out/bin
      install -m 0755 sing-box-watcher $out/bin/sing-box-watcher
    '';
  };

in
{
  options.sing-box = {
    enable = mkEnableOption "sing-box";
    processes_to_proxy = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      internal = true;
      visible = false;
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.amneziawg-tools
      pkgs.nftables
    ];
    sing-box.processes_to_proxy = processes;

    boot = {
      extraModulePackages = [
        config.boot.kernelPackages.amneziawg
      ];
      kernelModules = [ "amneziawg" ];
    };

    boot.kernel.sysctl = {
      "net.ipv6.conf.all.forwarding" = 1;
      "net.ipv4.ping_group_range" = "0 2147483647";
      "net.ipv4.ip_forward" = 1;
    };

    systemd.services = {
      "awg-interface@" = {
        description = "AmneziaWG Interface (%i)";
        bindsTo = [ "sing-box-init.service" ];
        partOf = [ "sing-box-init.service" ];
        path = with pkgs; [
          amneziawg-tools
          iproute2
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
          ExecStart = "${awg_up_script} %i";
          ExecStop = "${awg_down_script} %i";
        };
      };

      sing-box = {
        description = "Sing-box Connection Supervisor and Physical Link Watcher";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-pre.target" ];
        path = with pkgs; [
          systemd
        ];
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "3s";
          ExecStart = "${sing-box-watcher}/bin/sing-box-watcher";
          ExecStopPost = "${pkgs.systemd}/bin/systemctl stop sing-box-init.service";
        };
      };

      sing-box-init = {
        description = "Sing-box Initialization and Configuration Generator";
        wants = [ "sing-box-core.service" ];
        before = [ "sing-box-core.service" ];
        partOf = [ "sing-box-core.service" ];
        path = with pkgs; [
          iproute2
          nftables
          jq
          gnugrep
          gawk
          systemd
          python3
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
          RuntimeDirectory = "sing-box";
          RuntimeDirectoryMode = "0700";
          ExecStart = "${init_script}";
          ExecStop = "${stop_script}";
        };
      };

      sing-box-core = {
        description = "Sing-box Core Daemon";
        bindsTo = [ "sing-box-init.service" ];
        after = [ "sing-box-init.service" ];
        serviceConfig = {
          ExecStart = "${pkgs.sing-box}/bin/sing-box run -c /run/sing-box/config.json";

          DynamicUser = true;
          RuntimeDirectory = "sing-box-daemon";
          WorkingDirectory = "/run/sing-box-daemon";
          PrivateDevices = false;
          NoNewPrivileges = true;
          RemoveIPC = true;

          CapabilityBoundingSet = [
            "CAP_NET_ADMIN"
            "CAP_NET_BIND_SERVICE"
            "CAP_NET_RAW"
            "CAP_SYS_PTRACE"
            "CAP_DAC_READ_SEARCH"
          ];
          AmbientCapabilities = [
            "CAP_NET_ADMIN"
            "CAP_NET_BIND_SERVICE"
            "CAP_NET_RAW"
            "CAP_SYS_PTRACE"
            "CAP_DAC_READ_SEARCH"
          ];
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectControlGroups = true;
          ProtectKernelTunables = false;
          ProtectKernelModules = true;
          ProtectClock = true;
          ProtectKernelLogs = true;
          RestrictNamespaces = false;
          RestrictRealtime = true;
          LockPersonality = true;
          PrivateUsers = false;
          MemoryDenyWriteExecute = true;
          ProtectProc = "default";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_NETLINK"
            "AF_UNIX"
          ];
          SystemCallArchitectures = "native";
          SystemCallFilter = "@system-service";
          SystemCallErrorNumber = "EPERM";
          DeviceAllow = "/dev/net/tun rwm";
        };
      };

      zapret = {
        bindsTo = [ "sing-box-core.service" ];
        partOf = [ "sing-box-core.service" ];
        after = [ "sing-box-core.service" ];
        wantedBy = [ "sing-box-core.service" ];
        serviceConfig = {
          DynamicUser = true;
          RuntimeDirectory = "nfqws";
          WorkingDirectory = "/run/nfqws";
          ExecStart = "${pkgs.zapret}/bin/nfqws --qnum=${zapret-qnum} ${zapret-flags}";
          Restart = "always";
          RestartSec = 5;

          PrivateDevices = true;
          NoNewPrivileges = true;
          RemoveIPC = true;

          CapabilityBoundingSet = [
            "CAP_NET_ADMIN"
            "CAP_NET_RAW"
          ];
          AmbientCapabilities = [
            "CAP_NET_ADMIN"
            "CAP_NET_RAW"
          ];
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectControlGroups = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectClock = true;
          ProtectKernelLogs = true;
          RestrictNamespaces = true;
          RestrictRealtime = true;
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          ProtectProc = "invisible";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_NETLINK"
            "AF_UNIX"
          ];
          SystemCallArchitectures = "native";
          SystemCallFilter = "@system-service";
          SystemCallErrorNumber = "EPERM";
        };
      };
    };

    security.wrappers.vpnify = {
      owner = "root";
      group = "root";
      capabilities = "cap_sys_admin+ep";
      source = "${vpnifyBin}/bin/vpnify";
    };

    services = {
      resolved.enable = false;
      dnsmasq = {
        enable = true;
        resolveLocalQueries = false;
        settings = {
          bind-dynamic = true;
          except-interface = "waydroid0";
          server = [
            dns
            dns-ipv6
          ];
          neg-ttl = 1;
          cache-size = 10000;
        };
      };
    };

    networking = {
      firewall.enable = false;
      nameservers = [
        "127.0.0.1"
        "::1"
      ];
      networkmanager.dns = "none";
    };
  };
}
