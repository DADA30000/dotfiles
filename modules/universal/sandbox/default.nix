args@{
  lib,
  options,
  pkgs,
  inputs,
  config,
  ...
}:
let
  staticBwrap = pkgs.pkgsStatic.bubblewrap;
  patchedStaticDbusProxy = pkgs.pkgsStatic.xdg-dbus-proxy.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ../../../stuff/patches/xdg-dbus-proxy-unicast-signals.patch
    ];
  });

  staticDbusProxy =
    pkgs.runCommand "xdg-dbus-proxy"
      {
        nativeBuildInputs = [
          pkgs.nukeReferences
          pkgs.removeReferencesTo
        ];
      }
      ''
        mkdir -p $out/bin
        cp ${patchedStaticDbusProxy}/bin/xdg-dbus-proxy $out/bin/
        remove-references-to -t ${pkgs.pkgsStatic.glib.dev} $out/bin/xdg-dbus-proxy
        remove-references-to -t ${pkgs.pkgsStatic.glib.out} $out/bin/xdg-dbus-proxy
        ${pkgs.nukeReferences}/bin/nuke-refs $out/bin/xdg-dbus-proxy
        chmod +x $out/bin/xdg-dbus-proxy
      '';
  sloth = import ./sloth.nix { inherit lib; };

  processes_to_proxy =
    if (args ? osConfig) && (args.osConfig ? sing-box.processes_to_proxy) then
      args.osConfig.sing-box.processes_to_proxy
    else
      config.sing-box.processes_to_proxy;

  sing-box-sandbox-config = (pkgs.formats.json { }).generate "sing-box-sandbox-config" {
    log.level = "info";
    log.timestamp = true;
    route = {
      final = "direct";
      rules = [
        {
          action = "sniff";
        }
        {
          inbound = [
            "dns-in"
            "dns-in6"
          ];
          outbound = "direct";
        }
        {
          port = [ 53 ];
          outbound = "direct";
        }
        {
          ip_cidr = [
            "127.0.0.0/8"
            "::1/128"
          ];
          outbound = "real-direct";
        }
        {
          outbound = "to-host-vpn";
          process_name = processes_to_proxy;
        }
      ];
    };
    inbounds = [
      {
        type = "direct";
        tag = "dns-in";
        listen = "127.0.0.1";
        listen_port = 53;
      }
      {
        type = "direct";
        tag = "dns-in6";
        listen = "::1";
        listen_port = 53;
      }
      {
        type = "tun";
        tag = "tun-in";
        interface_name = "sb-net";
        address = [
          "172.19.0.5/30"
          "fd00::5/126"
        ];
        auto_route = true;
        strict_route = true;
        auto_redirect = true;
        iproute2_table_index = 254;
        stack = "system";
        mtu = 1480;
      }
    ];
    outbounds = [
      {
        type = "vless";
        tag = "to-host-vpn";
        server = "127.0.0.1";
        server_port = 1919;
        uuid = "a1c0d4be-6c12-485c-8515-4451ee91ddc3";
        packet_encoding = "xudp";
      }
      {
        type = "vless";
        tag = "direct";
        server = "127.0.0.1";
        server_port = 2121;
        uuid = "a1c0d4be-6c12-485c-8515-4451ee91ddc3";
        packet_encoding = "xudp";
      }
      {
        tag = "real-direct";
        type = "direct";
      }
    ];
  };

  sing-box-lite =
    (pkgs.sing-box.override {
      withNaiveOutbound = false;
      withStaticCronet = false;
    }).overrideAttrs
      (prev: {
        ldflags = (prev.ldflags or [ ]) ++ [
          "-s"
          "-w"
        ];
        tags = [
          "with_inbound_tun"
          "with_outbound_vless"
          "with_outbound_direct"
          "with_local_interceptor"
        ];
      });

  pasta-pkg = pkgs.passt.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ../../../stuff/patches/passt-fix-user-namespace-detection.patch
    ];
  });

  way-secure-pkg = pkgs.rustPlatform.buildRustPackage {
    pname = "way-secure";
    version = "unstable";
    src = inputs.way-secure;
    cargoLock.lockFile = "${inputs.way-secure}/Cargo.lock";
  };

  syscallsJson = pkgs.runCommand "sb-syscalls.json" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python3 - "${pkgs.linuxHeaders}/include/asm/unistd_64.h" "${pkgs.linuxHeaders}/include/asm/unistd_32.h" "$out" << 'EOF'
    import json, re, sys

    def parse_header(path):
        res = {}
        with open(path, "r") as f:
            for line in f:
                m = re.match(r"^\s*#define\s+__NR_([a-zA-Z0-9_]+)\s+(\d+)\s*$", line)
                if m:
                    res[m.group(1)] = int(m.group(2))
        return res

    data = {
        "x86_64": parse_header(sys.argv[1]),
        "i386": parse_header(sys.argv[2]),
    }
    with open(sys.argv[3], "w") as out:
        json.dump(data, out, sort_keys=True)
    EOF
  '';

  sbRunConfigData = {
    defaults = {
      network = "sandboxed";
      wayland = "sandboxed";
      x11 = "off";
      pulse = "sandboxed";
      pipewire = "sandboxed";
      dbus = "sandboxed";
      shm = "sandboxed";
      tmp = "sandboxed";
      webcam = 0;
      gpu = false;
      gamepad = false;
      landlock = true;
      seccomp = true;
      portals = true;
      tmpfs = false;
      share_pid = false;
      share_ipc = false;
      vpnify = false;
      flatpak_info = true;
      scope = true;
    };
    bins = {
      bwrap = "${staticBwrap}/bin/bwrap";
      sb_executor = "/run/current-system/sw/bin/sb-executor";
      dbus_proxy = "${staticDbusProxy}/bin/xdg-dbus-proxy";
      way_secure = "${way-secure-pkg}/bin/way-secure";
      pasta = "${pasta-pkg}/bin/pasta";
      xwayland_satellite = "${pkgs.xwayland-satellite}/bin/xwayland-satellite";
      singbox = "${sing-box-lite}/bin/sing-box";
      rust_bridge = "/run/current-system/sw/bin/rust-bridge";
      app2unit = "app2unit";
      systemctl = "${pkgs.systemd}/bin/systemctl";
      vpnify = "/run/wrappers/bin/vpnify";
      notify_send = "${pkgs.libnotify}/bin/notify-send";
      neovide = "neovide";
    };
    singbox_config = "/etc/sb-run/sing-box.json";
    syscalls_file = "/etc/sb-run/syscalls.json";
    seccomp = {
      default_allowed = [
        # Process / thread / runtime / scheduling
        "exit"
        "exit_group"
        "fork"
        "vfork"
        "clone"
        "clone3"
        "execve"
        "execveat"
        "wait4"
        "waitid"
        "waitpid"
        "getpid"
        "getppid"
        "gettid"
        "getpgid"
        "getpgrp"
        "setpgid"
        "getsid"
        "setsid"
        "getuid"
        "geteuid"
        "getgid"
        "getegid"
        "getresuid"
        "getresgid"
        "getgroups"
        "setuid"
        "setgid"
        "setreuid"
        "setregid"
        "setresuid"
        "setresgid"
        "setfsuid"
        "setfsgid"
        "setgroups"
        "getuid32"
        "geteuid32"
        "getgid32"
        "getegid32"
        "getresuid32"
        "getresgid32"
        "getgroups32"
        "setuid32"
        "setgid32"
        "setreuid32"
        "setregid32"
        "setresuid32"
        "setresgid32"
        "setfsuid32"
        "setfsgid32"
        "setgroups32"
        "capget"
        "capset"
        "prctl"
        "arch_prctl"
        "seccomp"
        "landlock_create_ruleset"
        "landlock_add_rule"
        "landlock_restrict_self"
        "lsm_get_self_attr"
        "lsm_list_modules"
        "getrlimit"
        "setrlimit"
        "ugetrlimit"
        "prlimit64"
        "getrusage"
        "times"
        "uname"
        "sysinfo"
        "umask"
        "getpriority"
        "setpriority"
        "nice"
        "sched_yield"
        "sched_getaffinity"
        "sched_setaffinity"
        "sched_getparam"
        "sched_setparam"
        "sched_getscheduler"
        "sched_setscheduler"
        "sched_getattr"
        "sched_setattr"
        "sched_get_priority_max"
        "sched_get_priority_min"
        "sched_rr_get_interval"
        "sched_rr_get_interval_time64"
        "ioprio_get"
        "ioprio_set"
        "set_tid_address"
        "set_robust_list"
        "get_robust_list"
        "set_thread_area"
        "get_thread_area"
        "rseq"
        "rseq_slice_yield"
        "pidfd_open"
        "pidfd_getfd"
        "pidfd_send_signal"

        # Signals / timers / clocks (read-only)
        "rt_sigaction"
        "rt_sigprocmask"
        "rt_sigreturn"
        "rt_sigpending"
        "rt_sigtimedwait"
        "rt_sigtimedwait_time64"
        "rt_sigqueueinfo"
        "rt_tgsigqueueinfo"
        "rt_sigsuspend"
        "sigaction"
        "signal"
        "sigpending"
        "sigprocmask"
        "sigreturn"
        "sigsuspend"
        "sgetmask"
        "ssetmask"
        "sigaltstack"
        "restart_syscall"
        "kill"
        "tkill"
        "tgkill"
        "pause"
        "alarm"
        "nanosleep"
        "clock_nanosleep"
        "clock_nanosleep_time64"
        "clock_gettime"
        "clock_gettime64"
        "clock_getres"
        "clock_getres_time64"
        "gettimeofday"
        "time"
        "getitimer"
        "setitimer"
        "timer_create"
        "timer_delete"
        "timer_getoverrun"
        "timer_gettime"
        "timer_gettime64"
        "timer_settime"
        "timer_settime64"
        "timerfd_create"
        "timerfd_gettime"
        "timerfd_gettime64"
        "timerfd_settime"
        "timerfd_settime64"

        # Memory management & futex
        "brk"
        "mmap"
        "mmap2"
        "munmap"
        "mprotect"
        "mremap"
        "msync"
        "mincore"
        "madvise"
        "mlock"
        "mlock2"
        "munlock"
        "mlockall"
        "munlockall"
        "membarrier"
        "memfd_create"
        "mseal"
        "map_shadow_stack"
        "pkey_alloc"
        "pkey_free"
        "pkey_mprotect"
        "cachestat"
        "mbind"
        "get_mempolicy"
        "set_mempolicy"
        "futex"
        "futex_time64"
        "futex_wait"
        "futex_wake"
        "futex_requeue"
        "futex_waitv"
        "getcpu"
        "getrandom"

        # Filesystem / FD / I/O
        "read"
        "write"
        "open"
        "openat"
        "openat2"
        "creat"
        "close"
        "close_range"
        "lseek"
        "_llseek"
        "pread64"
        "pwrite64"
        "readv"
        "writev"
        "preadv"
        "pwritev"
        "preadv2"
        "pwritev2"
        "readahead"
        "stat"
        "fstat"
        "lstat"
        "stat64"
        "fstat64"
        "lstat64"
        "newfstatat"
        "fstatat64"
        "statx"
        "statfs"
        "fstatfs"
        "statfs64"
        "fstatfs64"
        "ustat"
        "access"
        "faccessat"
        "faccessat2"
        "chdir"
        "fchdir"
        "getcwd"
        "getdents"
        "getdents64"
        "readlink"
        "readlinkat"
        "link"
        "linkat"
        "unlink"
        "unlinkat"
        "symlink"
        "symlinkat"
        "rename"
        "renameat"
        "renameat2"
        "mkdir"
        "mkdirat"
        "rmdir"
        "mknod"
        "mknodat"
        "chmod"
        "fchmod"
        "fchmodat"
        "fchmodat2"
        "chown"
        "fchown"
        "lchown"
        "fchownat"
        "chown32"
        "fchown32"
        "lchown32"
        "truncate"
        "ftruncate"
        "truncate64"
        "ftruncate64"
        "fallocate"
        "fadvise64"
        "fadvise64_64"
        "fsync"
        "fdatasync"
        "sync"
        "syncfs"
        "sync_file_range"
        "utime"
        "utimes"
        "futimesat"
        "utimensat"
        "utimensat_time64"
        "dup"
        "dup2"
        "dup3"
        "fcntl"
        "fcntl64"
        "flock"
        "ioctl"
        "getxattr"
        "lgetxattr"
        "fgetxattr"
        "getxattrat"
        "setxattr"
        "lsetxattr"
        "fsetxattr"
        "setxattrat"
        "listxattr"
        "llistxattr"
        "flistxattr"
        "listxattrat"
        "removexattr"
        "lremovexattr"
        "fremovexattr"
        "removexattrat"
        "file_getattr"
        "file_setattr"
        "copy_file_range"
        "sendfile"
        "sendfile64"
        "splice"
        "vmsplice"
        "tee"

        # Event loops / pipes / async I/O / IPC
        "pipe"
        "pipe2"
        "poll"
        "ppoll"
        "ppoll_time64"
        "select"
        "_newselect"
        "pselect6"
        "pselect6_time64"
        "epoll_create"
        "epoll_create1"
        "epoll_ctl"
        "epoll_ctl_old"
        "epoll_wait"
        "epoll_wait_old"
        "epoll_pwait"
        "epoll_pwait2"
        "eventfd"
        "eventfd2"
        "signalfd"
        "signalfd4"
        "inotify_init"
        "inotify_init1"
        "inotify_add_watch"
        "inotify_rm_watch"
        "io_setup"
        "io_destroy"
        "io_submit"
        "io_cancel"
        "io_getevents"
        "io_pgetevents"
        "io_pgetevents_time64"
        "io_uring_setup"
        "io_uring_enter"
        "io_uring_register"
        "mq_open"
        "mq_unlink"
        "mq_timedsend"
        "mq_timedsend_time64"
        "mq_timedreceive"
        "mq_timedreceive_time64"
        "mq_notify"
        "mq_getsetattr"
        "shmget"
        "shmat"
        "shmdt"
        "shmctl"
        "semget"
        "semop"
        "semtimedop"
        "semtimedop_time64"
        "semctl"
        "msgget"
        "msgsnd"
        "msgrcv"
        "msgctl"
        "ipc"

        # Networking & sockets
        "socket"
        "socketpair"
        "socketcall"
        "bind"
        "listen"
        "accept"
        "accept4"
        "connect"
        "shutdown"
        "getsockname"
        "getpeername"
        "setsockopt"
        "getsockopt"
        "sendto"
        "sendmsg"
        "sendmmsg"
        "recvfrom"
        "recvmsg"
        "recvmmsg"
        "recvmmsg_time64"
      ];
      silent_errno = [
        "clone_newuser"
        "unshare"
        "setns"
        "ptrace"
      ];
    };
    dbus = {
      default_talks = [
        "org.freedesktop.portal.Desktop"
        "org.freedesktop.portal.Documents"
        "org.freedesktop.portal.Secret"
        "org.freedesktop.Notifications"
        "org.freedesktop.FileManager1"
        "org.freedesktop.ScreenSaver"
        "org.gnome.Mutter.IdleMonitor"
        "org.kde.StatusNotifierWatcher"
        "org.ayatana.indicator.application"
        "com.canonical.AppMenu.Registrar"
        "org.mpris.MediaPlayer2.Player"
      ];
      default_owns = [
        "org.kde.StatusNotifierItem.*"
        "org.kde.StatusNotifierItem"
        "org.mpris.MediaPlayer2.*"
      ];
    };
    pasta_args = [
      "--config-net"
      "--no-dhcp"
      "--no-dhcpv6"
      "--no-ra"
      "--no-map-gw"
      "-t"
      "none"
      "-u"
      "none"
      "-T"
      "none"
      "-U"
      "none"
      "--ns-ifname"
      "eth0"
      "--address"
      "192.168.1.100"
      "--netmask"
      "255.255.255.0"
      "--gateway"
      "192.168.1.1"
      "--dns-forward"
      "192.168.1.1"
      "--search"
      "none"
    ];
    paths = {
      allowed_env_vars = [
        "HOME"
        "XDG_RUNTIME_DIR"
        "XDG_CONFIG_HOME"
        "XDG_DATA_HOME"
        "XDG_STATE_HOME"
        "XDG_CACHE_HOME"
        "USER"
      ];
      ro_system_paths = [
        "/nix/store"
        "/bin"
        "/usr/bin"
        "/run/current-system"
        "/etc/xdg"
        "/etc/fonts"
        "/etc/localtime"
        "/etc/zoneinfo"
        "/etc/profiles"
        "/etc/static"
        "/nix/profile"
        "/nix/var/nix/profiles"
        "/etc/ssl/certs"
        "/etc/static/ssl/certs"
        "/etc/pki"
        "/etc/hosts"
        "/etc/nsswitch.conf"
        "/etc/machine-id"
        "/etc/os-release"
        "/etc/mime.types"
        "/etc/passwd"
        "/etc/group"
        "/sys/class/hwmon"
        "/etc/xdg/openxr"
      ];
      user_theme_subpaths = [
        ".nix-profile"
        ".local/state/nix/profile"
        ".icons"
        ".themes"
      ];
      xdg_config_subpaths = [
        "user-dirs.dirs"
        "user-dirs.conf"
        "gtk-4.0"
        "gtk-3.0"
        "qt6ct"
        "qt5ct"
        "Kvantum"
        "starship.toml"
        "fastfetch"
        "openvr"
        "openxr"
      ];
      xdg_data_subpaths = [
        "zsh/.zshenv"
        "zsh/.zshrc"
        "icons"
        "themes"
      ];
      nvidia_nodes = [
        "/dev/nvidia0"
        "/dev/nvidiactl"
        "/dev/nvidia-modeset"
        "/dev/nvidia-uvm"
        "/dev/nvidia-uvm-tools"
      ];
    };
  };

  sbRunConfigFile = (pkgs.formats.json { }).generate "sb-run-config.json" sbRunConfigData;

  portal-xdg-open = pkgs.writeShellScriptBin "xdg-open" ''
    exec ${pkgs.systemd}/bin/busctl --user call \
      org.freedesktop.portal.Desktop \
      /org/freedesktop/portal/desktop \
      org.freedesktop.portal.OpenURI \
      OpenURI \
      ssa{sv} "" "$1" 0
  '';

  portal-files = pkgs.runCommand "portal-files" { } ''
    mkdir -p $out/applications

    cat > $out/applications/nixpak-portal.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=Nixpak Portal
    Exec=${portal-xdg-open}/bin/xdg-open %u
    MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;x-scheme-handler/about;x-scheme-handler/unknown;
    EOF

    cat > $out/mimeapps.list <<EOF
    [Default Applications]
    text/html=nixpak-portal.desktop
    x-scheme-handler/http=nixpak-portal.desktop
    x-scheme-handler/https=nixpak-portal.desktop
    x-scheme-handler/about=nixpak-portal.desktop
    x-scheme-handler/unknown=nixpak-portal.desktop
    EOF
  '';

  mkSandbox =
    args@{
      appId,
      package,
      gpu ? false,
      network ? "off", # "off" | "sandboxed" | "singbox" | "passthrough"
      webcam ? 0,
      audio_pulse ? "off", # "off" | "sandboxed" | "passthrough"
      audio_pipewire ? "off", # "off" | "sandboxed" | "passthrough"
      wayland ? "off", # "off" | "sandboxed" | "passthrough"
      x11 ? "off", # "off" | "sandboxed" | "passthrough"
      use_landlock ? true,
      use_seccomp ? true,
      seccomp_allow ? [ ],
      seccomp_block ? [ ],
      portals_for_files ? true,
      sandbox_shm ? true,
      sandbox_tmp ? true,
      main_desktop_file ? "none",
      additional_args ? { },
      additional_inside_commands ? "",
      additional_outside_commands ? "",
      extraAttrs ? [ ],
    }:
    let
      rawArgs =
        if builtins.isFunction additional_args then
          additional_args { inherit sloth lib pkgs; }
        else
          additional_args;

      dbusCfg = rawArgs.dbus or { };
      systemDbusCfg = rawArgs.system_dbus or (rawArgs.system-dbus or { });
      bwrapCfg = rawArgs.bubblewrap or { };

      dbusEnabled = dbusCfg.enable or true;
      dbusPolicies = dbusCfg.policies or { };

      dbusFlags = lib.concatLists (
        lib.mapAttrsToList (name: policy: [ "--dbus-${policy}=${name}" ]) dbusPolicies
      );

      systemDbusEnabled = systemDbusCfg.enable or (dbusCfg.system or false);
      systemDbusPolicies = systemDbusCfg.policies or { };

      systemDbusFlags = lib.optionals systemDbusEnabled (
        [ "--system-dbus" ]
        ++ lib.concatLists (
          lib.mapAttrsToList (name: policy: [ "--system-dbus-${policy}=${name}" ]) systemDbusPolicies
        )
      );

      extractList =
        val:
        if builtins.isList val then
          val
        else if builtins.isAttrs val && val ? content then
          extractList val.content
        else
          [ ];

      rwFlags = map (
        p: "--rw=${if builtins.isList p then "${builtins.head p}:${builtins.elemAt p 1}" else toString p}"
      ) (extractList (bwrapCfg.bind.rw or [ ]));

      roFlags = map (
        p: "--ro=${if builtins.isList p then "${builtins.head p}:${builtins.elemAt p 1}" else toString p}"
      ) (extractList (bwrapCfg.bind.ro or [ ]));

      devFlags = map (
        p: "--dev=${if builtins.isList p then "${builtins.head p}:${builtins.elemAt p 1}" else toString p}"
      ) (extractList (bwrapCfg.bind.dev or [ ]));

      sharePidFlag = lib.optional (bwrapCfg.sharePid or false) "--share-pid";
      landlockFlag = lib.optional (!use_landlock) "--no-landlock";
      portalsFlag = lib.optional (!portals_for_files) "--no-portals";
      portalEnvFlags = lib.optionals portals_for_files [
        "--env"
        "PATH=${portal-xdg-open}/bin:/run/current-system/sw/bin:/bin:/usr/bin"
        "--env"
        "XDG_DATA_DIRS=${portal-files}:/usr/share:/run/current-system/sw/share"
        "--env"
        "XDG_CONFIG_DIRS=${portal-files}:/etc/xdg"
      ];
      envFlags = lib.concatLists (
        lib.mapAttrsToList (k: v: [
          "--env"
          "${k}=${v}"
        ]) (bwrapCfg.env or { })
      );

      sbRunFlags = lib.flatten [
        "--id"
        appId
        "--net"
        network
        (if gpu then "--gpu" else "--no-gpu")
        [
          "--pulse"
          audio_pulse
          "--pipewire"
          audio_pipewire
          "--wayland"
          wayland
          "--x11"
          x11
          "--shm"
          (if sandbox_shm then "sandboxed" else "passthrough")
          "--tmp"
          (if sandbox_tmp then "sandboxed" else "passthrough")
        ]
        landlockFlag
        (if use_seccomp then "--seccomp" else "--no-seccomp")
        (lib.optionals (seccomp_allow != [ ]) [
          "--seccomp-allow"
          (lib.concatStringsSep "," seccomp_allow)
        ])
        (lib.optionals (seccomp_block != [ ]) [
          "--seccomp-block"
          (lib.concatStringsSep "," seccomp_block)
        ])
        portalsFlag
        portalEnvFlags
        (lib.optional (webcam != 0) [
          "--webcam"
          (toString webcam)
        ])
        (
          if dbusEnabled then
            [
              "--dbus"
              "sandboxed"
            ]
          else
            [
              "--dbus"
              "off"
            ]
        )
        systemDbusFlags
        dbusFlags
        rwFlags
        roFlags
        devFlags
        envFlags
        sharePidFlag
        (if (args.cli or false) then "--cli" else "--gui")
      ];

      wrapperScript = pkgs.writeShellScript "sandbox-launcher-${appId}" ''
        if [ -e "/etc/.not-a-sandbox" ] || [ -e "$HOME/.not-a-sandbox" ]; then
          MY_CGROUP="/sys/fs/cgroup$(cat /proc/self/cgroup | cut -d: -f3)"
          MY_SCOPE="$(basename "$MY_CGROUP" 2>/dev/null)"
          case "$MY_SCOPE" in
            *"${appId}"*)
              ;;
            *)
              exec app2unit -a "${appId}" -- "$0" "$@"
              ;;
          esac

          mkdir -p "$MY_CGROUP/helpers"
          echo $$ > "$MY_CGROUP/helpers/cgroup.procs"
          echo "+memory +pids +cpu +io" > "$(dirname "$MY_CGROUP")/cgroup.subtree_control" 2>/dev/null || true
          echo "+memory +pids +cpu +io" > "$MY_CGROUP/cgroup.subtree_control" 2>/dev/null || true
          mkdir -p "$MY_CGROUP/inside"
          export MY_CGROUP MY_SCOPE

          export START_TIME=$(date +%s%N)
          export APP_ID="${appId}"

          export SANDBOX_DIR="$XDG_RUNTIME_DIR/.nixpak/${appId}"
          export SANDBOXED_RUNTIME_DIR="$SANDBOX_DIR/runtime"
          mkdir -p "$SANDBOXED_RUNTIME_DIR"

          ${additional_outside_commands}
          exec sb-run ${lib.escapeShellArgs sbRunFlags} \
            ${
              lib.optionalString (
                additional_inside_commands != ""
              ) "--inside-init ${lib.escapeShellArg additional_inside_commands}"
            } \
            -- "$TARGET" "$@"
        else
          exec "$TARGET" "$@"
        fi
      '';

      wrapWithProxy =
        pkg:
        let
          wrapped =
            pkgs.symlinkJoin {
              name = "${appId}-wrapper";
              paths = [ pkg ];
              nativeBuildInputs = [ pkgs.findutils ];
              postBuild = ''
                materialize_path() {
                  local target_path="$1"
                  local rel="''${target_path#$out/}"
                  local current="$out"
                  IFS='/' read -ra parts <<< "$rel"
                  for part in "''${parts[@]}"; do
                    [[ -z "$part" ]] && continue
                    current="$current/$part"
                    if [[ -L "$current" ]] && [[ -d "$current" ]]; then
                      local link_target
                      link_target="$(readlink -f "$current")"
                      rm "$current"
                      mkdir -p "$current"
                      find "$link_target" -maxdepth 1 -mindepth 1 -exec ln -s -t "$current/" {} +
                    fi
                  done
                }

                find "$out" -type l -not -xtype d | while read -r link; do
                  target="$(readlink -fm "$link")"
                  
                  is_desktop_or_service=0
                  is_executable=0
                  
                  if [[ "$link" == *.desktop ]] || [[ "$link" == *.service ]]; then
                    is_desktop_or_service=1
                  elif [[ "$link" != *.so* ]]; then
                    if LC_ALL=C grep -q "^.ELF" "$target" 2>/dev/null; then
                      is_executable=1
                    elif LC_ALL=C grep -q "^#!" "$target" 2>/dev/null; then
                      is_executable=1
                    fi
                  fi

                  if [ "$is_desktop_or_service" -eq 1 ] || [ "$is_executable" -eq 1 ]; then
                    materialize_path "$(dirname "$link")"
                    rm "$link"
                    
                    if [ "$is_desktop_or_service" -eq 1 ]; then
                      cp "$target" "$link"
                      chmod +w "$link"
                      sed -i "s|${pkg}|$out|g" "$link"
                    else
                      cp "${wrapperScript}" "$link"
                      sed -i "1a TARGET=\"$target\"" "$link"
                      chmod +x "$link"
                    fi
                  fi
                done

                if [[ -d "$out/share/applications" ]]; then
                  materialize_path "$out/share/applications"
                  
                  shopt -s nullglob
                  apps=("$out/share/applications/"*.desktop)
                  target_name="$out/share/applications/${appId}.desktop"

                  if [[ "${main_desktop_file}" != "none" ]]; then
                    src="$out/share/applications/${main_desktop_file}"
                    if [[ -e "$src" ]] && [[ "$src" != "$target_name" ]]; then
                      mv "$src" "$target_name"
                    fi
                  elif [[ ''${#apps[@]} -eq 1 ]]; then
                    if [[ "''${apps[0]}" != "$target_name" ]]; then
                      mv "''${apps[0]}" "$target_name"
                    fi
                  fi
                  shopt -u nullglob
                fi
              '';
            }
            // {
              pname = "${appId}-wrapped";
              version = pkg.version or "1.0";
            };
        in
        wrapped
        // (lib.optionalAttrs (pkg ? override) {
          override = overrideArgs: wrapWithProxy (pkg.override overrideArgs);
        })
        // (lib.optionalAttrs (pkg ? overrideAttrs) {
          overrideAttrs = f: wrapWithProxy (pkg.overrideAttrs f);
        });

      mainWrapper = wrapWithProxy package;
      proxiedExtra = lib.genAttrs extraAttrs (
        attr:
        let
          origAttr = package.${attr} or null;
        in
        if lib.isDerivation origAttr then wrapWithProxy origAttr else origAttr
      );
    in
    mainWrapper
    // proxiedExtra
    // (lib.optionalAttrs (package ? override) {
      override =
        overrideArgs:
        mkSandbox (
          args
          // {
            package = package.override overrideArgs;
          }
        );
    })
    // (lib.optionalAttrs (package ? overrideAttrs) {
      overrideAttrs =
        f:
        mkSandbox (
          args
          // {
            package = package.overrideAttrs f;
          }
        );
    });

  pipewireRestrictedSocketConfig = {
    "module.protocol-native.args".sockets = [
      { name = "pipewire-0"; }
      { name = "pipewire-0-manager"; }
      { name = "pipewire-0-restricted"; }
    ];
    "module.access.args"."access.socket" = {
      "pipewire-0" = "unrestricted";
      "pipewire-0-manager" = "unrestricted";
      "pipewire-0-restricted" = "flatpak";
    };
  };

  pipewirePulseRestrictedSocketConfig = {
    "pulse.properties"."server.address" = [
      "unix:native"
      {
        address = "unix:restricted";
        "client.access" = "restricted";
      }
    ];
    "pulse.rules" = [
      {
        matches = [
          { "pipewire.client.access" = "restricted"; }
          { "pipewire.client.access" = "flatpak"; }
        ];
        actions.quirks = [
          "block-source-volume"
          "block-sink-volume"
        ];
      }
    ];
  };

  wireplumberRestrictedPermissionsConfig = {
    "access.permission-managers" = [
      {
        name = "sandbox-restricted";
        default_permissions = "rx";
        core_permissions = "rx";
        rules = [
          {
            matches = [
              { "device.name" = "~.*"; }
              { "node.name" = "~.*"; }
            ];
            actions.set-permissions = "rx";
          }
        ];
      }
    ];
    "access.rules" = [
      {
        matches = [
          { "pipewire.client.access" = "restricted"; }
          { "pipewire.client.access" = "flatpak"; }
        ];
        actions.update-props.permission_manager_name = "sandbox-restricted";
      }
    ];
  };
