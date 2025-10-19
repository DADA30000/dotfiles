#!/usr/bin/env bash
if [[ -f ./check ]]; then
  if [[ ! -f ./stuff/nixpkgs.tar.zst ]]; then
    cat stuff/nixpkgs.tar.zst.part* > ./stuff/nixpkgs.tar.zst
    git add ./stuff/nixpkgs.tar.zst
  fi
else
  echo "change your working directory to dotfiles already"
fi
