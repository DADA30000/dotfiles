{
  config,
  pkgs,
  lib,
  ...
}:
let
  proton-ge-10 = pkgs.stdenv.mkDerivation (finalAttrs: {
    name = "proton-ge";
    version = "10-34";
    phases = [ "installPhase" ];
    src = pkgs.fetchurl {
      url = "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton${finalAttrs.version}/GE-Proton${finalAttrs.version}.tar.gz";
      hash = "sha256-UcWAtmqDPHOZj+APBxfurFcZdlQECi8u1RiePuaNdz0=";
    };
    installPhase = ''
      mkdir -p "$out"
      tar -C "$out" --strip-components=1 -xf "$src"
    '';
  });

  proton-umu-10 = pkgs.stdenv.mkDerivation (finalAttrs: {
    name = "proton-umu";
    version = "10.0-4";
    phases = [ "installPhase" ];
    src = pkgs.fetchurl {
      url = "https://github.com/Open-Wine-Components/umu-proton/releases/download/UMU-Proton-${finalAttrs.version}/UMU-Proton-${finalAttrs.version}.tar.gz";
      hash = "sha256-YumeApoY+jE+b6Y9QjkJGBAXMKlA40kcVNnVjKuIfGk=";
    };
    installPhase = ''
      mkdir -p "$out"
      tar -C "$out" --strip-components=1 -xf "$src"
    '';
  });

  proton-umu-9 = pkgs.stdenv.mkDerivation (finalAttrs: {
    name = "proton-umu";
    version = "9.0-4e";
    phases = [ "installPhase" ];
    src = pkgs.fetchurl {
      url = "https://github.com/Open-Wine-Components/umu-proton/releases/download/UMU-Proton-${finalAttrs.version}/UMU-Proton-${finalAttrs.version}.tar.gz";
      hash = "sha256-1TYX073YlPTVyP1D6Cf/+7zbtJv0c9f7O+JhjdRx6/M=";
    };
    installPhase = ''
      mkdir -p "$out"
      tar -C "$out" --strip-components=1 -xf "$src"
    '';
  });

  proton-umu-8 = pkgs.stdenv.mkDerivation (finalAttrs: {
    name = "proton-umu";
    version = "8.0-5-3";
    phases = [ "installPhase" ];
    src = pkgs.fetchurl {
      url = "https://github.com/Open-Wine-Components/umu-proton/releases/download/ULWGL-Proton-${finalAttrs.version}/ULWGL-Proton-${finalAttrs.version}.tar.gz";
      hash = "sha256-JmBo/hk5pBnzi3JrRkv9WlEoCPYpe9AWs7Mcns7j0bA=";
    };
    installPhase = ''
      mkdir -p "$out"
      tar -C "$out" --strip-components=1 -xf "$src"
    '';
  });

  steamrt4_data = builtins.fromJSON (builtins.readFile ../../../stuff/home/umu/steamrt4.json);
  steamrt3_data = builtins.fromJSON (builtins.readFile ../../../stuff/home/umu/steamrt3.json);

  steamrt3 = pkgs.stdenv.mkDerivation {
    name = "steamrt3";
    version = steamrt3_data.version;
    phases = [ "installPhase" ];
    src = pkgs.fetchurl {
      url = "https://repo.steampowered.com/steamrt3/images/${steamrt3_data.version}/SteamLinuxRuntime_sniper.tar.xz";
      hash = steamrt3_data.hash;
    };
    installPhase = ''
      mkdir -p "$out"
      cd "$out"
      tar -C . --strip-components=1 -xf "$src"
      ln -s "_v2-entry-point" "umu"
      echo "ok" > ".installed.ok"
    '';
  };

  steamrt4 = pkgs.stdenv.mkDerivation {
    name = "steamrt4";
    version = steamrt4_data.version;
    phases = [ "installPhase" ];
    src = pkgs.fetchurl {
      url = "https://repo.steampowered.com/steamrt4/images/${steamrt4_data.version}/SteamLinuxRuntime_4.tar.xz";
      hash = steamrt4_data.hash;
    };
    installPhase = ''
      mkdir -p "$out"
      cd "$out"
      tar -C . --strip-components=1 -xf "$src"
      ln -s "_v2-entry-point" "umu"
      echo "ok" > ".installed.ok"
    '';
  };

  openal =
    (pkgs.pkgsCross.mingw32.openal.override {
      alsaSupport = false;
      pulseSupport = false;
      dbusSupport = false;
    }).overrideAttrs
      (old: {
        buildInputs = [ ];
        nativeBuildInputs = old.nativeBuildInputs ++ [
          pkgs.cmake
          pkgs.ninja
        ];
        meta = old.meta // {
          platforms = [ "i686-windows" ];
        };
        preConfigure = (old.preConfigure or "") + ''
          export LDFLAGS="$LDFLAGS -static -static-libgcc -static-libstdc++"
        '';
        cmakeFlags = (old.cmakeFlags or [ ]) ++ [
          "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
          "-DALSOFT_REQUIRE_WINMM=ON"
          "-DALSOFT_REQUIRE_DSOUND=ON"
          "-DALSOFT_BACKEND_ALSA=OFF"
          "-DALSOFT_BACKEND_OSS=OFF"
          "-DALSOFT_BACKEND_PULSEAUDIO=OFF"
          "-DALSOFT_BACKEND_JACK=OFF"
          "-DALSOFT_EXAMPLES=OFF"
          "-DALSOFT_UTILS=OFF"
        ];
      });

  patch-proton = pkgs.writers.writePython3 "patch-proton" { doCheck = false; } ''
    import os
    import sys

    for path in sys.argv[1:]:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            s = f.read()

        if "import filecmp" not in s:
            s = s.replace("#!/usr/bin/env python3\n", "#!/usr/bin/env python3\nimport filecmp\n", 1)

        old_check = "        if file_exists(dst, follow_symlinks=False):\n            os.remove(dst)"
        new_check = (
            "        if file_exists(dst, follow_symlinks=False):\n"
            "            if os.path.isfile(dst) and os.path.isfile(src):\n"
            "                try:\n"
            "                    if os.path.samefile(src, dst) or (os.path.getsize(src) == os.path.getsize(dst) and filecmp.cmp(src, dst, shallow=False)):\n"
            "                        return\n"
            "                except OSError:\n"
            "                    pass\n"
            "            os.remove(dst)"
        )
        if old_check not in s:
            raise RuntimeError(f"Could not find old_check in {path}")
        s = s.replace(old_check, new_check, 1)

        old_file_check = "        if file_exists(dst, follow_symlinks=False):\n            os.remove(dst)\n        copyfile(src, dst)"
        new_file_check = (
            "        if file_exists(dst, follow_symlinks=False):\n"
            "            if os.path.isfile(dst) and os.path.isfile(src):\n"
            "                try:\n"
            "                    if os.path.samefile(src, dst) or (os.path.getsize(src) == os.path.getsize(dst) and filecmp.cmp(src, dst, shallow=False)):\n"
            "                        return\n"
            "                except OSError:\n"
            "                    pass\n"
            "            os.remove(dst)\n"
            "        copyfile(src, dst)"
        )
        if old_file_check not in s:
            raise RuntimeError(f"Could not find old_file_check in {path}")
        s = s.replace(old_file_check, new_file_check, 1)

        os.chmod(path, 0o755)
        with open(path, "w", encoding="utf-8") as f:
            f.write(s)
        print("Successfully patched proton script:", path)
  '';

  runtime = pkgs.stdenv.mkDerivation {
    name = "umu-runtime.img";
    version = steamrt4_data.version;
    nativeBuildInputs = [
      pkgs.erofs-utils
      pkgs.bubblewrap
      pkgs.util-linux
      pkgs.umu-launcher
    ];
    phases = [ "installPhase" ];
    installPhase = ''
      # =========================================================================
      # STAGE 1: Generate clean base prefixes using wineboot inside bwrap
      # =========================================================================
      cat << "EOF" > run-wineboot-stage.sh
      #!/bin/sh
      set -e

      TMP_HOME="$TMPDIR/stage1_home"
      mkdir -p "$TMP_HOME/.local/share/umu/steamrt3"
      mkdir -p "$TMP_HOME/.local/share/umu/steamrt4"
      mkdir -p "$TMP_HOME/.local/share/umu/proton"

      echo "Setting up temporary runtimes for wineboot..."
      cp -rL --no-preserve=ownership "${steamrt3}/." "$TMP_HOME/.local/share/umu/steamrt3/"
      cp -rL --no-preserve=ownership "${steamrt4}/." "$TMP_HOME/.local/share/umu/steamrt4/"

      cp -rL --no-preserve=ownership "${proton-ge-10}/." "$TMP_HOME/.local/share/umu/proton/proton-ge-10/"
      cp -rL --no-preserve=ownership "${proton-umu-10}/." "$TMP_HOME/.local/share/umu/proton/proton-umu-10/"
      cp -rL --no-preserve=ownership "${proton-umu-9}/." "$TMP_HOME/.local/share/umu/proton/proton-umu-9/"
      cp -rL --no-preserve=ownership "${proton-umu-8}/." "$TMP_HOME/.local/share/umu/proton/proton-umu-8/"
      cp -rL --no-preserve=ownership "${pkgs.proton-ge-bin.steamcompattool}/." "$TMP_HOME/.local/share/umu/proton/proton-ge-latest/"

      chmod -R u+w "$TMP_HOME/.local/share/umu"

      # Patch proton scripts inside stage 1
      ${patch-proton} "$TMP_HOME"/.local/share/umu/proton/*/proton

      export HOME="$TMP_HOME"
      export XDG_DATA_HOME="$TMP_HOME/.local/share"
      export UMU_RUNTIME_UPDATE=0
      BASE_PFX_OUT="$TMPDIR/base_prefixes"
      mkdir -p "$BASE_PFX_OUT"

      run_wineboot_for_proton() {
        local name="$1"
        local pfx_path="$BASE_PFX_OUT/$name"
        local proton_path="$TMP_HOME/.local/share/umu/proton/$name"
        local wine_lib="$proton_path/files/lib/wine"
        [ -d "$wine_lib" ] || wine_lib="$proton_path/dist/lib64/wine"
        local wine_lib32="$proton_path/files/lib/wine"
        [ -d "$wine_lib32" ] || wine_lib32="$proton_path/dist/lib/wine"

        echo "Generating base prefix via wineboot for: $name"
        mkdir -p "$pfx_path"
        WINEPREFIX="$pfx_path" PROTONPATH="$proton_path" umu-run wineboot -u

        # Inject OpenAL32.dll into syswow64
        mkdir -p "$pfx_path/drive_c/windows/syswow64"
        cp --no-preserve=mode "${openal}/bin/OpenAL32.dll" "$pfx_path/drive_c/windows/syswow64/OpenAL32.dll"

        # Inject Steam client stubs
        local steam_dest="$pfx_path/drive_c/Program Files (x86)/Steam"
        mkdir -p "$steam_dest"
        if [ -f "$wine_lib/x86_64-windows/lsteamclient.dll" ]; then
          cp --no-preserve=mode "$wine_lib/x86_64-windows/lsteamclient.dll" "$steam_dest/steamclient64.dll"
        fi
        if [ -f "$wine_lib32/i386-windows/lsteamclient.dll" ]; then
          cp --no-preserve=mode "$wine_lib32/i386-windows/lsteamclient.dll" "$steam_dest/steamclient.dll"
        fi

        # Resolve all file symlinks into actual regular files
        echo "Resolving file symlinks in base prefix for: $name"
        find "$pfx_path" -type l | while read -r symlink; do
          target=$(readlink -f "$symlink" 2>/dev/null || true)
          if [ -n "$target" ] && [ -f "$target" ]; then
            rm -f "$symlink"
            cp "$target" "$symlink"
          fi
        done

        # Remove sandbox-specific paths
        rm -f "$pfx_path/dosdevices/x:"
        rm -f "$pfx_path/drive_c/users/nixbld"

        # Normalize config_info and .update-timestamp in base prefix
        if [ -f "$pfx_path/config_info" ]; then
          sed -i "s|$TMP_HOME|@UMU_USER_HOME@|g" "$pfx_path/config_info"
          sed -i 's|^[0-9]\+\.[0-9]\+$|1.0|' "$pfx_path/config_info"
        fi
        echo -n "1" > "$pfx_path/.update-timestamp"

        touch "$pfx_path/creation_sync_guard"
        touch "$pfx_path/check-do_not_delete_this"
        ln -sfn . "$pfx_path/pfx"
      }

      run_wineboot_for_proton "proton-umu-8"
      run_wineboot_for_proton "proton-umu-9"
      run_wineboot_for_proton "proton-umu-10"
      run_wineboot_for_proton "proton-ge-10"
      run_wineboot_for_proton "proton-ge-latest"

      echo "Base prefixes generated successfully. Cleaning temporary runtimes..."
      rm -rf "$TMP_HOME"
      EOF

      chmod +x run-wineboot-stage.sh

      # Run stage 1 inside bwrap to provide /sys, /proc, /dev and FHS root
      bwrap \
        --tmpfs / \
        --dir /sys \
        --ro-bind /nix /nix \
        --ro-bind /bin /bin \
        --ro-bind /etc /etc \
        --dev /dev \
        --proc /proc \
        --bind /tmp /tmp \
        --bind /build /build \
        ./run-wineboot-stage.sh

      rm -f run-wineboot-stage.sh

      # =========================================================================
      # STAGE 2: Assemble clean EROFS filesystem with runtime & base prefixes
      # =========================================================================
      echo "Assembling final runtime image..."
      mkdir -p build/proton
      cp -aL "${steamrt3}" build/steamrt3
      cp -aL "${steamrt4}" build/steamrt4
      cp -aL "${proton-ge-10}" build/proton/proton-ge-10
      cp -aL "${proton-umu-10}" build/proton/proton-umu-10
      cp -aL "${proton-umu-9}" build/proton/proton-umu-9
      cp -aL "${proton-umu-8}" build/proton/proton-umu-8
      cp -aL "${pkgs.proton-ge-bin.steamcompattool}" build/proton/proton-ge-latest

      # Ensure permissions for patching and pressure-vessel
      chmod -R u+w build

      # Patch proton scripts in final image
      ${patch-proton} build/proton/*/proton

      # Copy generated clean base prefixes into image
      mv "$TMPDIR/base_prefixes" build/base_prefixes

      # Resolve any remaining file symlinks in build/ to actual file copies
      echo "Resolving all file symlinks in build image..."
      find build -type l | while read -r symlink; do
        target=$(readlink -f "$symlink" 2>/dev/null || true)
        if [ -n "$target" ] && [ -f "$target" ]; then
          rm -f "$symlink"
          cp "$target" "$symlink"
        fi
      done

      # Ensure permissions for pressure-vessel
      chmod -R u+w build

      # Create immutable EROFS with inode deduplication
      mkfs.erofs \
        --force-uid=0 \
        --force-gid=0 \
        --workers "$NIX_BUILD_CORES" \
        --ignore-mtime \
        --zD=1 \
        -z zstd,19 \
        -C 65536 \
        -m 65536:zstd,19 \
        -E 48bit,all-fragments,dot-omitted,fragdedupe=inode \
        -T 0 \
        -x -1 \
        "$out" \
        build
    '';
  };

  mount-umu-src = pkgs.writeText "mount-umu.c" ''
    #define _GNU_SOURCE
    #include <asm/unistd_64.h>
    #include <linux/mount.h>
    #include <errno.h>
    #include <fcntl.h>
    #include <linux/loop.h>
    #include <pwd.h>
    #include <sched.h>
    #include <signal.h>
    #include <stdint.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <sys/ioctl.h>
    #include <sys/mount.h>
    #include <sys/stat.h>
    #include <sys/types.h>
    #include <sys/wait.h>
    #include <unistd.h>

    struct clone_mount_attr {
      uint64_t attr_set;
      uint64_t attr_clr;
      uint64_t propagation;
      uint64_t userns_fd;
    };

    #define TRUSTED_LOWER_IMG "${runtime}"

    static int write_map(pid_t pid, const char *file, unsigned int id1, unsigned int id2) {
      char path[64], map[256];
      snprintf(path, sizeof(path), "/proc/%d/%s", pid, file);
      if (id1 > id2) {
        unsigned int t = id1;
        id1 = id2;
        id2 = t;
      }

      int off = (id1 == id2) ? snprintf(map, sizeof(map), "0 0 65536\n") : 0;
      if (id1 != id2) {
        if (id1 > 0)
          off += snprintf(map + off, sizeof(map) - off, "0 0 %u\n", id1);
        off += snprintf(map + off, sizeof(map) - off, "%u %u 1\n", id1, id2);
        if (id2 > id1 + 1)
          off += snprintf(map + off, sizeof(map) - off, "%u %u %u\n", id1 + 1, id1 + 1, id2 - id1 - 1);
        off += snprintf(map + off, sizeof(map) - off, "%u %u 1\n", id2, id1);
        if (id2 < 65535)
          off += snprintf(map + off, sizeof(map) - off, "%u %u %u\n", id2 + 1, id2 + 1, 65535 - id2);
      }

      int fd = open(path, O_WRONLY);
      if (fd < 0) return -1;
      int ret = write(fd, map, off) == off ? 0 : -1;
      close(fd);
      return ret;
    }

    static int create_userns(uid_t i_uid, uid_t u_uid, gid_t i_gid, gid_t u_gid) {
      int pipefd[2];
      if (pipe(pipefd) < 0) return -1;
      pid_t pid = fork();
      if (pid < 0) {
        close(pipefd[0]);
        close(pipefd[1]);
        return -1;
      }

      if (pid == 0) {
        close(pipefd[0]);
        if (unshare(CLONE_NEWUSER) != 0 || write(pipefd[1], "1", 1) != 1) exit(1);
        close(pipefd[1]);
        pause();
        exit(0);
      }
      close(pipefd[1]);

      char c;
      if (read(pipefd[0], &c, 1) <= 0 || write_map(pid, "uid_map", i_uid, u_uid) < 0) goto err;
      close(pipefd[0]);

      char path[64];
      snprintf(path, sizeof(path), "/proc/%d/setgroups", pid);
      int fd = open(path, O_WRONLY);
      if (fd >= 0) {
        if (write(fd, "deny", 4) < 0) {}
        close(fd);
      }

      if (write_map(pid, "gid_map", i_gid, u_gid) < 0) goto err;

      snprintf(path, sizeof(path), "/proc/%d/ns/user", pid);
      int userns_fd = open(path, O_RDONLY | O_CLOEXEC);

      kill(pid, SIGKILL);
      waitpid(pid, NULL, 0);
      return userns_fd;

    err:
      close(pipefd[0]);
      kill(pid, SIGKILL);
      waitpid(pid, NULL, 0);
      return -1;
    }

    int main(int argc, char *argv[]) {
      if (argc < 2) {
        fprintf(stderr, "Usage: %s <uid>\n", argv[0]);
        return 1;
      }
      uid_t uid = (uid_t)atoi(argv[1]);
      struct passwd *pw = getpwuid(uid);
      gid_t gid = pw ? pw->pw_gid : uid;

      char target[256];
      snprintf(target, sizeof(target), "/run/umu/%u", uid);

      // Clean up previous stale mounts on target if any
      int check_fd = open(target, O_PATH | O_DIRECTORY | O_CLOEXEC);
      if (check_fd >= 0) {
        close(check_fd);
        umount2(target, MNT_DETACH);
      }

      mkdir("/run/umu", 0755);
      mkdir(target, 0700);
      chown(target, uid, gid);

      int target_fd = open(target, O_PATH | O_DIRECTORY | O_CLOEXEC);
      if (target_fd < 0) {
        perror("open target");
        return 1;
      }

      char upper_tmp[] = "/run/umu/.up-XXXXXX";
      char tmp_path[] = "/run/umu/.tmp-XXXXXX";
      if (!mkdtemp(upper_tmp)) {
        perror("mkdtemp upper_tmp");
        close(target_fd);
        return 1;
      }
      if (!mkdtemp(tmp_path)) {
        perror("mkdtemp tmp_path");
        rmdir(upper_tmp);
        close(target_fd);
        return 1;
      }

      char mount_opts[128];
      snprintf(mount_opts, sizeof(mount_opts), "mode=0700,uid=%u,gid=%u", uid, gid);
      if (mount("tmpfs", upper_tmp, "tmpfs", MS_NODEV | MS_NOSUID, mount_opts) != 0) {
        perror("mount tmpfs");
        rmdir(upper_tmp);
        rmdir(tmp_path);
        close(target_fd);
        return 1;
      }

      char upper[256], work[256];
      snprintf(upper, sizeof(upper), "%s/upper", upper_tmp);
      snprintf(work, sizeof(work), "%s/work", upper_tmp);
      mkdir(upper, 0700); chown(upper, uid, gid);
      mkdir(work, 0700); chown(work, uid, gid);

      int upper_fd = open(upper, O_PATH | O_DIRECTORY | O_CLOEXEC);
      int work_fd = open(work, O_PATH | O_DIRECTORY | O_CLOEXEC);
      int ret = 1;
      if (upper_fd < 0 || work_fd < 0) {
        perror("open upper/work");
        goto cleanup_upper;
      }

      int img_fd = open(TRUSTED_LOWER_IMG, O_RDONLY | O_CLOEXEC);
      if (img_fd < 0) {
        perror("open TRUSTED_LOWER_IMG");
        goto cleanup_upper;
      }

      int fs_fd = syscall(__NR_fsopen, "erofs", FSOPEN_CLOEXEC);
      int needs_loop = (fs_fd < 0);
      if (!needs_loop) {
        if (syscall(__NR_fsconfig, fs_fd, FSCONFIG_SET_FLAG, "ro", NULL, 0) < 0 ||
            syscall(__NR_fsconfig, fs_fd, FSCONFIG_SET_FD, "source", NULL, img_fd) < 0 ||
            syscall(__NR_fsconfig, fs_fd, FSCONFIG_CMD_CREATE, NULL, NULL, 0) < 0) {
          needs_loop = 1;
        }
      }

      if (needs_loop) {
        if (fs_fd >= 0) { close(fs_fd); fs_fd = -1; }
        int loop_ctl = open("/dev/loop-control", O_RDWR | O_CLOEXEC);
        if (loop_ctl < 0) { perror("open loop-control"); close(img_fd); goto cleanup_upper; }
        int dev_nr = ioctl(loop_ctl, LOOP_CTL_GET_FREE);
        close(loop_ctl);
        if (dev_nr < 0) { perror("LOOP_CTL_GET_FREE"); close(img_fd); goto cleanup_upper; }

        char loop_name[64];
        snprintf(loop_name, sizeof(loop_name), "/dev/loop%d", dev_nr);
        int loop_fd = open(loop_name, O_RDONLY | O_CLOEXEC);
        if (loop_fd < 0) { perror("open loop_fd"); close(img_fd); goto cleanup_upper; }

        struct loop_config config = {0};
        config.fd = img_fd;
        config.info.lo_flags = LO_FLAGS_AUTOCLEAR | LO_FLAGS_READ_ONLY;
        if (ioctl(loop_fd, LOOP_CONFIGURE, &config) < 0) {
          perror("ioctl LOOP_CONFIGURE"); close(loop_fd); close(img_fd); goto cleanup_upper;
        }

        fs_fd = syscall(__NR_fsopen, "erofs", FSOPEN_CLOEXEC);
        if (fs_fd < 0) { perror("fsopen fallback"); close(loop_fd); close(img_fd); goto cleanup_upper; }
        syscall(__NR_fsconfig, fs_fd, FSCONFIG_SET_FLAG, "ro", NULL, 0);
        syscall(__NR_fsconfig, fs_fd, FSCONFIG_SET_STRING, "source", loop_name, 0);

        int max_retries = 10;
        while (syscall(__NR_fsconfig, fs_fd, FSCONFIG_CMD_CREATE, NULL, NULL, 0) < 0) {
          if (errno != EBUSY || --max_retries == 0) {
            perror("fsconfig CMD_CREATE"); close(loop_fd); close(fs_fd); close(img_fd); goto cleanup_upper;
          }
          usleep(20000);
        }
        close(loop_fd);
      }
      close(img_fd);

      int tree_fd = syscall(__NR_fsmount, fs_fd, FSMOUNT_CLOEXEC,
                            MOUNT_ATTR_RDONLY | MOUNT_ATTR_NOSUID | MOUNT_ATTR_NODEV);
      close(fs_fd);
      if (tree_fd < 0) { perror("fsmount"); goto cleanup_upper; }

      // ID-map: maps image UID 0 to target user's UID
      int userns_fd = create_userns(0, uid, 0, gid);
      if (userns_fd >= 0) {
        struct clone_mount_attr attr = {.attr_set = MOUNT_ATTR_IDMAP, .userns_fd = (uint64_t)userns_fd};
        syscall(__NR_mount_setattr, tree_fd, "", AT_EMPTY_PATH | AT_RECURSIVE, &attr, sizeof(attr));
        close(userns_fd);
      }

      if (syscall(__NR_move_mount, tree_fd, "", AT_FDCWD, tmp_path, MOVE_MOUNT_F_EMPTY_PATH) != 0) {
        perror("move_mount"); close(tree_fd); goto cleanup_upper;
      }
      close(tree_fd);

      char opts[2048], target_proc[64];
      snprintf(opts, sizeof(opts),
               "lowerdir=%s,upperdir=/proc/self/fd/%d,workdir=/proc/self/fd/%d,index=on,metacopy=on,redirect_dir=on",
               tmp_path, upper_fd, work_fd);
      snprintf(target_proc, sizeof(target_proc), "/proc/self/fd/%d", target_fd);

      ret = mount("overlay", target_proc, "overlay", MS_NOSUID | MS_NODEV, opts);
      if (ret != 0) {
        perror("mount overlay");
      }

      // Ephemeral Detach: remove lower and upper from VFS hierarchy immediately.
      // They now exist only as anonymous kernel inodes held by the active overlay mount.
      umount2(tmp_path, MNT_DETACH);
    cleanup_upper:
      umount2(upper_tmp, MNT_DETACH);
      rmdir(tmp_path);
      rmdir(upper_tmp);
      if (target_fd >= 0) close(target_fd);
      if (upper_fd >= 0) close(upper_fd);
      if (work_fd >= 0) close(work_fd);
      return ret == 0 ? 0 : 1;
    }
  '';

  mount-umu-bin = pkgs.stdenv.mkDerivation {
    pname = "mount-umu";
    version = "1.0";
    src = mount-umu-src;
    dontUnpack = true;
    buildPhase = ''
      gcc -O2 -Wall $src -o mount-umu
    '';
    installPhase = ''
      mkdir -p $out/bin
      install -m 0755 mount-umu $out/bin/mount-umu
    '';
  };

  unmount-umu = pkgs.writeShellScript "unmount-umu" ''
    set -euo pipefail
    TARGET_UID="$1"
    [[ "$TARGET_UID" =~ ^[0-9]+$ ]] || exit 1
    TARGET="/run/umu/$TARGET_UID"
    umount -l "$TARGET" 2>/dev/null || true
    rmdir "$TARGET" 2>/dev/null || true
  '';

  cfg = config.umu;
in
{
  options.umu = {
    enable = lib.mkEnableOption "umu - universal windows apps launcher (system runtime & mount service)";
  };

  config = lib.mkIf cfg.enable {
    systemd.services."umu-mount@" = {
      description = "Isolated ephemeral UMU runtime overlay for UID %i";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${mount-umu-bin}/bin/mount-umu %i";
        ExecStop = "${unmount-umu} %i";
      };
    };

    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units") {
          var unit = action.lookup("unit");
          if (unit === "umu-mount@" + subject.uid + ".service" ||
              unit === "umu-mount@" + subject.user + ".service") {
            return polkit.Result.YES;
          }
        }
      });
    '';
  };
}
