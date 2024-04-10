#!/usr/bin/env bash
if [ -f ./check ]; then
  sudo rm /etc/nixos/configuration.nix
  sudo rm /etc/nixos/flake.nix
  sudo rm /etc/nixos/flake.lock
  sudo cp ./nixos/* /etc/nixos
  mkdir ~/.config
  stow .
  git remote add origin https://github.com/DADA30000/dotfiles.git
  git config --global credential.helper store
  nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
  nix-channel --update
  sudo nixos-rebuild switch
  mkdir ~/.mpd
  home-manager switch
  systemctl --user enable mpd
  xdg-user-dirs-update
fi
