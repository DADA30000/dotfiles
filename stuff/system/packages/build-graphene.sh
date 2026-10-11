# vim: set ft=bash ts=2 sw=2 et:

DEVICE="tokay"
KERNEL_CODENAME="caimito"
TAG="2026100600"
UPDATE_URL="https://update.sanic.space/"
OS_DIR="$HOME/Documents/grapheneos"
KERNEL_DIR="$HOME/Downloads/kernel_pixel_6.1"

# Apply shallow-protection patch directly from embedded diff (prevents auto-unshallow and 110GB bloat)
patch_repo_tool() {
  local p="$OS_DIR/.repo/repo/project.py"
  if [ ! -d "$OS_DIR/.repo/repo" ]; then
    echo "[-] FATAL: Repo tool directory $OS_DIR/.repo/repo does not exist! Run repo init first." >&2
    return 1
  fi
  grep -q "Never fall back to unshallowing" "$p" 2>/dev/null && return 0
  echo "[*] Applying embedded shallow-protection patch to .repo/repo/project.py..."
  if ! git -C "$OS_DIR/.repo/repo" apply - <<'EOF'
diff --git a/project.py b/project.py
--- a/project.py
+++ b/project.py
@@ -1881,10 +1881,9 @@ class Project:
         else:
             depth = self.manifest.manifestProject.depth
 
-        # If the project has been manually unshallowed (e.g. via
-        # `git fetch --unshallow`), don't re-shallow it during sync.
-        if depth and not is_new and not self._HasShallow():
-            depth = None
+        # Never discard depth on existing projects; respect configured clone depth.
+        # if depth and not is_new and not self._HasShallow():
+        #     depth = None
 
         if depth and clone_filter_for_depth:
             depth = None
@@ -3471,13 +3470,7 @@ class Project:
 
         if depth:
             cmd.append("--depth=%s" % depth)
-        else:
-            # If this repo has shallow objects, then we don't know which refs
-            # have shallow objects or not. Tell git to unshallow all fetched
-            # refs.  Don't do this with projects that don't have shallow
-            # objects, since it is less efficient.
-            if self._HasShallow():
-                cmd.append("--depth=2147483647")
+        # Never automatically un-shallow to 2.14 billion commits if depth is None.
 
         # Use clone-depth="1" as a heuristic for repositories containing
         # large binaries and disable auto GC to prevent potential hangs.
@@ -3661,14 +3654,10 @@ class Project:
                     # upstream field; it doesn't exist, thus abort the
                     # optimization attempt and do a full sync.
                     break
-                elif depth and is_sha1 and ret == 1:
-                    # In sha1 mode, when depth is enabled, syncing the revision
-                    # from upstream may not work because some servers only allow
-                    # fetching named refs. Fetching a specific sha1 may result
-                    # in an error like 'server does not allow request for
-                    # unadvertised object'. In this case, attempt a full sync
-                    # without depth.
-                    break
+                # In sha1 mode, allow transient network errors (ret == 1) to retry
+                # via the exponential backoff loop instead of aborting to an unshallow.
+                # elif depth and is_sha1 and ret == 1:
+                #     break
                 elif ret < 0:
                     # Git died with a signal, exit immediately.
                     break
@@ -3722,6 +3711,11 @@ class Project:
                 use_superproject=use_superproject,
                 depth=depth,
             ):
+                if depth:
+                    # Never fall back to unshallowing a 100GB repo if depth was explicitly configured.
+                    # Fail cleanly so outer retry loop (until repo sync...) re-attempts shallow fetch.
+                    return False
+
                 # Sync the current branch only with depth set to None.
                 # We always pass depth=None down to avoid infinite recursion.
                 return self._RemoteFetch(
EOF
  then
    echo "[-] FATAL: Failed to apply embedded shallow-protection patch cleanly! Aborting." >&2
    return 1
  fi
  if ! python3 -m py_compile "$p" 2>/dev/null; then
    echo "[-] FATAL: project.py syntax check failed after patch! Aborting." >&2
    return 1
  fi
  echo "[+] Shallow-protection patch verified and active."
}

# Initial shallow OS clone + auto-retry loop + smart GC + update server URL
os_init_sync() {
  mkdir -p "$OS_DIR" && cd "$OS_DIR" && repo init -u https://github.com/GrapheneOS/platform_manifest.git -b "refs/tags/$TAG" --depth=1 --no-clone-bundle -p linux && patch_repo_tool && until repo sync -c --no-tags --optimized-fetch -j4; do echo "Sync dropped, retrying in 3s..." && sleep 3; done && gc && sed -i "s|https://releases.grapheneos.org/|$UPDATE_URL|g" "$OS_DIR/packages/apps/Updater/res/values/config.xml"
}

# Recurring tag update (every 1-2 weeks): reset config + init new tag + retry loop + smart GC + update URL
tag_update() {
  cd "$OS_DIR" && git -C packages/apps/Updater checkout -- res/values/config.xml && repo init -u https://github.com/GrapheneOS/platform_manifest.git -b "refs/tags/$TAG" --depth=1 && patch_repo_tool && until repo sync -c --no-tags --optimized-fetch -j4; do echo "Sync dropped, retrying in 3s..." && sleep 3; done && gc && sed -i "s|https://releases.grapheneos.org/|$UPDATE_URL|g" packages/apps/Updater/res/values/config.xml
}

