use std::env;
use std::ffi::{CString, c_void};
use std::fmt::Write as _;
use std::fs;
use std::io::{Read, Write};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::io::{AsRawFd, RawFd};
use std::os::unix::net::{UnixListener, UnixStream};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, exit};
use std::sync::atomic::{AtomicI32, Ordering};
use std::time::{Duration, Instant};

const IPC_MAGIC: [u8; 4] = *b"SBEX";
const IPC_VERSION: u16 = 1;

const MSG_EXEC_REQUEST: u16 = 1;
const MSG_WINSIZE: u16 = 2;
const MSG_SIGNAL: u16 = 3;
const MSG_EXIT_RESPONSE: u16 = 4;

const FLAG_WAIT_EXIT: u32 = 1 << 0;
const FLAG_IS_TTY: u32 = 1 << 1;
const FLAG_HELPER: u32 = 1 << 2;

const SOL_SOCKET: i32 = 1;
const SCM_RIGHTS: i32 = 1;

const SUBSYS_GPU: u32 = 1 << 0;
const SUBSYS_GAMEPAD: u32 = 1 << 1;

const CFG_TMPFS: u32 = 1 << 0;
const CFG_DBUS: u32 = 1 << 1;
const CFG_SHARE_PID: u32 = 1 << 2;
const CFG_IS_CLI: u32 = 1 << 3;
const CFG_LANDLOCK: u32 = 1 << 4;
const CFG_SHARE_IPC: u32 = 1 << 5;
const CFG_PORTALS: u32 = 1 << 6;
const CFG_USE_VPNIFY: u32 = 1 << 7;
const CFG_SYSTEM_DBUS: u32 = 1 << 8;
const CFG_FLATPAK_INFO: u32 = 1 << 9;
const CFG_SCOPE: u32 = 1 << 10;

const TIOCGWINSZ: usize = 0x5413;
const SYS_PIDFD_OPEN: i64 = 434;
const SO_PEERCRED: i32 = 17;
const EPOLL_CTL_ADD: i32 = 1;
const EPOLL_CTL_DEL: i32 = 2;
const EPOLLIN: u32 = 1;
const EPOLLPRI: u32 = 0x0002;
const EPOLLERR: u32 = 0x0008;

const ALLOWED_ENV_VARS: &[&str] = &[
    "HOME",
    "XDG_RUNTIME_DIR",
    "XDG_CONFIG_HOME",
    "XDG_DATA_HOME",
    "XDG_STATE_HOME",
    "XDG_CACHE_HOME",
    "USER",
];

const RO_SYSTEM_PATHS: &[&str] = &[
    "/nix/store",
    "/bin",
    "/usr/bin",
    "/run/current-system",
    "/etc/xdg",
    "/etc/fonts",
    "/etc/localtime",
    "/etc/profiles",
    "/etc/static",
    "/nix/profile",
    "/nix/var/nix/profiles",
    "/etc/ssl/certs",
    "/etc/static/ssl/certs",
    "/etc/pki",
    "/etc/hosts",
    "/etc/nsswitch.conf",
    "/etc/machine-id",
    "/etc/os-release",
    "/etc/mime.types",
    "/etc/passwd",
    "/etc/group",
    "/sys/class/hwmon",
    "/etc/xdg/openxr",
];

const USER_THEME_SUBPATHS: &[&str] = &[
    ".nix-profile",
    ".local/state/nix/profile",
    ".icons",
    ".themes",
];

const XDG_CONFIG_SUBPATHS: &[&str] = &[
    "user-dirs.dirs",
    "user-dirs.conf",
    "gtk-4.0",
    "gtk-3.0",
    "qt6ct",
    "qt5ct",
    "Kvantum",
    "starship.toml",
    "fastfetch",
    "openvr",
    "openxr",
];

const XDG_DATA_SUBPATHS: &[&str] = &["zsh/.zshenv", "zsh/.zshrc", "icons", "themes"];

const NVIDIA_NODES: &[&str] = &[
    "/dev/nvidia0",
    "/dev/nvidiactl",
    "/dev/nvidia-modeset",
    "/dev/nvidia-uvm",
    "/dev/nvidia-uvm-tools",
];

const DEFAULT_DBUS_TALKS: &[&str] = &[
    "org.freedesktop.portal.Desktop",
    "org.freedesktop.portal.Documents",
    "org.freedesktop.portal.Secret",
    "org.freedesktop.Notifications",
    "org.freedesktop.FileManager1",
    "org.freedesktop.ScreenSaver",
    "org.gnome.Mutter.IdleMonitor",
    "org.kde.StatusNotifierWatcher",
    "org.ayatana.indicator.application",
    "com.canonical.AppMenu.Registrar",
    "org.mpris.MediaPlayer2.Player",
];

const DEFAULT_DBUS_OWNS: &[&str] = &[
    "org.kde.StatusNotifierItem.*",
    "org.kde.StatusNotifierItem",
    "org.mpris.MediaPlayer2.*",
];

const PASTA_DEFAULT_ARGS: &[&str] = &[
    "--config-net",
    "--no-dhcp",
    "--no-dhcpv6",
    "--no-ra",
    "--no-map-gw",
    "-t",
    "none",
    "-u",
    "none",
    "-T",
    "none",
    "-U",
    "none",
    "--ns-ifname",
    "eth0",
    "--address",
    "192.168.1.100",
    "--netmask",
    "255.255.255.0",
    "--gateway",
    "192.168.1.1",
    "--dns-forward",
    "192.168.1.1",
    "--search",
    "none",
];

const DEFAULT_FLATPAK_POLICY_BUS: &str = "\n[Session Bus Policy]\norg.kde.StatusNotifierWatcher=talk\norg.kde.StatusNotifierItem.*=own\norg.kde.StatusNotifierItem=own\norg.ayatana.indicator.application=talk\ncom.canonical.AppMenu.Registrar=talk\norg.freedesktop.Notifications=talk\norg.freedesktop.portal.Desktop=talk\norg.freedesktop.portal.Secret=talk\norg.freedesktop.portal.Documents=talk\norg.freedesktop.FileManager1=talk\norg.freedesktop.ScreenSaver=talk\norg.gnome.Mutter.IdleMonitor=talk\norg.mpris.MediaPlayer2.Player=talk\norg.mpris.MediaPlayer2.*=own\n";

#[repr(C)]
#[derive(Clone, Copy, Debug)]
struct WinSizePayload {
    row: u16,
    col: u16,
    xpixel: u16,
    ypixel: u16,
}

static PENDING_SIGNAL: AtomicI32 = AtomicI32::new(0);
static PENDING_WINCH: AtomicI32 = AtomicI32::new(0);

extern "C" fn forward_sig_handler(sig: i32) {
    if sig == 28 {
        PENDING_WINCH.store(1, Ordering::Relaxed);
    } else {
        PENDING_SIGNAL.store(sig, Ordering::Relaxed);
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug)]
struct IpcHeader {
    magic: [u8; 4],
    version: u16,
    msg_type: u16,
    payload_len: u32,
    flags: u32,
    extra: [u8; 16],
}

impl IpcHeader {
    const fn new(msg_type: u16, payload_len: u32, flags: u32) -> Self {
        Self {
            magic: IPC_MAGIC,
            version: IPC_VERSION,
            msg_type,
            payload_len,
            flags,
            extra: [0; 16],
        }
    }

    fn to_bytes(self) -> [u8; 32] {
        let mut b = [0u8; 32];
        b[0..4].copy_from_slice(&self.magic);
        b[4..6].copy_from_slice(&self.version.to_le_bytes());
        b[6..8].copy_from_slice(&self.msg_type.to_le_bytes());
        b[8..12].copy_from_slice(&self.payload_len.to_le_bytes());
        b[12..16].copy_from_slice(&self.flags.to_le_bytes());
        b[16..32].copy_from_slice(&self.extra);
        b
    }

    fn from_bytes(bytes: &[u8]) -> Option<Self> {
        if bytes.len() < 32 {
            return None;
        }
        let magic: [u8; 4] = bytes[0..4].try_into().ok()?;
        let version = u16::from_le_bytes(bytes[4..6].try_into().ok()?);
        let msg_type = u16::from_le_bytes(bytes[6..8].try_into().ok()?);
        let payload_len = u32::from_le_bytes(bytes[8..12].try_into().ok()?);
        let flags = u32::from_le_bytes(bytes[12..16].try_into().ok()?);
        let extra: [u8; 16] = bytes[16..32].try_into().ok()?;

        if magic == IPC_MAGIC && version == IPC_VERSION {
            Some(Self {
                magic,
                version,
                msg_type,
                payload_len,
                flags,
                extra,
            })
        } else {
            None
        }
    }
}

#[repr(C)]
struct LibcIovec {
    iov_base: *mut c_void,
    iov_len: usize,
}

#[repr(C)]
struct LibcMsghdr {
    name: *mut c_void,
    namelen: u32,
    _pad1: u32,
    iov: *mut LibcIovec,
    iovlen: usize,
    control: *mut c_void,
    controllen: usize,
    flags: i32,
    _pad2: i32,
}

#[repr(C)]
struct LibcCmsghdr {
    len: usize,
    level: i32,
    type_: i32,
}

unsafe extern "C" {
    fn sendmsg(sockfd: i32, msg: *const LibcMsghdr, flags: i32) -> isize;
    fn isatty(fd: i32) -> i32;
    fn raise(sig: i32) -> i32;
    fn mkfifo(pathname: *const i8, mode: u32) -> i32;
    fn ioctl(fd: i32, request: usize, ...) -> i32;
    fn signal(sig: i32, handler: usize) -> usize;
    fn kill(pid: i32, sig: i32) -> i32;
}

#[repr(C, align(8))]
struct CmsgBuffer([u8; 128]);

fn send_header_with_fds(
    sock: &UnixStream,
    header: &IpcHeader,
    fds: &[RawFd],
) -> std::io::Result<()> {
    let header_bytes = header.to_bytes();
    let mut iov = LibcIovec {
        iov_base: header_bytes.as_ptr().cast::<c_void>().cast_mut(),
        iov_len: header_bytes.len(),
    };

    let mut cmsg_buf = CmsgBuffer([0u8; 128]);
    let raw_len = if fds.is_empty() {
        0
    } else {
        size_of::<LibcCmsghdr>() + std::mem::size_of_val(fds)
    };
    let control_space = (raw_len + 7) & !7;

    let msg = LibcMsghdr {
        name: std::ptr::null_mut(),
        namelen: 0,
        _pad1: 0,
        iov: &raw mut iov,
        iovlen: 1,
        control: if fds.is_empty() {
            std::ptr::null_mut()
        } else {
            cmsg_buf.0.as_mut_ptr().cast()
        },
        controllen: control_space,
        flags: 0,
        _pad2: 0,
    };

    if !fds.is_empty() {
        let cmsghdr_ptr = msg.control.cast::<LibcCmsghdr>();
        unsafe {
            (*cmsghdr_ptr).len = raw_len;
            (*cmsghdr_ptr).level = SOL_SOCKET;
            (*cmsghdr_ptr).type_ = SCM_RIGHTS;
            let data_ptr = cmsghdr_ptr.add(1).cast::<RawFd>();
            for (i, &fd) in fds.iter().enumerate() {
                *data_ptr.add(i) = fd;
            }
        }
    }

    let n = unsafe { sendmsg(sock.as_raw_fd(), &raw const msg, 0) };
    if n < 0 {
        return Err(std::io::Error::last_os_error());
    }

    Ok(())
}

