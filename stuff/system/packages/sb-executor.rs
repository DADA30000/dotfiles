use std::env;
use std::ffi::{CString, c_void};
use std::fs;
use std::io::{Read, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::io::{AsRawFd, FromRawFd, OwnedFd, RawFd};
use std::os::unix::net::{UnixListener, UnixStream};
use std::process::{Command, exit};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

static ACTIVE_CHILDREN: AtomicUsize = AtomicUsize::new(0);
static HAS_LAUNCHED: AtomicBool = AtomicBool::new(false);
static HAS_PRINTED_STARTUP: AtomicBool = AtomicBool::new(false);

const IPC_MAGIC: [u8; 4] = *b"SBEX";
const IPC_VERSION: u16 = 1;

const MSG_EXEC_REQUEST: u16 = 1;
const MSG_WINSIZE: u16 = 2;
const MSG_SIGNAL: u16 = 3;
const MSG_EXIT_RESPONSE: u16 = 4;

const FLAG_WAIT_EXIT: u32 = 1 << 0;

const SOL_SOCKET: i32 = 1;
const SCM_RIGHTS: i32 = 1;
const SIGTERM: i32 = 15;

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
#[derive(Clone, Copy, Debug)]
struct WinSizePayload {
    row: u16,
    col: u16,
    xpixel: u16,
    ypixel: u16,
}

#[repr(C)]
struct PollFd {
    fd: RawFd,
    events: i16,
    revents: i16,
}

const POLLIN: i16 = 0x0001;
const POLLHUP: i16 = 0x0010;
const POLLERR: i16 = 0x0008;

const WNOHANG: i32 = 1;
const TIOCSWINSZ: usize = 0x5414;

const SYS_LANDLOCK_CREATE_RULESET: i64 = 444;
const SYS_LANDLOCK_RESTRICT_SELF: i64 = 446;
const LANDLOCK_SCOPE_SIGNAL: u64 = 1 << 0;
const LANDLOCK_SCOPE_ABSTRACT_UNIX_SOCKET: u64 = 1 << 1;
const PR_SET_NO_NEW_PRIVS: i32 = 38;

#[repr(C)]
struct LandlockRulesetAttr {
    handled_access_fs: u64,
    handled_access_net: u64,
    scoped: u64,
}

fn apply_landlock() {
    let mut attr = LandlockRulesetAttr {
        handled_access_fs: 0,
        handled_access_net: 0,
        scoped: LANDLOCK_SCOPE_SIGNAL | LANDLOCK_SCOPE_ABSTRACT_UNIX_SOCKET,
    };
    unsafe {
        let mut fd = syscall(
            SYS_LANDLOCK_CREATE_RULESET,
            (&raw const attr as usize).cast_signed(),
            size_of::<LandlockRulesetAttr>(),
            0,
        );
        if fd < 0 {
            attr.scoped = LANDLOCK_SCOPE_SIGNAL;
            fd = syscall(
                SYS_LANDLOCK_CREATE_RULESET,
                (&raw const attr as usize).cast_signed(),
                size_of::<LandlockRulesetAttr>(),
                0,
            );
        }
        if fd >= 0
            && let Ok(fd_i32) = i32::try_from(fd)
        {
            let _ = prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0);
            let _ = syscall(SYS_LANDLOCK_RESTRICT_SELF, fd, 0);
            close(fd_i32);
        }
    }
}

