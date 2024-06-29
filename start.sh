#!/usr/bin/env bash
if [ -f ./check ]; then
  sudo find /mnt/etc/nixos ! -name 'hardware-configuration.nix' -type f -exec rm -rf {} +
  sudo cp -r ./nixos/* /mnt/etc/nixos
  sudo nixos-install --flake "/mnt/etc/nixos#nixosConfigurations.nixos"
else
  echo "change your working directory to dotfiles"
fi
