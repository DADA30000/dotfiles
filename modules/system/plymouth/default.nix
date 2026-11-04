{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.plymouth;
in
{
  options.plymouth = {
    enable = mkEnableOption "plymouth";
    simpledrm = mkEnableOption "simpledrm";
  };

  config = mkIf cfg.enable {
    boot = {
      plymouth = {
        enable = true;
        theme = "logo";
        themePackages = [ (pkgs.callPackage ./logo.nix { }) ];
      };
      kernelParams = [
        "quiet"
      ]
      ++ (lib.optionals cfg.simpledrm [
        "plymouth.use-simpledrm"
      ]);
    };
  };
}
