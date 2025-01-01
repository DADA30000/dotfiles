{ config, lib, pkgs, inputs, ... }:
with lib;
let
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.system};
  #hazy = pkgs.fetchgit {
  #  url = "https://github.com/Astromations/Hazy";
  #  rev = "25e472cc4563918d794190e72cba6af8397d3a78";
  #  sha256 = "sha256-zK17CWwYJNSyo5pbYdIDUMKyeqKkFbtghFoK9JBR/C8=";
  #};
  cfg = config.spicetify;
in
{
  options.spicetify = {
    enable = mkEnableOption "Enable spotify with theme";
  };
  

  imports = [ inputs.spicetify-nix.nixosModules.default ];
  config = mkIf cfg.enable {
    programs.spicetify = {
      enable = true;
      enabledExtensions = with spicePkgs.extensions; [
        adblock
        hidePodcasts
        shuffle
      ];
      theme = spicePkgs.themes.hazy;
    };
  };
}
