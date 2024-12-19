#!/usr/bin/env bash
if [ -f ./check ]; then
  rm -rf ./machines ./modules ./stuff ./flake.nix ./flake.lock
  cp -r /etc/nixos/* ./
  rm ./stuff/singbox/config.json
  ./archive.sh
  git add . --all
  git add .gitattributes
  echo "Enter commit name (enter to default)"
  read name
  if [ -n "$name" ]; then
    git commit -m "$name"
    git push -u
  else
    git commit -m "lil update"
    git push -u
  fi
else
  echo "change your working directory to dotfiles already"
fi
