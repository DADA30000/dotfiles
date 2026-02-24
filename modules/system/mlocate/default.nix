{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.mlocate;
in
{
  options.mlocate = {
    enable = mkEnableOption "mlocate (find files on system quickly)";
  };

  config = mkIf cfg.enable {
    services.locate = {
      enable = true;
      package = pkgs.mlocate;
      interval = "hourly";
      localuser = null;
    };
    environment.systemPackages = [ pkgs.mlocate ];
  };
}