in
{
  options.sandboxing.enable = lib.mkEnableOption "app sandboxing";
  config = {
    _module.args = {
      inherit staticBwrap mkSandbox;
    };
  }
  // lib.optionalAttrs (options ? home.file) {
    home = {
      packages = [
        staticBwrap
        pasta-pkg
        way-secure-pkg
      ];
      file.".not-a-sandbox".text = "not a sandbox";
    };
    xdg = {
      configFile = {
        "pipewire/pipewire.conf.d/99-restricted-socket.conf".text =
          builtins.toJSON pipewireRestrictedSocketConfig;
        "pipewire/pipewire-pulse.conf.d/99-restricted-socket.conf".text =
          builtins.toJSON pipewirePulseRestrictedSocketConfig;
        "wireplumber/wireplumber.conf.d/99-restricted-permissions.conf".text =
          builtins.toJSON wireplumberRestrictedPermissionsConfig;
      };
      dataFile = {
        "sb-run/config.json".source = sbRunConfigFile;
        "sb-run/syscalls.json".source = syscallsJson;
        "sb-run/sing-box.json".source = sing-box-sandbox-config;
      };
    };
  }
  // lib.optionalAttrs (options ? environment.etc) {
    environment = {
      systemPackages = [
        staticBwrap
        pasta-pkg
        way-secure-pkg
      ];
      etc = {
        ".not-a-sandbox".text = "not a sandbox";
        "sb-run/config.json".source = sbRunConfigFile;
        "sb-run/syscalls.json".source = syscallsJson;
        "sb-run/sing-box.json".source = sing-box-sandbox-config;
      };
    };
    services.pipewire = {
      package = pkgs.pipewire.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ../../../stuff/patches/pipewire-quirk-block-mute.patch
        ];
      });
      wireplumber.extraConfig."99-restricted-permissions" = wireplumberRestrictedPermissionsConfig;
      extraConfig = {
        pipewire."99-restricted-socket" = pipewireRestrictedSocketConfig;
        pipewire-pulse."99-restricted-socket" = pipewirePulseRestrictedSocketConfig;
      };
    };
  };
}
