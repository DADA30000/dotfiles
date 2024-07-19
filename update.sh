#!/usr/bin/env bash
if [ -f ./check ]; then
  mkdir nixos
  rm -rf ./nixos ./iso ./flake.nix ./flake.lock
  cp -r /etc/nixos/* ./
  git add . --all
  git commit -m "iso update"
  git push -u
else
  echo "change your working directory to dotfiles already"
fi
