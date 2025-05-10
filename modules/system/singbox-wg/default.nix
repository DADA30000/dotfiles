{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  sing-box = pkgs.sing-box.overrideAttrs {
    vendorHash = "sha256-mS2b52uKbYkv8g5bfrNSyPre/OaKwovhZBC0Abc+Nes=";
    src = pkgs.fetchFromGitHub {
      owner = "SagerNet";
      repo = "sing-box";
      rev = "v1.12.0-alpha.21";
      hash = "sha256-dsgNe6X446KoAWh1vKPGgqdDwg8N76tT/3Hf752vMsY=";
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
