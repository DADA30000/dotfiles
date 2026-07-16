{
  pkgs,
  lib,
  user,
  wrapped,
  orig,
  config,
  inputs,
  evalAndSubstitute,
  ...
}:
let
  mkPyApp =
    {
      name,
      src,
      pathDeps ? [ ],
    }:
    pkgs.stdenv.mkDerivation {
      pname = name;
      version = "1.0";
      src = pkgs.writeText "${name}-src" src;
      dontUnpack = true;

      nativeBuildInputs = [
        pkgs.wrapGAppsHook3
        pkgs.gobject-introspection
      ];
      buildInputs = [
        pkgs.gtk3
        pkgs.gsettings-desktop-schemas
        pkgs.adwaita-icon-theme
      ];

      pythonEnv = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);

      installPhase = ''
        mkdir -p $out/bin
        echo "#!$pythonEnv/bin/python" > $out/bin/${name}
        cat $src >> $out/bin/${name}
        chmod +x $out/bin/${name}
      '';

      preFixup = ''
        gappsWrapperArgs+=(
          --prefix PATH : "${lib.makeBinPath pathDeps}"
        )
      '';
    };
  disableServices =
    list:
    let
      disabledAttrs = lib.foldl' (
        acc: item:
        let
          parts = lib.splitString "/" item;
          type = lib.elemAt parts 0;
          name = lib.elemAt parts 1;
          path =
            if type == "user" then
              [
                "user"
                "services"
                name
                "wantedBy"
              ]
            else
              [
                "services"
                name
                "wantedBy"
              ];
        in
        lib.recursiveUpdate acc (lib.setAttrByPath path (lib.mkForce [ ]))
      ) { } list;

      servicesJson = pkgs.writeText "services.json" (builtins.toJSON list);

      installScript = pkgs.writeShellScript "install-script" ''
        neovide-term "zsh -c 'nix-install; exec zsh -i'"
      '';

      servicePrompterApp = mkPyApp {
        name = "service-prompter";
        src = evalAndSubstitute {
          string = builtins.readFile ../../stuff/prompt.py;
          scope = { inherit pkgs servicesJson installScript; };
        };
      };

      prompterService = {
        user.services.service-prompter = {
          wantedBy = [ config.home-manager.users.${user}.wayland.systemd.target ];
          description = "Graphical service manager and installer prompt";
          after = [ config.home-manager.users.${user}.wayland.systemd.target ];
          partOf = [ config.home-manager.users.${user}.wayland.systemd.target ];
          unitConfig.ConditionEnvironment = "WAYLAND_DISPLAY";
          serviceConfig = {
            ExecStart = "${servicePrompterApp}/bin/service-prompter";
            Restart = "on-failure";
            RestartSec = "10";
          };
        };
      };
    in
    lib.recursiveUpdate disabledAttrs prompterService;
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
  nix-install = ''
    if [[ $EUID -ne 0 ]]; then
      exec sudo WAYLAND_DISPLAY=$WAYLAND_DISPLAY HOME=$HOME GTK_THEME=$GTK_THEME XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR nix-install
    fi
    setfont cyr-sun16
    clear
    if gum confirm "Провести оффлайн установку?"; then
      cd /repo
      exec ./start.sh offline
    else
      echo -e "\e[34mПроверка наличия соединения с интернетом...\e[0m"
      if ! nc -zw1 google.com 443 > /dev/null 2>&1; then
        echo -e "\e[31mСоединение не установлено :(\e[0m"
        if gum confirm "Настроить подключение?"; then
          nmtui
          if ! nc -zw1 google.com 443 > /dev/null 2>&1; then
            echo -e "\e[34mСоединение не было установлено, перезапуск...\e[0m"
            sleep 2; exec nix-install
          fi
        fi
      fi
      echo -e "\e[32mСоединение установлено!\e[0m"
    fi
    sleep 1
    url="https://github.com/DADA30000/dotfiles"
    clear
    if gum confirm --default=false "Использовать встроенный в ISO репозиторий?"; then
      cd /repo
      exec ./start.sh
    else
      if gum confirm --default=false "Поменять URL репозитория с файлами конфигурации? (скрипт запускает start.sh из репозитория, репозиторий должен быть публичным)"; then
        url=$(gum input --placeholder "Пример: https://github.com/DADA30000/dotfiles")
      fi
      if GIT_ASKPASS=true git ls-remote "$url" > /dev/null 2>&1; then
        clear
        echo -e "\e[34mКлонирование репозитория...\e[0m"
        rm -rf /mnt2
        mkdir /mnt2
        if git clone "$url" --depth 1 /mnt2/dotfiles; then
          cd /mnt2/dotfiles
          echo -e "\e[34mЗапуск start.sh...\e[0m"
          exec ./start.sh
        else
          echo -e "\e[31mОшибка клонирования репозитория, перезапуск скрипта...\e[0m"
          sleep 3
          rm -rf /mnt2
          exec nix-install
        fi
      else
        echo -e "\e[31mURL репозитория неверный или приватный, перезапуск скрипта...\e[0m"
        sleep 3
        exec nix-install
      fi
    fi
  '';
  install-offline =
    if wrapped then
      ''
        nixos-install -v --system '${orig.config.system.build.toplevel}' --keep-going --impure
      ''
    else
      ''
        echo "can't install twice :("
        exit 1
      '';
