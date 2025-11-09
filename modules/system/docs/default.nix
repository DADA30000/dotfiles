{
  lib,
  ...
}:
with lib;
{
  options.docs = {
    man-cache-home = mkOption { 
      type = types.str;
      visible = false;
    };
    man-cache-nix = mkOption {
      type = types.str; 
      visible = false;
    };
    hm-html = mkOption {
      type = types.str;
      visible = false;
    };
    hm-man = mkOption {
      type = types.str;
      visible = false;
    };
    enable = mkEnableOption "Enable docs generation (manpage, html)";
    nos = {
      enable = mkEnableOption "Enable nix-option-search";
      darwin = mkEnableOption "Render docs for nix-darwin? (Increases eval time)";
      stable = mkEnableOption "Render docs for stable nixpkgs? (Increases eval time)";
    };
  };

  imports = [
    ./builder.nix
    ./tools.nix
  ];
}
