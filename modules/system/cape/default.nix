{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.cape;
  seabios_pkg = pkgs.seabios-qemu.overrideAttrs (prev: {
    postPatch = prev.postPatch ++ ''
      substituteInPlace src/config.h --replace-fail "Bochs" "${cfg.spoofing.bios.vendor}"
      substituteInPlace src/config.h --replace-fail "BOCHSCPU" "${cfg.spoofing.bios.cpu}"
      substituteInPlace src/config.h --replace-fail "BOCHS " "${cfg.spoofing.bios.vendor}"
    '';
  });
  qemu_pkg = pkgs.qemu_kvm.overrideAttrs (prev: {
    postPatch = prev.postPatch ++ ''
      substituteInPlace hw/ide/core.c --replace-fail "QEMU HARDDISK" "${cfg.spoofing.disk.model}"
      substituteInPlace hw/scsi/scsi-disk.c --replace-fail "QEMU HARDDISK" "${cfg.spoofing.disk.model}"
      substituteInPlace hw/scsi/scsi-disk.c --replace-fail 's->vendor = g_strdup("QEMU");' 's->vendor = g_strdup("${cfg.spoofing.disk.vendor}");'

      substituteInPlace hw/ide/core.c --replace-fail "QEMU DVD-ROM" "${cfg.spoofing.dvdrom.vendor} ${cfg.spoofing.model}"
      substituteInPlace hw/ide/atapi.c --replace-fail "QEMU DVD-ROM" "${cfg.spoofing.dvdrom.vendor} ${cfg.spoofing.model}"
      substituteInPlace hw/scsi/scsi-disk.c --replace-fail "QEMU CD-ROM" "${cfg.spoofing.dvdrom.vendor} ${cfg.spoofing.model}"
      substituteInPlace hw/ide/atapi.c --replace-fail 'padstr8(buf + 8, 8, "QEMU");' 'padstr8(buf + 8, 8, "${cfg.spoofing.dvdrom.vendor}");'

      substituteInPlace hw/usb/dev-wacom.c --replace-fail "QEMU PenPartner tablet" "${cfg.spoofing.tablet.vendor} ${cfg.spoofing.tablet.model}"
      
      substituteInPlace hw/ide/core.c --replace-fail "QEMU MICRODRIVE" "${cfg.spoofing.microdrive.vendor} MICRODRIVE"

      substituteInPlace target/i386/kvm/kvm.c --replace-fail "KVMKVMKVM\\0\\0\\0" "${cfg.spoofing.hypervisor}"

      substituteInPlace block/bochs.c --replace-fail "bochs" "${cfg.spoofing.disk.vendor}"
      substituteInPlace include/hw/acpi/aml-build.h --replace-fail "BOCHS" "${cfg.spoofing.disk.vendor}"

      substituteInPlace roms/ipxe/src/drivers/net/pnic.c --replace-fail "Bochs Pseudo" "${cfg.spoofing.network}"

      substituteInPlace include/hw/acpi/aml-build.h --replace-fail "BXPC" "${cfg.spoofing.motherboard.vendor}"
    '';
    configureFlags = prev.configureFlags ++ [
      "--target-list=i386-softmmu,x86_64-softmmu,i386-linux-user,x86_64-linux-user"
      "--enable-kvm"
      "--enable-gtk"
      "--enable-spice"
      "--enable-vnc"
      "--enable-vnc-sasl"
      "--enable-gnutls"
      "--enable-docs"
      "--enable-curl"
      "--enable-linux-aio"
      "--enable-cap-ng"
      "--enable-vhost-net"
      "--enable-vhost-crypto"
      "--enable-usb-redir"
      "--enable-lzo"
      "--enable-snappy"
      "--enable-bzip2"
      "--enable-coroutine-pool"
      "--enable-replication"
      "--enable-tools"
    ];
  });
in
{
  options.cape = {
    enable = mkEnableOption "Enable CAPEv2";
    users = mkOption {
      type = types.listOf types.str;
      description = ''
        Which users should be able to use CAPEv2 and libvirtd
      '';
    };
    spoofing = {
      disk = {
        model = mkOption {
          type = types.str;
          default = "XPG GAMMIX S11 Pro";
          description = ''
            Disk model to spoof in CAPEv2 VM (default is XPG GAMMIX S11 Pro)
          '';
        };
        vendor = mkOption {
          type = types.str;
          default = "ADATA";
          description = ''
            Disk vendor to spoof in CAPEv2 VM (default is ADATA)
          '';
        };
      };
      dvdrom = { 
        model = mkOption {
          type = types.str;
          default = "DVD-RW DVR-219L";
          description = ''
            DVD-ROM (CD_ROM) model to spoof in CAPEv2 VM (default is DVD-RW DVR-219L)
          '';
        };
        vendor = mkOption {
          type = types.str;
          default = "PIONEER";
          description = ''
            DVD-ROM (CD_ROM) vendor to spoof in CAPEv2 VM (default is PIONEER)
          '';
        };
      };
      tablet = { 
        model = mkOption {
          type = types.str;
          default = "Tablet GT08";
          description = ''
            Tablet model to spoof in CAPEv2 VM (default is Tablet GT08)
          '';
        };
        vendor = mkOption {
          type = types.str;
          default = "Veikk";
          description = ''
            Tablet vendor to spoof in CAPEv2 VM (default is Veikk)
          '';
        };
      };
      microdrive.vendor = mkOption {
        type = types.str;
        default = "SanDisk";
        description = ''
          Microdrive vendor to spoof in CAPEv2 VM (default is SanDisk)
        '';
      };
      motherboard.vendor = mkOption {
          type = types.str;
          default = "ASUS";
          description = ''
            Motherboard vendor to spoof in CAPEv2 VM (default is ASUS)
          '';
      };
      bios = {
        vendor = mkOption {
          type = types.str;
          default = "AMI";
          description = ''
            BIOS vendor to spoof in CAPEv2 VM (default is ASUS)
          '';
        };
        cpu = mkOption {
          type = types.str;
          default = "AMDCPU";
          description = ''
            BIOS vendor to spoof in CAPEv2 VM (default is ASUS)
          '';
        };
      };
    };
  };

  config = mkIf cfg.enable {
    virtualisation = {
      bios = seabios_pkg;
      libvirtd = {
        enable = true;
        qemu = {
          package = qemu_pkg;
          swtpm.enable = true;
        };
      };
    };
    users.users = builtins.listToAttrs (
      builtins.map (x: { name = x; value = { extraGroups = [ "libvirtd" ]; }; }) cfg.users
    );
  };
}