in
{
  config = lib.mkMerge [
    (lib.mkIf wrapped {
      system.build.isoImage = lib.mkForce (
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
            nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ pkgs.erofs-utils ];
            squashfsCommand = ''
              closureInfo=${pkgs.closureInfo { rootPaths = config.isoImage.storeContents; }}
              cp $closureInfo/registration nix-path-registration
              sed 's|^/nix/store/||' $closureInfo/store-paths > relative-store-paths
              tar -cf - \
                --mode='u+w' \
                -C . nix-path-registration \
                -C /nix/store \
                -T relative-store-paths \
                | mkfs.erofs \
                    --force-uid=0 \
                    --force-gid=0 \
                    -z zstd,19 \
                    -C 1048576 \
                    --workers $NIX_BUILD_CORES \
                    -E dot-omitted \
                    -T 0 \
                    --ignore-mtime \
                    --tar=f \
                    "$out" \
                    /dev/stdin
            '';
          })
      );
      boot.initrd.systemd.services.initrd-find-nixos-closure = {
        serviceConfig.ExecStart = lib.mkForce (
          pkgs.writeScript "find-nixos-closure" ''
            #!/bin/bash
            mkdir -p /etc
            INIT_PATH=$(echo /sysroot/nix/store/*-nixos-system-iso-*/init)
            echo "NEW_INIT=''${INIT_PATH#/sysroot}" > /etc/switch-root.conf
            closure_raw=''${INIT_PATH%/init}
            closure=''${closure_raw#/sysroot}
            ln -sfn "$closure" /nixos-closure
          ''
        );
      };
      boot.initrd.systemd.storePaths = [
        config.boot.initrd.systemd.services.initrd-find-nixos-closure.serviceConfig.ExecStart
      ];
      home-manager.users.${user} = import ./home.nix;
      boot.supportedFilesystems.zfs = lib.mkForce false;
      networking.hostName = "iso";

      systemd = disableServices [
        "user/replays"
        "user/opentabletdriver"
        "user/sunshine"
        "user/kdeconnect-indicator"
        "user/kdeconnect"
        "user/wivrn"
        "user/easyeffects"
        "system/zerotierone"
        "system/tailscaled"
        "system/sing-box"
        "system/sshd"
        "system/cups"
        "system/cups-browsed"
        "system/openrgb"
        "system/ydotool"
      ];

      security.polkit.extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (subject.isInGroup("wheel")) {
            return polkit.Result.YES;
          }
        });
      '';

      system.activationScripts.repo = {

        # Run after /dev has been mounted
        deps = [ "specialfs" ];

        text = ''
          PATH="$PATH:${pkgs.coreutils-full}/bin"
          if [[ ! -d /repo ]]; then
            rm -rf /repo
            cp -r --no-preserve=mode "${inputs.self}" /repo
            mkdir -p /etc/nixos
            cp -r /repo/{machines,stuff,modules,flake.nix,flake.lock} /etc/nixos
          fi
        '';

      };

      boot.kernel.sysctl."vm.swappiness" = 200;

      services.ollama.enable = lib.mkForce false;

      graphics.amdgpu.pro = lib.mkForce false;

      disks.enable = lib.mkForce false;

      my-services.cloudflare-ddns.enable = lib.mkForce false;

      my-services.nginx.enable = lib.mkForce false;

      cape.enable = lib.mkForce false;

      boot.loader.timeout = lib.mkForce 0;

      fonts.fontconfig.enable = true;

      xdg = {
        mime.enable = true;
        icons.enable = true;
        autostart.enable = true;
      };

      networking.wireless.enable = false;

      environment.systemPackages = with pkgs; [
        gum
        lolcat
        openssl
        gparted
        (python3.withPackages (ps: with ps; [ tkinter ]))
        (writeShellScriptBin "nix-install" nix-install)
        (writeShellScriptBin "install-offline" install-offline)
      ];

      # Configure the loopback store mount using the EROFS driver
      fileSystems."/nix/.ro-store" = lib.mkImageMediaOverride {
        fsType = "erofs";
        device = "${lib.optionalString config.boot.initrd.systemd.enable "/sysroot"}/iso/nix-store.squashfs";
        options = [ "loop" ];
        neededForBoot = true;
      };

      # Add the EROFS driver to the available kernel modules in stage 1
      boot.initrd.availableKernelModules = [ "erofs" ];
    })
    {
      nixpkgs.hostPlatform = "x86_64-linux";
      hardware.enableAllHardware = true;
      hardware.enableRedistributableFirmware = true;
      graphics.nvidia.enable = lib.mkForce true;
      boot.loader.grub.enable = false;
    }
  ];
}
