set -euo pipefail
POOL="${1:-}"
if [ -z "$POOL" ]; then
  echo "Usage: sudo zfs-eject <pool-name>"
  exit 1
fi

echo "Ejecting pool: $POOL..."

for mp in $(zfs list -H -o mountpoint -r "$POOL" 2>/dev/null || true); do
  if [ -n "$mp" ] && [ "$mp" != "none" ] && [ "$mp" != "legacy" ] && mountpoint -q "$mp" 2>/dev/null; then
    umount "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null || true
  fi
done
if mountpoint -q "/mnt/$POOL" 2>/dev/null; then
  umount "/mnt/$POOL" 2>/dev/null || umount -l "/mnt/$POOL" 2>/dev/null || true
fi

if zpool list "$POOL" >/dev/null 2>&1; then
  zpool export "$POOL"
fi

if [ -e "/dev/mapper/$POOL" ]; then
  cryptsetup close "$POOL"
fi

echo "Successfully and safely ejected $POOL. You can now pull the cable."
