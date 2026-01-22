{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.singbox;
in
{
  options.singbox = {
    enable = mkEnableOption "Enable singbox";
  };

  config = mkIf cfg.enable {
    systemd.services.singbox = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.sing-box}/bin/sing-box -c /config.json run";
      };
    };
    #services.resolved = {
    #  enable = true;
    #  settings.Resolve.DNSStubListenerExtra = "127.0.0.1";
    #};
    services = {
      resolved.enable = false;
      dnsmasq = {
        enable = true;
        resolveLocalQueries = false;
        settings = {
          port = 5353;
          server = [ "1.1.1.1" ];
          cache-size = 10000;
          interface = "lo";
          bind-interfaces = true;
        };
      };
    };
    networking = {
      nameservers = [ "198.18.0.55" ];
      networkmanager.dns = "none";
    };
  };
}
