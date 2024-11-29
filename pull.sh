#!/usr/bin/env bash
if [ -f ./check ]; then
  sudo mv /etc/nixos/stuff/singbox/config /tmp/config-aaaa
  git pull
  sudo rm -rf /etc/nixos/*
  sudo cp -r ./machines ./modules ./stuff ./flake.lock ./flake.nix /etc/nixos/
  sudo mv /tmp/config-aaaa /etc/nixos/stuff/singbox/config
else
  echo "change your working directory to dotfiles already"
fi
