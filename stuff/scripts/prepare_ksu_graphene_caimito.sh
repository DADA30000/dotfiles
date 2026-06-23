set -euo pipefail

cd "$1/common/ack"

GKI_ROOT="$(pwd)"
KSU_DIR="$GKI_ROOT/KernelSU-Next"
OWNER="pershoot"
REPO="KernelSU-Next"

DRIVER_DIR="$GKI_ROOT/drivers"
DRIVER_MAKEFILE=$DRIVER_DIR/Makefile
DRIVER_KCONFIG=$DRIVER_DIR/Kconfig

echo "[+] Setting up $REPO..."
test -d "$GKI_ROOT/$REPO" || git clone "https://github.com/$OWNER/$REPO" && echo "[+] Repository cloned."
cd "$GKI_ROOT/$REPO"
git stash && echo "[-] Stashed current changes."

BRANCH="$(git rev-parse --abbrev-ref origin/HEAD | sed 's@^origin/@@')"
if [ "$(git status | grep -Po 'v\d+(\.\d+)*' | head -n1)" ]; then
  git checkout "$BRANCH" && echo "[-] Switched to $BRANCH branch."
fi

git pull && echo "[+] Repository updated."
git checkout dev-susfs && echo "[-] Checked out dev-susfs." || echo "[-] Checkout default branch"
cd "$DRIVER_DIR"
rm -rf kernelsu
cp -rL "$KSU_DIR"/kernel kernelsu
echo "[+] Copied KSU to drivers"

grep -q "kernelsu" "$DRIVER_MAKEFILE" || printf "\nobj-\$(CONFIG_KSU) += kernelsu/\n" >>"$DRIVER_MAKEFILE" && echo "[+] Modified Makefile."
grep -q "source \"drivers/kernelsu/Kconfig\"" "$DRIVER_KCONFIG" || sed -i "/endmenu/i\source \"drivers/kernelsu/Kconfig\"" "$DRIVER_KCONFIG" && echo "[+] Modified Kconfig."
echo '[+] Done.'

FILE="$GKI_ROOT/drivers/kernelsu/Kbuild"
TARGET_1="KSU_VERSION_TAG_FALLBACK := v0.0.1"
TARGET_2="KSU_VERSION_FALLBACK := 1"
BASE_BRANCH=$(cd "$KSU_DIR" && git rev-parse --abbrev-ref HEAD | sed 's:-.*::' 2>/dev/null)
BASE_COMMIT=$(cd "$KSU_DIR" && git merge-base HEAD refs/remotes/origin/"$BASE_BRANCH" 2>/dev/null || git merge-base HEAD refs/remotes/origin/main 2>/dev/null || echo HEAD)
KSU_VERSION=$((30000 + $(cd "$KSU_DIR" && git rev-list --count "$BASE_COMMIT" 2>/dev/null)))
KSU_TAG=$(cd "$KSU_DIR" && git describe --tags --abbrev=0 "$BASE_COMMIT" 2>/dev/null)

export KSU_VERSION
export KSU_TAG

rm -rf "$KSU_DIR"

awk -v tag="$KSU_TAG" -v ver="$KSU_VERSION" '
    {
        if ($0 ~ /KSU_VERSION_TAG_FALLBACK :=/) {
            $0 = "KSU_VERSION_TAG_FALLBACK := " tag
            count1++
        }
        else if ($0 ~ /KSU_VERSION_FALLBACK :=/) {
            $0 = "KSU_VERSION_FALLBACK := " ver
            count2++
        }
        print
    }
    END {
        if (count1 == 0 || count2 == 0) {
            print "ERROR: Substitution failed in Kbuild!" > "/dev/stderr"
            exit 1
        }
    }
' "$FILE" >"$FILE.tmp" && mv "$FILE.tmp" "$FILE"

TMP_DIR="$(mktemp -d)"
SUSFS_DIR="$TMP_DIR/susfs"
git clone 'https://gitlab.com/simonpunk/susfs4ksu' -b gki-android14-6.1 --depth 1 "$SUSFS_DIR"
cp -r "$SUSFS_DIR"/kernel_patches/fs/* "$GKI_ROOT"/fs
cp -r "$SUSFS_DIR"/kernel_patches/include/linux/* "$GKI_ROOT"/include/linux
cd "$GKI_ROOT"
echo "CONFIG_KSU=y" >>"$GKI_ROOT"/../../private/devices/google/caimito/caimito_defconfig
echo "CONFIG_KSU_SUSFS=y" >>"$GKI_ROOT"/../../private/devices/google/caimito/caimito_defconfig
echo "[+] Resolving SusFS patches..."
PATCH_FILE=$(find "$SUSFS_DIR/kernel_patches" -name "50_add_susfs_in_*.patch" | head -n 1)
LITTER_DIR="/tmp/kernel_patch_litter"

rm -rf "$LITTER_DIR"
mkdir -p "$LITTER_DIR"

patch -p1 -V none -t -i "$PATCH_FILE" || true

if [ -n "$(find . -name "*.rej" -print -quit)" ]; then
  echo "[!] Hard rejects found. Launching interactive wiggle browser..."
  while IFS= read -r rej_file; do
    target_file="${rej_file#./}"
    target_file="${target_file%.rej}"

    echo "    -> Opening wiggle TUI for: $target_file"

    wiggle --browse --no-backup --replace "$target_file" "$rej_file" </dev/tty || true

    mkdir -p "$LITTER_DIR/$(dirname "$target_file")"
    mv "$rej_file" "$LITTER_DIR/$target_file.rej"
  done < <(find . -name "*.rej")
  echo "[+] Wiggle execution complete"
else
  echo "[+] Patch applied completely clean with native settings. No wiggling required!"
fi
echo "[+] Scrubbing stray patch backups..."
find . -type f -name "*.~*~" -delete
find . -type f -name "*.orig" -delete
rm -rf "$LITTER_DIR" "$TMP_DIR"
