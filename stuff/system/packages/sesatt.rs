use std::collections::BTreeMap;
use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::net::Shutdown;
use std::os::unix::net::{UnixListener, UnixStream};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

type CInt = i32;
type CLong = i64;
type CChar = i8;
type CVoid = std::ffi::c_void;

#[repr(C)]
#[derive(Copy, Clone)]
struct Termios {
    c_iflag: u32,
    c_oflag: u32,
    c_cflag: u32,
    c_lflag: u32,
    c_line: u8,
    c_cc: [u8; 32],
    c_ispeed: u32,
    c_ospeed: u32,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq)]
struct Winsize {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
}

#[link(name = "util")]
extern "C" {
    fn openpty(
        amaster: *mut CInt,
        aslave: *mut CInt,
        name: *mut CChar,
        termp: *const CVoid,
        winp: *const Winsize,
    ) -> CInt;
    fn login_tty(fd: CInt) -> CInt;
    fn fork() -> CInt;
    fn setsid() -> CInt;
    fn getpid() -> CInt;
    fn tcsetpgrp(fd: CInt, pgrp: CInt) -> CInt;
    fn _exit(status: CInt) -> !;
    fn read(fd: CInt, buf: *mut CVoid, count: usize) -> isize;
    fn write(fd: CInt, buf: *const CVoid, count: usize) -> isize;
    fn close(fd: CInt) -> CInt;
    fn tcgetattr(fd: CInt, termios_p: *mut Termios) -> CInt;
    fn tcsetattr(fd: CInt, optional_actions: CInt, termios_p: *const Termios) -> CInt;
    fn cfmakeraw(termios_p: *mut Termios);
    fn ioctl(fd: CInt, request: CLong, ...) -> CInt;
    fn signal(sig: CInt, handler: usize) -> CVoid;
    fn open(path: *const CChar, flags: CInt) -> CInt;
    fn dup2(oldfd: CInt, newfd: CInt) -> CInt;
}

const TCSANOW: CInt = 0;
const TIOCGWINSZ: CLong = 0x5413;
const TIOCSWINSZ: CLong = 0x5414;
const SIGHUP: CInt = 1;
const SIGWINCH: CInt = 28;
const SIG_IGN: usize = 1;
const O_RDWR: CInt = 2;

static WINCH_RECEIVED: AtomicBool = AtomicBool::new(false);

extern "C" fn sigwinch_handler(_: CInt) {
    WINCH_RECEIVED.store(true, Ordering::SeqCst);
}

fn ffi_get_terminal_size() -> io::Result<Winsize> {
    let mut ws: Winsize = unsafe { std::mem::zeroed() };
    let res = unsafe { ioctl(0, TIOCGWINSZ, &mut ws) };
    if res == 0 && ws.ws_col > 0 && ws.ws_row > 0 {
        Ok(ws)
    } else {
        Err(io::Error::new(
            io::ErrorKind::Other,
            "Failed to query terminal dimensions",
        ))
    }
}

fn ffi_set_raw_mode() -> io::Result<Termios> {
    let mut orig: Termios = unsafe { std::mem::zeroed() };
    if unsafe { tcgetattr(0, &mut orig) } != 0 {
        return Err(io::Error::last_os_error());
    }
    let mut raw = orig;
    unsafe { cfmakeraw(&mut raw) };
    if unsafe { tcsetattr(0, TCSANOW, &raw) } != 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(orig)
}

fn ffi_reset_mode(orig: &Termios) {
    unsafe {
        tcsetattr(0, TCSANOW, orig);
    }
}

fn ffi_daemonize_server() {
    unsafe {
        setsid();
        signal(SIGHUP, SIG_IGN);
        let devnull = open(b"/dev/null\0".as_ptr() as *const CChar, O_RDWR);
        if devnull >= 0 {
            dup2(devnull, 0);
            dup2(devnull, 1);
            dup2(devnull, 2);
            if devnull > 2 {
                close(devnull);
            }
        }
    }
}

fn get_sesatt_dir() -> PathBuf {
    let xdg = match env::var("XDG_RUNTIME_DIR") {
        Ok(val) if !val.is_empty() => PathBuf::from(val),
        _ => {
            eprintln!("Error: 'XDG_RUNTIME_DIR' environment variable is not set.");
            std::process::exit(1);
        }
    };

    let dir = xdg.join("sesatt");
    if let Err(e) = fs::create_dir_all(&dir) {
        eprintln!(
            "Error: Failed to create sesatt runtime directory '{:?}': {}",
            dir, e
        );
        std::process::exit(1);
    }
    dir
}

