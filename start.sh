#!/usr/bin/env bash
if [ -f ./check ]; then
  git clone https://github.com/DADA30000/mozilla.git ~/.mozilla
  sudo rm /etc/nixos/*
  sudo cp ./nixos/* /etc/nixos
  mkdir ~/.config
  sudo touch /password
  ( echo "Введите пароль Nextcloud"; read; sudo chmod 777 /password; echo $REPLY >> /password; sudo chown nextcloud:nextcloud /password; sudo chmod 400 /password )
  stow .
  sudo mkdir /fileserver
  git config --global credential.helper store
  sudo nixos-rebuild switch
  sudo chown -R nginx:nginx /fileserver
  systemctl --user enable mpd
  xdg-user-dirs-update
fi