fn build_exec_payload(cwd: &str, args: &[String], env_vars: &[String]) -> Vec<u8> {
    let mut buf = Vec::new();

    let write_str = |b: &mut Vec<u8>, s: &str| {
        let bytes = s.as_bytes();
        let len = u32::try_from(bytes.len()).unwrap_or(0);
        b.extend_from_slice(&len.to_le_bytes());
        b.extend_from_slice(bytes);
    };

    write_str(&mut buf, cwd);

    let arg_count = u32::try_from(args.len()).unwrap_or(0);
    buf.extend_from_slice(&arg_count.to_le_bytes());
    for arg in args {
        write_str(&mut buf, arg);
    }

    let env_count = u32::try_from(env_vars.len()).unwrap_or(0);
    buf.extend_from_slice(&env_count.to_le_bytes());
    for item in env_vars {
        write_str(&mut buf, item);
    }

    buf
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum BridgeDirection {
    FromSandbox,
    ToSandbox,
}

#[derive(Clone, Debug)]
struct BridgeRule {
    direction: BridgeDirection,
    address: String,
    ports: String,
}

#[derive(Default)]
struct SandboxConfig {
    app_id: String,
    custom_dir: Option<PathBuf>,
    network: String,
    wayland_mode: String,
    x11_mode: String,
    pulse_mode: String,
    pipewire_mode: String,
    dbus_mode: String,
    shm_mode: String,
    tmp_mode: String,
    bridges: Vec<BridgeRule>,
    subsystems: u32,
    flags: u32,
    webcam_count: usize,
    executor_path: Option<PathBuf>,
    dbus_talk: Vec<String>,
    dbus_own: Vec<String>,
    dbus_see: Vec<String>,
    dbus_extra_args: Vec<String>,
    system_dbus_talk: Vec<String>,
    system_dbus_own: Vec<String>,
    system_dbus_see: Vec<String>,
    system_dbus_extra_args: Vec<String>,
    rw_binds: Vec<String>,
    ro_binds: Vec<String>,
    dev_binds: Vec<String>,
    mkdir_dirs: Vec<String>,
    bwrap_extra_args: Vec<String>,
    extra_env: Vec<String>,
    singbox_bin: Option<PathBuf>,
    singbox_config: Option<PathBuf>,
    dbus_proxy_bin: Option<PathBuf>,
    way_secure_bin: Option<PathBuf>,
    pasta_bin: Option<PathBuf>,
    xwayland_satellite_bin: Option<PathBuf>,
    custom_uid: Option<u32>,
    custom_gid: Option<u32>,
    inside_init: Vec<String>,
    is_helper_request: bool,
    command: Vec<String>,
}

#[derive(Default)]
struct HelperProcesses {
    way_secure_close_fd: Option<i32>,
    dbus_proxy: Option<Child>,
    system_dbus_proxy: Option<Child>,
    singbox_bridge: Option<Child>,
    pasta: Option<Child>,
}

fn parse_bridge_arg(arg: &str) -> Option<BridgeRule> {
    let parts: Vec<&str> = arg.splitn(3, ':').collect();
    if parts.len() < 2 {
        return None;
    }
    let dir_str = parts[0].to_lowercase();
    let direction = match dir_str.as_str() {
        "from" | "from-sandbox" | "out" => BridgeDirection::FromSandbox,
        "to" | "to-sandbox" | "in" => BridgeDirection::ToSandbox,
        _ => return None,
    };

    let (address, raw_ports) = if parts.len() == 2 {
        ("127.0.0.1".to_string(), parts[1].to_string())
    } else {
        (parts[1].to_string(), parts[2].to_string())
    };

    let clean_ports = raw_ports.trim_matches(|c| c == '[' || c == ']').to_string();
    if clean_ports.is_empty() {
        return None;
    }

    Some(BridgeRule {
        direction,
        address,
        ports: clean_ports,
    })
}

fn expand_env_path(path_str: &str) -> String {
    let mut result = path_str.to_string();
    if result.starts_with("~/")
        && let Ok(home) = env::var("HOME")
    {
        result = format!("{home}/{}", &result[2..]);
    }
    for &k in ALLOWED_ENV_VARS {
        if let Ok(v) = env::var(k) {
            let var_dollar = format!("${k}");
            let var_braced = format!("${{{k}}}");
            if result.contains(&var_dollar) {
                result = result.replace(&var_dollar, &v);
            }
            if result.contains(&var_braced) {
                result = result.replace(&var_braced, &v);
            }
        }
    }
    result
}

fn parse_subsystem_flag(arg: &str, subs: &mut u32) -> bool {
    match arg {
        "--gpu" => {
            *subs |= SUBSYS_GPU;
            true
        }
        "--no-gpu" => {
            *subs &= !SUBSYS_GPU;
            true
        }
        "--gamepad" => {
            *subs |= SUBSYS_GAMEPAD;
            true
        }
        "--no-gamepad" => {
            *subs &= !SUBSYS_GAMEPAD;
            true
        }
        _ => false,
    }
}

fn prompt_user(prompt: &str, default: &str) -> String {
    print!("{prompt} [{default}]: ");
    let _ = std::io::stdout().flush();
    let mut line = String::new();
    let _ = std::io::stdin().read_line(&mut line);
    let trimmed = line.trim();
    if trimmed.is_empty() {
        default.to_string()
    } else {
        trimmed.to_string()
    }
}

fn run_interactive_prompt(cfg: &mut SandboxConfig) {
    if cfg.command.is_empty() {
        let exe = prompt_user("Executable to run", "/bin/sh");
        cfg.command = vec![exe];
    }

    let net = prompt_user("Network [sandboxed|singbox|passthrough|off]", &cfg.network);
    cfg.network = net;

    let tmpfs = prompt_user(
        "Use ephemeral tmpfs? (y/n)",
        if (cfg.flags & CFG_TMPFS) != 0 {
            "y"
        } else {
            "n"
        },
    );
    if tmpfs.eq_ignore_ascii_case("y") {
        cfg.flags |= CFG_TMPFS;
    } else {
        cfg.flags &= !CFG_TMPFS;
    }

    let cwd = env::current_dir().unwrap_or_else(|_| PathBuf::from("/"));
    let add_cwd = prompt_user(
        &format!("Bind current directory ({}) as RW? (y/n)", cwd.display()),
        "y",
    );
    if add_cwd.eq_ignore_ascii_case("y") {
        cfg.rw_binds.push(cwd.to_string_lossy().to_string());
    }

    loop {
        let extra = prompt_user("Add path to bind (or press Enter to finish)", "");
        if extra.is_empty() {
            break;
        }
        let mode = prompt_user("Mode [rw/ro]", "rw");
        if mode.eq_ignore_ascii_case("ro") {
            cfg.ro_binds.push(expand_env_path(&extra));
        } else {
            cfg.rw_binds.push(expand_env_path(&extra));
        }
    }
}

fn parse_dbus_arg(cfg: &mut SandboxConfig, args: &[String], i: &mut usize) -> bool {
    let arg = &args[*i];
    if let Some(talk) = arg.strip_prefix("--system-dbus-talk=") {
        cfg.system_dbus_talk.push(talk.into());
        cfg.flags |= CFG_SYSTEM_DBUS;
        *i += 1;
        true
    } else if let Some(own) = arg.strip_prefix("--system-dbus-own=") {
        cfg.system_dbus_own.push(own.into());
        cfg.flags |= CFG_SYSTEM_DBUS;
        *i += 1;
        true
    } else if let Some(see) = arg.strip_prefix("--system-dbus-see=") {
        cfg.system_dbus_see.push(see.into());
        cfg.flags |= CFG_SYSTEM_DBUS;
        *i += 1;
        true
    } else if let Some(call) = arg.strip_prefix("--system-dbus-call=") {
        cfg.system_dbus_extra_args.push(format!("--call={call}"));
        cfg.flags |= CFG_SYSTEM_DBUS;
        *i += 1;
        true
    } else if arg == "--system-dbus-talk" && *i + 1 < args.len() {
        cfg.system_dbus_talk.push(args[*i + 1].clone());
        cfg.flags |= CFG_SYSTEM_DBUS;
        *i += 2;
        true
    } else if arg == "--system-dbus-own" && *i + 1 < args.len() {
        cfg.system_dbus_own.push(args[*i + 1].clone());
        cfg.flags |= CFG_SYSTEM_DBUS;
        *i += 2;
        true
    } else if arg == "--system-dbus-see" && *i + 1 < args.len() {
        cfg.system_dbus_see.push(args[*i + 1].clone());
        cfg.flags |= CFG_SYSTEM_DBUS;
        *i += 2;
        true
    } else if (arg == "--system-dbus-arg" || arg == "--system-dbus-call") && *i + 1 < args.len() {
        cfg.system_dbus_extra_args.push(args[*i + 1].clone());
        cfg.flags |= CFG_SYSTEM_DBUS;
        *i += 2;
        true
    } else if let Some(talk) = arg.strip_prefix("--dbus-talk=") {
        cfg.dbus_talk.push(talk.into());
        *i += 1;
        true
    } else if let Some(own) = arg.strip_prefix("--dbus-own=") {
        cfg.dbus_own.push(own.into());
        *i += 1;
        true
    } else if let Some(see) = arg.strip_prefix("--dbus-see=") {
        cfg.dbus_see.push(see.into());
        *i += 1;
        true
    } else if let Some(call) = arg.strip_prefix("--dbus-call=") {
        cfg.dbus_extra_args.push(format!("--call={call}"));
        *i += 1;
        true
    } else if (arg == "--talk" || arg == "--dbus-talk") && *i + 1 < args.len() {
        cfg.dbus_talk.push(args[*i + 1].clone());
        *i += 2;
        true
    } else if (arg == "--own" || arg == "--dbus-own") && *i + 1 < args.len() {
        cfg.dbus_own.push(args[*i + 1].clone());
        *i += 2;
        true
    } else if (arg == "--see" || arg == "--dbus-see") && *i + 1 < args.len() {
        cfg.dbus_see.push(args[*i + 1].clone());
        *i += 2;
        true
    } else if (arg == "--dbus-arg" || arg == "--call" || arg == "--dbus-call")
        && *i + 1 < args.len()
    {
        cfg.dbus_extra_args.push(args[*i + 1].clone());
        *i += 2;
        true
    } else {
        false
    }
}

fn parse_audio_display_arg(cfg: &mut SandboxConfig, args: &[String], i: &mut usize) -> bool {
    match args[*i].as_str() {
        "--pulse" if *i + 1 < args.len() => {
            cfg.pulse_mode.clone_from(&args[*i + 1]);
            *i += 2;
            true
        }
        "--pipewire" if *i + 1 < args.len() => {
            cfg.pipewire_mode.clone_from(&args[*i + 1]);
            *i += 2;
            true
        }
        "--audio" => {
            cfg.pulse_mode = "sandboxed".into();
            cfg.pipewire_mode = "sandboxed".into();
            *i += 1;
            true
        }
        "--no-audio" => {
            cfg.pulse_mode = "off".into();
            cfg.pipewire_mode = "off".into();
            *i += 1;
            true
        }
        "--no-pulse" => {
            cfg.pulse_mode = "off".into();
            *i += 1;
            true
        }
        "--no-pipewire" => {
            cfg.pipewire_mode = "off".into();
            *i += 1;
            true
        }
        "--wayland" => {
            if *i + 1 < args.len() && !args[*i + 1].starts_with('-') {
                cfg.wayland_mode.clone_from(&args[*i + 1]);
                *i += 2;
            } else {
                cfg.wayland_mode = "sandboxed".into();
                *i += 1;
            }
            true
        }
        "--no-wayland" => {
            cfg.wayland_mode = "off".into();
            *i += 1;
            true
        }
        "--x11" => {
            if *i + 1 < args.len() && !args[*i + 1].starts_with('-') {
                cfg.x11_mode.clone_from(&args[*i + 1]);
                *i += 2;
            } else {
                cfg.x11_mode = "sandboxed".into();
                *i += 1;
            }
            true
        }
        "--no-x11" => {
            cfg.x11_mode = "off".into();
            *i += 1;
            true
        }
        _ => false,
    }
}

fn parse_dbus_ipc_arg(cfg: &mut SandboxConfig, args: &[String], i: &mut usize) -> bool {
    match args[*i].as_str() {
        "--dbus" => {
            if *i + 1 < args.len() && !args[*i + 1].starts_with('-') {
                cfg.dbus_mode.clone_from(&args[*i + 1]);
                if cfg.dbus_mode == "off" {
                    cfg.flags &= !CFG_DBUS;
                } else {
                    cfg.flags |= CFG_DBUS;
                }
                *i += 2;
            } else {
                cfg.dbus_mode = "sandboxed".into();
                cfg.flags |= CFG_DBUS;
                *i += 1;
            }
            true
        }
        "--no-dbus" => {
            cfg.dbus_mode = "off".into();
            cfg.flags &= !CFG_DBUS;
            *i += 1;
            true
        }
        "--system-dbus" => {
            cfg.flags |= CFG_SYSTEM_DBUS;
            *i += 1;
            true
        }
        "--no-system-dbus" => {
            cfg.flags &= !CFG_SYSTEM_DBUS;
            *i += 1;
            true
        }
        "--share-ipc" => {
            cfg.flags |= CFG_SHARE_IPC;
            *i += 1;
            true
        }
        "--unshare-ipc" => {
            cfg.flags &= !CFG_SHARE_IPC;
            *i += 1;
            true
        }
        _ => false,
    }
}

fn parse_system_state_arg(cfg: &mut SandboxConfig, args: &[String], i: &mut usize) -> bool {
    if parse_dbus_ipc_arg(cfg, args, i) {
        return true;
    }
    match args[*i].as_str() {
        "--shm" if *i + 1 < args.len() => {
            cfg.shm_mode.clone_from(&args[*i + 1]);
            *i += 2;
            true
        }
        "--tmp" if *i + 1 < args.len() => {
            cfg.tmp_mode.clone_from(&args[*i + 1]);
            *i += 2;
            true
        }
        "--portals" => {
            cfg.flags |= CFG_PORTALS;
            *i += 1;
            true
        }
        "--no-portals" => {
            cfg.flags &= !CFG_PORTALS;
            *i += 1;
            true
        }
        "--flatpak-info" => {
            cfg.flags |= CFG_FLATPAK_INFO;
            *i += 1;
            true
        }
        "--tmpfs" => {
            cfg.flags |= CFG_TMPFS;
            *i += 1;
            true
        }
        "--no-tmpfs" => {
            cfg.flags &= !CFG_TMPFS;
            *i += 1;
            true
        }
        "--scope" => {
            cfg.flags |= CFG_SCOPE;
            *i += 1;
            true
        }
        "--no-scope" => {
            cfg.flags &= !CFG_SCOPE;
            *i += 1;
            true
        }
        "--share-pid" => {
            cfg.flags |= CFG_SHARE_PID;
            *i += 1;
            true
        }
        "--unshare-pid" => {
            cfg.flags &= !CFG_SHARE_PID;
            *i += 1;
            true
        }
        "--landlock" => {
            cfg.flags |= CFG_LANDLOCK;
            *i += 1;
            true
        }
        "--no-landlock" => {
            cfg.flags &= !CFG_LANDLOCK;
            *i += 1;
            true
        }
        _ => false,
    }
}

fn parse_bind_arg(cfg: &mut SandboxConfig, args: &[String], i: &mut usize) -> bool {
    let arg = &args[*i];
    if let Some(val) = arg.strip_prefix("--rw=") {
        cfg.rw_binds.push(expand_env_path(val));
        *i += 1;
        return true;
    }
    if let Some(val) = arg.strip_prefix("--ro=") {
        cfg.ro_binds.push(expand_env_path(val));
        *i += 1;
        return true;
    }
    if let Some(val) = arg.strip_prefix("--dev=") {
        cfg.dev_binds.push(expand_env_path(val));
        *i += 1;
        return true;
    }
    if let Some(val) = arg.strip_prefix("--mkdir=") {
        cfg.mkdir_dirs.push(expand_env_path(val));
        *i += 1;
        return true;
    }

    match arg.as_str() {
        "--rw" | "--bind-rw" if *i + 1 < args.len() => {
            cfg.rw_binds.push(expand_env_path(&args[*i + 1]));
            *i += 2;
            true
        }
        "--ro" | "--bind-ro" if *i + 1 < args.len() => {
            cfg.ro_binds.push(expand_env_path(&args[*i + 1]));
            *i += 2;
            true
        }
        "--dev" | "--bind-dev" if *i + 1 < args.len() => {
            cfg.dev_binds.push(expand_env_path(&args[*i + 1]));
            *i += 2;
            true
        }
        "--mkdir" if *i + 1 < args.len() => {
            cfg.mkdir_dirs.push(expand_env_path(&args[*i + 1]));
            *i += 2;
            true
        }
        _ => false,
    }
}

fn parse_command_and_env_arg(cfg: &mut SandboxConfig, args: &[String], i: &mut usize) -> bool {
    match args[*i].as_str() {
        "--bwrap-arg" if *i + 1 < args.len() => {
            cfg.bwrap_extra_args.push(args[*i + 1].clone());
            *i += 2;
            true
        }
        "--cli" => {
            cfg.flags |= CFG_IS_CLI;
            *i += 1;
            true
        }
        "--gui" => {
            cfg.flags &= !CFG_IS_CLI;
            *i += 1;
            true
        }
        "--vpnify" => {
            cfg.flags |= CFG_USE_VPNIFY;
            *i += 1;
            true
        }
        "--bridge" if *i + 1 < args.len() => {
            if let Some(rule) = parse_bridge_arg(&args[*i + 1]) {
                cfg.bridges.push(rule);
            }
            *i += 2;
            true
        }
        "--inside-init" if *i + 1 < args.len() => {
            cfg.inside_init.push(args[*i + 1].clone());
            *i += 2;
            true
        }
        "--env" if *i + 1 < args.len() => {
            cfg.extra_env.push(args[*i + 1].clone());
            *i += 2;
            true
        }
        _ => false,
    }
}

fn parse_option_arg(cfg: &mut SandboxConfig, args: &[String], i: &mut usize) -> bool {
    if parse_subsystem_flag(&args[*i], &mut cfg.subsystems) {
        *i += 1;
        return true;
    }
    if parse_audio_display_arg(cfg, args, i) {
        return true;
    }
    if parse_system_state_arg(cfg, args, i) {
        return true;
    }
    if parse_dbus_arg(cfg, args, i) {
        return true;
    }
    if parse_bind_arg(cfg, args, i) {
        return true;
    }
    if parse_command_and_env_arg(cfg, args, i) {
        return true;
    }

    match args[*i].as_str() {
        "-h" | "--help" => {
            print_help_and_exit();
        }
        "-i" | "--interactive" => {
            run_interactive_prompt(cfg);
            *i += 1;
        }
        "--singbox-bin" if *i + 1 < args.len() => {
            cfg.singbox_bin = Some(PathBuf::from(expand_env_path(&args[*i + 1])));
            *i += 2;
        }
        "--singbox-config" if *i + 1 < args.len() => {
            cfg.singbox_config = Some(PathBuf::from(expand_env_path(&args[*i + 1])));
            *i += 2;
        }
        "--dbus-proxy-bin" if *i + 1 < args.len() => {
            cfg.dbus_proxy_bin = Some(PathBuf::from(expand_env_path(&args[*i + 1])));
            *i += 2;
        }
        "--way-secure-bin" if *i + 1 < args.len() => {
            cfg.way_secure_bin = Some(PathBuf::from(expand_env_path(&args[*i + 1])));
            *i += 2;
        }
        "--pasta-bin" if *i + 1 < args.len() => {
            cfg.pasta_bin = Some(PathBuf::from(expand_env_path(&args[*i + 1])));
            *i += 2;
        }
        "--uid" if *i + 1 < args.len() => {
            cfg.custom_uid = args[*i + 1].parse().ok();
            *i += 2;
        }
        "--gid" if *i + 1 < args.len() => {
            cfg.custom_gid = args[*i + 1].parse().ok();
            *i += 2;
        }
        "--xwayland-satellite-bin" if *i + 1 < args.len() => {
            cfg.xwayland_satellite_bin = Some(PathBuf::from(expand_env_path(&args[*i + 1])));
            *i += 2;
        }
        "--id" if *i + 1 < args.len() => {
            cfg.app_id.clone_from(&args[*i + 1]);
            *i += 2;
        }
        "--dir" if *i + 1 < args.len() => {
            cfg.custom_dir = Some(PathBuf::from(expand_env_path(&args[*i + 1])));
            *i += 2;
        }
        "--net" if *i + 1 < args.len() => {
            cfg.network.clone_from(&args[*i + 1]);
            *i += 2;
        }
        "--no-net" => {
            cfg.network = "off".into();
            *i += 1;
        }
        "--webcam" if *i + 1 < args.len() => {
            cfg.webcam_count = args[*i + 1].parse().unwrap_or(0);
            *i += 2;
        }
        "--no-webcam" => {
            cfg.webcam_count = 0;
            *i += 1;
        }
        "--executor-bin" if *i + 1 < args.len() => {
            cfg.executor_path = Some(PathBuf::from(&args[*i + 1]));
            *i += 2;
        }
        _ => return false,
    }
    true
}

fn validate_subsystem_modes(cfg: &SandboxConfig) {
    let check_mode = |name: &str, val: &str, allowed: &[&str]| {
        if !allowed.contains(&val) {
            eprintln!("[sb-run] Warning: unrecognized {name} mode '{val}'; allowed: {allowed:?}");
        }
    };
    check_mode(
        "network",
        &cfg.network,
        &["sandboxed", "singbox", "passthrough", "off"],
    );
    check_mode(
        "wayland",
        &cfg.wayland_mode,
        &["sandboxed", "passthrough", "off"],
    );
    check_mode("x11", &cfg.x11_mode, &["sandboxed", "passthrough", "off"]);
    check_mode(
        "pulse",
        &cfg.pulse_mode,
        &["sandboxed", "passthrough", "off"],
    );
    check_mode(
        "pipewire",
        &cfg.pipewire_mode,
        &["sandboxed", "passthrough", "off"],
    );
    check_mode("dbus", &cfg.dbus_mode, &["sandboxed", "passthrough", "off"]);
    check_mode("shm", &cfg.shm_mode, &["sandboxed", "passthrough"]);
    check_mode("tmp", &cfg.tmp_mode, &["sandboxed", "passthrough"]);
}

fn parse_cli_args() -> SandboxConfig {
    let args: Vec<String> = env::args().collect();
    let mut cfg = SandboxConfig {
        network: "sandboxed".into(),
        wayland_mode: "sandboxed".into(),
        x11_mode: "off".into(),
        pulse_mode: "sandboxed".into(),
        pipewire_mode: "sandboxed".into(),
        dbus_mode: "sandboxed".into(),
        shm_mode: "sandboxed".into(),
        tmp_mode: "sandboxed".into(),
        flags: CFG_DBUS | CFG_LANDLOCK | CFG_PORTALS | CFG_FLATPAK_INFO | CFG_SCOPE,
        ..Default::default()
    };

    let mut i = 1;
    while i < args.len() {
        if parse_option_arg(&mut cfg, &args, &mut i) {
            continue;
        }
        if args[i] == "--" {
            cfg.command = args[i + 1..].to_vec();
            break;
        }
        if !args[i].starts_with('-') {
            cfg.command = args[i..].to_vec();
            break;
        }
        eprintln!("[sb-run] Warning: unrecognized option '{}'", args[i]);
        i += 1;
    }

    if cfg.app_id.is_empty() {
        let ts = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.subsec_nanos());
        cfg.app_id = format!("tmp-{ts:x}");
    }

    validate_subsystem_modes(&cfg);

    cfg
}