fn validate_session_name(session: &str) {
    if session.is_empty()
        || session.contains('/')
        || session.contains('\\')
        || session.contains("..")
        || session.contains('*')
        || session.contains('?')
        || session.contains('[')
        || session.contains(']')
        || session.contains(' ')
    {
        eprintln!("Error: Invalid session name. Avoid spaces and special characters.");
        std::process::exit(1);
    }
}

fn get_session_dir(session: &str) -> PathBuf {
    get_sesatt_dir().join(session)
}

fn get_sock_path(session: &str) -> PathBuf {
    get_session_dir(session).join("sesatt.sock")
}

fn get_log_path(session: &str) -> PathBuf {
    get_session_dir(session).join("sesatt.log")
}

fn connect_with_retry(sock_path: &Path, retries: u32, delay: Duration) -> io::Result<UnixStream> {
    for _ in 0..retries {
        if let Ok(stream) = UnixStream::connect(sock_path) {
            return Ok(stream);
        }
        thread::sleep(delay);
    }
    UnixStream::connect(sock_path)
}

fn has_active_scope(session: &str) -> bool {
    let pattern1 = format!("app-sesatt-{}-*.scope", session);
    let pattern2 = format!("app-*sesatt*{}-*.scope", session);

    if let Ok(output) = Command::new("systemctl")
        .args([
            "--user",
            "list-units",
            "--plain",
            "--no-legend",
            "--state=active",
            &pattern1,
            &pattern2,
        ])
        .output()
    {
        !output.stdout.is_empty()
    } else {
        false
    }
}

