#!/usr/bin/env bash

DISKS_FILE="./modules/system/disks/default.nix"

main() {
  local disk_system="" usertemp="nixos" passtemp="" host="nixos"
  local disko_mode="online" system_mode="online" generate_sb_keys=false

  if [[ "$1" == "offline" ]]; then
    clear

    echo -e "\e[34m1. Выберите режим работы Disko (разметка диска):\e[0m"
    local disko_choice
    disko_choice=$(gum choose "1. Использовать готовый скрипт Disko из ISO (мгновенно, без сборки)" "2. Собрать Disko из Flake (динамическая оффлайн-эвалюация)")
    if [[ "$disko_choice" == 1* ]]; then
      disko_mode="prebuilt"
    else
      disko_mode="eval"
    fi

    clear
    echo -e "\e[34m2. Выберите режим установки системы (NixOS):\e[0m"
    local system_choice
    system_choice=$(gum choose "1. Использовать готовый образ системы из ISO (быстро, без сборки)" "2. Собрать систему из Flake (с учётом локальных правок)")
    if [[ "$system_choice" == 1* ]]; then
      system_mode="prebuilt"
    else
      system_mode="eval"
    fi

    clear
    echo -e "\e[32mВыбранные режимы: Disko -> $disko_mode | Система -> $system_mode\e[0m"
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
      if [[ "$luks_pass" == "$luks_pass2" ]] && [[ -n "$luks_pass" ]]; then
        break
      else
        echo -e "\e[31mПароли не совпадают или пустые, попробуйте снова.\e[0m"
      fi
    done
    echo -n "$luks_pass" >/tmp/secret.key
  else
    echo -e "\e[33mВНИМАНИЕ: Убедитесь, что в конфигурации установлено 'disks.encryption = false;'\e[0m"
    echo -n "dummy" >/tmp/secret.key
  fi
  clear

  if gum confirm --default=false "Сгенерировать новые ключи Secure Boot (sbctl)?"; then
    echo -e "\e[34mГенерация ключей Secure Boot...\e[0m"
    sudo rm -rf /var/lib/sbctl
    if sudo sbctl create-keys; then
      generate_sb_keys=true
      echo -e "\e[32mКлючи успешно сгенерированы!\e[0m"
    else
      echo -e "\e[31mОшибка генерации ключей sbctl.\e[0m"
    fi
    sleep 1
  fi
  clear

  if [[ "$system_mode" != "prebuilt" || "$disko_mode" != "prebuilt" ]]; then
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
  fi

  echo -e "Вы выбрали установку СИСТЕМЫ на \e[33m$disk_system\e[0m"
  if gum confirm "Отформатировать диск и начать установку? (ВНИМАНИЕ: ВСЕ ДАННЫЕ БУДУТ УДАЛЕНЫ!)"; then

    echo -e "\n\e[34mРазметка и форматирование диска через Disko...\e[0m\n"

    if [[ "$disko_mode" == "prebuilt" ]]; then
      cp /etc/disko-format-script/bin/disko-destroy-format-mount /tmp/disko-script.sh
      chmod +x /tmp/disko-script.sh
      sed -i "s|/dev/INSTALLER_DISK_REPLACE|$disk_system|g" /tmp/disko-script.sh

      if ! sudo /tmp/disko-script.sh --yes-wipe-all-disks; then
        echo -e "\e[31mОшибка выполнения готового скрипта Disko.\e[0m"
        rm -f /tmp/secret.key /tmp/disko-script.sh
        exit 1
      fi
      rm -f /tmp/disko-script.sh

    elif [[ "$disko_mode" == "eval" ]]; then
      cp "$DISKS_FILE" "${DISKS_FILE}.bak"
      sed -i "s|/dev/INSTALLER_DISK_REPLACE|$disk_system|g" "$DISKS_FILE"

      if ! nix build ".#nixosConfigurations.${host}.config.system.build.destroyFormatMount" --offline --keep-going -o /tmp/disko-script; then
        echo -e "\e[31mОшибка сборки Disko.\e[0m"
        mv "${DISKS_FILE}.bak" "$DISKS_FILE"
        rm -f /tmp/secret.key
        exit 1
      fi
      if ! sudo /tmp/disko-script/bin/disko-destroy-format-mount --yes-wipe-all-disks; then
        echo -e "\e[31mОшибка выполнения Disko.\e[0m"
        mv "${DISKS_FILE}.bak" "$DISKS_FILE"
        rm -f /tmp/secret.key
        exit 1
      fi
      mv "${DISKS_FILE}.bak" "$DISKS_FILE"

    else
      cp "$DISKS_FILE" "${DISKS_FILE}.bak"
      sed -i "s|/dev/INSTALLER_DISK_REPLACE|$disk_system|g" "$DISKS_FILE"

      if ! sudo disko --mode destroy,format,mount --flake ".#${host}"; then
        echo -e "\e[31mОшибка при выполнении Disko.\e[0m"
        mv "${DISKS_FILE}.bak" "$DISKS_FILE"
        rm -f /tmp/secret.key
        exit 1
      fi
      mv "${DISKS_FILE}.bak" "$DISKS_FILE"
    fi

    clear
    echo "Начинается установка, откиньтесь на спинку кресла и наслаждайтесь видом :)" | lolcat
    sleep 2
    echo -e "\n\e[34mКопирование файлов и подготовка системы...\e[0m\n"

    mkdir -p /mnt/etc/nixos
    nixos-generate-config --no-filesystems --root /mnt
    find /mnt/etc/nixos ! -name 'hardware-configuration.nix' -type f -exec rm -rf {} +

    cp -r ./machines ./stuff ./modules flake.{nix,lock} /mnt/etc/nixos
    mv /mnt/etc/nixos/hardware-configuration.nix /mnt/etc/nixos/machines/nixos/

    mkdir -p /mnt/persist/etc
    cp -r /mnt/etc/nixos /mnt/persist/etc

    if [[ "$generate_sb_keys" == true || -d /var/lib/sbctl ]]; then
      if [[ -n "$(ls -A /var/lib/sbctl 2>/dev/null)" ]]; then
        echo -e "\e[34mКопирование ключей Secure Boot в /mnt и /persist...\e[0m"
        mkdir -p /mnt/var/lib/sbctl /mnt/persist/var/lib/sbctl
        cp -a /var/lib/sbctl/. /mnt/var/lib/sbctl/
        cp -a /var/lib/sbctl/. /mnt/persist/var/lib/sbctl/
      fi
    fi

    local install_successful=false
    while [[ "$install_successful" == false ]]; do
      echo -e "\n\e[34mЗапуск установки системы...\e[0m\n"

      if [[ "$system_mode" == "prebuilt" ]]; then
        INSTALL_CMD="nixos-install -v --system /etc/nixos-toplevel-reference --no-channel-copy --keep-going"

      elif [[ "$system_mode" == "eval" ]]; then
        echo -e "\e[34mСборка системы (Оффлайн-эвалюация)...\e[0m"
        if ! nix build "/mnt/etc/nixos#nixosConfigurations.${host}.config.system.build.toplevel" --offline --keep-going -o /mnt/toplevel; then
          echo -e "\e[31mОшибка оффлайн-сборки toplevel!\e[0m"
          INSTALL_CMD="false"
        else
          INSTALL_CMD="nixos-install -v --system /mnt/toplevel --no-channel-copy --keep-going"
        fi

      else
        INSTALL_CMD="nixos-install -v --flake /mnt/etc/nixos#${host} --keep-going"
      fi

      if [[ "$INSTALL_CMD" != "false" ]] && eval "$INSTALL_CMD"; then
        install_successful=true
        finish_install
      else
        echo -e "\n\e[31mОшибка установки :(\e[0m"
        if gum confirm --default=true "Попробовать установить снова?"; then
          echo -e "\e[33mПовторная попытка...\e[0m"
        else
          echo -e "\e[31mУстановка прервана пользователем.\e[0m"
          rm -f /tmp/secret.key
          exit 1
        fi
      fi
    done
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

trap 'echo -e "\n\e[31mПрервано пользователем\e[0m"; rm -f /tmp/secret.key /tmp/disko-script.sh; [[ -f "${DISKS_FILE}.bak" ]] && mv "${DISKS_FILE}.bak" "$DISKS_FILE"; exit 1' INT

if [[ -f ./check ]]; then
  main "$@"
else
  echo "change your working directory to dotfiles"
fi
