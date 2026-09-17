OVMF='%{{{pkgs.OVMF.fd}}}'
qemu-system-x86_64 \
  -bios "$OVMF/FV/OVMF.fd" \
  "$@"
