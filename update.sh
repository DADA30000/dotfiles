#!/usr/bin/env bash
if [ -f ./check ]; then
  mkdir nixos
  rm -rf ./*
  cp -r /etc/nixos/. ./nixos
  rm ./nixos/hardware-configuration.nix
  git add . --all
  git commit -m "lil update"
  git push -u
else
  echo "change your working directory to dotfiles already"
fi
