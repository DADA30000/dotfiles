{
  config,
  lib,
  pkgs,
  inputs,
  user,
  system-modules,
  home-modules,
  ...
}:
with lib;
let
  standardBuildOptionsDocs =
    args@{ modules, ... }:
    let
      poisonModule =
        { options, ... }:
        {
          config = listToAttrs (
            map (n: {
              name = n;
              value = abort "documentation depends on config";
            }) (filter (n: n != "_module") (attrNames options))
          );
        };
      evaled = lib.evalModules {
        modules = modules ++ [
          poisonModule
          { _module.check = false; }
        ];
        class = "homeManager";
        specialArgs = { inherit pkgs lib; };
      };
    in
    pkgs.buildPackages.nixosOptionsDoc (
      {
        options = builtins.removeAttrs evaled.options [ "_module" ];
        transformOptions = opt: opt;
      }
      // builtins.removeAttrs args [ "modules" ]
    );
  lib-hm = (import "${inputs.home-manager}/modules/lib/stdlib-extended.nix" lib).extend (
    _: _: { mkDoc = s: s; }
  );
  baseModules = import "${inputs.home-manager}/modules/modules.nix" {
    inherit pkgs;
    lib = lib-hm;
    check = false;
  };
  revision = inputs.home-manager.rev;
  userModules = home-modules;
  allModules = baseModules ++ userModules;
  customBuildOptionsDocs =
    args@{ modules, ... }:
    let
      evaled = lib-hm.evalModules {
        modules = modules ++ [
          {
            config = {
              home.stateVersion = config.home-manager.users.${user}.home.stateVersion;
            };
          }
        ];
        class = "homeManager";
        specialArgs = { inherit inputs; };
      };
      prefixesToStrip = map (p: "${toString p}/") [ inputs.self ];
      stripAnyPrefixes = flip (foldr removePrefix) prefixesToStrip;
    in
    pkgs.buildPackages.nixosOptionsDoc (
      {
        options = evaled.options;
        transformOptions =
          opt:
          opt
          // {
            declarations = map stripAnyPrefixes opt.declarations;
          };
        warningsAreErrors = false;
      }
      // builtins.removeAttrs args [ "modules" ]
    );

  customHmOptionsDocs = customBuildOptionsDocs {
    modules = allModules;
    variablelistId = "home-manager-options";
  };
  nixosOptionsDocs = standardBuildOptionsDocs {
    modules = [ "${inputs.home-manager}/nixos" ];
    variablelistId = "nixos-options";
    optionIdPrefix = "nixos-opt-";
  };
  nixDarwinOptionsDocs = standardBuildOptionsDocs {
    modules = [ "${inputs.home-manager}/nix-darwin" ];
    variablelistId = "nix-darwin-options";
    optionIdPrefix = "nix-darwin-opt-";
  };

  hm-manpage =
    (pkgs.runCommand "hm-custom-manpage"
      {
        nativeBuildInputs = [ pkgs.nixos-render-docs ];
        inherit revision;
      }
      ''
        mkdir -p $out/share/man/man5
        ${pkgs.nixos-render-docs}/bin/nixos-render-docs -j $NIX_BUILD_CORES options manpage \
          --revision $revision --header ${inputs.home-manager}/docs/home-configuration-nix-header.5 \
          --footer ${inputs.home-manager}/docs/home-configuration-nix-footer.5 \
          ${customHmOptionsDocs.optionsJSON}/share/doc/nixos/options.json \
          $out/share/man/man5/home-configuration.nix.5
        rm -rf $out/nix-support
      ''
    ).overrideAttrs
      { __contentAddressed = true; };

  hm-html =
    (pkgs.callPackage "${inputs.home-manager}/docs/home-manager-manual.nix" {
      inherit revision;
      home-manager-options = {
        home-manager = customHmOptionsDocs.optionsJSON;
        nixos = nixosOptionsDocs.optionsJSON;
        nix-darwin = nixDarwinOptionsDocs.optionsJSON;
      };
    }).overrideAttrs
      {
        __contentAddressed = true;
        fixupPhase = ''
          ${pkgs.coreutils-full}/bin/rm -rf $out/nix-support/hydra-build-products
        '';
      };
  hm-html-opener = pkgs.callPackage "${inputs.home-manager}/docs/html-open-tool.nix" { } {
    html = hm-html;
  };
  cfg = config.docs;
in
{
  config = mkIf cfg.enable {
    documentation.nixos = {
      enable = true;
      includeAllModules = true;
      extraModules = builtins.map (x: builtins.toPath x) system-modules;
      options.warningsAreErrors = false;
      extraModuleSources = [ inputs.self ];
    };
    home-manager.users.${user}.manual.manpages.enable = false;
    environment.systemPackages = [
      hm-manpage
      hm-html-opener
      hm-html
    ];
    docs.hm-html = "${hm-html}";
    docs.hm-man = "${hm-manpage}";
  };
}
