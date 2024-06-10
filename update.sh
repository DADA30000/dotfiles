#!/usr/bin/env bash
if [ -f ./check ]; then
  rm -rf ./nixos/*
  cp -r /etc/nixos/* ./nixos
  rm ./nixos/hardware-configuration.nix
  git add . --all
  git commit -m "almost fully switched to nix"
  git push -u
  ( cd ~/.mozilla; ./update.sh )
  #rclone sync -v /fileserver/Music google:Music
fi
