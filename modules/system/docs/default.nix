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
let
  cfg = config.docs;
  standardBuildOptionsDocs =
    args@{ modules, ... }:
    let
      poisonModule =
        { options, ... }:
        {
          config = lib.listToAttrs (
            map (n: {
              name = n;
              value = abort "documentation depends on config";
            }) (lib.filter (n: n != "_module") (lib.attrNames options))
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
        options = removeAttrs evaled.options [ "_module" ];
        transformOptions = opt: opt;
      }
      // removeAttrs args [ "modules" ]
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
        specialArgs = {
          inherit inputs;
          osConfig = config;
        }; # osConfig might cause trouble !ATTENTION
      };
      prefixesToStrip = map (p: "${toString p}/") [ inputs.self ];
      stripAnyPrefixes = lib.flip (lib.foldr lib.removePrefix) prefixesToStrip;
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
      // removeAttrs args [ "modules" ]
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
    pkgs.runCommand "hm-custom-manpage"
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
      '';

  hm-html =
    (pkgs.callPackage "${inputs.home-manager}/docs/home-manager-manual.nix" {
      inherit revision;
      home-manager-options = {
        home-manager = {
          json = customHmOptionsDocs.optionsJSON;
        };
        nixos = {
          json = nixosOptionsDocs.optionsJSON;
        };
        nix-darwin = {
          json = nixDarwinOptionsDocs.optionsJSON;
        };
      };
    }).overrideAttrs
      {
        fixupPhase = ''
          ${pkgs.coreutils-full}/bin/rm -rf $out/nix-support/hydra-build-products
        '';
      };

  hm-html-opener = pkgs.callPackage "${inputs.home-manager}/docs/html-open-tool.nix" { } {
    html = hm-html;
  };

  nix-man =
    pkgs.runCommand "fixup manual"
      { manual = config.system.build.manual.nixos-configuration-reference-manpage; }
      ''
        mkdir -p $out
        ${pkgs.rsync}/bin/rsync -av $manual/* $out --exclude nix-support
      '';

  man-cache =
    pkgs.runCommand "generate-man-cache"
      {
        MAN_NIX = "${nix-man}/share/man/man5/configuration.nix.5.gz";
        MAN_HOME = "${hm-manpage}/share/man/man5/home-configuration.nix.5";
      }
      ''
        mkdir -p $out
        MANPAGER=cat ${pkgs.util-linux}/bin/script -q -c "${pkgs.man-db}/bin/man $MAN_NIX" /dev/null > $out/configuration.nix.cache
        MANPAGER=cat ${pkgs.util-linux}/bin/script -q -c "${pkgs.man-db}/bin/man $MAN_HOME" /dev/null > $out/home-configuration.nix.cache
      '';

  man-nix = pkgs.writeShellScriptBin "man-nix" "nvim -c 'silent! e +Man! ${man-cache}/configuration.nix.cache' ";
  man-home = pkgs.writeShellScriptBin "man-home" "nvim -c 'silent! e +Man! ${man-cache}/home-configuration.nix.cache' ";
in
{
  options.docs = {
    man-cache-home = lib.mkOption {
      type = lib.types.str;
      visible = false;
    };
    man-cache-nix = lib.mkOption {
      type = lib.types.str;
      visible = false;
    };
    hm-html = lib.mkOption {
      type = lib.types.str;
      visible = false;
    };
    hm-man = lib.mkOption {
      type = lib.types.str;
      visible = false;
    };
    enable = lib.mkEnableOption "docs generation (manpage, html)";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        documentation.nixos = {
          enable = true;
          includeAllModules = true;
          extraModules = map (x: builtins.toPath x) system-modules;
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
      }
      {
        docs = {
          man-cache-home = "${man-cache}/home-configuration.nix.cache";
          man-cache-nix = "${man-cache}/configuration.nix.cache";
        };
        environment.systemPackages = lib.mkIf cfg.enable [
          man-nix
          man-home
          pkgs.nixos-render-docs
        ];
      }
    ]
  );
}