fn get_token_for_app(app_id: &str) -> Option<[u8; 16]> {
    let uid = libc_getuid();
    let runtime_base = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| format!("/run/user/{uid}"));
    let token_path = PathBuf::from(format!("{runtime_base}/sb-tokens/{app_id}.token"));
    if let Ok(bytes) = fs::read(&token_path)
        && bytes.len() == 16
    {
        bytes.try_into().ok()
    } else {
        None
    }
}

fn create_token_for_app(app_id: &str) -> [u8; 16] {
    let uid = libc_getuid();
    let runtime_base = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| format!("/run/user/{uid}"));
    let tokens_dir = PathBuf::from(format!("{runtime_base}/sb-tokens"));
    let _ = fs::create_dir_all(&tokens_dir);
    let _ = fs::set_permissions(&tokens_dir, fs::Permissions::from_mode(0o700));
    let token_path = tokens_dir.join(format!("{app_id}.token"));

    let mut token = [0u8; 16];
    if let Ok(mut f) = fs::File::open("/dev/urandom") {
        let _ = f.read_exact(&mut token);
    }
    let _ = fs::write(&token_path, token);
    let _ = fs::set_permissions(&token_path, fs::Permissions::from_mode(0o600));
    token
}

fn cleanup_token_for_app(app_id: &str) {
    let uid = libc_getuid();
    let runtime_base = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| format!("/run/user/{uid}"));
    let token_path = PathBuf::from(format!("{runtime_base}/sb-tokens/{app_id}.token"));
    let _ = fs::remove_file(&token_path);
}

fn bytes_to_hex(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        let _ = std::fmt::Write::write_fmt(&mut s, format_args!("{b:02x}"));
    }
    s
}

fn try_connect_running_sandbox(ipc_sock: &Path, cfg: &SandboxConfig) -> Option<i32> {
    let Ok(mut stream) = UnixStream::connect(ipc_sock) else {
        return None;
    };

    let cwd = env::current_dir().map_or_else(|_| "/".into(), |p| p.to_string_lossy().to_string());

    let env_vars: Vec<String> = env::vars().map(|(k, v)| format!("{k}={v}")).collect();
    let payload = build_exec_payload(&cwd, &cfg.command, &env_vars);
    let payload_len = u32::try_from(payload.len()).unwrap_or(0);

    let is_cli = (cfg.flags & CFG_IS_CLI) != 0;
    let is_tty = unsafe { isatty(0) == 1 };
    let mut flags = 0u32;
    if cfg.is_helper_request {
        flags |= FLAG_HELPER;
    }
    if is_cli {
        flags |= FLAG_WAIT_EXIT;
    }
    if is_tty {
        flags |= FLAG_IS_TTY;
    }

    let mut header = IpcHeader::new(MSG_EXEC_REQUEST, payload_len, flags);
    if let Some(token) = get_token_for_app(&cfg.app_id) {
        header.extra = token;
    }

    let fds = if is_cli { vec![0, 1, 2] } else { Vec::new() };

    if send_header_with_fds(&stream, &header, &fds).is_err() {
        return None;
    }
    if stream.write_all(&payload).is_err() {
        return None;
    }
    let _ = stream.flush();

    if !is_cli {
        return Some(0);
    }

    Some(wait_for_cli_exit_response(&mut stream, is_tty))
}

fn forward_cli_events(stream: &mut UnixStream, is_tty: bool) {
    if is_tty && PENDING_WINCH.swap(0, Ordering::Relaxed) != 0 {
        let mut ws = WinSizePayload {
            row: 0,
            col: 0,
            xpixel: 0,
            ypixel: 0,
        };
        if unsafe { ioctl(0, TIOCGWINSZ, &raw mut ws.row) } == 0
            && let Ok(ws_len) = u32::try_from(size_of::<WinSizePayload>())
        {
            let ws_hdr = IpcHeader::new(MSG_WINSIZE, ws_len, 0);
            let _ = stream.write_all(&ws_hdr.to_bytes());
            let ws_ptr = (&raw const ws).cast::<u8>();
            let ws_bytes =
                unsafe { std::slice::from_raw_parts(ws_ptr, size_of::<WinSizePayload>()) };
            let _ = stream.write_all(ws_bytes);
            let _ = stream.flush();
        }
    }

    let sig = PENDING_SIGNAL.swap(0, Ordering::Relaxed);
    if sig != 0
        && let Ok(sig_len) = u32::try_from(size_of::<i32>())
    {
        let sig_hdr = IpcHeader::new(MSG_SIGNAL, sig_len, 0);
        let _ = stream.write_all(&sig_hdr.to_bytes());
        let _ = stream.write_all(&sig.to_le_bytes());
        let _ = stream.flush();
    }
}

fn send_initial_winsize(stream: &mut UnixStream) {
    let mut ws = WinSizePayload {
        row: 0,
        col: 0,
        xpixel: 0,
        ypixel: 0,
    };
    if unsafe { ioctl(0, TIOCGWINSZ, &raw mut ws.row) } == 0
        && let Ok(ws_len) = u32::try_from(size_of::<WinSizePayload>())
    {
        let ws_hdr = IpcHeader::new(MSG_WINSIZE, ws_len, 0);
        let _ = stream.write_all(&ws_hdr.to_bytes());
        let ws_ptr = (&raw const ws).cast::<u8>();
        let ws_bytes = unsafe { std::slice::from_raw_parts(ws_ptr, size_of::<WinSizePayload>()) };
        let _ = stream.write_all(ws_bytes);
        let _ = stream.flush();
    }
}

fn parse_exit_status(raw_status: i32) -> i32 {
    let term_sig = raw_status & 0x7f;
    if term_sig != 0 {
        unsafe { raise(term_sig) };
        128 + term_sig
    } else {
        (raw_status >> 8) & 0xff
    }
}

fn wait_for_cli_exit_response(stream: &mut UnixStream, is_tty: bool) -> i32 {
    if is_tty {
        send_initial_winsize(stream);
    }

    unsafe {
        signal(2, forward_sig_handler as *const () as usize);
        signal(15, forward_sig_handler as *const () as usize);
        signal(28, forward_sig_handler as *const () as usize);
    }

    let _ = stream.set_read_timeout(Some(Duration::from_millis(50)));

    let mut resp_header_buf = [0u8; size_of::<IpcHeader>()];
    let mut header_read = 0;

    let exit_code = loop {
        forward_cli_events(stream, is_tty);

        match stream.read(&mut resp_header_buf[header_read..]) {
            Ok(0) => break 1,
            Ok(n) => {
                header_read += n;
                if header_read >= size_of::<IpcHeader>() {
                    break 0;
                }
            }
            Err(ref e)
                if e.kind() == std::io::ErrorKind::WouldBlock
                    || e.kind() == std::io::ErrorKind::TimedOut => {}
            Err(_) => break 1,
        }
    };

    unsafe {
        signal(2, 0);
        signal(15, 0);
        signal(28, 0);
    }
    let _ = stream.set_read_timeout(None);

    if exit_code != 0 {
        return 1;
    }

    let Some(resp_hdr) = IpcHeader::from_bytes(&resp_header_buf) else {
        return 1;
    };
    if resp_hdr.msg_type != MSG_EXIT_RESPONSE {
        return 1;
    }

    let mut status_buf = [0u8; 4];
    if stream.read_exact(&mut status_buf).is_err() {
        return 1;
    }
    let raw_status = i32::from_le_bytes(status_buf);
    parse_exit_status(raw_status)
}

