#!/usr/bin/env bash
set -euo pipefail

if [ $# -eq 0 ]; then
  echo "Usage: run0edit <files...>" >&2
  exit 1
fi

TMPDIR="$(mktemp -d "/dev/shm/run0edit.XXXXXX")"
trap 'rm -rf "$TMPDIR"' EXIT

TARGETS=()
TMPFILES=()
ORIG_HASHES=()

i=0
for arg in "$@"; do
  real="$(realpath -m "$arg")"
  # Preserve filename/extension so Neovim/LSP detects filetype properly
  tmp="$TMPDIR/${i}_$(basename "$real")"
  i=$((i + 1))

  TARGETS+=("$real")
  TMPFILES+=("$tmp")
done

# 1. Copy original files to /dev/shm and give ownership to your user (1 single run0 call)
run0 --setenv=PATH --background= bash -c '
  set -euo pipefail
  uid="$1"; gid="$2"; shift 2
  n=$(( $# / 2 ))
  for (( i=1; i<=n; i++ )); do
    real="${!i}"
    tmp_idx=$(( i + n ))
    tmp="${!tmp_idx}"
    if [ -e "$real" ]; then
      if [ -d "$real" ]; then
        echo "run0edit: $real: is a directory" >&2
        exit 1
      fi
      cp -p "$real" "$tmp"
    else
      touch "$tmp"
    fi
    chown "$uid:$gid" "$tmp"
  done
' bash "$(id -u)" "$(id -g)" "${TARGETS[@]}" "${TMPFILES[@]}"

# 2. Record hashes before editing
for tmp in "${TMPFILES[@]}"; do
  ORIG_HASHES+=("$(sha256sum "$tmp" | cut -d' ' -f1)")
done

# 3. Run editor directly in your normal shell (100% of your env & sockets stay intact!)
${SUDO_EDITOR:-${VISUAL:-${EDITOR:-nvim}}} "${TMPFILES[@]}"

# 4. Check which files changed
CHANGED_TMP=()
CHANGED_REAL=()
for idx in "${!TMPFILES[@]}"; do
  new_hash="$(sha256sum "${TMPFILES[$idx]}" | cut -d' ' -f1)"
  if [ "$new_hash" = "${ORIG_HASHES[$idx]}" ]; then
    echo "run0edit: ${TARGETS[$idx]} unchanged"
  else
    CHANGED_TMP+=("${TMPFILES[$idx]}")
    CHANGED_REAL+=("${TARGETS[$idx]}")
  fi
done

# 5. Copy modified files back (uses cached Polkit token if <5 min)
if [ ${#CHANGED_REAL[@]} -gt 0 ]; then
  run0 --setenv=PATH --background= bash -c '
    set -euo pipefail
    n=$(( $# / 2 ))
    for (( i=1; i<=n; i++ )); do
      tmp="${!i}"
      real_idx=$(( i + n ))
      real="${!real_idx}"
      mkdir -p "$(dirname "$real")"
      cat "$tmp" > "$real"
    done
  ' bash "${CHANGED_TMP[@]}" "${CHANGED_REAL[@]}"
fi
