{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib;
let
  hm-manual = inputs.home-manager.packages.${pkgs.stdenv.hostPlatform.system}.docs-html;
  darwin-manual = inputs.nix-darwin.packages.${pkgs.stdenv.hostPlatform.system}.manualHTML;
  stable-manual =
    (inputs.nixpkgs-stable.lib.nixosSystem {
      modules = [ { nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux"; } ];
    }).config.system.build.manual.manualHTML;
  nos_unwrapped = (
    (pkgs.callPackage "${inputs.nos}/default.nix" {
      inherit pkgs;
      gitignoreSrc = {
        gitignoreSource = (x: x);
      };
    }).overrideAttrs
      {
        patches = [ ../../../stuff/nos.patch ];
      }
  );
  nos-cache = pkgs.runCommand "kekma" { } ''
    mkdir -p $out
    echo 'NOX_HTML_Nix_Darwin="${darwin-manual}/share/doc/darwin/index.html" NOX_HTML_NixOS="${stable-manual}/share/doc/nixos/options.html" NOX_HTML_NixOS_Unstable="${config.system.build.manual.manualHTML}/share/doc/nixos/options.html" NOX_HTML_Home_Manager="${hm-manual}/share/doc/home-manager/options.html" NOX_HTML_Home_Manager_NixOS="${hm-manual}/share/doc/home-manager/nixos-options.html" NOX_HTML_Home_Manager_Nix_Darwin="${hm-manual}/share/doc/home-manager/nix-darwin-options.html" NOX_PREFETCH_CACHE_PATH=$out ${nos_unwrapped}/bin/nox'
  '';
  nos = pkgs.writeShellScriptBin "nos" ''
    NIX_OPTIONS_SEARCH_CACHE=${nos-cache} ${nos_unwrapped}/bin/nox
  '';
  cfg = config.nos;
in
{
  options.nos = {
    enable = mkEnableOption "Enable nix-option-search";
  };

  config = mkIf cfg.enable {
    #documentation.nixos.includeAllModules = true;
    environment.systemPackages = [ nos ];
  };
}
