{
  pkgs,
  inputs,
  config,
  lib,
  ...
}:
let
  cfg = config.android;

  shared-start = /* bash */ ''
    GPU_INFO=$(lspci -nn | grep -Ei 'vga|3d|display' | grep -iv 'nvidia')

    if echo "$GPU_INFO" | grep -qi 'amd'; then
        export MESA_LOADER_DRIVER_OVERRIDE=radeonsi
        export VK_DRIVER_FILES=/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json
    elif echo "$GPU_INFO" | grep -qi 'intel'; then
        export MESA_LOADER_DRIVER_OVERRIDE=iris
        export VK_DRIVER_FILES=/run/opengl-driver/share/vulkan/icd.d/intel_icd.x86_64.json
    fi
    export DRI_PRIME=0

    HIGHEST_HZ=$(${pkgs.wayland-utils}/bin/wayland-info 2>/dev/null | awk '
      /refresh:/ {
        for (i = 1; i <= NF; i++) {
          if ($i == "refresh:") {
            val = $(i+1)
            sub(/,/, "", val)
            print int(val + 0.5)
            next
          }
        }
      }
    ' | sort -rn | head -n 1)

    FINAL_MEM=$(awk '/MemTotal/ {
      half_gb = int($2 / 1024 / 1024 / 2);
      
      low_p2 = 1;
      while (low_p2 * 2 <= half_gb) { low_p2 *= 2; }
      high_p2 = low_p2 * 2;
      
      if (half_gb - low_p2 <= 1) {
        print low_p2;
      } else if (high_p2 - half_gb <= 1) {
        print high_p2;
      } else {
        if (half_gb % 2 == 0) {
          print half_gb;
        } else {
          print half_gb - 1;
        }
      }
    }' /proc/meminfo)

    ${pkgs.steam-run}/bin/steam-run emulator -cores $(nproc) -vsync-rate "$HIGHEST_HZ" -memory "$(($FINAL_MEM * 1024))" \
  '';

  shared-attrs = {
    gpu = true;
    wayland = true;
    network = true;
    audio = true;
    x11_shared = true;
    webcam = 5;
    additional_args.bubblewrap.bind = {
      ro = [
        sdkPath
        "${config.xdg.dataHome}/android-kernel/bzImage"
      ];
      dev = [
        "/dev/kvm"
        "/dev/bus/usb"
      ];
    };
  };

  start-rooted-1 = config.mkSandbox (
    {
      appId = "rooted.android.first";
      package = pkgs.writeShellScriptBin "start-rooted-1" ''
        export ANDROID_HOME="${sdkPath}"
        export ANDROID_SDK_ROOT="${sdkPath}"
        export ANDROID_AVD_HOME="${config.xdg.dataHome}/.android/avd"
        if [[ ! -d "$ANDROID_AVD_HOME/rooted-1.avd" ]]; then
          mkdir -p "$ANDROID_AVD_HOME/rooted-1.avd"
          cp --no-preserve=mode "${../../../stuff/android.ini}" "$ANDROID_AVD_HOME/rooted-1.avd/config.ini"
          echo "
            avd.ini.encoding=UTF-8
            path=$ANDROID_AVD_HOME/rooted-1.avd
            path.rel=avd/rooted-1.avd
            target=android-CANARY
          " > "$ANDROID_AVD_HOME/rooted-1.ini"
        fi
        ${shared-start} -kernel "$XDG_DATA_HOME/android-kernel/bzImage" -avd rooted-1 "$@"
        adb kill-server
      '';
    }
    // shared-attrs
  );

  start-rooted-2 = config.mkSandbox (
    {
      appId = "rooted.android.second";
      package = pkgs.writeShellScriptBin "start-rooted2" ''
        export ANDROID_HOME="${sdkPath}"
        export ANDROID_SDK_ROOT="${sdkPath}"
        export ANDROID_AVD_HOME="${config.xdg.dataHome}/.android/avd"
        if [[ ! -d "$ANDROID_AVD_HOME/rooted-2.avd" ]]; then
          mkdir -p "$ANDROID_AVD_HOME/rooted-2.avd"
          cp --no-preserve=mode "${../../../stuff/android.ini}" "$ANDROID_AVD_HOME/rooted-2.avd/config.ini"
          echo "
            avd.ini.encoding=UTF-8
            path=$ANDROID_AVD_HOME/rooted-2.avd
            path.rel=avd/rooted-2.avd
            target=android-CANARY
          " > "$ANDROID_AVD_HOME/rooted-2.ini"
        fi
        ${shared-start} -kernel "$XDG_DATA_HOME/android-kernel/bzImage" -avd rooted-2 "$@"
        adb kill-server
      '';
    }
    // shared-attrs
  );

  start-unrooted = config.mkSandbox (
    {
      appId = "unrooted.android";
      package = pkgs.writeShellScriptBin "start-unrooted" ''
        export ANDROID_HOME="${sdkPath}"
        export ANDROID_SDK_ROOT="${sdkPath}"
        export ANDROID_AVD_HOME="${config.xdg.dataHome}/.android/avd"
        if [[ ! -d "$ANDROID_AVD_HOME/unrooted.avd" ]]; then
          mkdir -p "$ANDROID_AVD_HOME/unrooted.avd"
          cp --no-preserve=mode "${../../../stuff/android.ini}" "$ANDROID_AVD_HOME/unrooted.avd/config.ini"
          echo "
            avd.ini.encoding=UTF-8
            path=$ANDROID_AVD_HOME/unrooted.avd
            path.rel=avd/unrooted.avd
            target=android-CANARY
          " > "$ANDROID_AVD_HOME/unrooted.ini"
        fi
        ${shared-start} -avd unrooted "$@"
        adb kill-server
      '';
    }
    // shared-attrs
  );

  sdkPackage = inputs.android-nixpkgs.sdk.${pkgs.stdenv.hostPlatform.system} (
    sdkPkgs: with sdkPkgs; [
      cmdline-tools-latest
      emulator
      system-images-android-CANARY-google-apis-playstore-x86-64
      platform-tools
    ]
  );

  sdkPath = "${config.xdg.dataHome}/android";

  makefile = builtins.readFile (inputs.android-kernel-src + "/Makefile");
  makefileLines = lib.splitString "\n" makefile;

  getMakeVar =
    var:
    let
      matches = map (line: builtins.match "${var}[ \t]*=[ \t]*([0-9a-zA-Z_-]*).*" line) makefileLines;
      validMatches = lib.filter (m: m != null) matches;
    in
    if validMatches == [ ] then "" else builtins.head (builtins.head validMatches);

  kernelVersion = "${getMakeVar "VERSION"}.${getMakeVar "PATCHLEVEL"}.${getMakeVar "SUBLEVEL"}${getMakeVar "EXTRAVERSION"}";
in
{
  options.android.enable = lib.mkEnableOption "android vm";

  config = lib.mkIf cfg.enable {
    home = {
      file.${sdkPath}.source = "${sdkPackage}/share/android-sdk";
      packages = [
        sdkPackage
        start-rooted-1
        start-rooted-2
        start-unrooted
      ];
      sessionVariables = {
        ANDROID_HOME = sdkPath;
        ANDROID_SDK_ROOT = sdkPath;
        ANDROID_AVD_HOME = "${config.xdg.dataHome}/.android/avd";
      };
    };

    xdg = {
      desktopEntries = {
        "rooted.android.first" = {
          name = "Android VM with KSU Next (first)";
          exec = "${start-rooted-1}/bin/start-rooted-1";
          icon = ../../../stuff/android.png;
        };
        "rooted.android.second" = {
          name = "Android VM with KSU Next (second)";
          exec = "${start-rooted-2}/bin/start-rooted-2";
          icon = ../../../stuff/android.png;
        };
        "unrooted.android" = {
          name = "Android VM";
          exec = "${start-unrooted}/bin/start-unrooted";
          icon = ../../../stuff/android.png;
        };
      };
      dataFile.android-kernel.source =
        (pkgs.buildLinux {
          stdenv = pkgs.llvmPackages_18.stdenv;
          version = "${kernelVersion}-android16";
          modDirVersion = kernelVersion;
          src = inputs.android-kernel-src;
          defconfig = "gki_defconfig";

          enableCommonConfig = false;
          autoModules = false;
          ignoreConfigErrors = true;

          structuredExtraConfig = with pkgs.lib.kernel; {
            KSU = yes;
            KSU_SUSFS = yes;
            KSU_MANUAL_HOOK = yes;
            KSU_KPROBES_HOOK = no;
            ANDROID_BINDER_IPC = yes;
            CFI_CLANG = yes;
            CFI_PERMISSIVE = yes;
          };

          kernelPatches = [
            {
              name = "fix-susfs";
              patch = ../../../stuff/fix_susfs.patch;
            }
            {
              name = "fix-syscalls";
              patch = ../../../stuff/fix_syscalls.patch;
            }
            {
              name = "susfs-kernel-core";
              patch = "${inputs.susfs4ksu}/kernel_patches/50_add_susfs_in_gki-android16-6.12.patch";
            }
          ];

        }).overrideAttrs
          (oldAttrs: {
            nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [
              pkgs.lz4
              pkgs.llvmPackages_18.lld
            ];

            postPatch = (oldAttrs.postPatch or "") + ''
              substituteInPlace fs/proc/task_mmu.c \
                --replace-fail 'if (!vma_pages(vma))' 'if (!vma_data_pages(vma))'
            '';

            prePatch = (oldAttrs.prePatch or "") + ''
              mkdir -p drivers/kernelsu
              cp -rL ${inputs.ksu-next}/kernel/* drivers/kernelsu/
              chmod -R +w drivers/kernelsu

              cp ${inputs.susfs4ksu}/kernel_patches/fs/* fs/
              cp ${inputs.susfs4ksu}/kernel_patches/include/linux/* include/linux/
              chmod +w fs/* include/linux/*

              echo 'obj-y += kernelsu/' >> drivers/Makefile
              substituteInPlace drivers/Kconfig \
                --replace-fail 'source "drivers/devfreq/Kconfig"' 'source "drivers/devfreq/Kconfig"
                source "drivers/kernelsu/Kconfig"'

              substituteInPlace kernel/module/main.c \
                --replace-fail '#include "internal.h"' '#include "internal.h"
              #define same_magic(...) 1
              #define check_modstruct_version(...) 1
              #define check_version(...) 1'

              substituteInPlace kernel/cfi.c \
                --replace-fail 'report_cfi_failure(struct pt_regs *regs, unsigned long addr,' \
                               'report_cfi_failure_unused(struct pt_regs *regs, unsigned long addr,'

              echo 'enum bug_trap_type report_cfi_failure(struct pt_regs *regs, unsigned long addr, unsigned long *target, u32 type) { return BUG_TRAP_TYPE_WARN; }' >> kernel/cfi.c

              substituteInPlace init/version.c \
                --replace-fail 'LINUX_COMPILER' '"gcc version (clang " LINUX_COMPILER ")"'

              substituteInPlace drivers/kernelsu/Kbuild \
                --replace-fail '-Wno-unused-variable' '-Wno-unused-variable -Wno-unused-result'

              substituteInPlace drivers/kernelsu/policy/app_profile.c \
                --replace-fail '#include <linux/seccomp.h>' '#include <linux/seccomp.h>
                #include <linux/version.h>
                #if defined(CONFIG_GENERIC_ENTRY) && LINUX_VERSION_CODE >= KERNEL_VERSION(5, 11, 0)
                #include <linux/entry-common.h>
                #endif' \
                --replace-fail 'if (likely(test_thread_flag(TIF_SECCOMP)))' '
                #if defined(CONFIG_GENERIC_ENTRY) && LINUX_VERSION_CODE >= KERNEL_VERSION(5, 11, 0)
                    if (likely(test_syscall_work(SECCOMP)))
                #else
                    if (likely(test_thread_flag(TIF_SECCOMP)))
                #endif'

              substituteInPlace drivers/kernelsu/runtime/ksud.h \
                --replace-fail '#include <asm/syscall.h>' '#include <asm/syscall.h>
                #ifdef CONFIG_COMPAT
                #include <linux/compat.h>
                #endif'
            '';

            makeFlags = (oldAttrs.makeFlags or [ ]) ++ [
              "LLVM=1"
              "KSU_GIT_VERSION=${toString inputs.ksu-next.revCount}"
              "KSU_VERSION_TAG=v3.2.0"
              "KSU_GIT_VERSION_VALID=1"
              "KSU_KERNEL_DIR=../drivers/kernelsu"
            ];
          });
    };
  };
}
