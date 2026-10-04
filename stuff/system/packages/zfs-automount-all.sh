#!/usr/bin/env bash
set -euo pipefail
export PATH="/run/current-system/sw/bin:$PATH"

for dev in /dev/disk/by-label/*-encrypted; do
  [ -e "$dev" ] || continue
  label="$(basename "$dev")"
  name="${label%-encrypted}"

  [ "$name" = "nixos" ] && continue
  [ "$name" = "rpool" ] && continue

  key="/etc/credstore/$name.key"

  if [ -f "$key" ] && [ ! -e "/dev/mapper/$name" ]; then
    crypt_args=("--key-file" "$key")

    if [ "$(lsblk -n -d -o ROTATIONAL "$dev" 2>/dev/null)" = "0" ]; then
      crypt_args+=(
        "--allow-discards"
        "--perf-no_read_workqueue"
        "--perf-no_write_workqueue"
      )
    fi

    cryptsetup open "$dev" "$name" "${crypt_args[@]}" || true
  fi
done

importable_pools="$(zpool import -d /dev/mapper -d /dev/disk/by-label -d /dev/disk/by-id -d /dev 2>/dev/null | awk '/pool:/ {print $2}' || true)"

for pool in $importable_pools; do
  [ "$pool" = "nixos" ] && continue
  [ "$pool" = "rpool" ] && continue

  zpool import -d /dev/mapper -d /dev/disk/by-label -d /dev/disk/by-id -d /dev -N -f "$pool" || true
done

for pool in $(zpool list -H -o name 2>/dev/null || true); do
  [ "$pool" = "nixos" ] && continue
  [ "$pool" = "rpool" ] && continue

  mkdir -p "/mnt/$pool"
  if ! mountpoint -q "/mnt/$pool"; then
    mount -t zfs "$pool/data" "/mnt/$pool" 2>/dev/null || mount -t zfs "$pool" "/mnt/$pool" 2>/dev/null || zfs mount "$pool" 2>/dev/null || true
  fi

  chmod 1777 "/mnt/$pool" 2>/dev/null || true

  for u in $(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd); do
    mkdir -p "/mnt/$pool/$u"
    chown "$u:users" "/mnt/$pool/$u"
    chmod 0700 "/mnt/$pool/$u"
  done
done
