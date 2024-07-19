{ pkgs, modulesPath, var, ... }:
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];
  nixpkgs.hostPlatform = "x86_64-linux";
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  networking.hostName = "iso";
  networking.networkmanager.enable = true;
  time.timeZone = "Europe/Moscow";
  i18n.defaultLocale = "ru_RU.UTF-8";
  nixpkgs.config.allowUnfree = true;
  boot.kernelPackages = pkgs.linuxPackages_xanmod_latest;
  environment.systemPackages = with pkgs; [
    git
    gum
    neovim
    btrfs-progs
    (writeShellScriptBin "nix-install" ''
      #!/usr/bin/env bash
      sudo -i
      clear
      echo "Проверка наличия соединения с интернетом..."
      if ! nc -zw1 google.com 443 > /dev/null 2>&1; then
        echo "Соединение не установлено :("
        if gum confirm "Настроить подключение?"; then
          nmtui
	  if ! nc -zw1 google.com 443 > /dev/null 2>&1; then
	    echo "Соединение не было установлено, перезапуск..."
	    sleep 2;
	    exec nix-install
	  fi
	fi
      fi
      echo "Соединение установлено!"
      sleep 2
      url="https://github.com/DADA30000/dotfiles"
      clear
      if gum confirm --default=false "Поменять URL репозитория с файлами конфигурации?"; then
        url=$(gum input --placeholder "Пример: https://github.com/DADA30000/dotfiles")
      fi
      clear
      echo -e "\e[34mВыберите диск на котором будет расположена \e[4;34mСИСТЕМА\e[0m"
      echo -e "\e[32mСовет: вы всегда можете перезапустить скрипт нажав Ctrl+C (желательно не во время этапа установки)\e[0m"
      sudo fdisk -l | grep -i -E "^(Диск|Disk|/)"; echo;
      disk_system=$(sudo fdisk -l | grep -i -E "^Диск" | gum choose | grep -oE '/[^[:space:]]*:' | sed 's/\://g')
      clear
      if gum confirm --default=false "Настроить дополнительный диск? (Он будет смонтирован/расположен в /home/пользователь/Games и так же будет ОТФОРМАТИРОВАН, настраивать его НЕОБЯЗАТЕЛЬНО)"; then
        echo -e "\e[34mВыберите диск, который будет использоваться как \e[4;34mДОПОЛНИТЕЛЬНЫЙ ДИСК\e[0m"
	disk_games=$(sudo fdisk -l | grep -i -E "^Диск" | gum choose | grep -oE '/[^[:space:]]*:' | sed 's/\://g')
      fi
      clear
      if [ -n "$disk_games" ]; then
        echo "Вы хотите установить СИСТЕМУ на $disk_system, и использовать в качестве ДОПОЛНИТЕЛЬНОГО ДИСКА $disk_games (предупреждение: он отформатируется)"
      else
        echo "Вы хотите установить СИСТЕМУ на $disk_system"
      fi
      if gum confirm "Всё верно?"; then
        echo "Начинается установка, откиньтесь на спинку кресла и наслаждайтесь видом :)" | clolcat
	echo "Разметка дисков..."
	echo "label: gpt" | sudo sfdisk "$disk_system"
	echo "start=        2048, size=     1048576, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B" | sudo sfdisk "$disk_system"
	echo "start=     1050624, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4" | sudo sfdisk "$disk_system"
	if [ -n "$disk_games" ]; then
	  echo "label: gpt" | sudo sfdisk "$disk_games"
	  echo "type=0FC63DAF-8483-4772-8E79-3D69D8477DE4" | sudo sfdisk "$disk_games"
	fi
	echo "Форматирование и монтирование разделов..."
	sudo mkdir -p /mnt
	if [ $(echo "$disk_system" | grep -c nvme) -eq 1 ]; then
	  sudo mkfs.fat -n boot -F 32 "''${disk_system}p1"
	  sudo mkfs.btrfs -L nixos "''${disk_system}p2"
	  sudo mount "''${disk_system}p2" /mnt
	  sudo btrfs subvolume create /mnt/root
	  sudo btrfs subvolume create /mnt/home
	  sudo btrfs subvolume create /mnt/nix
	  sudo umount /mnt
	  sudo mount -o compress-force=zstd,subvol=root "''${disk_system}p2" /mnt
	  sudo mkdir /mnt/{home,nix}
	  sudo mount -o compress-force=zstd,subvol=home "''${disk_system}p2" /mnt/home
	  sudo mount -o compress-force=zstd,noatime,subvol=nix "''${disk_system}p2" /mnt/nix
	  sudo mkdir /mnt/boot
	  sudo mount "''${disk_system}p1" /mnt/boot
	else
	  sudo mkfs.fat -n boot -F 32 "''${disk_system}1"
	  sudo mkfs.btrfs -L nixos "''${disk_system}2"
	  sudo mount "''${disk_system}2" /mnt
	  sudo btrfs subvolume create /mnt/root
	  sudo btrfs subvolume create /mnt/home
	  sudo btrfs subvolume create /mnt/nix
	  sudo umount /mnt
	  sudo mount -o compress-force=zstd,subvol=root "''${disk_system}2" /mnt
	  sudo mkdir /mnt/{home,nix}
	  sudo mount -o compress-force=zstd,subvol=home "''${disk_system}2" /mnt/home
	  sudo mount -o compress-force=zstd,noatime,subvol=nix "''${disk_system}2" /mnt/nix
	  sudo mkdir /mnt/boot
	  sudo mount "''${disk_system}1" /mnt/boot
	fi
	if [ -n "$disk_games" ]; then
	  if [ $(echo "$disk_games" | grep -c nvme) -eq 1 ]; then
	    sudo mkdir /mnt1
	    sudo mkfs.btrfs -L Games "''${disk_games}p1"
	    sudo mount "''${disk_games}p1" /mnt1
	    sudo btrfs subvolume create /mnt1/games
	    sudo umount /mnt1
	    sudo rmdir /mnt1
	    sudo mkdir -p /mnt/home/${var.user}/Games
	  else
	    sudo mkdir /mnt1
	    sudo mkfs.btrfs -L Games "''${disk_games}1"
	    sudo mount "''${disk_games}1" /mnt1
	    sudo btrfs subvolume create /mnt1/games
	    sudo umount /mnt1
	    sudo rmdir /mnt1
	    sudo mkdir -p /mnt/home/${var.user}/Games
	  fi
	fi
	echo "Копирование файлов конфигурации..."
	sudo mkdir /mnt1
	sudo git clone "$url" /mnt1/dotfiles
	sudo mkdir -p /mnt/etc/nixos
	echo "Установка системы..."
	(cd /mnt1/dotfiles; ./start.sh)
	sudo rm -rf /mnt1
	echo "Установка завершена, перезагрузка через 10 секунд... (Ctrl+C для отмены)"
	sleep 10
	reboot
      fi

    '')
  ];
}
