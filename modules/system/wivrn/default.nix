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
  pkg_wivrn = inputs.nixpkgs-xr.packages.${pkgs.stdenv.hostPlatform.system}.wivrn.override {
    xrizer = xrizer_multilib;
  };
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
