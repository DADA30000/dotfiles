{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.cape;
  qemu_pkg = pkgs.qemu.overrideAttrs (prev: {
    postPatch = prev.postPatch ++ ''
      substituteInPlace hw/ide/core.c --replace "QEMU HARDDISK" "SAMSUNG MZ76E120"
      substituteInPlace hw/scsi/scsi-disk.c --replace "QEMU HARDDISK" "SAMSUNG MZ76E120"
      substituteInPlace hw/ide/core.c --replace "QEMU DVD-ROM" "HL-PQ-SV WB8"
      substituteInPlace target/i386/kvm/kvm.c --replace "KVMKVMKVM\\0\\0\\0" "GenuineIntel"
      substituteInPlace include/hw/acpi/aml-build.h --replace '"BOCHS "' '"ALASKA"'
      substituteInPlace include/hw/acpi/aml-build.h --replace 'BXPC' '<WOOT>'
    '';
  });
in
{
  options.cape = {
    enable = mkEnableOption "Enable CAPEv2";
    users = mkOption {
      type = types.listOf types.str;
      description = ''
        Which users should be able to use CAPEv2 and libvirt
      '';
    };
  };

  config = mkIf cfg.enable {
    virtualisation.libvirtd = {
      enable = true;
    };
  };
}
