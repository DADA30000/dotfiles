{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.wivrn;
  pkg_xrizer =
    inputs.nixpkgs-xr.packages.${pkgs.stdenv.hostPlatform.system}.xrizer.overrideAttrs
      (prev: {
        patches = (prev.patches or [ ]) ++ [ ../../../stuff/patches/xrizer.patch ];
      });
  pkg_opencomposite = inputs.nixpkgs-xr.packages.${pkgs.stdenv.hostPlatform.system}.opencomposite;
  opencomposite_multilib = pkgs.symlinkJoin {
    name = "opencomposite-multilib";
    paths = [
      pkg_opencomposite
      (pkgs.pkgsi686Linux.callPackage pkg_opencomposite.override { })
    ];
  };
  wivrn_i686 = pkgs.pkgsi686Linux.callPackage (pkg_wivrn.override) {
    clientLibOnly = true;
    git = pkgs.pkgsi686Linux.git.override { withManual = false; };
    android-tools = pkgs.android-tools.overrideAttrs (old: {
      cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DOPENSSL_NO_ASM=ON" ];
    });
  };
  pkg_wivrn =
    (inputs.wivrn.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
      cudaSupport = true;
      xrizer = xrizer_multilib;
      opencomposite = opencomposite_multilib;
      cudaPackages = pkgs.cudaPackages;
    }).overrideAttrs
      (prevAttrs: {
        env.NIX_CFLAGS_COMPILE = (prevAttrs.env.NIX_CFLAGS_COMPILE or "") + " -march=native -O3";
      });
  # pkg_wivrn = (
  #   inputs.nixpkgs-xr.packages.${pkgs.stdenv.hostPlatform.system}.wivrn.override {
  #     cudaSupport = true;
  #     xrizer = xrizer_multilib;
  #     opencomposite = opencomposite_multilib;
  #     cudaPackages = pkgs.cudaPackages;
  #   }
  # ); # .overrideAttrs
  # (prevAttrs: {
  # # patches = (prevAttrs.patches or [ ]) ++ [ ../../../stuff/wivrn_debug.patch ];
  # NIX_CFLAGS_COMPILE = (prevAttrs.NIX_CFLAGS_COMPILE or "") + " -march=native -O3";
  # postUnpack = "";
  # buildInputs = (prevAttrs.buildInputs or [ ]) ++ [
  #   pkgs.kdePackages.kirigami-addons
  # ];
  # src = inputs.wivrn // {
  #   name = "${inputs.wivrn}";
  # };
  # monado = prevAttrs.monado.overrideAttrs (oldAttrs: {
  #   src = inputs.monado;
  #   # patches = (oldAttrs.patches or [ ]) ++ [
  #   #   ../../../stuff/monado_debug.patch
  #   # ];
  # });
  # });
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
    hardware.graphics.extraPackages = with pkgs; [
      monado-vulkan-layers
    ];
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
    environment.sessionVariables.OXR_RECENTER_STAGE = 1;
    systemd.user.services.wivrn.serviceConfig.ExecStart = mkForce "/run/wrappers/bin/wivrn-server";
  };
}
