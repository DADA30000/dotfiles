#!/usr/bin/env bash
if [ -f ./check ]; then
  mkdir nixos
  rm -rf ./nixos/*
  rm ./flake.nix
  rm ./flake.lock
  cp -r /etc/nixos/nixos ./
  cp /etc/nixos/flake.{lock,nix} .
  git add . --all
  git commit -m "iso update"
  git push -u
else
  echo "change your working directory to dotfiles already"
fi
