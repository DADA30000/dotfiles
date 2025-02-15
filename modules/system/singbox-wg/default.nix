{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  sing-box = pkgs.sing-box.overrideAttrs {
    vendorHash = "sha256-nauD1ynX+sjtWTtgjBKob9thaeVfZAk4+g/JuCUbNOU=";
    src = pkgs.fetchFromGitHub {
      owner = "SagerNet";
      repo = "sing-box";
      rev = "v1.11.0-beta.3";
      hash = "sha256-9iqPqP4gmhjnkpEYCF/iNUnT1wRF9cRnEb8QbwnjsQI=";
    };
  };
  cfg = config.singbox-wg;
in
{
  options.singbox-wg = {
    enable = mkEnableOption "Enable singbox proxy to my VPS with WireGuard";
  };
  
  
  config = mkMerge [
  (mkIf (cfg.enable && !builtins.pathExists ../../../stuff/singbox/config.json) {
    warnings = [ "singbox-wg module: config.json doesn't exist, singbox-wg WON'T be enabled." ];
  })
  (mkIf (cfg.enable && builtins.pathExists ../../../stuff/singbox/config.json) {
    systemd.services.singbox = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${sing-box}/bin/sing-box -c ${../../../stuff/singbox/config.json} run";
      };
    };
    services = {
      resolved.enable = true;
      dnscrypt-proxy2 = {
        enable = true;
        settings = {
          server_names = [
            "cloudflare"
            "scaleway-fr"
            "google"
            "yandex"
          ];
          listen_addresses = [
            "127.0.0.1:53"
            "[::1]:53"
          ];
        };
      };
    };
    networking = {
      nameservers = [
        "::1"
        "127.0.0.1"
      ];
      resolvconf.dnsSingleRequest = true;
    };
  })];
}
