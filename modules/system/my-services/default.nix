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
          "ip.${cfg.nginx.hostName}" = {
            forceSSL = true;
            enableACME = true;
            root = "/website";
            extraConfig = ''
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
        })
      ];
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
      ];
    }; 
    services.cron = mkIf cfg.cloudflare-ddns.enable {
      enable = true;
      systemCronJobs = [
        "*/59 * * * *   root  update-cloudflare-dns /cloudflare1.conf"
      ];
    };
  };
}
