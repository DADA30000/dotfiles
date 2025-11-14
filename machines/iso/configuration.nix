{
  pkgs,
  lib,
  user,
  wrapped,
  orig,
  ...
}:
let
  #bundle = pkgs.fetchurl {
  #  url = "https://github.com/DADA30000/dotfiles/releases/download/vmware/VMware-Workstation-Full-17.6.3-24583834.x86_64.bundle";
  #  hash = "sha256-eVdZF3KN7UxtC4n0q2qBvpp3PADuto0dEqwNsSVHjuA=";
  #};
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
  imports = [
    ../nixos/configuration.nix
  ];
  config = lib.mkMerge [
    (lib.mkIf wrapped {
      home-manager.users.${user} = import ./home.nix;
      boot.supportedFilesystems.zfs = lib.mkForce false;
      networking.hostName = "iso";

      systemd.user.services.replays.wantedBy = lib.mkForce [ ];

      systemd.user.services.opentabletdriver.wantedBy = lib.mkForce [ ];

      systemd.services.singbox.wantedBy = lib.mkForce [ ];

      warnings = lib.mkIf (!builtins.pathExists ../../stuff/singbox/config.json) [
        "singbox-wg module: config.json doesn't exist, singbox-wg WON'T be enabled."
      ];

      system.activationScripts = {

        repo = {

          # Run after /dev has been mounted
          deps = [ "specialfs" ];

          text = ''
            PATH="$PATH:${pkgs.gzip}/bin:${pkgs.coreutils-full}/bin:${pkgs.gnutar}/bin"
            mkdir /repo
            tar -xzvf ${../../stuff/repo.tar.gz} -C /repo
            rm /repo/stuff/nixpkgs.tar.zst
            cp -f "${../../stuff/nixpkgs.tar.zst}" /repo/stuff/nixpkgs.tar.zst
            chown root:root -R /repo
            cd /repo
            mkdir -p /etc/nixos
            cp -r ./machines ./stuff ./modules ./flake.nix ./flake.lock /etc/nixos
          '';

        };

        singbox = lib.mkIf (builtins.pathExists ../../stuff/singbox/config.json && wrapped) {

          deps = [ "specialfs" ];

          text = ''
            PATH="$PATH:${pkgs.coreutils}/bin"
            cp ${../../stuff/singbox/config.json} /config.json
            chmod 400 /config.json
          '';

        };

      };

      boot.kernel.sysctl."vm.swappiness" = 200;

      services.ollama.enable = lib.mkForce false;

      graphics.amdgpu.pro = lib.mkForce false;

      disks.enable = lib.mkForce false;

      my-services.cloudflare-ddns.enable = lib.mkForce false;

      my-services.nginx.enable = lib.mkForce false;

      cape.enable = lib.mkForce false;

      boot.loader.timeout = lib.mkForce 10;

      boot.initrd.systemd.enable = lib.mkForce false;

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
    })
    {
      nixpkgs.hostPlatform = "x86_64-linux";
      hardware.enableAllHardware = true;
      hardware.enableRedistributableFirmware = true;
      graphics.nvidia.enable = lib.mkForce true;
    }
  ];
}
