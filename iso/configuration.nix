{ pkgs, modulesPath, ... }:
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];
  nixpkgs.hostPlatform = "x86_64-linux";
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  networking.hostName = "iso";
  networking.networkmanager.enable = true;
  networking.wireless.enable = false;
  time.timeZone = "Europe/Moscow";
  i18n.defaultLocale = "ru_RU.UTF-8";
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    git
    gum
    neovim
    btrfs-progs
    lolcat
    openssl
    (writeShellScriptBin "nix-install" ''
      if [[ $EUID -ne 0 ]]; then
        exec sudo nix-install
      fi
      setfont cyr-sun16
      clear
      echo -e "\e[34mПроверка наличия соединения с интернетом...\e[0m"
      if ! nc -zw1 google.com 443 > /dev/null 2>&1; then
        echo -e "\e[31mСоединение не установлено :(\e[0m"
        if gum confirm "Настроить подключение?"; then
          nmtui
	  if ! nc -zw1 google.com 443 > /dev/null 2>&1; then
	    echo -e "\e[34mСоединение не было установлено, перезапуск...\e[0m"
	    sleep 2;
	    exec nix-install
	  fi
	fi
      fi
      echo -e "\e[32mСоединение установлено!\e[0m"
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
        if git clone "$url" /mnt2/dotfiles; then
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
    '')
  ];
}
