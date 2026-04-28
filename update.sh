#!/usr/bin/env bash
if [ -f ./check ]; then
  echo "Critical step, do not terminate script now"
  rm -rf ./machines ./modules ./stuff ./flake.nix ./flake.lock
  cp -r /etc/nixos/* ./
  ./archive.sh
  git add . --all
  echo "You can terminate now"
  printf "Enter commit name (enter to default): "
  read -r name
  if [ -n "$name" ]; then
    git commit -am "$name"
    git push
  else
    git commit -am "lil update"
    git push
  fi
else
  echo "change your working directory to dotfiles already"
fi
