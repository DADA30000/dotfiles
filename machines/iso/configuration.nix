{
  pkgs,
  inputs,
  lib,
  user,
  user_iso,
  ...
}:
let
  nix-install = ''
    if [[ $EUID -ne 0 ]]; then
      exec sudo nix-install
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
  orig = inputs.self.outputs.nixosConfigurations.nixos.config.users.users;
  users_without = lib.removeAttrs orig [ user ];
  imported = inputs.self.outputs.nixosConfigurations.nixos.config.users.users."${user}";
  changed = lib.mkMerge [ imported { hashedPassword = lib.mkForce null; initialPassword = lib.mkForce "1234"; }];
in
{
  home-manager.users."${user_iso}" = import ./home.nix;
  boot.supportedFilesystems.zfs = lib.mkForce false;
  nixpkgs.hostPlatform = "x86_64-linux";
  networking.wireless.enable = false;
  networking.hostName = "iso";
  imports = [
    ../../modules/system
    ../nixos/configuration.nix
  ];

  system.activationScripts = {

    repo = {

      # Run after /dev has been mounted
      deps = [ "specialfs" ];

      text = ''
        PATH=$PATH:${pkgs.gzip}/bin
        mkdir /repo
        ${pkgs.gnutar}/bin/tar -xzvf ${../../stuff/repo.tar.gz} -C /repo
        chown root:root -R /repo 
      '';

    };

  };

  users.users = lib.mkForce (
    users_without // { "${user_iso}" = changed; }
  );

  users.groups.nginx = {};
  
  nixpkgs.overlays = [
    (final: prev: {
      python313Packages.deal-solver = prev.python313Packages.deal-solver.overrideAttrs {
        disabledTests = [
          "test_expr_asserts_ok"
          "test_fuzz_math_floats"
          "test_timeout"
        ];
      };
    })
  ];

  disks.enable = lib.mkForce false;

  my-services.cloudflare-ddns.enable = lib.mkForce false;

  my-services.nginx.enable = lib.mkForce false;

  boot.loader.timeout = lib.mkForce 10;

  services.getty.autologinUser = lib.mkForce user;

  graphics.nvidia.enable = lib.mkForce true;

  boot.initrd.systemd.enable = lib.mkForce false;

  fonts.fontconfig.enable = true;

  xdg = {

    mime.enable = true;

    icons.enable = true;

    autostart.enable = true;

  };

  environment = {

    systemPackages =
      with pkgs;
      [
        gum
        lolcat
        openssl
        (writeShellScriptBin "nix-install" nix-install)
        (writeShellScriptBin "offline-install" "sudo nixos-install --system ${inputs.self.outputs.nixosConfigurations.nixos-offline.config.system.build.toplevel} $@")
      ]
      ++ (import ../../modules/system/stuff pkgs).scripts;

  };

}
