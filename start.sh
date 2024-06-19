#!/usr/bin/env bash
if [ -f ./check ] &; then
  #git clone https://github.com/DADA30000/mozilla.git ~/.mozilla
  sudo rm -r /etc/nixos/*
  sudo cp -r ./nixos/* /etc/nixos
  mkdir ~/.config
  #sudo touch /password
  #( echo "Введите пароль Nextcloud"; read; sudo chmod 777 /password; echo $REPLY >> /password; sudo chown nextcloud:nextcloud /password; sudo chmod 400 /password )
  #sudo mkdir /fileserver
  git config --global credential.helper store
  sudo nixos-rebuild switch
  sudo chown -R nginx:nginx /fileserver
else
  echo "change your working directory to dotfiles"
fi