fn main() -> io::Result<()> {
    let args: Vec<String> = env::args().collect();

    // Internal daemon launcher
    if args.len() >= 4 && args[1] == "--daemon" {
        let session = &args[2];
        validate_session_name(session);
        let cmd_args = args[3..].to_vec();
        let sock_path = get_sock_path(session);
        let log_path = get_log_path(session);
        let ws = ffi_get_terminal_size().unwrap_or(Winsize {
            ws_row: 24,
            ws_col: 80,
            ws_xpixel: 0,
            ws_ypixel: 0,
        });
        run_daemon_server(session, sock_path, log_path, cmd_args, ws);
        return Ok(());
    }

    // Query active NVIM socket from sesatt daemon
    if args.len() >= 3 && args[1] == "--get-nvim" {
        let session = &args[2];
        validate_session_name(session);
        let sock_path = get_sock_path(session);
        if let Ok(mut stream) = UnixStream::connect(&sock_path) {
            let _ = stream.write_all(&[0x03]);
            let mut buf = Vec::new();
            let _ = (&mut stream).take(4096).read_to_end(&mut buf);
            if !buf.is_empty() {
                let nvim_str = String::from_utf8_lossy(&buf);
                print!("{}", nvim_str);
            }
        }
        return Ok(());
    }

    // Helper editor launcher for git/SUDO_EDITOR/VISUAL
    if args.len() >= 1
        && (args[0].ends_with("sesatt-editor") || (args.len() >= 2 && args[1] == "--editor"))
    {
        let editor_args: Vec<String> = if args.len() >= 2 && args[1] == "--editor" {
            args[2..].to_vec()
        } else {
            args[1..].to_vec()
        };

        let target_nvim = if env::var("INSIDE_SESATT").as_deref() == Ok("1") {
            if let Ok(session) = env::var("SESATT_SESSION") {
                validate_session_name(&session);
                let sock_path = get_sock_path(&session);
                if let Ok(mut stream) = UnixStream::connect(&sock_path) {
                    let _ = stream.write_all(&[0x03]);
                    let mut buf = Vec::new();
                    let _ = (&mut stream).take(4096).read_to_end(&mut buf);
                    if !buf.is_empty() {
                        String::from_utf8_lossy(&buf).to_string()
                    } else {
                        env::var("NVIM").unwrap_or_default()
                    }
                } else {
                    env::var("NVIM").unwrap_or_default()
                }
            } else {
                env::var("NVIM").unwrap_or_default()
            }
        } else {
            env::var("NVIM").unwrap_or_default()
        };

        if !target_nvim.is_empty() {
            let mut cmd = Command::new("nvr");
            cmd.arg("--servername").arg(&target_nvim);
            cmd.arg("--remote-tab-wait");
            cmd.arg("+setlocal bufhidden=wipe");
            for a in editor_args {
                cmd.arg(a);
            }
            let err = cmd.exec();
            eprintln!("Error launching nvr: {}", err);
            std::process::exit(1);
        } else {
            let mut cmd = Command::new("nvim");
            for a in editor_args {
                cmd.arg(a);
            }
            let err = cmd.exec();
            eprintln!("Error launching nvim: {}", err);
            std::process::exit(1);
        }
    }

    if args.len() < 2 {
        print_help();
        return Ok(());
    }

    match args[1].as_str() {
        "-h" | "--help" => {
            print_help();
            return Ok(());
        }
        "-l" | "--list" => {
            list_sessions();
            return Ok(());
        }
        "-c" | "--clean" | "--prune" => {
            clean_dead_sessions();
            return Ok(());
        }
        "-k" | "--kill" => {
            if args.len() < 3 {
                eprintln!("Error: Missing session name to kill.");
                std::process::exit(1);
            }
            kill_session(&args[2]);
            return Ok(());
        }
        _ => {}
    }

    let mut detach_mode = false;
    let mut session_idx = 1;

    if args[1] == "-d" || args[1] == "--detach" {
        detach_mode = true;
        session_idx = 2;
        if args.len() <= session_idx {
            eprintln!("Error: Missing session name after {}.", args[1]);
            std::process::exit(1);
        }
    }

    let session = &args[session_idx];
    validate_session_name(session);

    let sock_path = get_sock_path(session);
    let log_path = get_log_path(session);

    if sock_path.exists() {
        if UnixStream::connect(&sock_path).is_ok() {
            if detach_mode {
                println!("Session '{}' already exists and is active.", session);
                return Ok(());
            }
            return attach_session(&sock_path, &log_path);
        } else {
            let _ = fs::remove_file(&sock_path);
        }
    }

    if log_path.exists() && args.len() == session_idx + 1 && !detach_mode {
        dump_scrollback(&log_path)?;
        println!("\n--- Process finished. Log preserved above. ---");
        return Ok(());
    }

    let cmd_args = if args.len() > session_idx + 1 {
        args[session_idx + 1..].to_vec()
    } else {
        match env::var("SHELL") {
            Ok(s) if !s.is_empty() => vec![s],
            _ => {
                eprintln!("Error: 'SHELL' environment variable is not set.");
                std::process::exit(1);
            }
        }
    };

    spawn_daemon(session, &cmd_args)?;

    if detach_mode {
        println!("Started session '{}' in detached mode.", session);
        return Ok(());
    }

    attach_session(&sock_path, &log_path)
}

fn print_help() {
    println!("sesatt - Lightweight native-scroll background session manager\n");
    println!("USAGE:");
    println!("  sesatt [OPTION] <SESSION_NAME> [COMMAND...]");
    println!("  sesatt [OPTION]\n");
    println!("ARGUMENTS:");
    println!("  <SESSION_NAME>       Name of the session to create or attach to");
    println!("  [COMMAND...]         Command to execute in a new session (defaults to $SHELL)\n");
    println!("OPTIONS:");
    println!("  -d, --detach         Start session in detached mode (do not attach)");
    println!("  -l, --list           List all background sessions (active and dead)");
    println!("  -c, --clean          Remove log and socket files for all dead sessions");
    println!("  -k, --kill <SESSION> Terminate specified session and its systemd scope");
    println!("  -h, --help           Print help information\n");
    println!("DETACH KEY:");
    println!(
        "  Ctrl + \\             Detach from session (leaves command running in background)\n"
    );
}

fn get_all_sessions() -> Vec<(String, bool)> {
    let dir = get_sesatt_dir();
    let mut sessions_map = BTreeMap::new();

    if let Ok(entries) = fs::read_dir(&dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                if let Some(name) = path.file_name().and_then(|s| s.to_str()) {
                    let sock_path = path.join("sesatt.sock");
                    let is_active = sock_path.exists() && UnixStream::connect(&sock_path).is_ok();
                    sessions_map.insert(name.to_string(), is_active);
                }
            }
        }
    }

    sessions_map.into_iter().collect()
}

