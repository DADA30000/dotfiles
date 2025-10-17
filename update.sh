#!/usr/bin/env bash
if [ -f ./check ]; then
  echo "Critical step, do not terminate script now"
  ./clean_prev.sh
  rm -rf ./machines ./modules ./stuff ./flake.nix ./flake.lock
  cp -r /etc/nixos/* ./
  split -b 45M -d -a 3 ./stuff/nixpkgs.tar.zst ./stuff/nixpkgs.tar.zst.part
  ./archive.sh
  ./complete.sh
  git add . --all
  git add .gitignore
  echo "You can terminate now"
  echo "Enter commit name (enter to default)"
  read -r name
  if [ -n "$name" ]; then
    git commit -m "$name"
    git push --set-upstream origin main -fu
  else
    git commit -m "lil update"
    git push --set-upstream origin main -fu
  fi
else
  echo "change your working directory to dotfiles already"
fi
