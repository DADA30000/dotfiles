#!/usr/bin/env bash
if [ -f ./check ]; then
  sudo nixos-generate-config --no-filesystems
  sudo find /mnt/etc/nixos ! -name 'hardware-configuration.nix' -type f -exec rm -rf {} +
  sudo rm ./nixos/hardware-configuration.nix
  sudo cp -r ./nixos flake.{nix,lock} /mnt/etc/nixos
  sudo nixos-install --flake "/mnt/etc/nixos#nixos"
  #sudo nixos-install --flake github:DADA30000/dotfiles#nixos
else
  echo "change your working directory to dotfiles"
fi

##!/usr/bin/env bash
#if [ -f ./check ] &; then
#  git clone https://github.com/DADA30000/mozilla.git ~/.mozilla
#  sudo touch /password
#  ( echo "Введите пароль Nextcloud"; read; sudo chmod 777 /password; echo $REPLY >> /password; sudo chown nextcloud:nextcloud /password; sudo chmod 400 /password )
#  sudo mkdir /fileserver
#  git config --global credential.helper store
#  sudo chown -R nginx:nginx /fileserver
#else
#  echo "change your working directory to dotfiles"
#fi
