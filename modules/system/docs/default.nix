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
  cfg = config.docs;
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
        specialArgs = { inherit inputs; osConfig = config; }; # osConfig might cause trouble !ATTENTION
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

  nix-man =
    (pkgs.runCommand "fixup manual"
      { manual = config.system.build.manual.nixos-configuration-reference-manpage; }
      ''
        mkdir -p $out
        ${pkgs.rsync}/bin/rsync -av $manual/* $out --exclude nix-support
      ''
    ).overrideAttrs
      { __contentAddressed = true; };

  nix-html =
    (pkgs.runCommand "fixup html" { manual = config.system.build.manual.manualHTML; } ''
      mkdir -p $out
      ${pkgs.rsync}/bin/rsync -av $manual/* $out --exclude nix-support
    '').overrideAttrs
      { __contentAddressed = true; };

  darwin-manual = inputs.nix-darwin.packages.${pkgs.stdenv.hostPlatform.system}.manualHTML;
  stable-manual =
    (inputs.nixpkgs-stable.lib.nixosSystem {
      modules = [ { nixpkgs.hostPlatform = lib.mkDefault pkgs.stdenv.hostPlatform.system; } ];
    }).config.system.build.manual.manualHTML;

  nos_unwrapped =
    (pkgs.callPackage "${inputs.nos}/default.nix" {
      inherit pkgs;
      gitignoreSrc = {
        gitignoreSource = (x: x);
      };
    }).overrideAttrs
      { patches = [ ../../../stuff/nos.patch ]; };

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

  nos-config = (pkgs.formats.toml { }).generate "nos-config" {
    use_cache = true;
    prewarm_cache = true;
    auto_refresh_cache = false;
    cache_dir = "leave_blank";
    cache_duration = "1week";
    enable_logging = true;
    log_level = "error";
    log_file = "/tmp/nos/nos.log";
    sources = [
      {
        name = "NixOS Unstable";
        url = "file://${nix-html}/share/doc/nixos/options.html";
        version_url = "file://${nix-html}/share/doc/nixos/index.html";
      }
      {
        name = "Home Manager";
        url = "file://${hm-html}/share/doc/home-manager/options.xhtml";
        version_url = "file://${hm-html}/share/doc/home-manager/index.xhtml";
      }
      {
        name = "Home Manager NixOS";
        url = "file://${hm-html}/share/doc/home-manager/nixos-options.xhtml";
        version_url = "file://${hm-html}/share/doc/home-manager/index.xhtml";
      }
      {
        name = "Home Manager Nix-Darwin";
        url = "file://${hm-html}/share/doc/home-manager/nix-darwin-options.xhtml";
        version_url = "file://${hm-html}/share/doc/home-manager/index.xhtml";
      }
      {
        name = "Nix Built-ins";
        url = "file://${pkgs.nix.doc}/share/doc/nix/manual/language/builtins.html";
      }
    ]
    ++ lib.optionals cfg.nos.darwin [
      {
        name = "Nix-Darwin";
        url = "file://${darwin-manual}/share/doc/darwin/index.html";
      }
    ]
    ++ lib.optionals cfg.nos.stable [
      {
        name = "NixOS";
        url = "file://${stable-manual}/share/doc/nixos/options.html";
        version_url = "file://${stable-manual}/share/doc/nixos/index.html";
      }
    ];
  };

  nos-cache =
    (pkgs.runCommand "nos-cache" { } ''
      mkdir -p $out/cache
      cp --no-preserve=mode "${nos-config}" "$out/config.toml"
      ${pkgs.gnused}/bin/sed -i "s%cache_dir = \"leave_blank\"%cache_dir = \"$out/cache\"%" "$out/config.toml"
      ${nos_unwrapped}/bin/nox -c "$out/config.toml"
      ${pkgs.gnused}/bin/sed -i 's/prewarm_cache = true/prewarm_cache = false/' "$out/config.toml"
    '').overrideAttrs
      { __contentAddressed = true; };

  nos = pkgs.writeShellScriptBin "nos" ''
    ${nos_unwrapped}/bin/nox -c "${nos-cache}/config.toml" "$@"
  '';
in
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
    enable = mkEnableOption "docs generation (manpage, html)";
    nos = {
      enable = mkEnableOption "nix-option-search";
      darwin = mkEnableOption "Render docs for nix-darwin? (Increases eval time)";
      stable = mkEnableOption "Render docs for stable nixpkgs? (Increases eval time)";
    };
  };

  config = mkIf cfg.enable (mkMerge [
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
      environment.systemPackages =
        optionals cfg.enable [
          man-nix
          man-home
        ]
        ++ optionals (cfg.enable && cfg.nos.enable) [ nos ];
    }
  ]);
}
