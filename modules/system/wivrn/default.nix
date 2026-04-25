{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.wivrn;
  pkg_xrizer = inputs.nixpkgs-xr.packages.${pkgs.stdenv.hostPlatform.system}.xrizer;
  wivrn_i686 = pkgs.pkgsi686Linux.callPackage (pkg_wivrn.override) {
    clientLibOnly = true;
    git = pkgs.pkgsi686Linux.git.override { withManual = false; };
    android-tools = pkgs.android-tools.overrideAttrs (old: {
      cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DOPENSSL_NO_ASM=ON" ];
    });
  };  
  pkg_wivrn = (inputs.nixpkgs-xr.packages.${pkgs.stdenv.hostPlatform.system}.wivrn.override {
    cudaSupport = true;
    xrizer = xrizer_multilib;
    cudaPackages = pkgs.cudaPackages;
  }).overrideAttrs
  (
    finalAttrs: prevAttrs: {
      NIX_CFLAGS_COMPILE = (prevAttrs.NIX_CFLAGS_COMPILE or "") +  " -march=znver5 -O3";
      monado = prevAttrs.monado.overrideAttrs (oldAttrs: {
        patches = (oldAttrs.patches or [ ]) ++ [
          ../../../stuff/monado.patch
        ];
      });
    }
  );  
  xrizer_multilib = pkgs.symlinkJoin {
    name = "xrizer-multilib";
    paths = [
      pkg_xrizer
      (pkgs.pkgsi686Linux.callPackage pkg_xrizer.override { })
    ];
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
