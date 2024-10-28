{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.my-services;
in
{
  options.my-services = {
    cloudflare-ddns.enable = mkEnableOption "Enable automatic Cloudflare DDNS";
    nginx = {
      enable = mkEnableOption "Enable nginx";
      website.enable = mkEnableOption "Enable my goofy website";
      nextcloud.enable = mkEnableOption "Enable nextcloud";
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
    systemd.services.nginx.serviceConfig.ReadWritePaths = [ "/website/stream" ];
    services.nginx = {
     enable = true;
     virtualHosts = mkMerge [
       (mkIf cfg.nginx.nextcloud.enable {
         ${config.services.nextcloud.hostName} = {
           forceSSL = true;
           enableACME = true;
         };
       })
       (mkIf cfg.nginx.website.enable {
         "${cfg.nginx.hostName}" = {
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
    #     "ip.${cfg.nginx.hostName}" = {
    #       forceSSL = true;
    #       enableACME = true;
    #       root = "/website";
    #       extraConfig = ''
    #         location / {
    #           if ($request_method = 'OPTIONS') {
    #              add_header 'Access-Control-Allow-Origin' '*';
    #              add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
    #              add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
    #              add_header 'Access-Control-Max-Age' 1728000;
    #              add_header 'Content-Type' 'text/plain; charset=utf-8';
    #              add_header 'Content-Length' 0;
    #              return 204;
    #           }
    #           if ($request_method = 'POST') {
    #              add_header 'Access-Control-Allow-Origin' '*' always;
    #              add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
    #              add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range' always;
    #              add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range' always;
    #           }
    #           if ($request_method = 'GET') {
    #              add_header 'Access-Control-Allow-Origin' '*' always;
    #              add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
    #              add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range' always;
    #              add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range' always;
    #           }
    #         }
    #         location /index/ {
    #           alias /website/index/;
    #           sub_filter_once off;
    #   	sub_filter '/.theme' '/index/.theme';
    #           add_before_body /index/.theme/theme.html;
    #   	autoindex_exact_size off;
    #           autoindex on;
    #         }
    #       '';
    #     };
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
          #"ip.${cfg.nginx.hostName}".email = "vadimhack.ru@gmail.com";
        })
      ];
    }; 
    services.cron = mkIf cfg.cloudflare-ddns.enable {
      enable = true;
      systemCronJobs = [
        "*/59 * * * *   root  update-cloudflare-dns /cloudflare1.conf"
	"*/59 * * * *   root  update-cloudflare-dns /cloudflare2.conf"
      ];
    };
    environment.systemPackages = mkIf cfg.cloudflare-ddns.enable [ pkgs.busybox ];
  };
}