fn print_help_and_exit() -> ! {
    println!(
        "Usage: sb-run [OPTIONS] [-- COMMAND [ARGS...]]\n\n\
        Options:\n\
          -h, --help               Show this help message and exit\n\
          -i, --interactive        Run interactive CLI wizard to configure sandbox\n\
          --id <APP_ID>            Sandbox application identifier\n\
          --dir <PATH>             Custom home directory persistence path\n\
          --net <MODE>             Network: sandboxed | singbox | passthrough | off\n\
          --gpu                    Enable GPU acceleration (/dev/dri, nvidia, vulkan)\n\
          --no-gpu                 Disable GPU acceleration\n\
          --gamepad                Enable gamepad/controller (/dev/input, /dev/uinput)\n\
          --no-gamepad             Disable gamepad/controller\n\
          --pulse <MODE>           PulseAudio: sandboxed | passthrough | off\n\
          --pipewire <MODE>        PipeWire: sandboxed | passthrough | off\n\
          --audio / --no-audio     Toggle all audio subsystems\n\
          --wayland <MODE>         Wayland: sandboxed | passthrough | off\n\
          --no-wayland             Disable Wayland\n\
          --x11 <MODE>             X11: sandboxed | passthrough | off\n\
          --no-x11                 Disable X11\n\
          --webcam <COUNT>         Number of webcam video nodes (0-10)\n\
          --dbus <MODE>            D-Bus: sandboxed | passthrough | off\n\
          --no-dbus                Disable D-Bus proxy\n\
          --dbus-talk <NAME>       Allow talking to D-Bus service\n\
          --dbus-own <NAME>        Allow owning D-Bus name\n\
          --dbus-see <NAME>        Allow seeing D-Bus name\n\
          --dbus-arg <ARG>         Raw argument forwarded to xdg-dbus-proxy\n\
          --landlock               Enable Landlock signal scoping (default)\n\
          --no-landlock            Disable Landlock\n\
          --tmpfs                  Use ephemeral tmpfs home directory\n\
          --share-pid              Share PID namespace with host\n\
          --portals / --no-portals Enable/disable XDG portals\n\
          --shm <MODE>             Shared memory (/dev/shm): sandboxed | passthrough\n\
          --tmp <MODE>             Temporary directory (/tmp): sandboxed | passthrough\n\
          --ro <SRC[:DST]>         Mount path read-only\n\
          --rw <SRC[:DST]>         Mount path read-write\n\
          --dev <SRC[:DST]>        Mount device node\n\
          --env <KEY=VAL>          Set environment variable\n\
          --bwrap-arg <ARG>        Pass raw argument directly to Bubblewrap\n\
          --executor-bin <PATH>    Path to custom sb-executor binary"
    );
    exit(0);
}

fn add_base_ro_binds(cmd: &mut Command) {
    for path in RO_SYSTEM_PATHS {
        if Path::new(path).exists() {
            cmd.arg("--ro-bind-try").arg(path).arg(path);
        }
    }
}

fn add_user_theme_binds(cmd: &mut Command, home: &str, xdg_config: &str, xdg_data: &str) {
    for sub in USER_THEME_SUBPATHS {
        let p = format!("{home}/{sub}");
        if Path::new(&p).exists() {
            cmd.arg("--ro-bind-try").arg(&p).arg(&p);
        }
    }
    for sub in XDG_CONFIG_SUBPATHS {
        let p = format!("{xdg_config}/{sub}");
        if Path::new(&p).exists() {
            cmd.arg("--ro-bind-try").arg(&p).arg(&p);
        }
    }
    for sub in XDG_DATA_SUBPATHS {
        let p = format!("{xdg_data}/{sub}");
        if Path::new(&p).exists() {
            cmd.arg("--ro-bind-try").arg(&p).arg(&p);
        }
    }
}

fn add_gpu_binds(cmd: &mut Command) {
    cmd.arg("--dev-bind").arg("/dev/dri").arg("/dev/dri");
    for node in NVIDIA_NODES {
        if Path::new(node).exists() {
            cmd.arg("--dev-bind").arg(node).arg(node);
        }
    }
    cmd.arg("--ro-bind")
        .arg("/run/opengl-driver")
        .arg("/run/opengl-driver");
    if Path::new("/run/opengl-driver-32").exists() {
        cmd.arg("--ro-bind")
            .arg("/run/opengl-driver-32")
            .arg("/run/opengl-driver-32");
    }
    cmd.arg("--ro-bind")
        .arg("/sys/dev/char")
        .arg("/sys/dev/char");
    if Path::new("/sys/devices/pci0000:00").exists() {
        cmd.arg("--ro-bind")
            .arg("/sys/devices/pci0000:00")
            .arg("/sys/devices/pci0000:00");
    }
    cmd.arg("--ro-bind")
        .arg("/sys/class/drm")
        .arg("/sys/class/drm");
    cmd.arg("--ro-bind").arg("/sys/devices").arg("/sys/devices");
    cmd.arg("--ro-bind").arg("/sys/bus/pci").arg("/sys/bus/pci");
}

fn add_audio_binds(cmd: &mut Command, cfg: &SandboxConfig, runtime_dir: &str) {
    match cfg.pulse_mode.as_str() {
        "sandboxed" => {
            let pulse_rest = format!("{runtime_dir}/pulse/restricted");
            let pulse_native = format!("{runtime_dir}/pulse/native");
            if Path::new(&pulse_rest).exists() {
                cmd.arg("--ro-bind-try").arg(&pulse_rest).arg(&pulse_native);
            }
        }
        "passthrough" => {
            let pulse_native = format!("{runtime_dir}/pulse/native");
            if Path::new(&pulse_native).exists() {
                cmd.arg("--ro-bind-try")
                    .arg(&pulse_native)
                    .arg(&pulse_native);
            }
        }
        _ => {}
    }

    match cfg.pipewire_mode.as_str() {
        "sandboxed" => {
            let pw_rest = format!("{runtime_dir}/pipewire-0-restricted");
            let pw_native = format!("{runtime_dir}/pipewire-0");
            if Path::new(&pw_rest).exists() {
                cmd.arg("--ro-bind-try").arg(&pw_rest).arg(&pw_native);
            }
        }
        "passthrough" => {
            let pw_native = format!("{runtime_dir}/pipewire-0");
            if Path::new(&pw_native).exists() {
                cmd.arg("--ro-bind-try").arg(&pw_native).arg(&pw_native);
            }
        }
        _ => {}
    }
}

fn add_display_binds(
    cmd: &mut Command,
    cfg: &SandboxConfig,
    runtime_dir: &str,
    sandbox_runtime: &Path,
) {
    match cfg.wayland_mode.as_str() {
        "sandboxed" => {
            let wayland_disp = env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "wayland-0".into());
            let wayland_sock = format!("{runtime_dir}/{wayland_disp}");
            let wayland_filtered = sandbox_runtime.join("wayland-secure");
            if wayland_filtered.exists() {
                cmd.arg("--ro-bind")
                    .arg(&wayland_filtered)
                    .arg(&wayland_sock);
            } else {
                eprintln!(
                    "[sb-run] Error: sandboxed Wayland requested but way-secure socket '{}' does not exist",
                    wayland_filtered.display()
                );
                exit(1);
            }
            cmd.arg("--setenv")
                .arg("WAYLAND_DISPLAY")
                .arg(&wayland_disp);
        }
        "passthrough" => {
            let wayland_disp = env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "wayland-0".into());
            let wayland_sock = format!("{runtime_dir}/{wayland_disp}");
            if Path::new(&wayland_sock).exists() {
                cmd.arg("--ro-bind-try")
                    .arg(&wayland_sock)
                    .arg(&wayland_sock);
            }
            cmd.arg("--setenv")
                .arg("WAYLAND_DISPLAY")
                .arg(&wayland_disp);
        }
        _ => {}
    }

    if cfg.x11_mode == "passthrough" && Path::new("/tmp/.X11-unix").exists() {
        cmd.arg("--ro-bind")
            .arg("/tmp/.X11-unix")
            .arg("/tmp/.X11-unix");
        let disp = env::var("DISPLAY").unwrap_or_else(|_| ":0".into());
        cmd.arg("--setenv").arg("DISPLAY").arg(&disp);
    } else if cfg.x11_mode == "sandboxed" {
        cmd.arg("--setenv").arg("DISPLAY").arg(":0");
    }
}

fn add_subsystem_binds(
    cmd: &mut Command,
    cfg: &SandboxConfig,
    runtime_dir: &str,
    sandbox_runtime: &Path,
) {
    if (cfg.subsystems & SUBSYS_GPU) != 0 {
        add_gpu_binds(cmd);
    }

    add_audio_binds(cmd, cfg, runtime_dir);
    add_display_binds(cmd, cfg, runtime_dir, sandbox_runtime);

    let wivrn_socket = format!("{runtime_dir}/wivrn");
    if Path::new(&wivrn_socket).exists() {
        cmd.arg("--ro-bind-try")
            .arg(&wivrn_socket)
            .arg(&wivrn_socket);
    }

    if (cfg.subsystems & SUBSYS_GAMEPAD) != 0 {
        if Path::new("/dev/input").exists() {
            cmd.arg("--dev-bind-try")
                .arg("/dev/input")
                .arg("/dev/input");
        }
        if Path::new("/dev/uinput").exists() {
            cmd.arg("--dev-bind-try")
                .arg("/dev/uinput")
                .arg("/dev/uinput");
        }
    }

    if cfg.webcam_count > 0 {
        for idx in 0..cfg.webcam_count {
            let dev_node = format!("/dev/video{idx}");
            if Path::new(&dev_node).exists() {
                cmd.arg("--dev-bind-try").arg(&dev_node).arg(&dev_node);
            }
        }
    }
}

fn is_trusted_executor_path(p: &Path) -> bool {
    let s = p.to_string_lossy();
    s.starts_with("/nix/store/") || s.starts_with("/run/current-system/")
}

fn resolve_executor_bin(cfg: &SandboxConfig) -> PathBuf {
    if let Some(ref p) = cfg.executor_path
        && p.exists()
    {
        return p.clone();
    }
    if let Ok(env_p) = env::var("SB_EXECUTOR_BIN") {
        let pb = PathBuf::from(env_p);
        if pb.exists() && is_trusted_executor_path(&pb) {
            return pb;
        }
    }
    if let Ok(current_exe) = env::current_exe()
        && let Some(parent) = current_exe.parent()
    {
        let sibling = parent.join("sb-executor");
        if sibling.is_file() && is_trusted_executor_path(&sibling) {
            return sibling;
        }
    }
    if let Ok(path_var) = env::var("PATH") {
        for entry in env::split_paths(&path_var) {
            if is_trusted_executor_path(&entry) {
                let candidate = entry.join("sb-executor");
                if candidate.is_file() {
                    return candidate;
                }
            }
        }
    }
    PathBuf::from("/run/current-system/sw/bin/sb-executor")
}

fn add_ipc_and_dbus_binds(
    cmd: &mut Command,
    cfg: &SandboxConfig,
    runtime: &str,
    sandbox_runtime: &Path,
) {
    let host_executor = resolve_executor_bin(cfg);
    let in_sandbox_dest = format!("{runtime}/bin/sb-executor");
    if host_executor.exists() {
        cmd.arg("--ro-bind")
            .arg(&host_executor)
            .arg(&in_sandbox_dest);
    }

    if cfg.dbus_mode == "sandboxed" {
        let dbus_proxy_sock = sandbox_runtime.join("nixpak-bus");
        cmd.arg("--bind-try")
            .arg(&dbus_proxy_sock)
            .arg(format!("{runtime}/nixpak-bus"));
        cmd.arg("--bind-try")
            .arg(&dbus_proxy_sock)
            .arg(format!("{runtime}/bus"));
        cmd.arg("--setenv")
            .arg("DBUS_SESSION_BUS_ADDRESS")
            .arg(format!("unix:path={runtime}/nixpak-bus"));
    } else if cfg.dbus_mode == "passthrough" {
        if let Ok(session_bus) = env::var("DBUS_SESSION_BUS_ADDRESS") {
            if let Some(path) = session_bus.strip_prefix("unix:path=") {
                cmd.arg("--bind-try").arg(path).arg(path);
                cmd.arg("--bind-try")
                    .arg(path)
                    .arg(format!("{runtime}/bus"));
            }
            cmd.arg("--setenv")
                .arg("DBUS_SESSION_BUS_ADDRESS")
                .arg(&session_bus);
        }
    } else {
        cmd.arg("--unsetenv").arg("DBUS_SESSION_BUS_ADDRESS");
    }

    if (cfg.flags & CFG_SYSTEM_DBUS) != 0 {
        let host_sys_proxy = sandbox_runtime.join("nixpak-system-bus");
        let in_sandbox_sys_proxy = format!("{runtime}/nixpak-system-bus");
        cmd.arg("--bind-try")
            .arg(&host_sys_proxy)
            .arg(&in_sandbox_sys_proxy);
        cmd.arg("--bind-try")
            .arg(&host_sys_proxy)
            .arg("/run/dbus/system_bus_socket");
        cmd.arg("--setenv")
            .arg("DBUS_SYSTEM_BUS_ADDRESS")
            .arg(format!("unix:path={in_sandbox_sys_proxy}"));
    }
}

fn create_flatpak_info(sandbox_runtime: &Path, cfg: &SandboxConfig) -> PathBuf {
    let instance_id = format!("nixpak-app-{}", cfg.app_id);
    let uid = libc_getuid();
    let runtime_base = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| format!("/run/user/{uid}"));
    let flatpak_dir = PathBuf::from(format!("{runtime_base}/.flatpak/{instance_id}"));
    let _ = fs::create_dir_all(&flatpak_dir);

    let info_path = sandbox_runtime.join("flatpak-info");
    let mut content = format!(
        "[Application]\nname={}\nruntime=runtime/com.nixpak.Platform/x86_64/1\n\n[Context]\n",
        cfg.app_id
    );

    let mut shared = Vec::new();
    if (cfg.flags & CFG_SHARE_IPC) != 0 {
        shared.push("ipc");
    }
    if cfg.network == "passthrough" {
        shared.push("network");
    }
    if !shared.is_empty() {
        let _ = writeln!(content, "shared={};", shared.join(";"));
    }

    let _ = write!(
        content,
        "\n[Instance]\ninstance-id={instance_id}\napp-path=/app\nruntime-path=/usr\n"
    );

    content.push_str(DEFAULT_FLATPAK_POLICY_BUS);

    for talk in &cfg.dbus_talk {
        let _ = writeln!(content, "{talk}=talk");
    }
    for own in &cfg.dbus_own {
        let _ = writeln!(content, "{own}=own");
    }
    for see in &cfg.dbus_see {
        let _ = writeln!(content, "{see}=see");
    }

    let _ = fs::write(&info_path, &content);
    let _ = fs::write(flatpak_dir.join("info"), &content);
    unsafe {
        env::set_var("FLATPAK_METADATA_FILE", flatpak_dir.join("info"));
    }
    info_path
}