unsafe extern "C" {
    fn syscall(number: i64, ...) -> i64;
    fn prctl(option: i32, arg2: usize, arg3: usize, arg4: usize, arg5: usize) -> i32;
    fn close(fd: i32) -> i32;
    fn fork() -> i32;
    fn execvp(file: *const i8, argv: *const *const i8) -> i32;
    fn waitpid(pid: i32, status: *mut i32, options: i32) -> i32;
    fn dup2(oldfd: i32, newfd: i32) -> i32;
    fn chdir(path: *const i8) -> i32;
    fn setenv(name: *const i8, val: *const i8, overwrite: i32) -> i32;
    fn setsid() -> i32;
    fn kill(pid: i32, sig: i32) -> i32;
    fn ioctl(fd: i32, request: usize, ...) -> i32;
    fn poll(fds: *mut PollFd, nfds: usize, timeout: i32) -> i32;
    fn recvmsg(sockfd: i32, msg: *mut LibcMsghdr, flags: i32) -> isize;
    fn unshare(flags: i32) -> i32;
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

#[repr(C, align(8))]
struct CmsgBuffer([u8; 128]);

fn recv_header_with_fds(sock: &UnixStream) -> std::io::Result<(IpcHeader, Vec<OwnedFd>)> {
    let mut header_buf = [0u8; size_of::<IpcHeader>()];
    let mut iov = LibcIovec {
        iov_base: header_buf.as_mut_ptr().cast(),
        iov_len: header_buf.len(),
    };

    let mut cmsg_buf = CmsgBuffer([0u8; 128]);
    let mut msg = LibcMsghdr {
        name: std::ptr::null_mut(),
        namelen: 0,
        _pad1: 0,
        iov: &raw mut iov,
        iovlen: 1,
        control: cmsg_buf.0.as_mut_ptr().cast(),
        controllen: cmsg_buf.0.len(),
        flags: 0,
        _pad2: 0,
    };

    let n = unsafe { recvmsg(sock.as_raw_fd(), &raw mut msg, 0) };
    if n < 0 {
        return Err(std::io::Error::last_os_error());
    }

    let Ok(recvd_len) = usize::try_from(n) else {
        return Err(std::io::Error::new(
            std::io::ErrorKind::UnexpectedEof,
            "negative read size",
        ));
    };
    if recvd_len < size_of::<IpcHeader>() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::UnexpectedEof,
            "incomplete header",
        ));
    }

    let Some(header) = IpcHeader::from_bytes(&header_buf) else {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "invalid header magic or version",
        ));
    };

    let mut received_fds = Vec::new();
    if msg.controllen >= size_of::<LibcCmsghdr>() {
        let cmsghdr_ptr = msg.control.cast::<LibcCmsghdr>();
        unsafe {
            if !cmsghdr_ptr.is_null()
                && (*cmsghdr_ptr).len >= size_of::<LibcCmsghdr>()
                && (*cmsghdr_ptr).len <= msg.controllen
                && (*cmsghdr_ptr).level == SOL_SOCKET
                && (*cmsghdr_ptr).type_ == SCM_RIGHTS
            {
                let data_ptr = cmsghdr_ptr.add(1).cast::<i32>();
                let data_len = (*cmsghdr_ptr).len - size_of::<LibcCmsghdr>();
                let fd_count = (data_len / size_of::<i32>()).min(16);
                for i in 0..fd_count {
                    let fd = *data_ptr.add(i);
                    if fd >= 0 {
                        received_fds.push(OwnedFd::from_raw_fd(fd));
                    }
                }
            }
        }
    }

    Ok((header, received_fds))
}

struct ExecPayload {
    cwd: String,
    args: Vec<String>,
    env: Vec<String>,
}

fn parse_exec_payload(buf: &[u8]) -> Option<ExecPayload> {
    let mut cursor = 0;
    let read_u32 = |c: &mut usize| -> Option<u32> {
        if *c + 4 > buf.len() {
            return None;
        }
        let val = u32::from_le_bytes(buf[*c..*c + 4].try_into().ok()?);
        *c += 4;
        Some(val)
    };

    let read_string = |c: &mut usize| -> Option<String> {
        let len = usize::try_from(read_u32(c)?).ok()?;
        if *c + len > buf.len() {
            return None;
        }
        let s = String::from_utf8(buf[*c..*c + len].to_vec()).ok()?;
        *c += len;
        Some(s)
    };

    let cwd = read_string(&mut cursor)?;
    let arg_count = usize::try_from(read_u32(&mut cursor)?).ok()?;
    if arg_count > 65536 {
        return None;
    }
    let mut args = Vec::with_capacity(arg_count);
    for _ in 0..arg_count {
        args.push(read_string(&mut cursor)?);
    }

    let env_count = usize::try_from(read_u32(&mut cursor)?).ok()?;
    if env_count > 65536 {
        return None;
    }
    let mut env = Vec::with_capacity(env_count);
    for _ in 0..env_count {
        env.push(read_string(&mut cursor)?);
    }

    Some(ExecPayload { cwd, args, env })
}

