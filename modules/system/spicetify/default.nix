{ config, lib, pkgs, inputs, ... }:
with lib;
let
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.system};
  hazy = pkgs.fetchgit {
    url = "https://github.com/Astromations/Hazy";
    rev = "413748dd7048857f5b4a1c013e945c10818e1169";
    sha256 = "sha256-d+TqbigGjEfjk4KUNAkIHlczUG9ELvVADUVrFhoGmv0=";
  };
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
      theme = {
        name = "Hazy";
        src = hazy;
        injectCss = true;
        injectThemeJs = true;
        replaceColors = true;
        homeConfig = true;
        overwriteAssets = true;
        additonalCss = ''
          :root {
            background: none;
            background-color: transparent;
          }
          .Root {
            background: none;
            background-color: transparent;
          }
          .Root__top-container::before {
            background: none;
            background-color: transparent;
          }
        '';
        requiredExtensions = [
          {
            name = "hazy.js";
            src = "${hazy}";
          }
        ];
      };
    };
  };
}
