{ lib, config, ... }:
let
  cfg = config.wivrn;
in
with lib;
{
  options.wivrn = {
    enable = mkEnableOption "Enable WiVRn";
  };
  config = mkIf cfg.enable {
    services.wivrn = {
      enable = true;
      openFirewall = true;
      defaultRuntime = true;
      autoStart = true;
      # You should use the default configuration (which is no configuration), as that works the best out of the box.
      # However, if you need to configure something see https://github.com/WiVRn/WiVRn/blob/master/docs/configuration.md for configuration options and https://mynixos.com/nixpkgs/option/services.wivrn.config.json for an example configuration.
    };
  };
}
