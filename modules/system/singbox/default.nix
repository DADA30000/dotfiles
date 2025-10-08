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

  config = mkIf (cfg.enable && builtins.pathExists ../../../stuff/singbox/config.json) {
    systemd.services.singbox = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.sing-box}/bin/sing-box -c /config.json run";
      };
    };
    services.resolved = {
      enable = true;
      extraConfig = ''
        [Resolve]
        DNSStubListenerExtra=127.0.0.1
      '';
    };
  };
}
