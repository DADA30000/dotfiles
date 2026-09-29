{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.umu;

  mount-umu-bin = pkgs.pkgsStatic.stdenv.mkDerivation {
    pname = "mount-umu";
    version = "2.0";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.pkgsStatic.rustc ];
    buildPhase = ''
      rustc --edition 2024 \
        --target x86_64-unknown-linux-musl \
        -C target-feature=+crt-static \
        -C linker=$CC \
        -C opt-level=s \
        -C lto=fat \
        -C codegen-units=1 \
        -C panic=abort \
        -C strip=symbols \
        -O ${../../../stuff/system/packages/mount-umu.rs} -o mount-umu
    '';
    installPhase = ''
      mkdir -p $out/bin
      install -m 0755 mount-umu $out/bin/mount-umu
    '';
  };
in
{
  options.umu = {
    enable = lib.mkEnableOption "umu - universal windows apps launcher (system runtime & mount service)";
  };

  config = lib.mkIf cfg.enable {
    systemd.services."umu-mount@" = {
      description = "Isolated ephemeral UMU runtime overlay for UID %i";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${mount-umu-bin}/bin/mount-umu %i";
        ExecStop = "${mount-umu-bin}/bin/mount-umu -u %i";
      };
    };

    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units") {
          var unit = action.lookup("unit");
          if (unit === "umu-mount@" + subject.uid + ".service" ||
              unit === "umu-mount@" + subject.user + ".service") {
            return polkit.Result.YES;
          }
        }
      });
    '';
  };
}
