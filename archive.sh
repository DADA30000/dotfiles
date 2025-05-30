#!/usr/bin/env bash
if [ -f ./check ]; then
  git rm ./stuff/repo.tar.gz
  rm ./stuff/repo.tar.gz
  tar --exclude=repo.tar.gz --exclude=*.mp4 -czvf ./stuff/repo.tar.gz ./check ./flake.lock ./flake.nix ./machines ./modules ./pull.sh ./README.md ./screenshot.png ./start.sh ./stuff ./update.sh ./archive.sh
else
  echo "change your working directory to dotfiles already"
fi
