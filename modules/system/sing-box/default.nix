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
  MTU = 1480;
  CREDENTIAL_DIR = "/etc/credstore";
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
        tag = "direct-in";
        listen = "127.0.0.1";
        listen_port = 2121;
        users = [
          {
            uuid = "a1c0d4be-6c12-485c-8515-4451ee91ddc3";
            name = "sandbox-user";
          }
        ];
      }
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
        type = "tun";
        interface_name = "tun0";
        mtu = MTU;
        strict_route = true;
        auto_route = true;
        auto_redirect = true;
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
        inet4_bind_address = "10.201.0.1";
        inet6_bind_address = "fd00:201::1";
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

  vpnRoutingNft = pkgs.writeText "vpn_routing.nft" (evalAndSubstitute {
    string = builtins.readFile ../../../stuff/system/sing-box/vpn_routing.nft;
    scope = { inherit zapret-qnum; };
  });

  cleanup_script = pkgs.writeShellScript "sing-box-cleanup" (evalAndSubstitute {
    string = builtins.readFile ../../../stuff/system/sing-box/sing-box-cleanup.sh;
    scope = { inherit pkgs; };
  });

  setup_script = pkgs.writeShellScript "sing-box-setup" (evalAndSubstitute {
    string = builtins.readFile ../../../stuff/system/sing-box/sing-box-setup.sh;
    scope = {
      inherit
        pkgs
        cleanup_script
        vpnRoutingNft
        MTU
        ;
    };
  });

  init_script = pkgs.writeShellScript "sing-box-init" (evalAndSubstitute {
    string = builtins.readFile ../../../stuff/system/sing-box/sing-box-init.sh;
    scope = {
      inherit
        setup_script
        CREDENTIAL_DIR
        build-config-py
        sing-box-config-file
        ;
    };
  });

  stop_script = pkgs.writeShellScript "sing-box-stop" "${cleanup_script}";

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
      pkgs.nftables
    ];
    sing-box.processes_to_proxy = processes;

    boot.kernel.sysctl = {
      "net.ipv6.conf.all.forwarding" = 1;
      "net.ipv4.ping_group_range" = "0 2147483647";
      "net.ipv4.ip_forward" = 1;
    };

    systemd.services = {
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
          ExecStart = "/run/current-system/sw/bin/sing-box-watcher";
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
          interface = [
            "lo"
            "veth_host"
            "tun-sb"
          ];
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
