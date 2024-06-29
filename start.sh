#!/usr/bin/env bash
if [ -f ./check ]; then
  sudo rm -r /etc/nixos/*
  sudo cp -r ./nixos/* /etc/nixos
  sudo nixos-rebuild -v switch
else
  echo "change your working directory to dotfiles"
fi
