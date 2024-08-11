{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.anicli-ru;
in
{
  options.anicli-ru = {
    enable = mkEnableOption "Enable russian anicli";
  };
  


  config = mkIf cfg.enable {
    environment.systemPackages = [ (pkgs.callPackage ./anicli-ru.nix { }) ];
  };
}