fn list_sessions() {
    let sessions = get_all_sessions();
    if sessions.is_empty() {
        println!("No sesatt sessions found.");
        return;
    }

    for (name, is_active) in sessions {
        if is_active {
            println!("• {} (active)", name);
        } else {
            println!("• {} (dead)", name);
        }
    }
}

fn clean_dead_sessions() {
    let sessions = get_all_sessions();
    let mut cleaned_count = 0;

    for (name, is_active) in sessions {
        if !is_active {
            let session_dir = get_session_dir(&name);
            let _ = fs::remove_dir_all(&session_dir);
            println!("Cleaned dead session '{}'.", name);
            cleaned_count += 1;
        }
    }

    if cleaned_count == 0 {
        println!("No dead sessions found to clean.");
    }
}

fn kill_session(session: &str) {
    validate_session_name(session);
    let session_dir = get_session_dir(session);

    let dir_exists = session_dir.exists();
    let scope_active = has_active_scope(session);

    if !dir_exists && !scope_active {
        eprintln!("Error: Session '{}' does not exist.", session);
        std::process::exit(1);
    }

    let pattern1 = format!("app-sesatt-{}-*.scope", session);
    let pattern2 = format!("app-*sesatt*{}-*.scope", session);

    let _ = Command::new("systemctl")
        .args(["--user", "stop", &pattern1, &pattern2])
        .stderr(Stdio::null())
        .status();

    let _ = fs::remove_dir_all(&session_dir);
    println!("Session '{}' terminated.", session);
}

fn send_resize_pkt(stream: &mut UnixStream, ws: &Winsize) -> io::Result<()> {
    let ws_bytes: [u8; 8] = unsafe { std::mem::transmute(*ws) };
    let mut pkt = Vec::with_capacity(9);
    pkt.push(0x01);
    pkt.extend_from_slice(&ws_bytes);
    stream.write_all(&pkt)
}

fn send_nvim_pkt(stream: &mut UnixStream) -> io::Result<()> {
    if let Ok(nvim) = env::var("NVIM") {
        if !nvim.is_empty() {
            let bytes = nvim.as_bytes();
            let len = (bytes.len().min(u16::MAX as usize)) as u16;
            let mut pkt = Vec::with_capacity(3 + len as usize);
            pkt.push(0x02);
            pkt.extend_from_slice(&len.to_be_bytes());
            pkt.extend_from_slice(&bytes[..len as usize]);
            return stream.write_all(&pkt);
        }
    }
    Ok(())
}

fn attach_session(sock_path: &Path, log_path: &Path) -> io::Result<()> {
    let mut stream = match connect_with_retry(sock_path, 50, Duration::from_millis(10)) {
        Ok(s) => s,
        Err(e) => {
            if log_path.exists() {
                let _ = dump_scrollback(log_path);
            }
            eprintln!("\nError: Could not connect to session socket: {}", e);
            std::process::exit(1);
        }
    };

    let ws = ffi_get_terminal_size()?;
    send_resize_pkt(&mut stream, &ws)?;
    send_nvim_pkt(&mut stream)?;

    let mut stream_stdin = stream.try_clone()?;
    let mut stream_winch = stream.try_clone()?;

    let orig_termios = ffi_set_raw_mode()?;

    unsafe {
        signal(SIGWINCH, sigwinch_handler as *const () as usize);
    }

    thread::spawn(move || {
        let mut last_ws = ws;
        loop {
            thread::sleep(Duration::from_millis(100));
            if WINCH_RECEIVED.swap(false, Ordering::SeqCst) {
                if let Ok(cur_ws) = ffi_get_terminal_size() {
                    if cur_ws != last_ws {
                        last_ws = cur_ws;
                        if send_resize_pkt(&mut stream_winch, &cur_ws).is_err() {
                            break;
                        }
                    }
                }
            }
        }
    });

    thread::spawn(move || {
        let mut buf = [0u8; 1024];
        loop {
            let n = unsafe { read(0, buf.as_mut_ptr() as *mut CVoid, 1024) };
            if n <= 0 {
                break;
            }
            let chunk = &buf[..n as usize];

            if chunk.contains(&0x1c) {
                ffi_reset_mode(&orig_termios);
                println!("\n[sesatt: detached session]");
                std::process::exit(0);
            }

            let len = chunk.len() as u16;
            let mut pkt = Vec::with_capacity(3 + chunk.len());
            pkt.push(0x00);
            pkt.extend_from_slice(&len.to_be_bytes());
            pkt.extend_from_slice(chunk);

            if stream_stdin.write_all(&pkt).is_err() {
                break;
            }
        }
    });

    let mut buf = [0u8; 4096];
    loop {
        let n = stream.read(&mut buf)?;
        if n == 0 {
            break;
        }
        unsafe {
            write(1, buf.as_ptr() as *const CVoid, n);
        }
    }

    ffi_reset_mode(&orig_termios);
    println!("\n[sesatt: session finished]");
    Ok(())
}

