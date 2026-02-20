{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib;
let
  nix-man =
    (pkgs.runCommand "fixup manual"
      { manual = config.system.build.manual.nixos-configuration-reference-manpage; }
      ''
        mkdir -p $out
        ${pkgs.rsync}/bin/rsync -av $manual/* $out --exclude nix-support
      ''
    ).overrideAttrs
      {
        __contentAddressed = true;
      };
  nix-html =
    (pkgs.runCommand "fixup html" { manual = config.system.build.manual.manualHTML; } ''
      mkdir -p $out
      ${pkgs.rsync}/bin/rsync -av $manual/* $out --exclude nix-support
    '').overrideAttrs
      {
        __contentAddressed = true;
      };
  darwin-manual = inputs.nix-darwin.packages.${pkgs.stdenv.hostPlatform.system}.manualHTML;
  stable-manual =
    (inputs.nixpkgs-stable.lib.nixosSystem {
      modules = [ { nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux"; } ];
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
        MAN_HOME = "${config.docs.hm-man}/share/man/man5/home-configuration.nix.5";
      }
      ''
        mkdir -p $out
        MANPAGER=cat ${pkgs.util-linux}/bin/script -q -c "${pkgs.man-db}/bin/man $MAN_NIX" /dev/null > $out/configuration.nix.cache
        MANPAGER=cat ${pkgs.util-linux}/bin/script -q -c "${pkgs.man-db}/bin/man $MAN_HOME" /dev/null > $out/home-configuration.nix.cache
      '';
  man-nix = pkgs.writeShellScriptBin "man-nix" "nvim -c 'silent! e +Man! ${man-cache}/configuration.nix.cache' ";
  man-home = pkgs.writeShellScriptBin "man-home" "nvim -c 'silent! e +Man! ${man-cache}/home-configuration.nix.cache' ";

  nos-cache =
    (pkgs.runCommand "nos-cache" { } ''
      mkdir -p $out/nix-options-search
      export RUST_BACKTRACE=full
      ${
        if cfg.nos.darwin then
          ''export NOX_HTML_Nix_Darwin="${darwin-manual}/share/doc/darwin/index.html"''
        else
          ''export NOX_HTML_Nix_Darwin="${nix-html}/share/doc/nixos/options.html"''
      }
      ${
        if cfg.nos.stable then
          ''export NOX_HTML_NixOS="${stable-manual}/share/doc/nixos/options.html"''
        else
          ''export NOX_HTML_NixOS="${nix-html}/share/doc/nixos/options.html"''
      }
      export NOX_HTML_NixOS_Unstable="${nix-html}/share/doc/nixos/options.html"
      export NOX_HTML_Home_Manager="${config.docs.hm-html}/share/doc/home-manager/options.xhtml"
      export NOX_HTML_Home_Manager_NixOS="${config.docs.hm-html}/share/doc/home-manager/nixos-options.xhtml"
      export NOX_HTML_Home_Manager_Nix_Darwin="${config.docs.hm-html}/share/doc/home-manager/nix-darwin-options.xhtml"
      export NOX_PREFETCH_CACHE_PATH=$out
      ${nos_unwrapped}/bin/nox
    '').overrideAttrs
      { __contentAddressed = true; };
  nos = pkgs.writeShellScriptBin "nos" ''
    NOX_CACHE=${nos-cache} ${nos_unwrapped}/bin/nox "$@"
  '';
  cfg = config.docs;
in
{
  config = mkIf cfg.enable {
    docs = {
      man-cache-home = "${man-cache}/home-configuration.nix.cache";
      man-cache-nix = "${man-cache}/configuration.nix.cache";
    };
    environment.systemPackages = mkIf cfg.nos.enable [
      nos
      man-nix
      man-home
    ];
  };
}
