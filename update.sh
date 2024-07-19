#!/usr/bin/env bash
if [ -f ./check ]; then
  rm -rf ./nixos ./iso ./flake.nix ./flake.lock
  cp -r /etc/nixos/* ./
  git add . --all
  git commit -m "lil update"
  git push -u
else
  echo "change your working directory to dotfiles already"
fi