fn run_child_process(
    payload: &ExecPayload,
    fds: &[OwnedFd],
    is_cli: bool,
    use_landlock: bool,
) -> ! {
    if fds.len() >= 3 {
        unsafe {
            dup2(fds[0].as_raw_fd(), 0);
            dup2(fds[1].as_raw_fd(), 1);
            dup2(fds[2].as_raw_fd(), 2);
        }
    }

    if !is_cli {
        unsafe { setsid() };
    }

    if let Ok(c_cwd) = CString::new(payload.cwd.as_bytes()) {
        unsafe { chdir(c_cwd.as_ptr()) };
    }

    for item in &payload.env {
        if let Some((k, v)) = item.split_once('=')
            && let (Ok(ck), Ok(cv)) = (CString::new(k), CString::new(v))
        {
            unsafe { setenv(ck.as_ptr(), cv.as_ptr(), 1) };
        }
    }

    let Ok(c_argv) = payload
        .args
        .iter()
        .map(|arg| CString::new(arg.as_bytes()))
        .collect::<Result<Vec<CString>, _>>()
    else {
        eprintln!("[sb-executor] Argument contains invalid null byte");
        exit(1);
    };
    let mut c_ptrs: Vec<*const i8> = c_argv.iter().map(|cs| cs.as_ptr()).collect();
    c_ptrs.push(std::ptr::null());

    if use_landlock {
        apply_landlock();
    }

    if let Some(first) = c_argv.first() {
        unsafe {
            execvp(first.as_ptr(), c_ptrs.as_ptr());
        }
    }

    let cmd_name = payload.args.first().map_or("unknown", |s| s.as_str());
    eprintln!(
        "[sb-executor] execvp failed for '{cmd_name}': {}",
        std::io::Error::last_os_error()
    );
    exit(127);
}

fn monitor_cli_child(mut stream: UnixStream, child_pid: i32) {
    let mut status: i32 = 0;
    let stream_fd = stream.as_raw_fd();

    loop {
        let mut poll_fds = [PollFd {
            fd: stream_fd,
            events: POLLIN | POLLHUP | POLLERR,
            revents: 0,
        }];

        let n = unsafe { poll(poll_fds.as_mut_ptr(), 1, 100) };

        let res = unsafe { waitpid(child_pid, &raw mut status, WNOHANG) };
        if res == child_pid {
            let Ok(len_u32) = u32::try_from(size_of::<i32>()) else {
                break;
            };
            let resp_header = IpcHeader::new(MSG_EXIT_RESPONSE, len_u32, 0);
            let _ = stream.write_all(&resp_header.to_bytes());
            let _ = stream.write_all(&status.to_le_bytes());
            let _ = stream.flush();
            break;
        }
        if res < 0 {
            break;
        }

        if n > 0 {
            let rev = poll_fds[0].revents;
            if (rev & POLLIN) != 0 {
                let mut ctl_buf = [0u8; size_of::<IpcHeader>()];
                if stream.read_exact(&mut ctl_buf).is_ok()
                    && let Some(ctl_hdr) = IpcHeader::from_bytes(&ctl_buf)
                {
                    match ctl_hdr.msg_type {
                        MSG_SIGNAL => {
                            let mut sig_bytes = [0u8; 4];
                            if stream.read_exact(&mut sig_bytes).is_ok() {
                                let sig = i32::from_le_bytes(sig_bytes);
                                unsafe {
                                    kill(-child_pid, sig);
                                    kill(child_pid, sig);
                                };
                            }
                        }
                        MSG_WINSIZE => {
                            let mut ws_bytes = [0u8; size_of::<WinSizePayload>()];
                            if stream.read_exact(&mut ws_bytes).is_ok() {
                                unsafe { ioctl(0, TIOCSWINSZ, ws_bytes.as_ptr().cast::<c_void>()) };
                            }
                        }
                        _ => {}
                    }
                }
            }
            if (rev & (POLLHUP | POLLERR)) != 0 {
                unsafe { kill(child_pid, SIGTERM) };
                let _ = unsafe { waitpid(child_pid, &raw mut status, 0) };
                break;
            }
        }
    }
}

