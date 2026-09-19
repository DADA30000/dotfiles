{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my-services;

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

    # Ensure stream directories exist so Nginx mount namespace never fails
    systemd.tmpfiles.rules = [
      "d /website/stream/hls 0750 nginx nginx -"
      "d /website/stream/dash 0750 nginx nginx -"
    ];

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
        nginx.serviceConfig.ReadWritePaths = [ "/website/stream" ];
        cloudflare-ddns = lib.mkIf cfg.cloudflare-ddns.enable {
          description = "Update Cloudflare DDNS Records";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "/run/current-system/sw/bin/update-cloudflare-dns /etc/credstore/cloudflare-ddns";
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
