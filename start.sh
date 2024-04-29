#!/usr/bin/env bash
if [ -f ./check ]; then
  git clone https://github.com/DADA30000/mozilla.git ~/.mozilla
  sudo rm /etc/nixos/configuration.nix
  sudo rm /etc/nixos/flake.nix
  sudo rm /etc/nixos/flake.lock
  sudo cp ./nixos/* /etc/nixos
  mkdir ~/.config
  sudo touch /password
  ( echo "Введите пароль Nextcloud"; read; sudo chmod 777 /password; echo $REPLY >> /password; sudo chown nextcloud:nextcloud /password; sudo chmod 400 /password )
  stow .
  sudo mkdir /fileserver
  git remote add origin https://github.com/DADA30000/dotfiles.git
  git config --global credential.helper store
  nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
  nix-channel --update
  sudo nixos-rebuild switch
  sudo chown -R nginx:nginx /fileserver
  mkdir ~/.mpd
  systemctl --user enable mpd
  xdg-user-dirs-update
fi