fn handle_connection(
    mut stream: UnixStream,
    use_landlock: bool,
    listener_fd: RawFd,
    auth_token: Option<[u8; 16]>,
) {
    let (header, fds) = match recv_header_with_fds(&stream) {
        Ok(res) => res,
        Err(err) => {
            eprintln!("[sb-executor] Failed to receive header: {err}");
            return;
        }
    };

    if let Some(expected) = auth_token
        && header.extra != expected
    {
        eprintln!("[sb-executor] Rejected connection: invalid auth token");
        return;
    }

    if header.msg_type != MSG_EXEC_REQUEST {
        eprintln!(
            "[sb-executor] Expected EXEC_REQUEST, got {}",
            header.msg_type
        );
        return;
    }

    let Ok(payload_len) = usize::try_from(header.payload_len) else {
        return;
    };
    if payload_len > 16 * 1024 * 1024 {
        eprintln!("[sb-executor] Rejected oversized payload: {payload_len} bytes");
        return;
    }

    let mut payload_buf = vec![0u8; payload_len];
    if let Err(err) = stream.read_exact(&mut payload_buf) {
        eprintln!("[sb-executor] Failed to read payload: {err}");
        return;
    }

    let Some(payload) = parse_exec_payload(&payload_buf) else {
        eprintln!("[sb-executor] Malformed payload");
        return;
    };

    if payload.args.is_empty() {
        eprintln!("[sb-executor] Empty argv");
        return;
    }

    let is_cli = (header.flags & FLAG_WAIT_EXIT) != 0;

    ACTIVE_CHILDREN.fetch_add(1, Ordering::Release);
    HAS_LAUNCHED.store(true, Ordering::Release);

    let child_pid = unsafe { fork() };
    if child_pid < 0 {
        eprintln!(
            "[sb-executor] fork failed: {}",
            std::io::Error::last_os_error()
        );
        ACTIVE_CHILDREN.fetch_sub(1, Ordering::Release);
        return;
    }

    if child_pid == 0 {
        unsafe { close(listener_fd) };
        drop(stream);
        run_child_process(&payload, &fds, is_cli, use_landlock);
    }

    drop(fds);

    if !HAS_PRINTED_STARTUP.swap(true, Ordering::AcqRel)
        && let Some(item) = payload.env.iter().find(|e| e.starts_with("START_TIME="))
        && let Some((_, start_str)) = item.split_once('=')
        && let Ok(start_ns) = start_str.trim().parse::<u128>()
    {
        let now_ns = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_nanos());
        if now_ns >= start_ns {
            let elapsed_ms = (now_ns - start_ns) / 1_000_000;
            let app_id = payload
                .env
                .iter()
                .find(|e| e.starts_with("APP_ID="))
                .and_then(|e| e.split_once('='))
                .map_or("sandbox", |(_, id)| id);
            println!("[{app_id}] Startup: {elapsed_ms} ms");
        }
    }

    if is_cli {
        monitor_cli_child(stream, child_pid);
        ACTIVE_CHILDREN.fetch_sub(1, Ordering::Release);
    } else {
        std::thread::spawn(move || {
            let mut status: i32 = 0;
            let _ = unsafe { waitpid(child_pid, &raw mut status, 0) };
            ACTIVE_CHILDREN.fetch_sub(1, Ordering::Release);
        });
    }
}

