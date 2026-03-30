{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.wivrn;
  xrSources = pkgs.callPackage "${inputs.nixpkgs-xr}/_sources/generated.nix" {};
  pkg_xrizer = inputs.nixpkgs-xr.packages.${pkgs.stdenv.hostPlatform.system}.xrizer;
  pkg_wivrn = (pkgs.wivrn.override { 
    cudaSupport = true;
    xrizer = xrizer_multilib;
  }).overrideAttrs (finalAttrs: prevAttrs: {
    inherit (xrSources.wivrn) pname version src;

    monado = pkgs.applyPatches {
      inherit (xrSources.wivrn-monado) src;
      inherit (prevAttrs.monado) patches postPatch;
    };

    patches = [ ];

    cmakeFlags = (pkgs.lib.filter (flag: !pkgs.lib.hasInfix "GIT_DESC" flag) prevAttrs.cmakeFlags)
      ++ [
        (pkgs.lib.cmakeFeature "GIT_DESC" "v${prevAttrs.version}-0-g${builtins.substring 0 8 finalAttrs.version}")
        (pkgs.lib.cmakeFeature "GIT_COMMIT" finalAttrs.version)
        (pkgs.lib.cmakeFeature "WIVRN_USE_NVENC" "ON")
      ];
  });
  xrizer_multilib = pkgs.symlinkJoin {
    name = "xrizer-multilib";
    paths = [
      pkg_xrizer
      (pkgs.pkgsi686Linux.callPackage pkg_xrizer.override { })
    ];
  };
  wivrn_i686 = pkgs.pkgsi686Linux.callPackage pkg_wivrn.override {
    clientLibOnly = true;
    git = pkgs.pkgsi686Linux.git.override { withManual = false; };
  };
in
with lib;
{
  options.wivrn = {
    enable = mkEnableOption "WiVRn";
  };
  config = mkIf cfg.enable {
    services.wivrn = {
      enable = true;
      openFirewall = true;
      defaultRuntime = true;
      autoStart = true;
      steam.importOXRRuntimes = true;
      highPriority = true;
      package = pkg_wivrn;
    };
    environment.etc."xdg/openxr/1/active_runtime.i686.json".source =
      "${wivrn_i686}/share/openxr/1/openxr_wivrn.i686.json";
    systemd.user.services.wivrn.serviceConfig.ExecStart = mkForce "/run/wrappers/bin/wivrn-server";
  };
}
