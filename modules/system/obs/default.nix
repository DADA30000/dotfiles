{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.obs;
in
{
  options.obs = {
    enable = mkEnableOption "OBS";
    virt-cam = mkEnableOption "virtual camera";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.wrapOBS {
        plugins = [
          pkgs.obs-studio-plugins.obs-vaapi
          pkgs.gst_all_1.gstreamer
        ];
      })
      pkgs.gst_all_1.gstreamer
      pkgs.obs-studio-plugins.obs-vaapi
    ];
    boot = mkIf cfg.virt-cam {
      # WORKAROUND: Nixpkgs issue #575861 - v4l2loopback install step runs depmod, generating index files that collide with kernel modules.builtin.alias.bin
      extraModulePackages = with config.boot.kernelPackages; [
        (v4l2loopback.overrideAttrs (old: {
          makeFlags = (old.makeFlags or [ ]) ++ [ "DEPMOD=true" ];
          postInstall = (old.postInstall or "") + ''
            rm -f $out/lib/modules/*/modules.*
          '';
        }))
      ];
      extraModprobeConfig = ''
        options v4l2loopback devices=1 video_nr=1 card_label="OBS Cam" exclusive_caps=1
      '';
      kernelModules = [
        "v4l2loopback"
      ];
    };
  };
}
