{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my-services;

  genSingBoxSubNginxConf = pkgs.writeShellScript "gen-sing-box-sub-nginx-conf" ''
    set -euo pipefail
    part_file="/etc/credstore/private_url.part"
    out_file="/run/nginx/sing-box-sub.conf"
    mkdir -p /run/nginx
    if [ -f "$part_file" ]; then
      raw="$(${pkgs.gnugrep}/bin/grep -vE '^[[:space:]]*(#|$)' "$part_file" | ${pkgs.coreutils}/bin/head -n 1 | ${pkgs.coreutils}/bin/tr -d '\r\n' | ${pkgs.gnused}/bin/sed -E 's/^[[:space:]\/]+|[[:space:]\/]+$//g')"
    else
      raw=""
    fi
    if [ -n "$raw" ] && printf '%s' "$raw" | ${pkgs.gnugrep}/bin/grep -qE '^[A-Za-z0-9._/-]+$' && ! printf '%s' "$raw" | ${pkgs.gnugrep}/bin/grep -q '\.\.'; then
      cat > "$out_file.tmp" <<EOF
location = /$raw {
  alias ${config.sing-box.subscription.outputPath};
  default_type application/json;
  add_header Cache-Control "no-store" always;
  add_header Profile-Title "sing-box" always;
  add_header Profile-Update-Interval "24" always;
}
EOF
    else
      printf '# /etc/credstore/private_url.part missing or invalid; subscription route disabled\n' > "$out_file.tmp"
    fi
    ${pkgs.coreutils}/bin/chown root:nginx "$out_file.tmp"
    ${pkgs.coreutils}/bin/chmod 0640 "$out_file.tmp"
    ${pkgs.coreutils}/bin/mv -f "$out_file.tmp" "$out_file"
  '';

  corsHeaders = ''
    add_header 'Access-Control-Allow-Origin' '*' always;
    add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
    add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range' always;
    add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range' always;
  '';

  shared-config = {
    forceSSL = true;
    enableACME = true;
    root = "/website";
    locations = {
      "/" = {
        extraConfig = ''
          ${corsHeaders}
          if ($request_method = 'OPTIONS') {
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
          }
        '';
      };
      "/.theme/" = {
        alias = "/website/index-theme/";
      };
      "/index/" = {
        alias = "/website/index/";
        extraConfig = ''
          add_before_body /.theme/theme.html;
          autoindex on;
          autoindex_exact_size off;
        '';
      };
    };
  };

in
{
  options.my-services = {
    cloudflare-ddns.enable = lib.mkEnableOption "automatic Cloudflare DDNS";
    nginx = {
      enable = lib.mkEnableOption "nginx";
      website.enable = lib.mkEnableOption "my goofy website";
      cape.enable = lib.mkEnableOption "integration with CAPEv2 sandbox";
      sub.enable = lib.mkEnableOption "serve SFA sing-box subscription on sub.<hostName>";
      hostName = lib.mkOption {
        type = lib.types.str;
        default = "sanic.space";
        example = "mybio.space";
        description = "Website domain";
      };
    };
  };

  config = lib.mkIf cfg.nginx.enable {
    security.acme.acceptTerms = true;

    sing-box.subscription.enable = lib.mkIf cfg.nginx.sub.enable (lib.mkDefault true);

    # Ensure stream and subscription directories exist so Nginx mount namespace never fails
    systemd.tmpfiles.rules = [
      "d /website/stream/hls 0750 nginx nginx -"
      "d /website/stream/dash 0750 nginx nginx -"
    ] ++ lib.optional cfg.nginx.sub.enable "d /run/sing-box-sub 0750 root nginx -";

    services.nginx = {
      enable = true;
      package = pkgs.nginx.override {
        modules = [ pkgs.nginxModules.rtmp ];
      };

      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;
      recommendedBrotliSettings = true;

      virtualHosts = lib.mkMerge [
        (lib.mkIf cfg.nginx.website.enable {
          "${cfg.nginx.hostName}" = shared-config;
          "ip.${cfg.nginx.hostName}" = shared-config;
        })
        (lib.mkIf cfg.nginx.cape.enable {
          "cape.${cfg.nginx.hostName}" = {
            forceSSL = true;
            enableACME = true;
            locations = {
              "/guac/" = {
                proxyPass = "http://127.0.0.1:8008";
                proxyWebsockets = true;
                recommendedProxySettings = true;
              };
              "/" = {
                proxyPass = "http://127.0.0.1:8000";
                proxyWebsockets = true;
                recommendedProxySettings = true;
              };
            };
          };
        })
        (lib.mkIf cfg.nginx.sub.enable {
          "sub.${cfg.nginx.hostName}" = {
            forceSSL = true;
            enableACME = true;
            extraConfig = ''
              include /run/nginx/sing-box-sub.conf;
            '';
            locations."/".return = "404";
          };
        })
      ];

      appendConfig = builtins.readFile ../../../stuff/system/my-services/nginx-rtmp.conf;
    };

    systemd = {
      services = {
        nginx.serviceConfig = {
          ReadWritePaths = [ "/website/stream" ];
          ExecStartPre = lib.mkIf cfg.nginx.sub.enable (lib.mkBefore [ "+${genSingBoxSubNginxConf}" ]);
          ExecReload = lib.mkIf cfg.nginx.sub.enable (lib.mkBefore [ "+${genSingBoxSubNginxConf}" ]);
        };
        cloudflare-ddns = lib.mkIf cfg.cloudflare-ddns.enable {
          description = "Update Cloudflare DDNS Records";
          path = with pkgs; [
            coreutils
            findutils
            gnused
          ];
          serviceConfig = {
            Type = "oneshot";
            DynamicUser = true;
            BindReadOnlyPaths = [ "/etc/credstore/cloudflare-ddns:/run/cloudflare-ddns" ];
            ExecStart = "/run/current-system/sw/bin/update-cloudflare-dns /run/cloudflare-ddns";

            NoNewPrivileges = true;
            CapabilityBoundingSet = "";
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            PrivateDevices = true;
            DevicePolicy = "closed";
            PrivateIPC = true;
            ProtectClock = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectControlGroups = true;
            ProtectProc = "invisible";
            ProcSubset = "pid";
            LockPersonality = true;
            MemoryDenyWriteExecute = true;
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            KeyringMode = "private";
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
            ];
            InaccessiblePaths = [
              "-/run/dbus/system_bus_socket"
              "-/run/systemd/private"
            ];
            SystemCallArchitectures = "native";
            SystemCallErrorNumber = "EPERM";
            SystemCallFilter = [
              "@system-service"
              "~@privileged"
              "~@resources"
            ];
            UMask = "0077";
          };
        };
      };

      timers = lib.mkIf cfg.cloudflare-ddns.enable {
        cloudflare-ddns = {
          description = "Timer for periodically updating Cloudflare DDNS";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "5min";
            OnUnitActiveSec = "1hour";
          };
        };
      };
    };
  };
}
