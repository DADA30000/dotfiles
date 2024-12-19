#!/usr/bin/env bash
if [ -f ./check ]; then
  sudo mv /etc/nixos/stuff/singbox/config.json /tmp/config-aaaa
  git pull
  sudo rm -rf /etc/nixos/*
  rm ./stuff/repo.tar.gz
  sudo cp -r ./machines ./modules ./stuff ./flake.lock ./flake.nix /etc/nixos/
  sudo mv /tmp/config-aaaa /etc/nixos/stuff/singbox/config.json
else
  echo "change your working directory to dotfiles already"
fi
