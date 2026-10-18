{
  pkgs,
  lib,
  user,
  wrapped,
  orig,
  config,
  inputs,
  ...
}:
let
  patchGrubDir =
    dir:
    pkgs.runCommand "patched-efi-dir" { } ''
      cp -r ${dir} $out
      chmod -R +w $out
      find $out -name grub.cfg -exec sed -i 's/terminal_output console/# terminal_output console/g' {} +
    '';

  patchEfiImg =
    img:
    pkgs.runCommand "patched-efi-img"
      {
        nativeBuildInputs = [ pkgs.mtools ];
      }
      ''
        cp ${img} $out
        chmod +w $out
        mcopy -i $out ::/EFI/BOOT/grub.cfg tmp.cfg
        sed -i 's/terminal_output console/# terminal_output console/g' tmp.cfg
        mdel -i $out ::/EFI/BOOT/grub.cfg
        mcopy -i $out tmp.cfg ::/EFI/BOOT/grub.cfg
      '';

  patchedContents = map (
    item:
    if item.target == "/EFI" then
      item // { source = patchGrubDir item.source; }
    else if item.target == "/boot/efi.img" then
      item // { source = patchEfiImg item.source; }
    else
      item
  ) config.isoImage.contents;

  mkIsoImage =
    workers:
    (pkgs.callPackage "${pkgs.path}/nixos/lib/make-iso9660-image.nix" (
      {
        inherit (config.isoImage) compressImage volumeID;
        contents = patchedContents;
        isoName = "${config.image.baseName}.iso";
        bootable = config.isoImage.makeBiosBootable;
        bootImage = "/isolinux/isolinux.bin";
        syslinux = if config.isoImage.makeBiosBootable then pkgs.syslinux else null;
        squashfsContents = config.isoImage.storeContents;
        squashfsCompression = config.isoImage.squashfsCompression;
      }
      // lib.optionalAttrs (config.isoImage.makeUsbBootable && config.isoImage.makeBiosBootable) {
        usbBootable = true;
        isohybridMbrImage = "${pkgs.syslinux}/share/syslinux/isohdpfx.bin";
      }
      // lib.optionalAttrs config.isoImage.makeEfiBootable {
        efiBootable = true;
        efiBootImage = "boot/efi.img";
      }
    )).overrideAttrs
      (oldAttrs: {
        nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [
          pkgs.erofs-utils
          pkgs.util-linux
        ];

        squashfsCommand = ''
          closureInfo=${pkgs.closureInfo { rootPaths = config.isoImage.storeContents; }}

          cat << 'EOF' > run-unshared.sh
          #!/bin/sh
          set -e

          mkdir -p erofs_root
          mount -t tmpfs -o size=20M tmpfs erofs_root
          cp "$1" erofs_root/nix-path-registration

          while IFS= read -r path; do
            [ -z "$path" ] && continue
            basename=$(basename "$path")
            target="erofs_root/$basename"
            
            if [ -L "$path" ]; then
              link_target=$(readlink "$path")
              ln -s "$link_target" "$target"
            else
              if [ -d "$path" ]; then
                mkdir -p "$target"
              else
                touch "$target"
              fi
              mount --bind "$path" "$target"
            fi
          done < "$2"

          mkfs.erofs \
            --force-uid=0 \
            --force-gid=0 \
            --workers ${workers} \
            --ignore-mtime \
            --zD=1 \
            -z zstd,19 \
            -C 1048576 \
            -m 1048576:zstd,19 \
            -E 48bit,all-fragments,dot-omitted,fragdedupe=inode \
            -T 0 \
            -x -1 \
            "$3" \
            erofs_root
          EOF
          chmod +x run-unshared.sh

          unshare -m -U -r ./run-unshared.sh "$closureInfo/registration" "$closureInfo/store-paths" "$out"

          rm -f run-unshared.sh
        '';
      });

in
{
  config = lib.mkMerge [
    (lib.mkIf wrapped {
      system.build.isoImage = lib.mkForce (mkIsoImage "$NIX_BUILD_CORES");
      boot.initrd.systemd.services.initrd-find-nixos-closure.serviceConfig.ExecStart = lib.mkForce (
        pkgs.writeScript "find-nixos-closure" ''
          #!/bin/sh
          mkdir -p /etc
          INIT_PATH=$(echo /sysroot/nix/store/*-nixos-system-iso-*/init)
          closure_raw=$(dirname "$INIT_PATH")
          closure=''${closure_raw#/sysroot}
          ln -sfn "$closure" /nixos-closure
          if [ -x "/sysroot$closure/prepare-root" ]; then
            echo 'NEW_INIT=' > /etc/switch-root.conf
          else
            echo "NEW_INIT=''${INIT_PATH#/sysroot}" > /etc/switch-root.conf
            echo "$closure does not look like a NixOS installation - not activating"
          fi
        ''
      );
      boot.initrd.systemd.storePaths = [
        config.boot.initrd.systemd.services.initrd-find-nixos-closure.serviceConfig.ExecStart
      ];
      home-manager.users.${user} = import ./home.nix;
      networking.hostName = "iso";

      system.activationScripts.repo = {
        deps = [ "specialfs" ];
        text = ''
          PATH="$PATH:${pkgs.coreutils-full}/bin"
          if [[ ! -d /repo ]]; then
            rm -rf /repo
            cp -r "${inputs.self}" /repo
            chmod -R u+w /repo
            mkdir -p /etc/nixos
            cp -r /repo/{machines,stuff,modules,flake.nix,flake.lock} /etc/nixos
          fi
        '';
      };

      disks.enable = lib.mkForce false;
      boot.loader.timeout = lib.mkForce 0;
      fonts.fontconfig.enable = true;

      xdg = {
        mime.enable = true;
        icons.enable = true;
        autostart.enable = true;
      };

      networking.wireless.enable = false;

      environment.etc."nixos-toplevel-reference".source = orig.config.system.build.toplevel;

      lib.isoFileSystems."/nix/.ro-store" = lib.mkImageMediaOverride {
        fsType = "erofs";
        device = "${lib.optionalString config.boot.initrd.systemd.enable "/sysroot"}/iso/nix-store.squashfs";
        neededForBoot = true;
      };

      boot.initrd.availableKernelModules = [ "erofs" ];
    })

    {
      nixpkgs.hostPlatform = "x86_64-linux";
      hardware.enableAllHardware = true;
      hardware.enableRedistributableFirmware = true;
      graphics.nvidia.enable = true;
      boot.loader.systemd-boot.enable = true;
    }
  ];
}
