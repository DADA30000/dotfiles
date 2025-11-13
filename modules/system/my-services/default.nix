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
in
{
  options.my-services = {
    cloudflare-ddns.enable = mkEnableOption "Enable automatic Cloudflare DDNS";
    nginx = {
      enable = mkEnableOption "Enable nginx";
      website.enable = mkEnableOption "Enable my goofy website";
      nextcloud.enable = mkEnableOption "Enable nextcloud";
      cape.enable = mkEnableOption "Enable integration with CAPEv2 sandbox";
      hostName = mkOption {
        type = types.str;
        default = "sanic.space";
        example = "mybio.space";
        description = "Website domain";
      };
    };
  };

  config = mkIf cfg.nginx.enable {
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
    security.acme = {
      acceptTerms = true;
      defaults.email = "vadimhack.ru@gmail.com";
      certs = mkMerge [
        (mkIf cfg.nginx.nextcloud.enable {
          "${config.services.nextcloud.hostName}".email = "vadimhack.ru@gmail.com";
        })
        (mkIf cfg.nginx.website.enable {
          "${cfg.nginx.hostName}".email = "vadimhack.ru@gmail.com";
          "ip.${cfg.nginx.hostName}".email = "vadimhack.ru@gmail.com";
        })
        (mkIf cfg.nginx.cape.enable {
          "cape.${cfg.nginx.hostName}".email = "vadimhack.ru@gmail.com";
        })
      ];
    };
    systemd.services = {
      "acme-order-renew-ip.sanic.space" = {
        after = lib.mkForce [
          "graphical.target"
          "acme-setup.service"
          "acme-ip.sanic.space.service"
        ];
        wantedBy = lib.mkForce [ "graphical.target" ];
      };
      "acme-order-renew-sanic.space" = {
        after = lib.mkForce [
          "graphical.target"
          "acme-setup.service"
          "acme-ip.sanic.space.service"
        ];
        wantedBy = lib.mkForce [ "graphical.target" ];
      };
      "acme-order-renew-cape.sanic.space" = {
        after = lib.mkForce [
          "graphical.target"
          "acme-setup.service"
          "acme-ip.sanic.space.service"
        ];
        wantedBy = lib.mkForce [ "graphical.target" ];
      };
      "acme-ip.sanic.space" = {
        after = [ "graphical.target" ];
        before = lib.mkForce [ ];
        wantedBy = lib.mkForce [ "graphical.target" ];
      };
      "acme-cape.sanic.space" = {
        after = [ "graphical.target" ];
        before = lib.mkForce [ ];
        wantedBy = lib.mkForce [ "graphical.target" ];
      };
      "acme-sanic.space" = {
        after = [ "graphical.target" ];
        before = lib.mkForce [ ];
        wantedBy = lib.mkForce [ "graphical.target" ];
      };
      "nginx" = {
        wantedBy = lib.mkForce [ "graphical.target" ];
        serviceConfig.ReadWritePaths = [ "/website/stream" ];
        before = lib.mkForce [ ];
        after = lib.mkForce [ "graphical.target" ];
      };
      "nginx-config-reload".wantedBy = lib.mkForce [
        "acme-order-renew-ip.sanic.space.service"
        "acme-order-renew-sanic.space.service"
      ];
    };
    services.cron = mkIf cfg.cloudflare-ddns.enable {
      enable = true;
      systemCronJobs = [
        "*/59 * * * *   root  update-cloudflare-dns /cloudflare1.conf"
        "*/59 * * * *   root  update-cloudflare-dns /cloudflare2.conf"
      ];
    };
    environment.systemPackages =
      with pkgs;
      mkIf cfg.cloudflare-ddns.enable [
        net-tools
        dig.dnsutils
      ];
  };
}
