{
  lib,
  config,
  inputs,
  pkgs,
  ...
}:
let
  cfg = config.amd-ai;
  xrt = pkgs.callPackage "${inputs.nix-amd-ai}/pkgs/xrt" { };
  xrt-plugin-amdxdna = pkgs.callPackage "${inputs.nix-amd-ai}/pkgs/xrt-plugin-amdxdna" {
    inherit xrt;
  };
  fastflowlm = pkgs.callPackage "${inputs.nix-amd-ai}/pkgs/fastflowlm" { inherit xrt; };
  xrtPrefix = "${xrt}/opt/xilinx/xrt";
  xrt-combined = pkgs.runCommand "xrt-combined" { } ''
    mkdir -p $out
    cp -rs ${xrtPrefix}/* $out/
    chmod -R u+w $out/lib
    ln -sf ${xrt-plugin-amdxdna}/opt/xilinx/xrt/lib/libxrt_driver_xdna* $out/lib/
  '';
in
{
  options.amd-ai.enable = lib.mkEnableOption "amd ai stuff";

  config = lib.mkIf cfg.enable {
    environment.sessionVariables = {
      XILINX_XRT = "${xrt-combined}";
      XRT_PATH = "${xrt-combined}";
      FLM_DISABLE_UPDATE_CHECK = "1";
    };
    environment.systemPackages = [
      xrt-combined
      fastflowlm
      pkgs.pciutils
      pkgs.lshw
    ];
    services.udev.extraRules = ''
      SUBSYSTEM=="accel", DRIVERS=="amdxdna", GROUP="video", MODE="0660"
      KERNEL=="accel*", SUBSYSTEM=="misc", ATTRS{driver}=="amdxdna", GROUP="video", MODE="0660"
    '';
    boot = {
      kernelParams = [ "iommu.passthrough=0" ];
      kernelModules = [ "amdxdna" ];
    };
    security.pam.loginLimits = [
      {
        domain = "@video";
        type = "-";
        item = "memlock";
        value = "unlimited";
      }
      {
        domain = "@render";
        type = "-";
        item = "memlock";
        value = "unlimited";
      }
    ];
    services = {
      searx = {
        enable = true;
        redisCreateLocally = true;
        environmentFile = "/var/lib/searx-secret";
        settings = {
          search.formats = [
            "html"
            "json"
          ];
          server = {
            port = 8000;
            bind_address = "127.0.0.1";
            limiter = false;
          };
        };
      };

      open-webui = {
        enable = true;
        host = "127.0.0.1";
        port = 8080;
        environment = {
          WEBUI_AUTH = "False";
          OLLAMA_API_BASE_URL = "http://127.0.0.1:11434";
        };
      };
    };
  };
}
