#!/usr/bin/env bash
if [ -f ./check ]; then
  rm -rf ./nixos/*
  cp -r /etc/nixos/* ./nixos
  rm ./nixos/hardware-configuration.nix
  git add . --all
  git commit -m "another update"
  git push -u
fi