fn get_tail_bytes(path: &Path, max_bytes: u64, max_lines: usize) -> io::Result<Vec<u8>> {
    let mut file = File::open(path)?;
    let len = file.metadata()?.len();
    let start = if len > max_bytes { len - max_bytes } else { 0 };
    file.seek(SeekFrom::Start(start))?;

    let mut bytes = Vec::new();
    file.read_to_end(&mut bytes)?;

    if bytes.is_empty() {
        return Ok(bytes);
    }

    let mut lines_count = 0;
    let mut start_idx = 0;

    for (i, &b) in bytes.iter().enumerate().rev() {
        if b == b'\n' {
            lines_count += 1;
            if lines_count == max_lines {
                start_idx = i + 1;
                break;
            }
        }
    }
    Ok(bytes[start_idx..].to_vec())
}

fn dump_scrollback(log_path: &Path) -> io::Result<()> {
    if log_path.exists() {
        if let Ok(bytes) = get_tail_bytes(log_path, 256 * 1024, 3000) {
            if !bytes.is_empty() {
                io::stdout().write_all(&bytes)?;
                io::stdout().flush()?;
            }
        }
    }
    Ok(())
}

fn spawn_daemon(session: &str, cmd_args: &[String]) -> io::Result<()> {
    let session_dir = get_session_dir(session);
    if let Err(e) = fs::create_dir_all(&session_dir) {
        eprintln!("Error: Failed to create session directory: {}", e);
        std::process::exit(1);
    }

    let sock_path = get_sock_path(session);
    let log_path = get_log_path(session);

    let _ = fs::remove_file(&sock_path);
    let _ = File::create(&log_path);

    let exe = match env::current_exe() {
        Ok(path) => path,
        Err(e) => {
            eprintln!("Error: Failed to resolve current executable path: {}", e);
            std::process::exit(1);
        }
    };

    // Probe if app2unit can connect to systemd bus in this environment
    let app2unit_works = Command::new("app2unit")
        .arg("true")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false);

    let mut app = if app2unit_works {
        let mut cmd = Command::new("app2unit");
        cmd.arg("-x");
        cmd.arg("-a").arg(format!("sesatt-{}", session));
        cmd.arg("--");
        cmd.arg(&exe);
        cmd
    } else {
        Command::new(&exe)
    };

    app.arg("--daemon");
    app.arg(session);
    for arg in cmd_args {
        app.arg(arg);
    }

    if let Err(e) = app.spawn() {
        eprintln!("Error: Failed to spawn daemon process: {}", e);
        std::process::exit(1);
    }

    Ok(())
}

