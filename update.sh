#!/usr/bin/env bash
if [ -f ./check ]; then
  rm -rf ./nixos ./iso ./flake.nix ./flake.lock
  cp -r /etc/nixos/* ./
  git add . --all
  echo "Enter commit name"
  read name
  git commit -m "$name"
  git push -u
else
  echo "change your working directory to dotfiles already"
fi