# Unified smart GC: checks in 2ms and skips clean repos with 0 I/O; prunes dead refs, shallow-truncates, and repacks only dirty repos
gc() {
  # shellcheck disable=SC2016
  cd "$OS_DIR" && repo forall -j"$(nproc)" -c 'gd="$(git rev-parse --git-dir)" && head="$(git rev-parse HEAD)" && [ "$head" = "$(cat "$gd/shallow" 2>/dev/null)" ] && [ -z "$(git for-each-ref --format="%(refname)" refs/remotes/aosp/ 2>/dev/null)" ] && [ "$(git count-objects | cut -d" " -f1)" = "0" ] && exit 0; echo "$head" > "$gd/shallow" && git for-each-ref --format="delete %(refname)" refs/remotes/aosp/ 2>/dev/null | git update-ref --stdin && git reflog expire --expire=now --all && git repack -a -d --quiet && git prune --expire=now && git prune-packed'
}

repo_check_clean() {
  cd "$OS_DIR" && repo status
}

repo_repair_offline() {
  cd "$OS_DIR" && repo sync -l
}

distrobox_create() {
  distrobox create --name grapheneos --image ubuntu:24.04 --home ~
}

distrobox_enter() {
  distrobox enter grapheneos
}

distrobox_provision() {
  sudo apt update && sudo apt install -y build-essential bc bison ca-certificates cpio curl diffutils dwarves flex fontconfig fonts-dejavu-core gawk gcc-multilib g++-multilib git git-lfs gnupg gperf hostname kmod lib32gcc-s1 lib32stdc++6 libc6-i386 libelf-dev libfreetype6 libfreetype6-dev libssl-dev openjdk-21-jdk-headless openssh-client openssl perl procps python3 python-is-python3 python3-pip rsync tar unzip wget wiggle xz-utils zip zsh zstd && curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash - && sudo apt install -y nodejs && sudo corepack enable
}

vendor_blobs() {
  cd "$OS_DIR" && yarn --cwd vendor/adevtool/ install && vendor/adevtool/bin/run generate-all -d "$DEVICE" && vendor/adevtool/bin/run trim-images --allDirs --noConfirm
}

kernel_build() {
  rm -rf "$KERNEL_DIR" && git clone https://gitlab.com/grapheneos/kernel_pixel_6.1.git -b 17 --depth 1 "$KERNEL_DIR" && cd "$KERNEL_DIR" && git submodule update --init --recursive --depth 1 --progress && "prepare_ksu_graphene_${KERNEL_CODENAME}" "$KERNEL_DIR" && KLEAF_REPO_MANIFEST=aosp_manifest.xml "./build_${KERNEL_CODENAME}.sh" --lto=full && cp -a "$KERNEL_DIR/out/${KERNEL_CODENAME}/dist/"* "$OS_DIR/device/google/${KERNEL_CODENAME}-kernels/6.1/grapheneos/"
}

keys_generate() {
  cd "$OS_DIR" && mkdir -p "keys/$DEVICE" && cd "keys/$DEVICE" && CN=GrapheneOS && ../../development/tools/make_key releasekey "/CN=$CN/" && ../../development/tools/make_key platform "/CN=$CN/" && ../../development/tools/make_key shared "/CN=$CN/" && ../../development/tools/make_key media "/CN=$CN/" && ../../development/tools/make_key networkstack "/CN=$CN/" && ../../development/tools/make_key bluetooth "/CN=$CN/" && ../../development/tools/make_key sdk_sandbox "/CN=$CN/" && ../../development/tools/make_key gmscompat_lib "/CN=$CN/" && ../../development/tools/make_key nfc "/CN=$CN/" && openssl genrsa 4096 | openssl pkcs8 -topk8 -scrypt -out avb.pem && ../../external/avb/avbtool.py extract_public_key --key avb.pem --output avb_pkmd.bin && cd ../.. && ssh-keygen -t ed25519 -f "keys/$DEVICE/id_ed25519" -N ""
}

os_build() {
  # shellcheck disable=SC1091
  cd "$OS_DIR" && export BUILD_NUMBER="$TAG" && export OFFICIAL_BUILD=true && source build/envsetup.sh && lunch "$DEVICE-cur-user" && m installclean && m vendorbootimage vendorkernelbootimage target-files-package otatools-package && script/finalize.sh && export TMPDIR="$PWD/out/tmp" && mkdir -p "$TMPDIR" && script/generate-release.sh "$DEVICE" "$TAG"
}

# ==============================================================================
# CLI DISPATCHER
# ==============================================================================
case "$1" in
os-init-sync) os_init_sync ;;
tag-update) tag_update ;;
gc) gc ;;
check-clean) repo_check_clean ;;
repair-offline) repo_repair_offline ;;
distrobox-create) distrobox_create ;;
distrobox-enter) distrobox_enter ;;
distrobox-provision) distrobox_provision ;;
vendor-blobs) vendor_blobs ;;
kernel-build) kernel_build ;;
keys-generate) keys_generate ;;
os-build) os_build ;;
*)
  echo "Usage: $0 {os-init-sync|tag-update|gc|check-clean|repair-offline|distrobox-create|distrobox-enter|distrobox-provision|vendor-blobs|kernel-build|keys-generate|os-build}"
  ;;
esac
