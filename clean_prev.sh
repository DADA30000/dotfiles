#!/usr/bin/env bash
if [ -f ./check ]; then
  git rm --cached ./stuff/nixpkgs.tar.zst.part*
  git commit --amend --no-edit
else
  echo "change your working directory to dotfiles already"
fi
