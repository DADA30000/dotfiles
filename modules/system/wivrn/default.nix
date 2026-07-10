{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.wivrn;
  patchXrizer =
    pkg: loader:
    pkg.overrideAttrs (prev: {
      buildInputs = (prev.buildInputs or [ ]) ++ [ loader ];
      nativeBuildInputs = (prev.nativeBuildInputs or [ ]) ++ [ pkgs.patchelf ];
      postFixup = (prev.postFixup or "") + ''
        find $out -type f \( -name "*.so*" -o -name "xrizer" -o -executable \) -exec patchelf --add-rpath "${loader}/lib" {} \;
      '';
    });
  pkg_xrizer =
    patchXrizer inputs.nixpkgs-xr.packages.${pkgs.stdenv.hostPlatform.system}.xrizer
      pkgs.openxr-loader;
  pkg_opencomposite = inputs.nixpkgs-xr.packages.${pkgs.stdenv.hostPlatform.system}.opencomposite;
  xrizer_multilib = pkgs.symlinkJoin {
    name = "xrizer-multilib";
    paths = [
      pkg_xrizer
      (patchXrizer (pkgs.pkgsi686Linux.callPackage pkg_xrizer.override
        { }
      ) pkgs.pkgsi686Linux.openxr-loader)
    ];
  };
  opencomposite_multilib = pkgs.symlinkJoin {
    name = "opencomposite-multilib";
    paths = [
      pkg_opencomposite
      (pkgs.pkgsi686Linux.callPackage pkg_opencomposite.override { })
    ];
  };
  pkg_wivrn = inputs.wivrn.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
    cudaSupport = true;
    xrizer = xrizer_multilib;
    opencomposite = opencomposite_multilib;
  };
  wivrn_i686 = pkgs.pkgsi686Linux.callPackage (pkg_wivrn.override) {
    clientLibOnly = true;
    git = pkgs.pkgsi686Linux.git.override { withManual = false; };
    android-tools = pkgs.android-tools.overrideAttrs (old: {
      cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DOPENSSL_NO_ASM=ON" ];
    });
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
