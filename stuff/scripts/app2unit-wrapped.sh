#!/usr/bin/env bash
# Custom app2unit launcher wrapper to normalize app names for systemd units.
# Extracted from your Hyprland rofi configuration in `/etc/nixos/modules/home/hyprland/default.nix`.
#
# It inspects the exec arguments, skips any leading environment variables (e.g. FOO=bar),
# extracts the clean binary name (stripping Nix hash paths, dot-prefixes, and hex-escapes),
# and invokes `app2unit -a "$n" -- "$@"`.

for arg; do
  case "$arg" in
  *=*)
    ;;
  *)
    exec_path="$arg"
    break
    ;;
  esac
done

n=$(basename "$exec_path" 2>/dev/null | sed -e 's/\\x2d/-/g' -e 's/^\.//' | tr -cd "[:alnum:]. _-")

if [[ -n "$n" ]]; then
  exec app2unit -a "$n" -- "$@"
else
  exec app2unit -- "$@"
fi
