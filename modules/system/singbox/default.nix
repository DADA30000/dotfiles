{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:
with lib;
let
  sing-box = pkgs.sing-box.overrideAttrs {
    vendorHash = null;
    src = inputs.singbox;
    tags = [
      "with_quic"
      "with_dhcp"
      "with_wireguard"
      "with_utls"
      "with_acme"
      "with_clash_api"
      "with_gvisor"
      "d"
    ];
  };
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
        ExecStart = "${sing-box}/bin/sing-box -c /config.json run";
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
