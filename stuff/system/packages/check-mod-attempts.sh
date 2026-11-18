#!/usr/bin/env bash
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

real_mods=()
other_mods=()

while IFS=$'\t' read -r cnt mod ts; do
  [[ -z "$mod" ]] && continue

  if [[ "$mod" == \[* ]]; then
    real_mods+=("$(printf "%s [x%s] (last: %s)" "$mod" "$cnt" "$ts")")
    continue
  fi

  # Check if mod or modalias resolves to an actual kernel module
  resolved=$(modprobe -R "$mod" 2>/dev/null | head -n 1 || true)
  if [[ -n "$resolved" ]] && modinfo "$resolved" &>/dev/null; then
    if [[ "$resolved" != "$mod" ]]; then
      real_mods+=("$(printf "%s (%s) [x%s] (last: %s)" "$mod" "$resolved" "$cnt" "$ts")")
    else
      real_mods+=("$(printf "%s [x%s] (last: %s)" "$mod" "$cnt" "$ts")")
    fi
  elif modinfo "$mod" &>/dev/null; then
    real_mods+=("$(printf "%s [x%s] (last: %s)" "$mod" "$cnt" "$ts")")
  else
    other_mods+=("$(printf "%s [x%s] (last: %s)" "$mod" "$cnt" "$ts")")
  fi
done < <(
  journalctl -b -t mod-autoload -o short-iso --no-pager 2>/dev/null | awk '
    /mod_autoload:/ {
      ts = $1
      sub(/T/, " ", ts); sub(/\+.*$/, "", ts)
      fmt = ""; s1 = ""; a1 = 0; a2 = 0; a3 = 0
      if (match($0, /fmt="[^"]+"/)) fmt = substr($0, RSTART + 5, RLENGTH - 6)
      if (match($0, /s1="[^"]+"/))  s1  = substr($0, RSTART + 4, RLENGTH - 5)
      if (match($0, /a1=[0-9]+/))   a1  = substr($0, RSTART + 3, RLENGTH - 3) + 0
      if (match($0, /a2=[0-9]+/))   a2  = substr($0, RSTART + 3, RLENGTH - 3) + 0
      if (match($0, /a3=[0-9]+/))   a3  = substr($0, RSTART + 3, RLENGTH - 3) + 0

      if (fmt ~ /%s/ && s1 != "") {
        sub(/%s/, s1, fmt)
      }
      if (fmt ~ /%[di]/) {
        sub(/%[di]/, a1, fmt)
        sub(/%[di]/, a2, fmt)
        sub(/%[di]/, a3, fmt)
      }
      if (fmt != "") {
        count[fmt]++
        last[fmt] = ts
      }
    }

    /mod_sys_(f)?init:/ {
      ts = $1
      sub(/T/, " ", ts); sub(/\+.*$/, "", ts)
      proc = $4
      sub(/-[0-9]+$/, "", proc)
      sc = ($0 ~ /mod_sys_finit:/) ? "finit_module" : "init_module"
      key = "[SYSCALL:" sc " by " proc "]"
      count[key]++
      last[key] = ts
    }

    END {
      for (k in count) {
        printf "%d\t%s\t%s\n", count[k], k, last[k]
      }
    }
  ' | sort -rn
)

echo "=== REAL KERNEL MODULES / SYSCALLS ==="
if [[ ${#real_mods[@]} -eq 0 ]]; then
  echo "(none)"
else
  printf "%s\n" "${real_mods[@]}"
fi

echo ""
echo "=== NON-EXISTENT / INTERFACE LOOKUPS ==="
if [[ ${#other_mods[@]} -eq 0 ]]; then
  echo "(none)"
else
  printf "%s\n" "${other_mods[@]}"
fi