fn signal_pipe(pipe_path: &str, msg: &str) {
    if let Ok(mut f) = fs::OpenOptions::new().write(true).open(pipe_path) {
        let _ = f.write_all(msg.as_bytes());
        let _ = f.flush();
    }
}

fn start_singbox_services(bin_path: &str, config_path: &str, sock_path: &str) {
    if !sock_path.is_empty()
        && let Err(err) = Command::new("rust-bridge")
            .args([
                "-r",
                "listen",
                "-s",
                sock_path,
                "--address",
                "127.0.0.1:[1919,2121]",
                "-d",
            ])
            .spawn()
    {
        eprintln!("[sb-executor] Failed to spawn rust-bridge: {err}");
    }

    let mut sb_cmd = Command::new(bin_path);
    sb_cmd.arg("run").arg("-c").arg(config_path);
    sb_cmd.env("GOMAXPROCS", "1");
    sb_cmd.env("GOMEMLIMIT", "16MiB");
    sb_cmd.env("GOGC", "15");
    sb_cmd.env("GODEBUG", "madvdontneed=1");
    if let Err(err) = sb_cmd.spawn() {
        eprintln!("[sb-executor] Failed to spawn sing-box: {err}");
    }
}

fn enter_user_namespace(user_id: u32, group_id: u32) {
    const CLONE_NEWUSER: i32 = 0x1000_0000;
    if user_id == 0 {
        return;
    }
    unsafe {
        if unshare(CLONE_NEWUSER) != 0 {
            eprintln!(
                "[sb-executor] Failed to unshare user namespace: {}",
                std::io::Error::last_os_error()
            );
            exit(1);
        }
    }

    if let Err(err) = fs::write("/proc/self/setgroups", "deny\n") {
        eprintln!("[sb-executor] Failed to write setgroups: {err}");
        exit(1);
    }
    if let Err(err) = fs::write("/proc/self/gid_map", format!("{group_id} 0 1\n")) {
        eprintln!("[sb-executor] Failed to write gid_map: {err}");
        exit(1);
    }
    if let Err(err) = fs::write("/proc/self/uid_map", format!("{user_id} 0 1\n")) {
        eprintln!("[sb-executor] Failed to write uid_map: {err}");
        exit(1);
    }
}

fn hex_to_16_bytes(hex: &str) -> Result<[u8; 16], ()> {
    if hex.len() != 32 {
        return Err(());
    }
    let mut bytes = [0u8; 16];
    for (i, byte) in bytes.iter_mut().enumerate() {
        *byte = u8::from_str_radix(&hex[i * 2..i * 2 + 2], 16).map_err(|_| ())?;
    }
    Ok(bytes)
}

struct ExecutorCli {
    socket_path: String,
    ready_pipe: String,
    use_landlock: bool,
    auth_token: Option<[u8; 16]>,
    singbox_bin: String,
    singbox_config: String,
    singbox_sock: String,
    x11_mode: String,
    xwayland_bin: String,
    user_id: u32,
    group_id: u32,
}

