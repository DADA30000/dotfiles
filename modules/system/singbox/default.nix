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
  zapret-qnum = "210";
  zapret-mark = 707;

  START_FWMARK = 51820;
  START_TABLE = 1234;

  CREDENTIAL_DIR = "/etc/credstore";

  zapret-flags = evalAndSubstitute {
    string = builtins.readFile ../../../stuff/modules/system/sing-box/zapret-flags;
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
    builtins.readFile ../../../stuff/modules/system/sing-box/sanitize-awg.py
  );

  build-config-py = pkgs.writers.writePython3 "build-config.py" { } (
    builtins.readFile ../../../stuff/modules/system/sing-box/build-config.py
  );

  # Base configurations block. "route.final" maps to the "final-toggle" selector outbound.
  sing-box-config-file = (pkgs.formats.json { }).generate "sing-box-config-base" {
    log = {
      level = "debug";
    };
    route = {
      rules = [
        {
          action = "sniff";
        }
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
          source_ip_cidr = [ "10.200.0.0/24" ];
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
            "xuyh0120.win"
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
      final = "final-toggle"; # Set default fallback route to selector tag
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
        type = "mixed";
      }
      {
        strict_route = true;
        stack = "system";
        interface_name = "tun0";
        auto_route = true;
        mtu = 1360;
        tag = "tun-in";
        address = "172.19.0.1/30";
        type = "tun";
        route_exclude_address = [
          "${dns}/32"
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
        tag = "final-toggle"; # Declarative selector group to control route.final fallback
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
    buildPhase = "gcc -O2 -Wall $src -o vpnify";
    installPhase = ''
      mkdir -p $out/bin
      install -m 0755 vpnify $out/bin/vpnify
    '';
  };

  FIX_INCOMING_PACKETS_TABLE = "1212";
  FIX_INCOMING_PACKETS_MARK = "0x1";
  VPNIFY_TABLE = "2030";
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

        iptables -t mangle -C BYPASS_CHECK -i awg0 -j RETURN 2>/dev/null || \
          iptables -t mangle -A BYPASS_CHECK -i awg0 -j RETURN

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
      if [[ $COUNT -gt 100 ]]; then
        sleep 180
      fi
      sleep 2
      (( COUNT++ ))
    done
  '';

  cleanup_script = pkgs.writeShellScript "sing-box_cleanup_script" (evalAndSubstitute {
    string = builtins.readFile ../../../stuff/modules/system/sing-box/sing-box_cleanup_script.sh;
    scope = {
      inherit
        pkgs
        FIX_INCOMING_PACKETS_MARK
        FIX_INCOMING_PACKETS_TABLE
        VPNIFY_TABLE
        GAME_PEERS_TABLE
        zapret-mark
        zapret-qnum
        ;
    };
  });

  setup_script = pkgs.writeShellScript "sing-box-setup" ''
    FIX_INCOMING_PACKETS_TABLE=${FIX_INCOMING_PACKETS_TABLE}
    FIX_INCOMING_PACKETS_MARK=${FIX_INCOMING_PACKETS_MARK}

    ${cleanup_script}

    set -e

    for f in /proc/sys/net/ipv4/conf/*/rp_filter; do
      echo 0 > "$f" 2>/dev/null || true
    done

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

    ip rule add to 10.200.0.0/24 lookup main priority 2

    mkdir -p /etc/netns/vpn_wrapper
    echo "nameserver 10.200.0.1" > /etc/netns/vpn_wrapper/resolv.conf
  '';
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
    environment.systemPackages = [ pkgs.amneziawg-tools ];
    sing-box.processes_to_proxy = processes;

    boot = {
      extraModulePackages = [
        (config.boot.kernelPackages.amneziawg.overrideAttrs (prev: {
          patches = (prev.patches or [ ]) ++ [ ../../../stuff/patches/amneziawg.patch ];
        }))
      ];
      kernelModules = [ "amneziawg" ];
    };

    systemd.services = {
      "awg-interface@" = {
        description = "AmneziaWG Interface (%i)";
        bindsTo = [ "sing-box-init.service" ];
        partOf = [ "sing-box-init.service" ];
        path = with pkgs; [
          amneziawg-tools
          iproute2
          iptables
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
          ExecStart = "${pkgs.writeShellScript "awg-up" ''
            set -e
            IFACE="$1"
            if [[ -f "/run/sing-box/$IFACE.state" ]]; then
              source "/run/sing-box/$IFACE.state"
            else
              echo "State file /run/sing-box/$IFACE.state missing!" >&2
              exit 1
            fi

            # Bring up the interface using the parsed and sanitized configuration
            ${pkgs.amneziawg-tools}/bin/awg-quick up "/run/sing-box/$IFACE.conf"

            # Route defaults manually so we do not pollute the main table
            ip route replace default dev "$IFACE" table "$TABLE" mtu 1280 2>/dev/null || \
              ip route add default dev "$IFACE" table "$TABLE" mtu 1280

            ip rule add oif "$IFACE" lookup "$TABLE" priority 1 2>/dev/null || true
            ip rule add fwmark "$FWMARK" lookup main priority 10 2>/dev/null || true
            iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE 2>/dev/null || true
          ''} %i";
          ExecStop = "${pkgs.writeShellScript "awg-down" ''
            IFACE="$1"
            if [[ -f "/run/sing-box/$IFACE.state" ]]; then
              source "/run/sing-box/$IFACE.state"
            fi
            TABLE=''${TABLE:-1234}
            FWMARK=''${FWMARK:-51820}

            ip rule del oif "$IFACE" lookup "$TABLE" priority 1 2>/dev/null || true
            ip rule del fwmark "$FWMARK" lookup main priority 10 2>/dev/null || true
            ip route flush table "$TABLE" 2>/dev/null || true
            iptables -t nat -D POSTROUTING -o "$IFACE" -j MASQUERADE 2>/dev/null || true

            ${pkgs.amneziawg-tools}/bin/awg-quick down "/run/sing-box/$IFACE.conf" || true
          ''} %i";
        };
      };

      # The Orchestrator Service: builds configuration on startup and manages AWG templates.
      # Hardened. Retains partOf = [ "sing-box.service" ] to ensure unified restarts.
      sing-box-init = {
        description = "Sing-box Initialization and Configuration Generator";
        wantedBy = [ "graphical.target" ];
        before = [ "sing-box.service" ];
        partOf = [ "sing-box.service" ];

        path = with pkgs; [
          iproute2
          iptables
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
          RuntimeDirectoryMode = "0755";
          ExecStart = pkgs.writeShellScript "sing-box-init" ''
            set -e
            CREDENTIAL_DIR="${CREDENTIAL_DIR}"

            if [[ ! -d "$CREDENTIAL_DIR" ]]; then
              echo "Error: CREDENTIAL_DIR ($CREDENTIAL_DIR) does not exist!" >&2
              exit 1
            fi

            echo "Initializing base network policies..."
            ${setup_script}

            # Discover AWG interface files safely
            AWG_FILES=()
            while IFS= read -r -d "" file; do
              AWG_FILES+=("$file")
            done < <(find "$CREDENTIAL_DIR" -maxdepth 1 -name "awg*.conf" -print0 | sort -z)

            START_FWMARK=${toString START_FWMARK}
            START_TABLE=${toString START_TABLE}

            # Helper functions to scan system for unique fwmarks and routing tables
            find_unique_fwmark() {
              local mark=$1
              while true; do
                local hex_mark
                hex_mark=$(printf "0x%x" "$mark")
                if ! ip rule show | grep -qE "fwmark ($mark|$hex_mark)" && \
                   ! grep -rq "FWMARK=$mark" /run/sing-box/*.state 2>/dev/null; then
                   echo "$mark"
                   return 0
                fi
                mark=$((mark + 1))
              done
            }

            find_unique_table() {
              local tbl=$1
              while true; do
                if ! ip rule show | grep -q "lookup $tbl" && \
                   ! ip route show table "$tbl" >/dev/null 2>&1 && \
                   ! grep -rq "TABLE=$tbl" /run/sing-box/*.state 2>/dev/null; then
                   echo "$tbl"
                   return 0
                fi
                tbl=$((tbl + 1))
              done
            }

            AWG_SERVICES=()
            AWG_OUTBOUNDS="[]"
            ALL_NEW_TAGS="[]"

            for conf_file in "''${AWG_FILES[@]}"; do
              filename=$(basename "$conf_file")
              iface_name="''${filename%.conf}"

              # Determine unique system-wide indexes
              FWMARK=$(find_unique_fwmark "$START_FWMARK")
              TABLE=$(find_unique_table "$START_TABLE")
              START_FWMARK=$((FWMARK + 1))
              START_TABLE=$((TABLE + 1))

              # Run embedded Python sanitizer
              python3 ${sanitize-awg-py} "$conf_file" "/run/sing-box/$iface_name.conf" "$FWMARK"

              # Write transient state variables
              cat <<EOF > "/run/sing-box/$iface_name.state"
            FWMARK=$FWMARK
            TABLE=$TABLE
            INTERFACE=$iface_name
            EOF

              # Extract the comment tag if present; fallback to interface name
              tag=$(grep -oP '(?<=# tag=")[^"]+' "$conf_file" || echo "$iface_name")

              # Build sing-box outbound entry
              awg_outbound=$(jq -n \
                --arg tag "$tag" \
                --arg iface "$iface_name" \
                '{tag: $tag, type: "direct", bind_interface: $iface}')
              
              AWG_OUTBOUNDS=$(echo "$AWG_OUTBOUNDS" | jq --argjson obj "$awg_outbound" '. + [$obj]')

              # Prepend tag to our array so additions bubble to the top
              ALL_NEW_TAGS=$(echo "$ALL_NEW_TAGS" | jq --arg tag "$tag" '[$tag] + .')

              # Boot up the template instance
              echo "Triggering interface awg-interface@$iface_name..."
              systemctl start "awg-interface@$iface_name.service"
              AWG_SERVICES+=("awg-interface@$iface_name.service")
            done

            # Wait for spawned templates to report completion status
            FAILED_SERVICES=()
            for svc in "''${AWG_SERVICES[@]}"; do
              if ! systemctl is-active --quiet "$svc"; then
                echo "Waiting for $svc to establish link..."
                local count=0
                while ! systemctl is-active --quiet "$svc"; do
                  sleep 0.5
                  count=$((count + 1))
                  if [[ $count -gt 25 ]]; then
                    FAILED_SERVICES+=("$svc")
                    break
                  fi
                done
              fi
            done

            # If templates failed, output logs to stderr, dismantle links and fail
            if [[ ''${#FAILED_SERVICES[@]} -gt 0 ]]; then
              echo "Error: One or more AWG interfaces failed to initialize!" >&2
              for failed in "''${FAILED_SERVICES[@]}"; do
                echo "=== Logs for $failed ===" >&2
                journalctl -u "$failed" -n 20 --no-pager >&2
              done
              for svc in "''${AWG_SERVICES[@]}"; do
                systemctl stop "$svc" || true
              done
              exit 1
            fi

            # Bubble tags from extra configs to the selector's top if config.json exists
            CRED_CONF_ARG="$CREDENTIAL_DIR/config.json"
            if [[ -f "$CRED_CONF_ARG" ]]; then
              CONFIG_OUT_TAGS=$(jq -r '.outbounds[]?.tag // empty' "$CRED_CONF_ARG" 2>/dev/null || true)
              CONFIG_EP_TAGS=$(jq -r '.endpoints[]?.tag // empty' "$CRED_CONF_ARG" 2>/dev/null || true)

              while read -r tag; do
                if [[ -n "$tag" ]]; then
                  ALL_NEW_TAGS=$(echo "$ALL_NEW_TAGS" | jq --arg tag "$tag" '[$tag] + .')
                fi
              done <<< "$CONFIG_OUT_TAGS"

              while read -r tag; do
                if [[ -n "$tag" ]]; then
                  ALL_NEW_TAGS=$(echo "$ALL_NEW_TAGS" | jq --arg tag "$tag" '[$tag] + .')
                fi
              done <<< "$CONFIG_EP_TAGS"
            else
              CRED_CONF_ARG="none"
            fi

            # Merge extra configuration, AWG targets, and organize priority list cleanly
            echo "Assembling and resolving unified sing-box config..."
            python3 ${build-config-py} \
              "${sing-box-config-file}" \
              "$CRED_CONF_ARG" \
              "/run/sing-box/config.json" \
              "$AWG_OUTBOUNDS" \
              "$ALL_NEW_TAGS"

            chmod 644 /run/sing-box/config.json
            echo "sing-box initialization complete. Unified configuration ready."
          '';
          ExecStop = pkgs.writeShellScript "sing-box-stop" ''
            # Tear down all running templates safely
            RUNNING_SVCS=$(systemctl list-units --type=service --state=active --no-legend "awg-interface@*" | awk '{print $1}')
            for svc in $RUNNING_SVCS; do
              echo "Stopping $svc..."
              systemctl stop "$svc" || true
            done
            ${cleanup_script}
          '';
        };
      };

      # Fully sandboxed sing-box execution layer.
      # sandboxed with PrivateDevices=false to ensure devicetree lookup on /dev/net/tun is fully permitted.
      sing-box = {
        wantedBy = [ "graphical.target" ];
        bindsTo = [ "sing-box-init.service" ];
        after = [ "sing-box-init.service" ];
        serviceConfig = {
          ExecStart = "${pkgs.sing-box}/bin/sing-box run -c /run/sing-box/config.json";
          ExecStartPost = "+${pkgs.writers.writeDash "sing-box-post-start" ''
            # Wait for tun0 to appear and immediately disable rp_filter on it as root
            for i in $(seq 1 20); do
              if [ -d "/proc/sys/net/ipv4/conf/tun0" ]; then
                echo 0 > /proc/sys/net/ipv4/conf/tun0/rp_filter
                echo "Successfully disabled rp_filter on tun0."
                exit 0
              fi
              sleep 0.1
            done
            echo "Warning: tun0 interface did not appear in time!" >&2
          ''}";

          # Strict Daemon Sandboxing policies
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

      sing-box-fix-incoming-packets = {
        bindsTo = [ "sing-box.service" ];
        partOf = [ "sing-box.service" ];
        after = [ "sing-box.service" ];
        wantedBy = [ "sing-box.service" ];
        serviceConfig = {
          ExecStart = fix_incoming_packets_script;
          PrivateDevices = true;
          NoNewPrivileges = true;
        };
      };

      zapret = {
        bindsTo = [ "sing-box.service" ];
        partOf = [ "sing-box.service" ];
        after = [ "sing-box.service" ];
        wantedBy = [ "sing-box.service" ];
        serviceConfig = {
          DynamicUser = true;
          RuntimeDirectory = "nfqws";
          WorkingDirectory = "/run/nfqws";
          ExecStart = "${pkgs.zapret}/bin/nfqws --qnum=${zapret-qnum} ${zapret-flags}";
          Restart = "always";
          RestartSec = 5;

          # Hardening
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