fn add_network_bwrap_args(cmd: &mut Command, cfg: &SandboxConfig, sandbox_runtime: &Path) {
    if cfg.network == "singbox" {
        cmd.arg("--unshare-net");
        cmd.arg("--uid").arg("0").arg("--gid").arg("0");
        cmd.arg("--cap-add").arg("CAP_NET_ADMIN");
        cmd.arg("--cap-add").arg("CAP_SETFCAP");
        cmd.arg("--cap-add").arg("CAP_NET_RAW");
        cmd.arg("--cap-add").arg("CAP_NET_BIND_SERVICE");
        cmd.arg("--dir").arg("/dev/net");
        cmd.arg("--dev-bind-try")
            .arg("/dev/net/tun")
            .arg("/dev/net/tun");
        cmd.arg("--ro-bind-try")
            .arg("/etc/resolv.conf")
            .arg("/etc/resolv.conf");
    } else if cfg.network == "sandboxed" {
        cmd.arg("--unshare-net");
        let resolv_path = sandbox_runtime.join("resolv.conf");
        let _ = fs::write(&resolv_path, "nameserver 192.168.1.1\n");
        cmd.arg("--ro-bind")
            .arg(&resolv_path)
            .arg("/etc/resolv.conf");
    } else if cfg.network != "passthrough" {
        cmd.arg("--unshare-net");
    }
}

fn add_custom_binds_and_env(cmd: &mut Command, cfg: &SandboxConfig) {
    for b in &cfg.ro_binds {
        let (src, dst) = b.split_once(':').unwrap_or((b.as_str(), b.as_str()));
        cmd.arg("--ro-bind-try").arg(src).arg(dst);
    }
    for b in &cfg.rw_binds {
        let (src, dst) = b.split_once(':').unwrap_or((b.as_str(), b.as_str()));
        if let Some(parent) = Path::new(src).parent() {
            let _ = fs::create_dir_all(parent);
        }
        cmd.arg("--bind-try").arg(src).arg(dst);
    }
    for b in &cfg.dev_binds {
        let (src, dst) = b.split_once(':').unwrap_or((b.as_str(), b.as_str()));
        cmd.arg("--dev-bind-try").arg(src).arg(dst);
    }
    for item in &cfg.extra_env {
        if let Some((k, v)) = item.split_once('=') {
            cmd.arg("--setenv").arg(k).arg(v);
        }
    }
    for arg in &cfg.bwrap_extra_args {
        cmd.arg(arg);
    }
}

fn add_bwrap_cgroup_pre_exec(
    cmd: &mut Command,
    pasta_sync: Option<(i32, i32)>,
    extra_info_fd: Option<i32>,
) {
    let cgroup = env::var("MY_CGROUP").ok();
    let c_path = cgroup.and_then(|cg| CString::new(format!("{cg}/helpers/cgroup.procs")).ok());

    unsafe {
        cmd.pre_exec(move || {
            if let Some((r_block, w_info)) = pasta_sync {
                let _ = fcntl(r_block, 2, 0);
                let _ = fcntl(w_info, 2, 0);
            }
            if let Some(w_info) = extra_info_fd {
                let _ = fcntl(w_info, 2, 0);
            }
            if let Some(ref path) = c_path {
                let fd = open(path.as_ptr(), 1);
                if fd >= 0 {
                    let pid = getpid();
                    let mut n = u32::try_from(pid).unwrap_or(0);
                    let mut buf = [0u8; 32];
                    let mut rev = [0u8; 16];
                    let mut r_idx = if n == 0 {
                        rev[0] = b'0';
                        1
                    } else {
                        let mut count = 0;
                        while n > 0 {
                            rev[count] = b'0' + (n % 10) as u8;
                            n /= 10;
                            count += 1;
                        }
                        count
                    };
                    let mut idx = 0;
                    while r_idx > 0 {
                        r_idx -= 1;
                        buf[idx] = rev[r_idx];
                        idx += 1;
                    }
                    buf[idx] = b'\n';
                    idx += 1;
                    let _ = write(fd, buf.as_ptr().cast(), idx);
                    let _ = close(fd);
                }
            }
            Ok(())
        });
    }
}

fn add_bwrap_executor_args(
    cmd: &mut Command,
    cfg: &SandboxConfig,
    runtime: &str,
    in_sandbox_socket: &str,
    in_sandbox_ready_pipe: &str,
    auth_token_hex: Option<&str>,
) {
    let host_executor = resolve_executor_bin(cfg);
    let exec_target = if host_executor.exists() {
        format!("{runtime}/bin/sb-executor")
    } else {
        "sb-executor".to_string()
    };

    cmd.arg(&exec_target)
        .arg("--socket")
        .arg(in_sandbox_socket)
        .arg("--ready-pipe")
        .arg(in_sandbox_ready_pipe);

    if let Some(token_hex) = auth_token_hex {
        cmd.arg("--token").arg(token_hex);
    }

    if cfg.network == "singbox" {
        if let Some(ref sb_bin) = cfg.singbox_bin {
            cmd.arg("--singbox-bin").arg(sb_bin);
        }
        if let Some(ref sb_cfg) = cfg.singbox_config {
            cmd.arg("--singbox-config").arg(sb_cfg);
        }
        cmd.arg("--singbox-sock")
            .arg(format!("{runtime}/sing-box.sock"));
        let user_id = libc_getuid();
        let group_id = libc_getgid();
        cmd.arg("--orig-uid").arg(user_id.to_string());
        cmd.arg("--orig-gid").arg(group_id.to_string());
    }

    if cfg.x11_mode == "sandboxed" {
        cmd.arg("--x11-mode").arg("sandboxed");
        if let Some(ref xwayland) = cfg.xwayland_satellite_bin {
            cmd.arg("--xwayland-bin").arg(xwayland);
        }
    }

    if (cfg.flags & CFG_LANDLOCK) == 0 {
        cmd.arg("--no-landlock");
    }

    for init_cmd in &cfg.inside_init {
        cmd.arg("--inside-init").arg(init_cmd);
    }
    let in_sandbox_migrator = format!("{runtime}/migrator.sock");
    cmd.arg("--migrator-socket").arg(&in_sandbox_migrator);
}

fn build_bwrap_command(
    cfg: &SandboxConfig,
    sandbox_runtime: &Path,
    sandbox_home: &Path,
    auth_token_hex: Option<&str>,
    pasta_sync: Option<(i32, i32)>,
    extra_info_fd: Option<i32>,
) -> Command {
    let mut cmd = if (cfg.flags & CFG_USE_VPNIFY) != 0 {
        let mut v = Command::new("vpnify");
        v.arg("bwrap");
        v
    } else {
        Command::new("bwrap")
    };

    if let Some((r_block, w_info)) = pasta_sync {
        cmd.arg("--block-fd").arg(r_block.to_string());
        cmd.arg("--info-fd").arg(w_info.to_string());
    } else if let Some(w_info) = extra_info_fd {
        cmd.arg("--info-fd").arg(w_info.to_string());
    }

    let home = env::var("HOME").unwrap_or_else(|_| "/home/user".into());
    let runtime = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/run/user/1000".into());
    let xdg_config = env::var("XDG_CONFIG_HOME").unwrap_or_else(|_| format!("{home}/.config"));
    let xdg_data = env::var("XDG_DATA_HOME").unwrap_or_else(|_| format!("{home}/.local/share"));

    cmd.arg("--die-with-parent");
    if let Some(uid) = cfg.custom_uid {
        cmd.arg("--unshare-user");
        cmd.arg("--uid").arg(uid.to_string());
        if let Some(gid) = cfg.custom_gid {
            cmd.arg("--gid").arg(gid.to_string());
        }
    } else {
        cmd.arg("--unshare-user-try");
    }
    if (cfg.flags & CFG_SHARE_IPC) == 0 {
        cmd.arg("--unshare-ipc");
    }
    if (cfg.flags & CFG_SHARE_PID) == 0 {
        cmd.arg("--unshare-pid");
    }
    cmd.arg("--unshare-uts");
    cmd.arg("--unshare-cgroup-try");

    cmd.arg("--proc").arg("/proc");
    cmd.arg("--dev").arg("/dev");

    add_network_bwrap_args(&mut cmd, cfg, sandbox_runtime);

    cmd.arg("--bind").arg(sandbox_home).arg(&home);
    cmd.arg("--bind").arg(sandbox_runtime).arg(&runtime);

    if cfg.shm_mode == "passthrough" {
        cmd.arg("--bind").arg("/dev/shm").arg("/dev/shm");
    } else {
        let shm_dir = sandbox_runtime.join("shm");
        let _ = fs::create_dir_all(&shm_dir);
        cmd.arg("--bind").arg(&shm_dir).arg("/dev/shm");
    }

    if cfg.tmp_mode == "passthrough" {
        cmd.arg("--bind").arg("/tmp").arg("/tmp");
    } else {
        let tmp_dir = sandbox_runtime.join("tmp");
        let _ = fs::create_dir_all(&tmp_dir);
        cmd.arg("--bind").arg(&tmp_dir).arg("/tmp");
    }

    let bin_dir = sandbox_runtime.join("bin");
    let _ = fs::create_dir_all(&bin_dir);

    if let Ok(p) = env::var("XDG_RUNTIME_DIR") {
        let host_sesatt = format!("{p}/sesatt/{}", cfg.app_id);
        let in_sandbox_sesatt = format!("{runtime}/sesatt/{}", cfg.app_id);
        let _ = fs::create_dir_all(&host_sesatt);
        cmd.arg("--bind-try")
            .arg(&host_sesatt)
            .arg(&in_sandbox_sesatt);

        let host_doc = format!("{p}/doc/by-app/{}", cfg.app_id);
        let in_sandbox_doc = format!("{runtime}/doc");
        cmd.arg("--bind-try").arg(&host_doc).arg(&in_sandbox_doc);
    }

    add_base_ro_binds(&mut cmd);
    add_user_theme_binds(&mut cmd, &home, &xdg_config, &xdg_data);
    add_subsystem_binds(&mut cmd, cfg, &runtime, sandbox_runtime);
    add_ipc_and_dbus_binds(&mut cmd, cfg, &runtime, sandbox_runtime);

    if (cfg.flags & CFG_FLATPAK_INFO) != 0 {
        let flatpak_info_path = create_flatpak_info(sandbox_runtime, cfg);
        cmd.arg("--ro-bind")
            .arg(&flatpak_info_path)
            .arg("/.flatpak-info");
    }

    if (cfg.flags & CFG_PORTALS) != 0 {
        let portal_mime = format!("{xdg_config}/mimeapps.list");
        if Path::new(&portal_mime).exists() {
            cmd.arg("--ro-bind-try").arg(&portal_mime).arg(&portal_mime);
        }
    }

    add_custom_binds_and_env(&mut cmd, cfg);

    let in_sandbox_socket = format!("{runtime}/ipc.sock");
    let in_sandbox_ready_pipe = format!("{runtime}/ready_pipe");

    add_bwrap_executor_args(
        &mut cmd,
        cfg,
        &runtime,
        &in_sandbox_socket,
        &in_sandbox_ready_pipe,
        auth_token_hex,
    );

    add_bwrap_cgroup_pre_exec(&mut cmd, pasta_sync, extra_info_fd);

    cmd
}

fn wait_for_file_created(dir: &Path, file_name: &str, timeout_ms: i32) -> bool {
    let full_path = dir.join(file_name);
    if full_path.exists() {
        return true;
    }
    let Ok(c_dir) = CString::new(dir.as_os_str().as_bytes()) else {
        return false;
    };
    let ifd = unsafe { inotify_init1(0x0008_0000) };
    if ifd < 0 {
        return full_path.exists();
    }
    let wd = unsafe { inotify_add_watch(ifd, c_dir.as_ptr(), 0x0000_0100) };
    if wd < 0 {
        let _ = unsafe { close(ifd) };
        return full_path.exists();
    }
    if full_path.exists() {
        let _ = unsafe { close(ifd) };
        return true;
    }
    let mut pfd = PollFd {
        fd: ifd,
        events: 0x0001,
        revents: 0,
    };
    let mut remaining = timeout_ms;
    while remaining > 0 {
        let start = Instant::now();
        let res = unsafe { poll(&raw mut pfd, 1, remaining) };
        if res > 0 {
            let mut buf = [0u8; 1024];
            let _ = unsafe { read(ifd, buf.as_mut_ptr().cast(), buf.len()) };
            if full_path.exists() {
                let _ = unsafe { close(ifd) };
                return true;
            }
        } else if res == 0 {
            break;
        }
        let elapsed = u32::try_from(start.elapsed().as_millis()).unwrap_or(0);
        let elapsed_i32 = i32::try_from(elapsed).unwrap_or(remaining);
        remaining -= elapsed_i32;
    }
    let _ = unsafe { close(ifd) };
    full_path.exists()
}