fn run_daemon_server(
    session: &str,
    sock_path: PathBuf,
    log_path: PathBuf,
    cmd_args: Vec<String>,
    ws: Winsize,
) {
    ffi_daemonize_server();

    let listener = UnixListener::bind(&sock_path).expect("Failed to bind unix socket");
    let log_file = Arc::new(
        OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_path)
            .expect("Failed to open log file"),
    );

    let mut master_fd: CInt = 0;
    let mut slave_fd: CInt = 0;
    unsafe {
        openpty(
            &mut master_fd,
            &mut slave_fd,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            &ws,
        );
    }

    let pid = unsafe { fork() };
    if pid == 0 {
        unsafe {
            close(master_fd);
            login_tty(slave_fd);

            let pgrp = getpid();
            tcsetpgrp(0, pgrp);
        }

        let mut child_cmd = Command::new(&cmd_args[0]);
        if cmd_args.len() > 1 {
            child_cmd.args(&cmd_args[1..]);
        }

        child_cmd.env("INSIDE_SESATT", "1");
        child_cmd.env("SESATT_SESSION", session);

        let err = child_cmd.exec();
        eprintln!("Error executing command: {}", err);
        unsafe {
            _exit(1);
        }
    }

    unsafe {
        close(slave_fd);
    }

    let clients: Arc<Mutex<Vec<UnixStream>>> = Arc::new(Mutex::new(Vec::new()));
    let latest_nvim: Arc<Mutex<String>> = Arc::new(Mutex::new(String::new()));

    let clients_clone = clients.clone();
    let latest_nvim_clone = latest_nvim.clone();
    let log_path_clone = log_path.clone();

    thread::spawn(move || {
        for stream in listener.incoming() {
            if let Ok(mut s) = stream {
                let latest_nvim_inner = latest_nvim_clone.clone();
                let clients_inner = clients_clone.clone();
                let log_path_inner = log_path_clone.clone();

                thread::spawn(move || {
                    let mut tag = [0u8; 1];
                    if s.read_exact(&mut tag).is_err() {
                        return;
                    }

                    if tag[0] == 0x03 {
                        if let Ok(guard) = latest_nvim_inner.lock() {
                            let _ = s.write_all(guard.as_bytes());
                            let _ = s.flush();
                        }
                        let _ = s.shutdown(Shutdown::Both);
                        return;
                    }

                    if let Ok(bytes) = get_tail_bytes(&log_path_inner, 256 * 1024, 3000) {
                        if !bytes.is_empty() {
                            let _ = s.write_all(&bytes);
                            let _ = s.flush();
                        }
                    }

                    let s_clone = match s.try_clone() {
                        Ok(c) => c,
                        Err(_) => return,
                    };

                    clients_inner.lock().unwrap().push(s_clone);

                    let mut my_nvim = String::new();
                    let mut current_tag = tag[0];
                    loop {
                        match current_tag {
                            0x00 => {
                                let mut len_buf = [0u8; 2];
                                if s.read_exact(&mut len_buf).is_err() {
                                    break;
                                }
                                let len = u16::from_be_bytes(len_buf) as usize;
                                let mut data_buf = vec![0u8; len];
                                if s.read_exact(&mut data_buf).is_err() {
                                    break;
                                }

                                if !my_nvim.is_empty() {
                                    if let Ok(mut guard) = latest_nvim_inner.lock() {
                                        *guard = my_nvim.clone();
                                    }
                                }

                                unsafe {
                                    write(master_fd, data_buf.as_ptr() as *const CVoid, len);
                                }
                            }
                            0x01 => {
                                let mut ws_buf = [0u8; 8];
                                if s.read_exact(&mut ws_buf).is_err() {
                                    break;
                                }
                                let client_ws: Winsize = unsafe { std::mem::transmute(ws_buf) };
                                unsafe {
                                    ioctl(master_fd, TIOCSWINSZ, &client_ws);
                                }
                            }
                            0x02 => {
                                let mut len_buf = [0u8; 2];
                                if s.read_exact(&mut len_buf).is_err() {
                                    break;
                                }
                                let len = u16::from_be_bytes(len_buf) as usize;
                                let mut str_buf = vec![0u8; len];
                                if s.read_exact(&mut str_buf).is_err() {
                                    break;
                                }
                                if let Ok(nvim_str) = String::from_utf8(str_buf) {
                                    my_nvim = nvim_str.clone();
                                    if let Ok(mut guard) = latest_nvim_inner.lock() {
                                        *guard = nvim_str;
                                    }
                                }
                            }
                            _ => break,
                        }

                        let mut next_tag = [0u8; 1];
                        if s.read_exact(&mut next_tag).is_err() {
                            break;
                        }
                        current_tag = next_tag[0];
                    }
                });
            }
        }
    });

    let mut buf = [0u8; 4096];
    loop {
        let n = unsafe { read(master_fd, buf.as_mut_ptr() as *mut CVoid, 4096) };
        if n <= 0 {
            break;
        }
        let chunk = &buf[..n as usize];

        let _ = (&*log_file).write_all(chunk);

        let mut guard = clients.lock().unwrap();
        guard.retain_mut(|c| c.write_all(chunk).is_ok());
    }

    let _ = fs::remove_file(sock_path);
}
