{
  user,
  pkgs,
  user-hash,
  config,
  ...
}:
{
  graphics.nvidia.enable = true;
  amd-ai.enable = false;
  nix-mineral.settings.kernel.intel-iommu = false;

  home-manager.users.${user} = import ./home.nix;

  # Rebinding that special GIMATE key on my laptop to a useful sysrq/print key.
  services.udev.extraHwdb = ''
    evdev:input:b0003v*
     KEYBOARD_KEY_70067=sysrq
  '';

  disks = {
    encryption = true;
    ssdOptimizations = true;
    autoScanZfs = true;
  };

  my-services = {
    cloudflare-ddns.enable = true;
    nginx = {
      enable = true;
      website.enable = true;
    };
  };

  boot = {
    kernelParams = [ "rd.shell=0" ];
    lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
    };
    initrd.systemd.services.pcr-gatekeeper =
      let
        luksUnits = map (n: "systemd-cryptsetup@${n}.service") (
          builtins.attrNames config.boot.initrd.luks.devices
        );
      in
      {
        wantedBy = [ "initrd.target" ];
        unitConfig.DefaultDependencies = false;
        serviceConfig.Type = "oneshot";

        before = [ "cryptsetup-pre.target" ] ++ luksUnits;
        requiredBy = luksUnits;
        after = [
          "plymouth-start.service"
          "dev-tpmrm0.device"
        ];

        path = with pkgs; [
          mkpasswd
          coreutils
          tpm2-tools
          config.boot.plymouth.package
          config.boot.initrd.systemd.package
        ];

        script = ''
          export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
          NV="0x1500016"
          PCRS="sha256:0,1,2,3,5,7"
          EXPECTED='${user-hash}'
          SALT=$(echo "$EXPECTED" | cut -d'$' -f1-4)\$

          if tpm2_nvread -P "pcr:$PCRS" "$NV"; then
            exit 0
          fi

          for try in 1 2 3; do
            PASS=$(plymouth ask-for-password --prompt="PCR Mismatch. Key ($try/3):")
            COMPUTED=$(echo -n "$PASS" | mkpasswd -m yescrypt -s -S "$SALT" 2>/dev/null || true)
            if [ -n "$COMPUTED" ] && [ "$COMPUTED" = "$EXPECTED" ]; then
              plymouth message --text="Enrolling new PCRs..."
              tpm2_nvundefine -C o "$NV" || true
              tpm2_createpolicy --policy-pcr -l "$PCRS" -L /tmp/p.dat
              tpm2_nvdefine -C o -s 2 -a "policyread|ownerwrite" -L /tmp/p.dat "$NV"
              echo -n "OK" | tpm2_nvwrite -C o -i - "$NV"
              rm -f /tmp/p.dat
              exit 0
            elif [ "$try" -lt 3 ]; then
              plymouth message --text="Incorrect attempt $try. Retrying..."
            else
              plymouth message --text="Lockout! Powering off..."
              sleep 2
              systemctl poweroff -ff
            fi
          done
        '';
      };

  };

}
