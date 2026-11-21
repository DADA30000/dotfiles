{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.replays;

  gsrPatched = pkgs.gpu-screen-recorder.overrideAttrs (prev: {
    patches = (prev.patches or [ ]) ++ [ ../../../stuff/patches/gsr-ambient-cap.patch ];
  });

  replaysRunner = pkgs.writeShellApplication {
    name = "replays-system-runner";
    runtimeInputs = [
      gsrPatched
      pkgs.coreutils
      pkgs.findutils
      pkgs.gawk
      pkgs.gnused
      pkgs.gnugrep
    ];
    text = ''
      set -euo pipefail
      export XDG_RUNTIME_DIR="/run/replays"
      export HOME="/var/cache/replays"
      export PULSE_SERVER="unix:/run/replays/pulse/native"
      if [ -f /run/replays/replays.env ]; then
        set -a
        # shellcheck disable=SC1091
        . /run/replays/replays.env
        set +a
      fi
      export WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-wayland-1}"

      mkdir -p /var/lib/replays
      pids=()
      for status_file in /sys/class/drm/*/status; do
        [ -r "$status_file" ] || continue
        if grep -q '^connected' "$status_file"; then
          mon=$(basename "$(dirname "$status_file")" | sed -E 's/^card[0-9]+-//')
          if [ -n "$mon" ]; then
            mkdir -p "/var/lib/replays/$mon"
            gpu-screen-recorder \
              -w "$mon" \
              -s 1920x1080 \
              -k hevc \
              -q ultra \
              -a default_output \
              -a default_input \
              -f 60 \
              -r 300 \
              -c mkv \
              -o "/var/lib/replays/$mon" &
            pids+=("$!")
          fi
        fi
      done

      if [ "''${#pids[@]}" -eq 0 ]; then
        echo "replays: no connected monitors found" >&2
        exit 1
      fi
      wait
    '';
  };

  replaysSaveScript = pkgs.writers.writePython3 "replays-save-runner" {
    flakeIgnore = [ "E501" ];
  } ''
    import ctypes
    import os
    import pwd
    import re
    import select
    import shutil
    import signal
    import struct
    import subprocess
    import sys

    IN_CLOEXEC = 0o2000000
    IN_CLOSE_WRITE = 0x00000008
    IN_MOVED_TO = 0x00000080

    libc = ctypes.CDLL("libc.so.6", use_errno=True)
    libc.inotify_init1.argtypes = [ctypes.c_int]
    libc.inotify_init1.restype = ctypes.c_int
    libc.inotify_add_watch.argtypes = [
        ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32
    ]
    libc.inotify_add_watch.restype = ctypes.c_int

    NOTIFY_BIN = "${pkgs.libnotify}/bin/notify-send"


    def notify_user(uid: int, gid: int, title: str, body: str,
                    urgency: str = "normal") -> None:
        env = {
            "DBUS_SESSION_BUS_ADDRESS": f"unix:path=/run/user/{uid}/bus",
            "XDG_RUNTIME_DIR": f"/run/user/{uid}",
        }
        subprocess.run(
            [NOTIFY_BIN, "-u", urgency, title, body],
            user=uid,
            group=gid,
            extra_groups=[],
            env=env,
            check=False,
        )


    def find_gsr_pids(replays_uid: int, mon: str) -> list[int]:
        pids = []
        for entry in os.listdir("/proc"):
            if not entry.isdigit():
                continue
            pid = int(entry)
            try:
                if os.stat(f"/proc/{pid}").st_uid != replays_uid:
                    continue
                with open(f"/proc/{pid}/cmdline", "rb") as f:
                    argv = [
                        p.decode("utf-8", "replace")
                        for p in f.read().split(b"\0") if p
                    ]
            except OSError:
                continue
            if not argv:
                continue
            prog = os.path.basename(argv[0])
            if "gpu-screen-recorder" not in prog:
                continue
            for idx, arg in enumerate(argv):
                if arg == "-w" and idx + 1 < len(argv) and argv[idx + 1] == mon:
                    pids.append(pid)
                    break
        return pids


    def main() -> int:
        if len(sys.argv) != 2 or not sys.argv[1].isdigit():
            print("usage: replays-save-runner <uid>", file=sys.stderr)
            return 2

        uid = int(sys.argv[1])
        pw = pwd.getpwuid(uid)
        replays_pw = pwd.getpwnam("replays")

        mon_file = f"/run/user/{uid}/replays-save.mon"
        if not os.path.isfile(mon_file):
            notify_user(uid, pw.pw_gid, "GPU-Screen-Recorder",
                        "Запрос сохранения повтора без указанного монитора",
                        "critical")
            return 1

        with open(mon_file, "r", encoding="utf-8") as f:
            mon = f.read().strip()

        if not re.fullmatch(r"[A-Za-z0-9._-]+", mon):
            notify_user(uid, pw.pw_gid, "GPU-Screen-Recorder",
                        "Отклонён некорректный идентификатор монитора",
                        "critical")
            return 1

        src_dir = f"/var/lib/replays/{mon}"
        dst_dir = os.path.join(pw.pw_dir, "Documents", "Replays", mon)
        os.makedirs(dst_dir, exist_ok=True)
        os.chown(dst_dir, uid, pw.pw_gid)

        pids = find_gsr_pids(replays_pw.pw_uid, mon)
        if not pids:
            notify_user(uid, pw.pw_gid, "GPU-Screen-Recorder",
                        f"Не найден активный рекордер для {mon}",
                        "critical")
            return 1

        ifd = libc.inotify_init1(IN_CLOEXEC)
        if ifd < 0:
            raise OSError(ctypes.get_errno(), "inotify_init1 failed")

        saved_name = None
        try:
            wd = libc.inotify_add_watch(
                ifd, src_dir.encode("utf-8"), IN_CLOSE_WRITE | IN_MOVED_TO
            )
            if wd < 0:
                raise OSError(ctypes.get_errno(), f"inotify_add_watch {src_dir}")

            # Trigger save only after the inotify watch is armed
            for pid in pids:
                os.kill(pid, signal.SIGUSR1)

            deadline_sec = 15.0
            while deadline_sec > 0 and saved_name is None:
                rlist, _, _ = select.select([ifd], [], [], deadline_sec)
                if not rlist:
                    break
                data = os.read(ifd, 4096)
                offset = 0
                while offset + 16 <= len(data):
                    _, _, _, name_len = struct.unpack_from("iIII", data, offset)
                    offset += 16
                    raw_name = data[offset:offset + name_len]
                    offset += name_len
                    name = raw_name.split(b"\0", 1)[0].decode("utf-8", "replace")
                    if name and not name.startswith("."):
                        saved_name = name
                        break
                deadline_sec = 0.5
        finally:
            os.close(ifd)

        if saved_name:
            src_path = os.path.join(src_dir, saved_name)
            dst_path = os.path.join(dst_dir, saved_name)
            shutil.move(src_path, dst_path)
            os.chown(dst_path, uid, pw.pw_gid)
            os.chmod(dst_path, 0o640)
            print(f"replays-save: saved {dst_path} for uid={uid}")
            notify_user(uid, pw.pw_gid, "GPU-Screen-Recorder",
                        f"Повтор с {mon} успешно сохранён ({saved_name})")
            return 0

        print(f"replays-save: timed out waiting for clip on {mon}",
              file=sys.stderr)
        notify_user(uid, pw.pw_gid, "GPU-Screen-Recorder",
                    f"Запрос сохранения повтора с {mon} (таймаут ожидания файла)",
                    "critical")
        return 1


    if __name__ == "__main__":
        sys.exit(main())
  '';
in
{
  options.replays.enable = lib.mkEnableOption "isolated GPU Screen Recorder replay shim + mandatory-notification saver";

  config = lib.mkIf cfg.enable {
    users.users.replays = {
      isSystemUser = true;
      group = "replays";
      extraGroups = [
        "video"
        "render"
      ];
    };
    users.groups.replays = { };

    environment.systemPackages = [ gsrPatched ];

    systemd.services = {
      "replays@" = {
        description = "Isolated GPU Screen Recorder replay daemon for UID %i";
        after = [
          "graphical.target"
          "user@%i.service"
        ];
        bindsTo = [ "user@%i.service" ];
        serviceConfig = {
          Type = "simple";
          User = "replays";
          Group = "replays";
          SupplementaryGroups = [
            "video"
            "render"
          ];
          ExecStart = "${replaysRunner}/bin/replays-system-runner";
          Restart = "on-failure";
          RestartSec = "5s";
          KillMode = "control-group";

          StateDirectory = "replays";
          StateDirectoryMode = "0700";
          CacheDirectory = "replays";
          CacheDirectoryMode = "0700";
          RuntimeDirectory = "replays";
          RuntimeDirectoryMode = "0700";

          # Expose ONLY the audio + Wayland sockets needed by GSR (no /run/user/%i/bus or $HOME)
          BindPaths = [
            "-/run/user/%i/pipewire-0:/run/replays/pipewire-0"
            "-/run/user/%i/pulse/native:/run/replays/pulse/native"
            "-/run/user/%i/wayland-0:/run/replays/wayland-0"
            "-/run/user/%i/wayland-1:/run/replays/wayland-1"
          ];
          BindReadOnlyPaths = [
            "-/run/user/%i/replays.env:/run/replays/replays.env"
          ];

          # Systemd-scoped CAP_SYS_ADMIN replaces /run/wrappers/bin/gsr-kms-server
          AmbientCapabilities = [ "CAP_SYS_ADMIN" ];
          CapabilityBoundingSet = [ "CAP_SYS_ADMIN" ];
          NoNewPrivileges = true;

          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateNetwork = true;
          IPAddressDeny = "any";
          ProtectClock = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectControlGroups = true;
          ProtectProc = "invisible";
          LockPersonality = true;
          RestrictNamespaces = true;
          RestrictSUIDSGID = true;
          KeyringMode = "private";
          RestrictAddressFamilies = [ "AF_UNIX" ];
          SystemCallArchitectures = "native";
          SystemCallErrorNumber = "EPERM";
          SystemCallFilter = [
            "@system-service"
            "~@clock"
            "~@cpu-emulation"
            "~@debug"
            "~@module"
            "~@mount"
            "~@obsolete"
            "~@raw-io"
            "~@reboot"
            "~@swap"
          ];
          UMask = "0077";
        };
      };

      "replays-save@" = {
        description = "Save replay from isolated GSR daemon and notify UID %i";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${replaysSaveScript} %i";

          CapabilityBoundingSet = [
            "CAP_KILL"
            "CAP_DAC_OVERRIDE"
            "CAP_CHOWN"
            "CAP_FOWNER"
            "CAP_SETUID"
            "CAP_SETGID"
          ];
          NoNewPrivileges = true;

          ProtectSystem = "strict";
          ReadWritePaths = [
            "/var/lib/replays"
            "/home"
          ];
          InaccessiblePaths = [
            "-/run/dbus/system_bus_socket"
            "-/run/systemd/private"
          ];
          PrivateDevices = true;
          DevicePolicy = "closed";
          PrivateTmp = true;
          PrivateNetwork = true;
          IPAddressDeny = "any";
          PrivateIPC = true;
          ProtectClock = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectControlGroups = true;
          LockPersonality = true;
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          KeyringMode = "private";
          RestrictAddressFamilies = [ "AF_UNIX" ];
          SystemCallArchitectures = "native";
          SystemCallErrorNumber = "EPERM";
          SystemCallFilter = [
            "@system-service"
            "~@clock"
            "~@cpu-emulation"
            "~@debug"
            "~@module"
            "~@mount"
            "~@obsolete"
            "~@raw-io"
            "~@reboot"
            "~@swap"
          ];
          UMask = "0077";
        };
      };
    };

    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units") {
          var unit = action.lookup("unit");
          if (unit === "replays@" + subject.uid + ".service" ||
              unit === "replays-save@" + subject.uid + ".service") {
            return polkit.Result.YES;
          }
        }
      });
    '';
  };
}
