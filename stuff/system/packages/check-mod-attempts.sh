#!/usr/bin/env bash
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

real_mods=()
other_mods=()

while IFS=$'\t' read -r cnt item ts; do
  [[ -z "$item" ]] && continue

  mod="${item%%|*}"
  caller="${item#*|}"

  if [[ "$mod" == \[* ]]; then
    real_mods+=("$(printf "%s [by %s] [x%s] (last: %s)" "$mod" "$caller" "$cnt" "$ts")")
    continue
  fi

  # modinfo -F name resolves both module names and modaliases without calling modprobe!
  resolved=$(modinfo -F name "$mod" 2>/dev/null | head -n 1 || true)
  if [[ -n "$resolved" ]]; then
    if [[ "$resolved" != "$mod" ]]; then
      real_mods+=("$(printf "%s (%s) [by %s] [x%s] (last: %s)" "$mod" "$resolved" "$caller" "$cnt" "$ts")")
    else
      real_mods+=("$(printf "%s [by %s] [x%s] (last: %s)" "$mod" "$caller" "$cnt" "$ts")")
    fi
  else
    other_mods+=("$(printf "%s [by %s] [x%s] (last: %s)" "$mod" "$caller" "$cnt" "$ts")")
  fi
done < <(
  journalctl -b -t mod-autoload -o short-iso --no-pager 2>/dev/null | awk '
    /mod_autoload:/ {
      ts = $1
      sub(/T/, " ", ts); sub(/\+.*$/, "", ts)
      caller = "unknown"; fmt = ""; s1 = ""; a1 = 0; a2 = 0; a3 = 0
      if (match($0, /caller="[^"]+"/)) caller = substr($0, RSTART + 8, RLENGTH - 9)
      if (match($0, /fmt="[^"]+"/))    fmt    = substr($0, RSTART + 5, RLENGTH - 6)
      if (match($0, /s1="[^"]+"/))     s1     = substr($0, RSTART + 4, RLENGTH - 5)
      if (match($0, /a1=[0-9]+/))      a1     = substr($0, RSTART + 3, RLENGTH - 3) + 0
      if (match($0, /a2=[0-9]+/))      a2     = substr($0, RSTART + 3, RLENGTH - 3) + 0
      if (match($0, /a3=[0-9]+/))      a3     = substr($0, RSTART + 3, RLENGTH - 3) + 0

      if (fmt ~ /%s/ && s1 != "") sub(/%s/, s1, fmt)
      if (fmt ~ /%[di]/) {
        sub(/%[di]/, a1, fmt)
        sub(/%[di]/, a2, fmt)
        sub(/%[di]/, a3, fmt)
      }
      if (fmt != "") {
        key = fmt "|" caller
        count[key]++
        last[key] = ts
      }
    }

    /mod_exec:/ {
      ts = $1
      sub(/T/, " ", ts); sub(/\+.*$/, "", ts)
      caller = "unknown"; arg1 = ""; arg2 = ""
      if (match($0, /caller="[^"]+"/)) caller = substr($0, RSTART + 8, RLENGTH - 9)
      if (match($0, /arg1="[^"]+"/))   arg1   = substr($0, RSTART + 6, RLENGTH - 7)
      if (match($0, /arg2="[^"]+"/))   arg2   = substr($0, RSTART + 6, RLENGTH - 7)

      # Ignore dry-run/lookup flags (-R, --resolve-alias, -n, --dry-run, --show-depends)
      if (arg1 ~ /^(-R|--resolve-alias|-n|--dry-run|-D|--show-depends)$/) next
      if (caller == "check-mod-attem") next

      target = (arg1 ~ /^-/) ? arg2 : arg1
      if (target != "" && target != "(fault)") {
        key = target "|modprobe<-" caller
        count[key]++
        last[key] = ts
      }
    }

    /mod_sys_(f)?init:/ {
      ts = $1
      sub(/T/, " ", ts); sub(/\+.*$/, "", ts)
      caller = "unknown"
      if (match($0, /caller="[^"]+"/)) caller = substr($0, RSTART + 8, RLENGTH - 9)
      if (caller == "modprobe") next
      sc = ($0 ~ /mod_sys_finit:/) ? "finit_module" : "init_module"
      key = "[SYSCALL:" sc "]|" caller
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