fn move_bridge_listener_to_helpers(cgroup_path: &Path, runner_pid: u32) -> Option<i32> {
    let inside_procs = cgroup_path.join("inside/cgroup.procs");
    let helpers_procs = cgroup_path.join("helpers/cgroup.procs");
    let runner_i32 = i32::try_from(runner_pid).unwrap_or(0);

    for _ in 0..50 {
        let pids = read_pids_from_file(&inside_procs);
        for pid in pids {
            if pid != runner_i32 {
                let cmdline_path = format!("/proc/{pid}/cmdline");
                if let Ok(cmd) = fs::read_to_string(&cmdline_path)
                    && cmd.contains("rust-bridge")
                {
                    let _ = fs::write(&helpers_procs, format!("{pid}\n"));
                    return Some(pid);
                }
            }
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    None
}

fn setup_bridge_from_sandbox(
    cfg: &SandboxConfig,
    bridge: &BridgeRule,
    host_sock: &Path,
    in_sandbox_sock: &str,
    ipc_sock: &Path,
    cgroup_path: Option<&Path>,
    runner_pid: u32,
) -> (Option<i32>, Option<i32>) {
    let addr_spec = format!("{}:[{}]", bridge.address, bridge.ports);
    let child = Command::new("rust-bridge")
        .args(["-r", "pass", "--address", &addr_spec, "-s"])
        .arg(host_sock)
        .spawn()
        .ok();

    let pid = child.and_then(|c| i32::try_from(c.id()).ok());

    if let Some(parent) = host_sock.parent()
        && let Some(name) = host_sock.file_name().and_then(|n| n.to_str())
    {
        wait_for_file_created(parent, name, 500);
    }

    let listen_cmd = vec![
        "rust-bridge".to_string(),
        "-r".to_string(),
        "listen".to_string(),
        "--address".to_string(),
        addr_spec,
        "-s".to_string(),
        in_sandbox_sock.to_string(),
        "-d".to_string(),
    ];
    let bridge_cfg = SandboxConfig {
        app_id: cfg.app_id.clone(),
        command: listen_cmd,
        is_helper_request: true,
        ..Default::default()
    };
    let _ = try_connect_running_sandbox(ipc_sock, &bridge_cfg);

    let listener_pid = cgroup_path.and_then(|cg| move_bridge_listener_to_helpers(cg, runner_pid));
    (pid, listener_pid)
}

fn setup_bridge_to_sandbox(
    cfg: &SandboxConfig,
    bridge: &BridgeRule,
    host_sock: &Path,
    in_sandbox_sock: &str,
    ipc_sock: &Path,
) -> Option<i32> {
    let addr_spec = format!("{}:[{}]", bridge.address, bridge.ports);
    let pass_cmd = vec![
        "rust-bridge".to_string(),
        "-r".to_string(),
        "pass".to_string(),
        "--address".to_string(),
        addr_spec.clone(),
        "-s".to_string(),
        in_sandbox_sock.to_string(),
    ];
    let bridge_cfg = SandboxConfig {
        app_id: cfg.app_id.clone(),
        command: pass_cmd,
        is_helper_request: true,
        ..Default::default()
    };
    let _ = try_connect_running_sandbox(ipc_sock, &bridge_cfg);

    if let Some(parent) = host_sock.parent()
        && let Some(name) = host_sock.file_name().and_then(|n| n.to_str())
    {
        wait_for_file_created(parent, name, 500);
    }

    let child = Command::new("rust-bridge")
        .args(["-r", "listen", "--address", &addr_spec, "-s"])
        .arg(host_sock)
        .arg("-d")
        .spawn()
        .ok()?;

    i32::try_from(child.id()).ok()
}

fn setup_bridges(
    cfg: &SandboxConfig,
    sandbox_runtime: &Path,
    ipc_sock: &Path,
    cgroup_path: Option<&Path>,
    runner_pid: u32,
) -> Vec<i32> {
    if cfg.network == "passthrough" {
        return Vec::new();
    }
    let mut pids = Vec::new();
    let runtime = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/run/user/1000".into());

    for (idx, bridge) in cfg.bridges.iter().enumerate() {
        let sock_name = format!("bridge_{idx}.sock");
        let host_sock = sandbox_runtime.join(&sock_name);
        let in_sandbox_sock = format!("{runtime}/{sock_name}");
        let _ = fs::remove_file(&host_sock);

        match bridge.direction {
            BridgeDirection::FromSandbox => {
                let (host_pid, listener_pid) = setup_bridge_from_sandbox(
                    cfg,
                    bridge,
                    &host_sock,
                    &in_sandbox_sock,
                    ipc_sock,
                    cgroup_path,
                    runner_pid,
                );
                if let Some(p) = host_pid {
                    pids.push(p);
                }
                if let Some(p) = listener_pid {
                    pids.push(p);
                }
            }
            BridgeDirection::ToSandbox => {
                if let Some(p) =
                    setup_bridge_to_sandbox(cfg, bridge, &host_sock, &in_sandbox_sock, ipc_sock)
                {
                    pids.push(p);
                }
            }
        }
    }
    pids
}

fn cleanup_bridges(pids: &[i32], sandbox_runtime: &Path, count: usize) {
    for pid in pids {
        unsafe { kill(*pid, 15) };
    }
    for idx in 0..count {
        let _ = fs::remove_file(sandbox_runtime.join(format!("bridge_{idx}.sock")));
    }
}

fn start_way_secure(cfg: &SandboxConfig, sandbox_runtime: &Path) -> Option<i32> {
    if cfg.wayland_mode != "sandboxed" {
        return None;
    }
    let sock_path = sandbox_runtime.join("wayland-secure");
    let _ = fs::remove_file(&sock_path);
    let _ = fs::remove_file(sandbox_runtime.join("wayland-secure.lock"));

    let mut ready_pipe = [0i32; 2];
    if unsafe { pipe(ready_pipe.as_mut_ptr()) } != 0 {
        eprintln!("[sb-run] Error: Failed to create pipe for way-secure readiness");
        exit(1);
    }
    let [ready_r, ready_w] = ready_pipe;

    let mut close_pipe = [0i32; 2];
    if unsafe { pipe(close_pipe.as_mut_ptr()) } != 0 {
        unsafe {
            close(ready_r);
            close(ready_w);
        }
        eprintln!("[sb-run] Error: Failed to create pipe for way-secure close");
        exit(1);
    }
    let [close_r, close_w] = close_pipe;

    let bin_name = cfg.way_secure_bin.as_ref().map_or_else(
        || {
            let sys = PathBuf::from("/run/current-system/sw/bin/way-secure");
            if sys.exists() {
                sys
            } else {
                PathBuf::from("way-secure")
            }
        },
        Clone::clone,
    );

    let mut cmd = Command::new(bin_name);
    cmd.arg("--socket-path")
        .arg(&sock_path)
        .arg("-a")
        .arg(&cfg.app_id)
        .arg("-e")
        .arg("flatpak")
        .arg("-r")
        .arg(ready_w.to_string())
        .arg("-c")
        .arg(close_r.to_string());

    unsafe {
        cmd.pre_exec(move || {
            let _ = fcntl(ready_w, 2, 0);
            let _ = fcntl(close_r, 2, 0);
            prctl(1, 15, 0, 0, 0);
            Ok(())
        });
    }

    match cmd.spawn() {
        Ok(mut child) => {
            unsafe {
                close(ready_w);
                close(close_r);
            }
            let mut buf = [0u8; 8];
            let n = unsafe { read(ready_r, buf.as_mut_ptr().cast(), 8) };
            unsafe { close(ready_r) };
            if n <= 0 && !sock_path.exists() {
                eprintln!(
                    "[sb-run] Error: way-secure failed before signaling readiness on '{}'",
                    sock_path.display()
                );
                let _ = child.kill();
                unsafe { close(close_w) };
                exit(1);
            }
            let _ = child.wait();
            Some(close_w)
        }
        Err(err) => {
            unsafe {
                close(ready_w);
                close(ready_r);
                close(close_r);
                close(close_w);
            }
            eprintln!("[sb-run] Error: Failed to spawn way-secure: {err}");
            exit(1);
        }
    }
}

fn add_dbus_proxy_rules(proxy_cmd: &mut Command, cfg: &SandboxConfig) {
    for talk in DEFAULT_DBUS_TALKS {
        proxy_cmd.arg(format!("--talk={talk}"));
    }
    for talk in &cfg.dbus_talk {
        proxy_cmd.arg(format!("--talk={talk}"));
    }
    for own in DEFAULT_DBUS_OWNS {
        proxy_cmd.arg(format!("--own={own}"));
    }
    for own in &cfg.dbus_own {
        proxy_cmd.arg(format!("--own={own}"));
    }
    for see in &cfg.dbus_see {
        proxy_cmd.arg(format!("--see={see}"));
    }
    for arg in &cfg.dbus_extra_args {
        proxy_cmd.arg(arg);
    }
}

fn start_dbus_proxy(cfg: &SandboxConfig, proxy_sock: &Path, flatpak_info: &Path) -> Option<Child> {
    let Ok(session_bus) = env::var("DBUS_SESSION_BUS_ADDRESS") else {
        return None;
    };
    let _ = fs::remove_file(proxy_sock);

    let bin_name = cfg.dbus_proxy_bin.as_ref().map_or_else(
        || {
            let sys = PathBuf::from("/run/current-system/sw/bin/xdg-dbus-proxy");
            if sys.exists() {
                sys
            } else {
                PathBuf::from("xdg-dbus-proxy")
            }
        },
        Clone::clone,
    );

    let bwrap_bin = {
        let sys = PathBuf::from("/run/current-system/sw/bin/bwrap");
        if sys.exists() {
            sys
        } else {
            PathBuf::from("bwrap")
        }
    };

    let mut proxy_cmd = Command::new(bwrap_bin);
    proxy_cmd
        .arg("--die-with-parent")
        .arg("--ro-bind")
        .arg("/etc")
        .arg("/etc")
        .arg("--ro-bind")
        .arg("/nix/store")
        .arg("/nix/store")
        .arg("--bind")
        .arg("/var")
        .arg("/var")
        .arg("--bind")
        .arg("/tmp")
        .arg("/tmp")
        .arg("--bind")
        .arg("/run")
        .arg("/run")
        .arg("--ro-bind-try")
        .arg(flatpak_info)
        .arg("/.flatpak-info")
        .arg("--")
        .arg(bin_name)
        .arg(&session_bus)
        .arg(proxy_sock)
        .arg("--filter");

    add_dbus_proxy_rules(&mut proxy_cmd, cfg);
    unsafe {
        proxy_cmd.pre_exec(|| {
            prctl(1, 15, 0, 0, 0);
            Ok(())
        });
    }

    match proxy_cmd.spawn() {
        Ok(child) => {
            if let Some(parent) = proxy_sock.parent()
                && let Some(name) = proxy_sock.file_name().and_then(|n| n.to_str())
            {
                wait_for_file_created(parent, name, 1000);
            }
            Some(child)
        }
        Err(err) => {
            eprintln!("[sb-run] Failed to spawn xdg-dbus-proxy via bwrap: {err}");
            None
        }
    }
}

fn add_system_dbus_proxy_rules(proxy_cmd: &mut Command, cfg: &SandboxConfig) {
    for talk in &cfg.system_dbus_talk {
        proxy_cmd.arg(format!("--talk={talk}"));
    }
    for own in &cfg.system_dbus_own {
        proxy_cmd.arg(format!("--own={own}"));
    }
    for see in &cfg.system_dbus_see {
        proxy_cmd.arg(format!("--see={see}"));
    }
    for arg in &cfg.system_dbus_extra_args {
        proxy_cmd.arg(arg);
    }
}

fn start_system_dbus_proxy(
    cfg: &SandboxConfig,
    proxy_sock: &Path,
    flatpak_info: &Path,
) -> Option<Child> {
    if !Path::new("/run/dbus/system_bus_socket").exists() {
        return None;
    }
    let _ = fs::remove_file(proxy_sock);

    let bin_name = cfg.dbus_proxy_bin.as_ref().map_or_else(
        || {
            let sys = PathBuf::from("/run/current-system/sw/bin/xdg-dbus-proxy");
            if sys.exists() {
                sys
            } else {
                PathBuf::from("xdg-dbus-proxy")
            }
        },
        Clone::clone,
    );

    let bwrap_bin = {
        let sys = PathBuf::from("/run/current-system/sw/bin/bwrap");
        if sys.exists() {
            sys
        } else {
            PathBuf::from("bwrap")
        }
    };

    let mut proxy_cmd = Command::new(bwrap_bin);
    proxy_cmd
        .arg("--die-with-parent")
        .arg("--ro-bind")
        .arg("/etc")
        .arg("/etc")
        .arg("--ro-bind")
        .arg("/nix/store")
        .arg("/nix/store")
        .arg("--bind")
        .arg("/var")
        .arg("/var")
        .arg("--bind")
        .arg("/tmp")
        .arg("/tmp")
        .arg("--bind")
        .arg("/run")
        .arg("/run")
        .arg("--ro-bind-try")
        .arg(flatpak_info)
        .arg("/.flatpak-info")
        .arg("--")
        .arg(bin_name)
        .arg("unix:path=/run/dbus/system_bus_socket")
        .arg(proxy_sock)
        .arg("--filter");

    add_system_dbus_proxy_rules(&mut proxy_cmd, cfg);
    unsafe {
        proxy_cmd.pre_exec(|| {
            prctl(1, 15, 0, 0, 0);
            Ok(())
        });
    }

    match proxy_cmd.spawn() {
        Ok(child) => {
            if let Some(parent) = proxy_sock.parent()
                && let Some(name) = proxy_sock.file_name().and_then(|n| n.to_str())
            {
                wait_for_file_created(parent, name, 1000);
            }
            Some(child)
        }
        Err(err) => {
            eprintln!("[sb-run] Failed to spawn system xdg-dbus-proxy via bwrap: {err}");
            None
        }
    }
}

fn start_pasta(cfg: &SandboxConfig, child_pid: u32) -> Option<Child> {
    if cfg.network != "sandboxed" {
        return None;
    }
    let pasta_bin = cfg.pasta_bin.as_ref().map_or_else(
        || {
            let sys = PathBuf::from("/run/current-system/sw/bin/pasta");
            if sys.exists() {
                sys
            } else {
                PathBuf::from("pasta")
            }
        },
        Clone::clone,
    );

    let mut cmd = Command::new(pasta_bin);
    cmd.args(PASTA_DEFAULT_ARGS);
    cmd.arg(child_pid.to_string());
    match cmd.spawn() {
        Ok(child) => Some(child),
        Err(err) => {
            eprintln!("[sb-run] Warning: Failed to spawn pasta: {err}");
            None
        }
    }
}

fn resolve_sandbox_home(cfg: &SandboxConfig, runtime_base: &str) -> PathBuf {
    if (cfg.flags & CFG_TMPFS) != 0 {
        let tmpfs_path = PathBuf::from(format!("{runtime_base}/sb-run/{}/home", cfg.app_id));
        let _ = fs::create_dir_all(&tmpfs_path);
        tmpfs_path
    } else if let Some(ref dir) = cfg.custom_dir {
        let _ = fs::create_dir_all(dir);
        dir.clone()
    } else {
        let home = env::var("HOME").unwrap_or_else(|_| "/home/user".into());
        let default_home = PathBuf::from(format!("{home}/.nixpak/{}/home", cfg.app_id));
        let _ = fs::create_dir_all(&default_home);
        default_home
    }
}

fn cleanup_session(
    cfg: &SandboxConfig,
    paths: &SandboxPaths,
    bridge_pids: &[i32],
    mut helpers: HelperProcesses,
) {
    if let Some(fd) = helpers.way_secure_close_fd {
        unsafe { close(fd) };
    }
    if let Some(ref mut c) = helpers.dbus_proxy {
        let pid = c.id();
        if let Ok(pid_i32) = i32::try_from(pid) {
            unsafe {
                kill(-pid_i32, 15);
                kill(pid_i32, 15);
            }
        }
        let _ = c.kill();
        let _ = c.wait();
    }
    if let Some(ref mut c) = helpers.system_dbus_proxy {
        let pid = c.id();
        if let Ok(pid_i32) = i32::try_from(pid) {
            unsafe {
                kill(-pid_i32, 15);
                kill(pid_i32, 15);
            }
        }
        let _ = c.kill();
        let _ = c.wait();
    }
    if let Some(ref mut c) = helpers.singbox_bridge {
        let _ = c.kill();
        let _ = c.wait();
    }
    if let Some(ref mut c) = helpers.pasta {
        let _ = c.kill();
        let _ = c.wait();
    }
    let _ = fs::remove_file(paths.runtime.join("wayland-secure"));
    let _ = fs::remove_file(paths.runtime.join("wayland-secure.lock"));
    cleanup_bridges(bridge_pids, &paths.runtime, cfg.bridges.len());
    let _ = fs::remove_file(&paths.ipc_sock);
    let _ = fs::remove_file(paths.runtime.join("migrator.sock"));
    let _ = fs::remove_file(paths.runtime.join("sing-box.sock"));
    cleanup_token_for_app(&cfg.app_id);
    let instance_id = format!("nixpak-app-{}", cfg.app_id);
    let uid = libc_getuid();
    let runtime_base = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| format!("/run/user/{uid}"));
    let _ = fs::remove_dir_all(format!("{runtime_base}/.flatpak/{instance_id}"));
    if (cfg.flags & CFG_TMPFS) != 0 {
        let _ = fs::remove_dir_all(&paths.runtime);
        let _ = fs::remove_dir_all(&paths.home);
    }
    if let Ok(scope) = env::var("MY_SCOPE")
        && scope_matches_app(&scope, cfg)
    {
        let _ = Command::new("systemctl")
            .args(["--user", "--no-block", "stop", &scope])
            .spawn();
    }
}

#[repr(C)]
#[derive(Clone, Copy)]
struct EpollEvent {
    events: u32,
    data: u64,
}

struct Epoll(i32);

impl Epoll {
    fn new() -> Option<Self> {
        let fd = unsafe { epoll_create1(0) };
        if fd >= 0 { Some(Self(fd)) } else { None }
    }

    fn add(&self, fd: i32) -> bool {
        let Ok(data) = u64::try_from(fd) else {
            return false;
        };
        let mut ev = EpollEvent {
            events: EPOLLIN,
            data,
        };
        unsafe { epoll_ctl(self.0, EPOLL_CTL_ADD, fd, &raw mut ev) == 0 }
    }

    fn add_pri(&self, fd: i32) -> bool {
        let Ok(data) = u64::try_from(fd) else {
            return false;
        };
        let mut ev = EpollEvent {
            events: EPOLLPRI | EPOLLERR,
            data,
        };
        unsafe { epoll_ctl(self.0, EPOLL_CTL_ADD, fd, &raw mut ev) == 0 }
    }

    fn del_and_close(&self, fd: i32) {
        unsafe {
            epoll_ctl(self.0, EPOLL_CTL_DEL, fd, std::ptr::null_mut());
            close(fd);
        }
    }

    fn wait(&self, events: &mut [EpollEvent], timeout_ms: i32) -> Result<usize, i32> {
        let Ok(len) = i32::try_from(events.len()) else {
            return Err(0);
        };
        let n = unsafe { epoll_wait(self.0, events.as_mut_ptr(), len, timeout_ms) };
        if n < 0 {
            let err = std::io::Error::last_os_error();
            Err(err.raw_os_error().unwrap_or(0))
        } else {
            usize::try_from(n).map_err(|_| 0)
        }
    }
}

impl Drop for Epoll {
    fn drop(&mut self) {
        unsafe { close(self.0) };
    }
}

fn pidfd_open(pid: i32) -> Option<i32> {
    if pid <= 0 {
        return None;
    }
    let res = unsafe { syscall(SYS_PIDFD_OPEN, i64::from(pid), 0) };
    let fd = i32::try_from(res).ok()?;
    if fd >= 0 { Some(fd) } else { None }
}

fn read_pids_from_file(path: &Path) -> std::collections::HashSet<i32> {
    fs::read_to_string(path)
        .unwrap_or_default()
        .lines()
        .filter_map(|l| l.trim().parse().ok())
        .filter(|&p| p > 0)
        .collect()
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct UCred {
    pid: i32,
    uid: u32,
    gid: u32,
}

fn handle_migration(listener: &UnixListener, inside_procs: Option<&Path>) -> Option<i32> {
    match listener.accept() {
        Ok((mut stream, _)) => {
            let mut ucred = UCred::default();
            let mut len = u32::try_from(size_of::<UCred>()).unwrap_or(0);
            let fd = stream.as_raw_fd();
            let res = unsafe {
                getsockopt(
                    fd,
                    SOL_SOCKET,
                    SO_PEERCRED,
                    (&raw mut ucred).cast(),
                    &raw mut len,
                )
            };
            if let Some(p) = inside_procs
                && res == 0
                && ucred.pid > 0
            {
                let _ = fs::write(p, format!("{}\n", ucred.pid));
            }
            let _ = stream.write_all(b"G");
            let _ = stream.flush();
            if res == 0 && ucred.pid > 0 {
                Some(ucred.pid)
            } else {
                None
            }
        }
        Err(_) => None,
    }
}

struct MonitorContext<'a> {
    epoll: &'a Epoll,
    cgroup_events_fd: i32,
    child_fd: i32,
    migrator_fd: i32,
    migrator_listener: Option<&'a UnixListener>,
    procs_path: &'a Path,
}

fn process_epoll_events(
    ctx: &MonitorContext<'_>,
    events: &[EpollEvent],
    monitored: &mut std::collections::HashSet<i32>,
) -> bool {
    for event in events {
        let Ok(fd) = i32::try_from(event.data) else {
            continue;
        };
        if fd == ctx.child_fd {
            return true;
        }
        if ctx.migrator_fd >= 0 && fd == ctx.migrator_fd {
            if let Some(l) = ctx.migrator_listener
                && let Some(pid) = handle_migration(l, Some(ctx.procs_path))
                && let Some(pfd) = pidfd_open(pid)
            {
                if ctx.epoll.add(pfd) {
                    monitored.insert(pid);
                } else {
                    unsafe { close(pfd) };
                }
            }
            continue;
        }
        if fd == ctx.cgroup_events_fd {
            let mut drain_buf = [0u8; 256];
            unsafe {
                lseek(ctx.cgroup_events_fd, 0, 0);
                read(
                    ctx.cgroup_events_fd,
                    drain_buf.as_mut_ptr().cast(),
                    drain_buf.len(),
                );
            };
            continue;
        }
        ctx.epoll.del_and_close(fd);
    }
    false
}

fn monitor_scope_and_cleanup(
    cfg: &SandboxConfig,
    paths: &SandboxPaths,
    bridge_pids: &[i32],
    helpers: HelperProcesses,
    child: &mut Child,
    migrator_listener: Option<&UnixListener>,
) {
    if let Ok(cgroup_path) = env::var("MY_CGROUP") {
        let procs_path = PathBuf::from(&cgroup_path).join("inside/cgroup.procs");
        let events_path = PathBuf::from(&cgroup_path).join("inside/cgroup.events");
        let mut has_seen_apps = false;

        let Some(epoll) = Epoll::new() else {
            let _ = child.wait();
            cleanup_session(cfg, paths, bridge_pids, helpers);
            return;
        };

        let c_events = CString::new(events_path.into_os_string().as_bytes()).ok();
        let cgroup_events_fd = c_events.map_or(-1, |p| unsafe { open(p.as_ptr(), 0) });
        if cgroup_events_fd >= 0 {
            let mut drain_buf = [0u8; 256];
            unsafe {
                lseek(cgroup_events_fd, 0, 0);
                read(
                    cgroup_events_fd,
                    drain_buf.as_mut_ptr().cast(),
                    drain_buf.len(),
                );
            };
            epoll.add_pri(cgroup_events_fd);
        }

        let child_i32 = i32::try_from(child.id()).unwrap_or(0);
        let child_fd = pidfd_open(child_i32).unwrap_or(-1);
        if child_fd >= 0 {
            epoll.add(child_fd);
        }

        let migrator_fd = migrator_listener.map_or(-1, AsRawFd::as_raw_fd);
        if migrator_fd >= 0 {
            epoll.add(migrator_fd);
        }

        let ctx = MonitorContext {
            epoll: &epoll,
            cgroup_events_fd,
            child_fd,
            migrator_fd,
            migrator_listener,
            procs_path: &procs_path,
        };

        let mut monitored = std::collections::HashSet::new();

        loop {
            let inside_pids = read_pids_from_file(&procs_path);

            if has_seen_apps && inside_pids.is_empty() {
                break;
            }

            for &pid in &inside_pids {
                has_seen_apps = true;
                if monitored.contains(&pid) {
                    continue;
                }
                if let Some(pfd) = pidfd_open(pid) {
                    if epoll.add(pfd) {
                        monitored.insert(pid);
                    } else {
                        unsafe { close(pfd) };
                    }
                }
            }

            let mut events = [EpollEvent { events: 0, data: 0 }; 16];
            let n = match epoll.wait(&mut events, -1) {
                Ok(n) => n,
                Err(4) => continue, // EINTR
                Err(_) => break,
            };

            if process_epoll_events(&ctx, &events[..n], &mut monitored) {
                break;
            }
        }

        if cgroup_events_fd >= 0 {
            unsafe { close(cgroup_events_fd) };
        }
    } else {
        let _ = child.wait();
    }

    cleanup_session(cfg, paths, bridge_pids, helpers);
}

fn parse_child_pid_from_info(buf: &[u8]) -> Option<u32> {
    let s = std::str::from_utf8(buf).ok()?;
    let needle = "\"child-pid\":";
    let idx = s.find(needle)?;
    let rem = s[idx + needle.len()..].trim_start();
    let num_str: String = rem.chars().take_while(char::is_ascii_digit).collect();
    num_str.parse().ok()
}

fn write_bwrap_info(app_id: &str, data: &[u8]) {
    let instance_id = format!("nixpak-app-{app_id}");
    let uid = libc_getuid();
    let runtime_base = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| format!("/run/user/{uid}"));
    let flatpak_dir = PathBuf::from(format!("{runtime_base}/.flatpak/{instance_id}"));
    let _ = fs::create_dir_all(&flatpak_dir);
    let _ = fs::write(flatpak_dir.join("bwrapinfo.json"), data);
}

