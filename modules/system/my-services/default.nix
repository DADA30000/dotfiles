{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.my-services;

  shared-config = {
    forceSSL = true;
    enableACME = true;
    root = "/website";
    extraConfig = ''
      location / {
        if ($request_method = 'OPTIONS') {
           add_header 'Access-Control-Allow-Origin' '*';
           add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
           add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
           add_header 'Access-Control-Max-Age' 1728000;
           add_header 'Content-Type' 'text/plain; charset=utf-8';
           add_header 'Content-Length' 0;
           return 204;
        }
        if ($request_method = 'POST') {
           add_header 'Access-Control-Allow-Origin' '*' always;
           add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
           add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range' always;
           add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range' always;
        }
        if ($request_method = 'GET') {
           add_header 'Access-Control-Allow-Origin' '*' always;
           add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
           add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range' always;
           add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range' always;
        }
      }
      location /index/ {
        alias /website/index/;
        sub_filter_once off;
        sub_filter '/.theme' '/index/.theme';
        add_before_body /index/.theme/theme.html;
        autoindex_exact_size off;
        autoindex on;
      }
    '';
  };

  # Dynamically list only active domains to prevent empty ghost units
  activeDomains =
    (lib.optionals cfg.nginx.website.enable [
      cfg.nginx.hostName
      "ip.${cfg.nginx.hostName}"
    ])
    ++ (lib.optional cfg.nginx.cape.enable "cape.${cfg.nginx.hostName}")
    ++ (lib.optional cfg.nginx.nextcloud.enable "nc.${cfg.nginx.hostName}");
in
{
  options.my-services = {
    cloudflare-ddns.enable = mkEnableOption "automatic Cloudflare DDNS";
    nginx = {
      enable = mkEnableOption "nginx";
      website.enable = mkEnableOption "my goofy website";
      nextcloud.enable = mkEnableOption "nextcloud";
      cape.enable = mkEnableOption "integration with CAPEv2 sandbox";
      hostName = mkOption {
        type = types.str;
        default = "sanic.space";
        example = "mybio.space";
        description = "Website domain";
      };
    };
  };

  config = mkIf cfg.nginx.enable {
    security.acme.acceptTerms = true;

    # Ensure stream directories exist so Nginx mount namespace never fails
    systemd.tmpfiles.rules = [
      "d /website/stream/hls 0750 nginx nginx -"
      "d /website/stream/dash 0750 nginx nginx -"
    ];

    services.nextcloud = mkIf cfg.nginx.nextcloud.enable {
      enable = true;
      configureRedis = true;
      config.adminpassFile = "/password";
      https = true;
      hostName = "nc.${cfg.nginx.hostName}";
      package = pkgs.nextcloud29;
    };

    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      virtualHosts = mkMerge [
        (mkIf cfg.nginx.nextcloud.enable {
          ${config.services.nextcloud.hostName} = {
            forceSSL = true;
            enableACME = true;
          };
        })
        (mkIf cfg.nginx.website.enable {
          "${cfg.nginx.hostName}" = shared-config;
          "ip.${cfg.nginx.hostName}" = shared-config;
        })
        (mkIf cfg.nginx.cape.enable {
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
      ];
      appendConfig = ''
        rtmp {
          server {
            listen 1935;
            chunk_size 4096;
            allow publish 127.0.0.1;
            deny publish all;
            application live {
              live on;
              record off;
              hls on;
              hls_path /website/stream/hls;
              hls_fragment 3;
              hls_playlist_length 60;
              dash on;
              dash_path /website/stream/dash;
            }
          }
        }
      '';
    };

    systemd = {
      services = {
        # Cloudflare DDNS runs only when network is online
        cloudflare-ddns = mkIf cfg.cloudflare-ddns.enable {
          description = "Update Cloudflare DDNS Records";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "/run/current-system/sw/bin/update-cloudflare-dns /etc/credstore/cloudflare-ddns";
          };
        };

        # 1. Prevent root setup from running at boot
        acme-setup.wantedBy = lib.mkForce [ ];

        # 2. Nginx autostarts ONLY after user 1000 logs in via greetd
        nginx = {
          wantedBy = lib.mkForce [ "user@1000.service" ];
          wants = [ "network-online.target" ];
          after = [
            "user@1000.service"
            "network-online.target"
          ];
          serviceConfig.ReadWritePaths = [ "/website/stream" ];
        };
      }
      // lib.listToAttrs (
        lib.concatMap (domain: [
          # 3. Local cert verify service (runs when Nginx starts, takes ~40ms),
          #    and does NOT trigger lego network renewals
          {
            name = "acme-${domain}";
            value = {
              wantedBy = lib.mkForce [ ];
              before = lib.mkForce [ ];
              wants = lib.mkForce [ "acme-setup.service" ];
            };
          }
          # 4. Lego renewal service is completely decoupled from boot and login
          {
            name = "acme-order-renew-${domain}";
            value = {
              wantedBy = lib.mkForce [ ];
              after = [ "network-online.target" ];
            };
          }
        ]) activeDomains
      );

      timers =
        (mkIf cfg.cloudflare-ddns.enable {
          cloudflare-ddns = {
            description = "Timer for periodically updating Cloudflare DDNS";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnBootSec = "5min";
              OnUnitActiveSec = "1hour";
            };
          };
        })
        // lib.listToAttrs (
          map (domain: {
            # 5. Prevent timers from running catch-up renewals on boot and delay initial tick
            name = "acme-renew-${domain}";
            value = {
              timerConfig = {
                Persistent = lib.mkForce false;
                OnBootSec = "1h";
              };
            };
          }) activeDomains
        );
    };
  };
}
