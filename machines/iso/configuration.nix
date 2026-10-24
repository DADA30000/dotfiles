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
in
{
  config = lib.mkMerge [
    (lib.mkIf wrapped {
      networking.hostName = "iso";
      networking.wireless.enable = false;
      disks.enable = lib.mkForce false;
      boot.loader.timeout = lib.mkForce 0;

      environment.etc."nixos-toplevel-reference".source = orig.config.system.build.toplevel;

      lib.isoFileSystems."/nix/.ro-store" = lib.mkImageMediaOverride {
        fsType = "erofs";
        neededForBoot = true;
        device = "${lib.optionalString config.boot.initrd.systemd.enable "/sysroot"}/iso/nix-store.squashfs";
      };

      boot.initrd.systemd.services.initrd-find-nixos-closure.script = lib.mkForce ''
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
      '';

      system.build.isoImage = lib.mkForce (
        config.system.build.isoImage.overrideAttrs (oldAttrs: {
          sources = map (x: x.source) patchedContents;
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
              --workers "$NIX_BUILD_CORES" \
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
        })
      );
    })

    {
      nixpkgs.hostPlatform = "x86_64-linux";
      graphics.nvidia.enable = true;
      boot.loader.systemd-boot.enable = true;
      fonts.fontconfig.enable = true;
      boot.initrd.availableKernelModules = [ "erofs" ];

      hardware = {
        enableAllHardware = true;
        enableRedistributableFirmware = true;
      };

      xdg = {
        mime.enable = true;
        icons.enable = true;
        autostart.enable = true;
      };

      systemd.services.init-repo = {
        description = "Initialize /repo and /etc/nixos from Flake Source";
        wantedBy = [ "multi-user.target" ];
        after = [ "local-fs.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        path = [ pkgs.coreutils ];

        script = ''
          rm -rf /repo
          cp -r "${inputs.self}" /repo
          chmod -R u+w /repo
          mkdir -p /etc/nixos
          cp -rf /repo/{machines,stuff,modules,flake.nix,flake.lock} /etc/nixos/
        '';
      };
    }
  ];
}