fn read_info_fd_data(r_fd: i32) -> Vec<u8> {
    let mut data = Vec::new();
    let mut chunk = [0u8; 256];
    while !data.contains(&b'}') {
        let n = unsafe { read(r_fd, chunk.as_mut_ptr().cast(), chunk.len()) };
        if n <= 0 {
            break;
        }
        if let Ok(u_len) = usize::try_from(n) {
            data.extend_from_slice(&chunk[..u_len]);
        }
    }
    unsafe { close(r_fd) };
    data
}

fn handle_pasta_sync(
    pasta_sync_fds: Option<([i32; 2], [i32; 2])>,
    cfg: &SandboxConfig,
) -> (Option<Child>, u32) {
    let Some(([r_block, w_block], [r_info, w_info])) = pasta_sync_fds else {
        return (None, 0);
    };
    unsafe {
        close(r_block);
        close(w_info);
    };
    let data = read_info_fd_data(r_info);

    let runner_pid = parse_child_pid_from_info(&data).unwrap_or(0);
    if runner_pid > 0 {
        write_bwrap_info(&cfg.app_id, &data);
    }

    let pasta_child = if runner_pid > 0 {
        start_pasta(cfg, runner_pid)
    } else {
        None
    };

    let _ = unsafe { write(w_block, b"x".as_ptr().cast(), 1) };
    unsafe { close(w_block) };

    (pasta_child, runner_pid)
}

struct SandboxPaths {
    runtime: PathBuf,
    home: PathBuf,
    ipc_sock: PathBuf,
    ready_pipe: PathBuf,
}

fn prepare_sandbox_paths(cfg: &SandboxConfig) -> SandboxPaths {
    let uid = libc_getuid();
    let runtime_base = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| format!("/run/user/{uid}"));

    let sandbox_dir = PathBuf::from(format!("{runtime_base}/.nixpak/{}", cfg.app_id));
    let sandbox_runtime = sandbox_dir.join("runtime");
    let _ = fs::create_dir_all(&sandbox_runtime);
    let mut ipc_sock = sandbox_runtime.join("ipc.sock");
    if !ipc_sock.exists() {
        let alt = PathBuf::from(format!("{runtime_base}/sb-run/{}/ipc.sock", cfg.app_id));
        if alt.exists() {
            ipc_sock = alt;
        }
    }

    let sandbox_home = resolve_sandbox_home(cfg, &runtime_base);

    let ready_pipe = sandbox_runtime.join("ready_pipe");
    let _ = fs::remove_file(&ready_pipe);
    if let Ok(c_pipe) = CString::new(ready_pipe.as_os_str().as_bytes()) {
        unsafe { mkfifo(c_pipe.as_ptr(), 0o600) };
    }

    SandboxPaths {
        runtime: sandbox_runtime,
        home: sandbox_home,
        ipc_sock,
        ready_pipe,
    }
}

