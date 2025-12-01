{ lib, config, pkgs, inputs, ... }:
let
  cfg = config.wivrn;
  xrizer_deps = pkgs.rustPlatform.fetchCargoVendor {
    src = inputs.xrizer;
    name = "xrizer-vendor";
    hash = "sha256-tLPwiwKkEBdsRxXgdcTM9TLJeNRZV32W11qUbyCVdHw="; 
  };

  xrizer_new = pkgs.xrizer.overrideAttrs (old: {
    src = inputs.xrizer;
    cargoDeps = xrizer_deps;
    patches = [];
    postPatch = ''
      substituteInPlace Cargo.toml \
        --replace-fail 'features = ["static"]' 'features = ["linked"]'
      substituteInPlace src/graphics_backends/gl.rs \
        --replace-fail 'libGLX.so.0' '${lib.getLib pkgs.libGL}/lib/libGLX.so.0'
    '';
  });
in
with lib;
{
  options.wivrn = {
    enable = mkEnableOption "Enable WiVRn";
  };
  config = mkIf cfg.enable {
    services.wivrn = {
      enable = true;
      openFirewall = true;
      defaultRuntime = true;
      autoStart = true;
      steam.importOXRRuntimes = true;
      highPriority = true;
      package = pkgs.wivrn.override { ovrCompatSearchPaths = "${xrizer_new}/lib/xrizer:${pkgs.opencomposite}/lib/opencomposite}"; };
      # You should use the default configuration (which is no configuration), as that works the best out of the box.
      # However, if you need to configure something see https://github.com/WiVRn/WiVRn/blob/master/docs/configuration.md for configuration options and https://mynixos.com/nixpkgs/option/services.wivrn.config.json for an example configuration.
    };
  };
}
