#!/usr/bin/env bash

DISKS_FILE="./modules/system/disks/default.nix"

main() {
  local disk_system="" usertemp="nixos" passtemp="" host="nixos" offline_mode=false

  if [[ "$1" == "offline" ]]; then
    offline_mode=true
    echo -e "\e[32mЗапуск в ОФФЛАЙН режиме\e[0m"
    sleep 1
  fi

  clear

  echo -e "\e[34mВыберите диск на котором будет расположена \e[4;34mСИСТЕМА\e[0m"
  echo -e "\e[32mСовет: вы всегда можете перезапустить скрипт нажав Ctrl+C\e[0m"
  fdisk -l | grep -i -E "^(Диск|Disk) /"
  echo

  disk_system=$(fdisk -l | grep -i -E "^(Диск|Disk) /" | gum choose | grep -oE '/dev/[^:]*')
  clear

  if gum confirm --default=true "Использовать шифрование (LUKS)?"; then
    echo -e "\e[33mВНИМАНИЕ: Убедитесь, что в конфигурации включено 'disks.encryption = true;'\e[0m"
    while true; do
      luks_pass=$(gum input --password --header="Введите пароль для шифрования диска")
      luks_pass2=$(gum input --password --header="Повторите пароль")
      if [[ "$luks_pass" == "$luks_pass2" ]]; then
        if [[ -n "$luks_pass" ]]; then
          break
        else
          echo -e "\e[31mПароль не может быть пустым!\e[0m"
        fi
      else
        echo -e "\e[31mПароли не совпадают, попробуйте снова.\e[0m"
      fi
    done
    echo -n "$luks_pass" >/tmp/secret.key
  else
    echo -e "\e[33mВНИМАНИЕ: Убедитесь, что в конфигурации установлено 'disks.encryption = false;'\e[0m"
    echo -n "dummy" >/tmp/secret.key
  fi
  clear

  if gum confirm --default=false "Изменить имя пользователя и пароль?"; then
    echo "Введите пароль пользователя"
    passtemp=$(mkpasswd -m sha-512)
    echo "Введите имя пользователя"
    read -r usertemp
    sed -i 's|user = ".*";|user = "'"${usertemp}"'";|' ./flake.nix
    sed -i 's|user-hash = ".*";|user-hash = "'"${passtemp}"'";|' ./flake.nix
  fi

  if gum confirm --default=false "Отредактировать файл конфигурации? (Тут можно включить/выключить шифрование)"; then
    nvim ./machines/nixos/configuration.nix
  fi

  if gum confirm --default=false "Изменить имя хоста в flake.nix (по умолчанию nixos)?"; then
    host=$(gum input --header="Имя хоста" --placeholder="nixos" --no-show-help)
  fi

  echo -e "Вы выбрали установку СИСТЕМЫ на \e[33m$disk_system\e[0m"
  if gum confirm "Отформатировать диск и начать установку? (ВНИМАНИЕ: ВСЕ ДАННЫЕ БУДУТ УДАЛЕНЫ!)"; then

    echo -e "\n\e[34mРазметка и форматирование диска через Disko...\e[0m\n"

    cp "$DISKS_FILE" "${DISKS_FILE}.bak"
    sed -i "s|/dev/INSTALLER_DISK_REPLACE|$disk_system|g" "$DISKS_FILE"

    if ! sudo disko --mode disko --flake ".#${host}"; then
      echo -e "\e[31mОшибка при выполнении Disko. Восстанавливаю конфигурацию...\e[0m"
      mv "${DISKS_FILE}.bak" "$DISKS_FILE"
      rm -f /tmp/secret.key
      exit 1
    fi

    mv "${DISKS_FILE}.bak" "$DISKS_FILE"

    clear
    echo "Начинается установка, откиньтесь на спинку кресла и наслаждайтесь видом :)" | lolcat
    sleep 2
    echo -e "\n\e[34mКопирование файлов и установка системы...\e[0m\n"

    mkdir -p /mnt/etc/nixos
    nixos-generate-config --no-filesystems --root /mnt
    find /mnt/etc/nixos ! -name 'hardware-configuration.nix' -type f -exec rm -rf {} +

    cp -r ./machines ./stuff ./modules flake.{nix,lock} /mnt/etc/nixos
    mv /mnt/etc/nixos/hardware-configuration.nix /mnt/etc/nixos/machines/nixos/

    mkdir -p /mnt/persist/etc
    cp -r /mnt/etc/nixos /mnt/persist/etc

    INSTALL_CMD="nixos-install -v --flake /mnt/etc/nixos#${host} --impure"

    if [ "$offline_mode" = true ]; then
      INSTALL_CMD="$INSTALL_CMD --offline"
    fi

    if eval "$INSTALL_CMD"; then
      finish_install
    else
      printf "\e[31mОшибка установки :(\e[0m\n"
    fi
  fi
}

finish_install() {
  rm -f /tmp/secret.key

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
}

if [[ -f ./check ]]; then
  trap 'echo -e "\n\e[31mПрервано пользователем\e[0m"; rm -f /tmp/secret.key; [[ -f "${DISKS_FILE}.bak" ]] && mv "${DISKS_FILE}.bak" "$DISKS_FILE"; exit 1' INT
  main "$@"
else
  echo "change your working directory to dotfiles"
fi