fn parse_executor_cli() -> ExecutorCli {
    let args: Vec<String> = env::args().collect();
    let mut socket_path = String::new();
    let mut ready_pipe = String::new();
    let mut use_landlock = true;
    let mut auth_token = None;
    let mut singbox_bin = String::new();
    let mut singbox_config = String::new();
    let mut singbox_sock = String::new();
    let mut x11_mode = String::new();
    let mut xwayland_bin = String::new();
    let mut user_id = 0u32;
    let mut group_id = 0u32;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--no-landlock" => {
                use_landlock = false;
                i += 1;
            }
            "--socket" if i + 1 < args.len() => {
                socket_path.clone_from(&args[i + 1]);
                i += 2;
            }
            "--ready-pipe" if i + 1 < args.len() => {
                ready_pipe.clone_from(&args[i + 1]);
                i += 2;
            }
            "--token" if i + 1 < args.len() => {
                if let Ok(bytes) = hex_to_16_bytes(&args[i + 1]) {
                    auth_token = Some(bytes);
                }
                i += 2;
            }
            "--singbox-bin" if i + 1 < args.len() => {
                singbox_bin.clone_from(&args[i + 1]);
                i += 2;
            }
            "--singbox-config" if i + 1 < args.len() => {
                singbox_config.clone_from(&args[i + 1]);
                i += 2;
            }
            "--singbox-sock" if i + 1 < args.len() => {
                singbox_sock.clone_from(&args[i + 1]);
                i += 2;
            }
            "--x11-mode" if i + 1 < args.len() => {
                x11_mode.clone_from(&args[i + 1]);
                i += 2;
            }
            "--xwayland-bin" if i + 1 < args.len() => {
                xwayland_bin.clone_from(&args[i + 1]);
                i += 2;
            }
            "--orig-uid" if i + 1 < args.len() => {
                user_id = args[i + 1].parse().unwrap_or(0);
                i += 2;
            }
            "--orig-gid" if i + 1 < args.len() => {
                group_id = args[i + 1].parse().unwrap_or(0);
                i += 2;
            }
            _ => i += 1,
        }
    }

    if socket_path.is_empty() {
        socket_path = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into()) + "/ipc.sock";
    }

    ExecutorCli {
        socket_path,
        ready_pipe,
        use_landlock,
        auth_token,
        singbox_bin,
        singbox_config,
        singbox_sock,
        x11_mode,
        xwayland_bin,
        user_id,
        group_id,
    }
}

fn main() {
    let cli = parse_executor_cli();

    if !cli.singbox_bin.is_empty() && !cli.singbox_config.is_empty() {
        start_singbox_services(&cli.singbox_bin, &cli.singbox_config, &cli.singbox_sock);
    }

    if cli.x11_mode == "sandboxed" {
        let x_bin = if cli.xwayland_bin.is_empty() {
            "xwayland-satellite"
        } else {
            &cli.xwayland_bin
        };
        let _ = Command::new(x_bin).args(["-nolisten", "local"]).spawn();
    }

    enter_user_namespace(cli.user_id, cli.group_id);

    let _ = fs::remove_file(&cli.socket_path);
    let listener = match UnixListener::bind(&cli.socket_path) {
        Ok(l) => l,
        Err(err) => {
            eprintln!(
                "[sb-executor] Failed to bind Unix socket '{}': {err}",
                cli.socket_path
            );
            exit(1);
        }
    };

    let listener_fd = listener.as_raw_fd();
    let _ = fs::set_permissions(&cli.socket_path, fs::Permissions::from_mode(0o600));

    // Notify host runner that socket is listening and ready
    if !cli.ready_pipe.is_empty() {
        signal_pipe(&cli.ready_pipe, "ready\n");
    }

    let _ = listener.set_nonblocking(true);
    let mut poll_fds = [PollFd {
        fd: listener_fd,
        events: POLLIN,
        revents: 0,
    }];

    loop {
        let res = unsafe { poll(poll_fds.as_mut_ptr(), 1, 500) };
        if res > 0 && (poll_fds[0].revents & POLLIN) != 0 {
            match listener.accept() {
                Ok((s, _)) => {
                    let auth_token = cli.auth_token;
                    let landlock = cli.use_landlock;
                    std::thread::spawn(move || {
                        handle_connection(s, landlock, listener_fd, auth_token);
                    });
                }
                Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {}
                Err(err) => {
                    eprintln!("[sb-executor] Error accepting connection: {err}");
                }
            }
        }

        if HAS_LAUNCHED.load(Ordering::Acquire) && ACTIVE_CHILDREN.load(Ordering::Acquire) == 0 {
            break;
        }
    }
}
