#!/usr/bin/env bash
pkexec env DISPLAY=$DISPLAY WAYLAND_DISPLAY=$WAYLAND_DISPLAY XDG_SESSION_TYPE=$XDG_SESSION_TYPE XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR neovide -- -u ~/.config/nvim/init.vim /etc/nixos
