#!/usr/bin/env bash
main() {
  local disk_system="" disk_games="" bootpart="" usertemp="nixos" partitioned=true passtemp="" host="nixos"
  ./complete.sh
  clear
  if gum confirm --default=true "Использовать встроенное в скрипт разделение диска на разделы? (Использует весь диск, если нажать нет, будет открыт GParted с инструкциями)"; then
    echo -e "\e[34mВыберите диск на котором будет расположена \e[4;34mСИСТЕМА\e[0m"
    echo -e "\e[32mСовет: вы всегда можете перезапустить скрипт нажав Ctrl+C (желательно не во время этапа установки)\e[0m"
    fdisk -l | grep -i -E "^(Диск|Disk|/)"
    echo
    disk_system=$(fdisk -l | grep -i -E "^Диск" | gum choose | grep -oE '/[^[:space:]]*:' | sed 's/\://g')
    clear
    if gum confirm --default=false "Настроить дополнительный диск? (Он будет смонтирован/расположен в /home/пользователь/Games и так же будет ОТФОРМАТИРОВАН, настраивать его НЕОБЯЗАТЕЛЬНО)"; then
      echo -e "\e[34mВыберите диск, который будет использоваться как \e[4;34mДОПОЛНИТЕЛЬНЫЙ ДИСК\e[0m"
      disk_games=$(fdisk -l | grep -i -E "^Диск" | gum choose | grep -oE '/[^[:space:]]*:' | sed 's/\://g')
    fi
    clear
    if gum confirm --default=false "Установить /boot на другой раздел?"; then
      fdisk -l
      printf "Введите полный путь до раздела: "
      read -r bootpart
    fi
    partitioned=false
  else
    echo -e "Сейчас будет открыт GParted
  \e[32mВ нём вам нужно будет создать 4 раздела, названия меток должны полностью совпадать, в том числе регистр: 
    1. Для загрузочного раздела (FAT32, 1 GiB) с меткой (label) boot.
    2. Для раздела подкачки (swap) (половина от оперативки, не больше 16 GiB) с меткой (label) swap.
    3. Для остальных файлов и системы (BTRFS, размер не меньше 40 GiB, желательно 100 GiB) с меткой (label) nixos. 
    4. Опциональный. Этот раздел будет смонтирован в /home/пользователь/Games (BTRFS, размер не важен), с меткой (label) Games.
  Все 4 раздела могут быть на разных дисках. В скобках рекомендуемый размер.\e[0m
  Нажмите Enter для продолжения."
    read -r
    sudo -E gparted
    partitioned=true
  fi
  if [[ "$1" != "offline" ]]; then
    if gum confirm --default=false "Изменить имя пользователя и пароль?"; then
      echo "Введите пароль"
      passtemp=$(mkpasswd)
      echo "Введите имя пользователя"
      read -r usertemp
      sed -i 's|user = ".*";|user = "'"${usertemp}"'";|' ./flake.nix
      sed -i 's|user-hash = ".*";|user-hash = "'"${passtemp}"'";|' ./flake.nix
    fi
    if gum confirm --default=false "Отредактировать файл конфигурации?"; then
      nvim ./machines/nixos/configuration.nix
    fi
    host="nixos"
    if gum confirm --default=false "Изменить имя хоста в flake.nix для установки (по умолчанию nixos)?"; then
      host=$(gum input --header="Имя хоста" --placeholder="Вводи сцука" --no-show-help)
    fi
  fi
  if ! $partitioned; then
    if [[ -n "$disk_games" ]]; then
      echo "Вы хотите установить СИСТЕМУ на $disk_system, и использовать в качестве ДОПОЛНИТЕЛЬНОГО ДИСКА $disk_games (предупреждение: он отформатируется)"
    else
      echo "Вы хотите установить СИСТЕМУ на $disk_system"
    fi
    if gum confirm "Отформатировать выбранные разделы?" && gum confirm "Всё верно?"; then
      echo -e "\n\e[34mРазметка дисков...\n"
      if [[ -n "$bootpart" ]] && [[ -n "$disk_system" ]]; then
        echo "
          label: gpt
          size=8G, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=\"swap\"
          type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=\"nixos\"
        " | sfdisk "$disk_system"
      elif [[ -n "$disk_system" ]]; then
        echo "
          label: gpt
          size=1G, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=\"boot\"
          size=8G, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=\"swap\"
          type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=\"nixos\"
        " | sfdisk "$disk_system"
      fi
      udevadm settle
      if [[ -n "$disk_games" ]]; then
        echo "
          label: gpt
          type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
        " | sfdisk "$disk_games"
      fi
      if [[ -n "$disk_system" ]]; then
        echo -e "\n\e[34mФорматирование разделов...\e[0m\n"
        if [[ "$(echo "$disk_games" | grep -c nvme)" -eq 1 ]]; then
          disk_games="${disk_games}p"
        fi
        if [[ "$(echo "$disk_system" | grep -c nvme)" -eq 1 ]]; then
          disk_system="${disk_system}p"
        fi
        if [ -n "$disk_games" ]; then
          mkfs.btrfs -f -L Games "${disk_games}1"
        fi
        if [[ -n "$bootpart" ]]; then
          mkfs.btrfs -f -L nixos "${disk_system}2"
          mkswap -L swap "${disk_system}1"
          mkfs.fat -n boot -F 32 "${bootpart}"
        else
          mkfs.btrfs -f -L nixos "${disk_system}3"
          mkswap -L swap "${disk_system}2"
          mkfs.fat -n boot -F 32 "${disk_system}1"
        fi
      fi
    fi
  fi
  echo -e "\n\e[34mМонтирование разделов...\e[0m\n"
  if [[ -n "$disk_games" ]]; then
    mkdir /mnt1
    mount "${disk_games}1" /mnt1
    btrfs subvolume create /mnt1/games
    umount /mnt1
    rmdir /mnt1
  fi
  mkdir -p /mnt
  mount /dev/disk/by-label/nixos /mnt
  btrfs subvolume create /mnt/root
  btrfs subvolume create /mnt/home
  btrfs subvolume create /mnt/nix
  btrfs subvolume create /mnt/persistent
  umount /mnt
  mount -o compress-force=zstd,subvol=root /dev/disk/by-label/nixos /mnt
  mkdir /mnt/{home,nix,persistent}
  mount -o compress-force=zstd,subvol=home /dev/disk/by-label/nixos /mnt/home
  mount -o compress-force=zstd,subvol=persistent /dev/disk/by-label/nixos /mnt/persistent
  mount -o compress-force=zstd,noatime,subvol=nix /dev/disk/by-label/nixos /mnt/nix
  mkdir /mnt/boot
  mount /dev/disk/by-label/boot /mnt/boot
  swapon /dev/disk/by-label/swap
  clear
  echo "Начинается установка, откиньтесь на спинку кресла и наслаждайтесь видом :)" | lolcat
  sleep 2
  echo -e "\n\e[34mУстановка системы...\e[0m\n"
  mkdir -p /mnt/etc/nixos
  rm -rf /mnt/etc/nixos/*
  rm ./machines/nixos/hardware-configuration.nix
  nixos-generate-config --no-filesystems --root /mnt
  find /mnt/etc/nixos ! -name 'hardware-configuration.nix' -type f -exec rm -rf {} +
  cp -r ./machines ./stuff ./modules flake.{nix,lock} /mnt/etc/nixos
  mv /mnt/etc/nixos/hardware-configuration.nix /mnt/etc/nixos/machines/nixos/
  mkdir /mnt/persistent/etc
  cp -r /mnt/etc/nixos /mnt/persistent/etc
  if [[ "$1" == "offline" ]]; then
    until install-offline; do
      echo "Игнорируйте эту ошибку, она ничего не значит, просто ждите :)"
    done
    printf "\e[32mУстановка завершена, перезагрузка через 10 секунд... (Ctrl+C для отмены)\e[0m\n"
    for i in {1..9}; do
      sleep 0.25
      printf "%s" "$i"
      sleep 0.25
      printf "."
      sleep 0.25
      printf "."
      sleep 0.25
      printf "."
    done
    sleep 0.25
    printf "10\n"
    reboot
  else
    if nixos-install -v --flake "/mnt/etc/nixos#${host}" --impure; then
      printf "\e[32mУстановка завершена, перезагрузка через 10 секунд... (Ctrl+C для отмены)\e[0m\n"
      for i in {1..9}; do
        sleep 0.25
        printf "%s" "$i"
        sleep 0.25
        printf "."
        sleep 0.25
        printf "."
        sleep 0.25
        printf "."
      done
      sleep 0.25
      printf "10\n"
      reboot
    else
      printf "\e[31mОшибка установки :(\e[0m\n"
    fi
  fi
}
if [[ -f ./check ]]; then
  trap 'echo -e "\n\e[31mПрервано пользователем\e[0m"; exit 1' INT
  main "$@"
else
  echo "change your working directory to dotfiles"
fi