fn spawn_initial_helpers(cfg: &SandboxConfig, sandbox_runtime: &Path) -> HelperProcesses {
    let mut helpers = HelperProcesses::default();
    let flatpak_info_path = create_flatpak_info(sandbox_runtime, cfg);

    if cfg.dbus_mode == "sandboxed" {
        let proxy_sock = sandbox_runtime.join("nixpak-bus");
        helpers.dbus_proxy = start_dbus_proxy(cfg, &proxy_sock, &flatpak_info_path);
    }

    if (cfg.flags & CFG_SYSTEM_DBUS) != 0 {
        let sys_proxy_sock = sandbox_runtime.join("nixpak-system-bus");
        helpers.system_dbus_proxy =
            start_system_dbus_proxy(cfg, &sys_proxy_sock, &flatpak_info_path);
    }

    helpers.way_secure_close_fd = start_way_secure(cfg, sandbox_runtime);

    if cfg.network == "singbox" {
        let sb_bridge_sock = sandbox_runtime.join("sing-box.sock");
        let _ = fs::remove_file(&sb_bridge_sock);
        let mut bridge_cmd = Command::new("rust-bridge");
        bridge_cmd.args(["-r", "pass", "--address", "127.0.0.1:[1919,2121]", "-s"]);
        bridge_cmd.arg(&sb_bridge_sock);
        unsafe {
            bridge_cmd.pre_exec(|| {
                prctl(1, 15, 0, 0, 0);
                Ok(())
            });
        }
        helpers.singbox_bridge = bridge_cmd.spawn().ok();
    }

    helpers
}

fn spawn_bwrap_and_get_runner(
    cfg: &SandboxConfig,
    paths: &SandboxPaths,
    token_hex: &str,
    pasta_sync_pass: Option<(i32, i32)>,
    extra_info_w: Option<i32>,
    extra_info_r: Option<i32>,
) -> (Child, u32) {
    let mut bwrap = build_bwrap_command(
        cfg,
        &paths.runtime,
        &paths.home,
        Some(token_hex),
        pasta_sync_pass,
        extra_info_w,
    );
    let child = match bwrap.spawn() {
        Ok(c) => c,
        Err(err) => {
            eprintln!("[sb-run] Failed to spawn bwrap: {err}");
            cleanup_token_for_app(&cfg.app_id);
            exit(1);
        }
    };

    let runner_pid = extra_info_r.map_or(0, |r_fd| {
        if let Some(w) = extra_info_w {
            unsafe { close(w) };
        }
        let data = read_info_fd_data(r_fd);
        if data.is_empty() {
            0
        } else {
            write_bwrap_info(&cfg.app_id, &data);
            parse_child_pid_from_info(&data).unwrap_or(0)
        }
    });

    (child, runner_pid)
}

fn systemd_unescape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars().peekable();
    while let Some(ch) = chars.next() {
        if ch == '\\' && chars.peek() == Some(&'x') {
            chars.next();
            let h1 = chars.next();
            let h2 = chars.next();
            if let (Some(c1), Some(c2)) = (h1, h2) {
                let mut buf = [0u8; 2];
                buf[0] = c1 as u8;
                buf[1] = c2 as u8;
                if let Ok(hex_str) = std::str::from_utf8(&buf)
                    && let Ok(byte) = u8::from_str_radix(hex_str, 16)
                {
                    out.push(byte as char);
                    continue;
                }
                out.push('\\');
                out.push('x');
                out.push(c1);
                out.push(c2);
                continue;
            }
        }
        out.push(ch);
    }
    out
}

fn scope_matches_app(scope_str: &str, cfg: &SandboxConfig) -> bool {
    let unescaped = systemd_unescape(scope_str);
    unescaped.contains(&cfg.app_id)
}

fn ensure_app2unit_scope(cfg: &SandboxConfig) {
    if (cfg.flags & CFG_SCOPE) == 0 || cfg.app_id.is_empty() {
        return;
    }
    let Ok(cgroup_content) = fs::read_to_string("/proc/self/cgroup") else {
        return;
    };
    let line = cgroup_content.lines().next().unwrap_or("");
    let mut rel_path = line.strip_prefix("0::").unwrap_or(line).trim();
    while let Some(parent) = rel_path.strip_suffix("/helpers") {
        rel_path = parent;
    }
    while let Some(parent) = rel_path.strip_suffix("/inside") {
        rel_path = parent;
    }
    if scope_matches_app(rel_path, cfg) {
        return;
    }

    let args: Vec<String> = env::args().collect();
    let current_exe = env::current_exe().unwrap_or_else(|_| PathBuf::from(&args[0]));

    let Ok(c_app2unit) = CString::new("app2unit") else {
        return;
    };
    let Ok(c_a) = CString::new("-a") else {
        return;
    };
    let Ok(c_app_id) = CString::new(cfg.app_id.as_bytes()) else {
        return;
    };
    let Ok(c_dashdash) = CString::new("--") else {
        return;
    };
    let Ok(c_exe) = CString::new(current_exe.as_os_str().as_bytes()) else {
        return;
    };

    let mut c_args = vec![c_app2unit.clone(), c_a, c_app_id, c_dashdash, c_exe];
    for a in &args[1..] {
        if let Ok(ca) = CString::new(a.as_bytes()) {
            c_args.push(ca);
        }
    }
    let mut c_ptrs: Vec<*const i8> = c_args.iter().map(|cs| cs.as_ptr()).collect();
    c_ptrs.push(std::ptr::null());

    unsafe {
        execvp(c_app2unit.as_ptr(), c_ptrs.as_ptr());
    }
}

fn setup_cgroup_and_scope(cfg: &SandboxConfig) {
    if (cfg.flags & CFG_SCOPE) == 0 {
        return;
    }
    if env::var("MY_CGROUP").is_ok() && env::var("MY_SCOPE").is_ok() {
        return;
    }
    let Ok(cgroup_content) = fs::read_to_string("/proc/self/cgroup") else {
        return;
    };
    let line = cgroup_content.lines().next().unwrap_or("");
    let mut rel_path = line.strip_prefix("0::").unwrap_or(line).trim();
    if rel_path.is_empty() || rel_path == "/" {
        return;
    }
    while let Some(parent) = rel_path.strip_suffix("/helpers") {
        rel_path = parent;
    }
    while let Some(parent) = rel_path.strip_suffix("/inside") {
        rel_path = parent;
    }

    if !scope_matches_app(rel_path, cfg) {
        return;
    }

    let cgroup_path = PathBuf::from(format!("/sys/fs/cgroup{rel_path}"));
    let scope_name = cgroup_path
        .file_name()
        .and_then(|n| n.to_str())
        .map(String::from);

    let helpers_dir = cgroup_path.join("helpers");
    let inside_dir = cgroup_path.join("inside");
    let _ = fs::create_dir_all(&helpers_dir);
    let _ = fs::create_dir_all(&inside_dir);

    let root_procs = read_pids_from_file(&cgroup_path.join("cgroup.procs"));
    for p in root_procs {
        let _ = fs::write(helpers_dir.join("cgroup.procs"), format!("{p}\n"));
    }
    let pid = unsafe { getpid() };
    let _ = fs::write(helpers_dir.join("cgroup.procs"), format!("{pid}\n"));

    if let Some(parent) = cgroup_path.parent() {
        let _ = fs::write(
            parent.join("cgroup.subtree_control"),
            "+memory +pids +cpu +io\n",
        );
    }
    let _ = fs::write(
        cgroup_path.join("cgroup.subtree_control"),
        "+memory +pids +cpu +io\n",
    );

    unsafe {
        env::set_var("MY_CGROUP", &cgroup_path);
        if let Some(ref sc) = scope_name {
            env::set_var("MY_SCOPE", sc);
        }
    }
}

fn create_pasta_sync_pipes(network: &str) -> Option<([i32; 2], [i32; 2])> {
    if network == "sandboxed" {
        let mut block_fds = [0i32; 2];
        let mut info_fds = [0i32; 2];
        let _ = unsafe { pipe(block_fds.as_mut_ptr()) };
        let _ = unsafe { pipe(info_fds.as_mut_ptr()) };
        Some((block_fds, info_fds))
    } else {
        None
    }
}

fn create_extra_info_pipes() -> (Option<i32>, Option<i32>) {
    let mut fds = [0i32; 2];
    if unsafe { pipe(fds.as_mut_ptr()) } == 0 {
        (Some(fds[0]), Some(fds[1]))
    } else {
        (None, None)
    }
}

fn main() {
    let raw_args: Vec<String> = env::args().collect();
    if raw_args.len() > 1 {
        eprintln!("[sb-run] Flags: {}", raw_args[1..].join(" "));
    }

    let cfg = parse_cli_args();
    ensure_app2unit_scope(&cfg);
    setup_cgroup_and_scope(&cfg);
    let paths = prepare_sandbox_paths(&cfg);

    if let Some(exit_code) = try_connect_running_sandbox(&paths.ipc_sock, &cfg) {
        exit(exit_code);
    }

    let mut helpers = spawn_initial_helpers(&cfg, &paths.runtime);

    let migrator_sock = paths.runtime.join("migrator.sock");
    let _ = fs::remove_file(&migrator_sock);
    let migrator_listener = UnixListener::bind(&migrator_sock).ok();
    if let Some(ref l) = migrator_listener {
        let _ = l.set_nonblocking(true);
    }

    let auth_token = create_token_for_app(&cfg.app_id);
    let token_hex = bytes_to_hex(&auth_token);

    let pasta_sync_fds = create_pasta_sync_pipes(&cfg.network);
    let pasta_sync_pass = pasta_sync_fds.map(|([r_b, _], [_, w_i])| (r_b, w_i));

    let (extra_info_r, extra_info_w) = if pasta_sync_fds.is_none() {
        create_extra_info_pipes()
    } else {
        (None, None)
    };

    let (mut child, extra_runner_pid) = spawn_bwrap_and_get_runner(
        &cfg,
        &paths,
        &token_hex,
        pasta_sync_pass,
        extra_info_w,
        extra_info_r,
    );

    let (pasta_child, pasta_runner_pid) = handle_pasta_sync(pasta_sync_fds, &cfg);
    helpers.pasta = pasta_child;

    let runner_pid = if pasta_runner_pid > 0 {
        pasta_runner_pid
    } else {
        extra_runner_pid
    };

    if let Ok(mut pipe_file) = fs::File::open(&paths.ready_pipe) {
        let mut buf = [0u8; 16];
        let _ = pipe_file.read(&mut buf);
    }
    let _ = fs::remove_file(&paths.ready_pipe);

    if let Ok(cgroup) = env::var("MY_CGROUP")
        && runner_pid > 0
    {
        let helpers_procs = format!("{cgroup}/helpers/cgroup.procs");
        let _ = fs::write(helpers_procs, format!("{runner_pid}\n"));
    }

    let cgroup_opt = env::var("MY_CGROUP").ok().map(PathBuf::from);
    let bridge_pids = if cfg.bridges.is_empty() {
        Vec::new()
    } else {
        setup_bridges(
            &cfg,
            &paths.runtime,
            &paths.ipc_sock,
            cgroup_opt.as_deref(),
            runner_pid,
        )
    };

    if cfg.command.is_empty() {
        let status = child.wait().map_or(1, |s| s.code().unwrap_or(1));
        cleanup_session(&cfg, &paths, &bridge_pids, helpers);
        exit(status);
    }

    let _ = try_connect_running_sandbox(&paths.ipc_sock, &cfg);
    let inside_procs = env::var("MY_CGROUP")
        .ok()
        .map(|cg| PathBuf::from(format!("{cg}/inside/cgroup.procs")));
    if let Some(ref listener) = migrator_listener {
        let mut pfd = PollFd {
            fd: listener.as_raw_fd(),
            events: 1, // POLLIN
            revents: 0,
        };
        if unsafe { poll(&raw mut pfd, 1, 5000) } > 0 {
            handle_migration(listener, inside_procs.as_deref());
        }
    }

    if (cfg.flags & CFG_IS_CLI) != 0 {
        let _ = child.kill();
        let _ = child.wait();
        cleanup_session(&cfg, &paths, &bridge_pids, helpers);
        exit(0);
    }

    monitor_scope_and_cleanup(
        &cfg,
        &paths,
        &bridge_pids,
        helpers,
        &mut child,
        migrator_listener.as_ref(),
    );
    exit(0);
}

unsafe extern "C" {
    fn syscall(number: i64, ...) -> i64;
    fn getuid() -> u32;
    fn getgid() -> u32;
    fn getpid() -> i32;
    fn open(path: *const i8, flags: i32) -> i32;
    fn write(fd: i32, buf: *const c_void, count: usize) -> isize;
    fn close(fd: i32) -> i32;
    fn lseek(fd: i32, offset: i64, whence: i32) -> i64;
    fn read(fd: i32, buf: *mut c_void, count: usize) -> isize;
    fn pipe(pipefd: *mut i32) -> i32;
    fn poll(fds: *mut PollFd, nfds: usize, timeout: i32) -> i32;
    fn fcntl(fd: i32, cmd: i32, arg: i32) -> i32;
    fn inotify_init1(flags: i32) -> i32;
    fn inotify_add_watch(fd: i32, pathname: *const i8, mask: u32) -> i32;
    fn prctl(option: i32, arg2: u64, arg3: u64, arg4: u64, arg5: u64) -> i32;
    fn epoll_create1(flags: i32) -> i32;
    fn epoll_ctl(epfd: i32, op: i32, fd: i32, event: *mut EpollEvent) -> i32;
    fn epoll_wait(epfd: i32, events: *mut EpollEvent, maxevents: i32, timeout: i32) -> i32;
    fn execvp(file: *const i8, argv: *const *const i8) -> i32;
    fn getsockopt(
        sockfd: i32,
        level: i32,
        optname: i32,
        optval: *mut c_void,
        optlen: *mut u32,
    ) -> i32;
}

#[repr(C)]
struct PollFd {
    fd: i32,
    events: i16,
    revents: i16,
}

fn libc_getuid() -> u32 {
    unsafe { getuid() }
}

fn libc_getgid() -> u32 {
    unsafe { getgid() }
}
