#!/usr/bin/env bash
if [ -f ./check ]; then
  sudo mv /etc/nixos/stuff/singbox/config.json /tmp/config-aaaa
  git pull
  sudo rm -rf /etc/nixos/*
  rm ./stuff/repo.tar.gz
  ./complete.sh
  sudo cp -r ./machines ./modules ./stuff ./flake.lock ./flake.nix /etc/nixos/
  sudo rm -rf /etc/nixos/stuff/nixpkgs.tar.zst.part*
  sudo mv /tmp/config-aaaa /etc/nixos/stuff/singbox/config.json
  echo "Файлы успешно скопированы"
else
  echo "change your working directory to dotfiles already"
fi
