#!/usr/bin/env bash
if [ -f ./check ]; then
  git lfs prune
  git rm ./stuff/nixpkgs.tar.zst
  rm ./stuff/nixpkgs.tar.zst
  rm -rf ./machines ./modules ./stuff ./flake.nix ./flake.lock
  cp -r /etc/nixos/* ./
  #rm ./stuff/singbox/config.json
  ./archive.sh
  git add . --all
  git add .gitattributes
  echo "Enter commit name (enter to default)"
  read -r name
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
