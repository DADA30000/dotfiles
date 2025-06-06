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
    ];
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
      services.resolved = {
        enable = true;
        extraConfig = ''
          [Resolve]
          DNSStubListenerExtra=127.0.0.1
        '';
      };
    })
  ];
}
