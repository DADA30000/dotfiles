use std::collections::{HashMap, HashSet};
use std::env;
use std::fs::{self, OpenOptions};
use std::io::{Read, Write};
use std::net::{Ipv4Addr, Shutdown, TcpListener, TcpStream};
use std::os::raw::c_char;
use std::os::unix::net::{UnixListener, UnixStream};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

unsafe extern "C" {
    fn fork() -> i32;
    fn setsid() -> i32;
    fn chdir(path: *const c_char) -> i32;
    fn close(fd: i32) -> i32;
    fn open(path: *const c_char, flags: i32, ...) -> i32;
    fn dup2(oldfd: i32, newfd: i32) -> i32;
}

const CONTROL_COMMAND_BIND: u8 = 1;
const CONTROL_COMMAND_UNBIND: u8 = 2;
const CONTROL_MESSAGE_SIZE: usize = 7;
const PACKET_TYPE_CONTROL: u8 = 0;
const PACKET_SIZE: usize = 7;
const CONFIG_LEN_SIZE: usize = 4;
const HEARTBEAT_SIZE: usize = 1;
const BUFFER_SIZE: usize = 8192;
const MAX_CONFIG_LEN: usize = 65536;

const DEFAULT_LOOP_SLEEP_MS: u64 = 100;

const STATE_TCP_LISTEN: &str = "0A";

static LOG_PATH: OnceLock<String> = OnceLock::new();

fn log_bridge(msg: &str) {
    if let Some(path) = LOG_PATH.get()
        && let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path)
    {
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |d| d.as_secs());
        let _ = writeln!(file, "[{timestamp}] {msg}");
    }
}

fn daemonize() {
    unsafe {
        let pid = fork();
        if pid < 0 {
            std::process::exit(1);
        }
        if pid > 0 {
            std::process::exit(0);
        }

        if setsid() < 0 {
            std::process::exit(1);
        }

        let pid2 = fork();
        if pid2 < 0 {
            std::process::exit(1);
        }
        if pid2 > 0 {
            std::process::exit(0);
        }

        let root = b"/\0";
        let _ = chdir(root.as_ptr().cast::<c_char>());

        let dev_null = b"/dev/null\0";
        let fd = open(dev_null.as_ptr().cast::<c_char>(), 2);
        if fd >= 0 {
            dup2(fd, 0);
            dup2(fd, 1);
            dup2(fd, 2);
            if fd > 2 {
                close(fd);
            }
        }
    }
}

fn print_help() {
    println!(
        "Usage: rust-bridge --role <pass|listen> --socket <path> [options]\n\n\
        Options:\n\
          -r, --role <pass|listen>      Mode of operation:\n\
                                        'pass' binds UNIX socket and handles active/dynamic outbound forwarders.\n\
                                        'listen' connects to UNIX socket and handles local TCP listeners.\n\
          -s, --socket <path>           UNIX domain socket path used for communication.\n\
          -a, --auto <ip>               Monitor and dynamically bind/unbind listening ports for IP (e.g. 127.0.0.1).\n\
              --address <ip:[p1,p2...]> Static mappings for destination IPs and ports.\n\
          -d, --detach                  Detach to background (daemonize) upon successful connection.\n\
          -l, --log <path>              Log file location for debugging.\n\
          -h, --help                    Show this help message.\n"
    );
}

fn ip_to_le_hex(ip_str: &str) -> Option<String> {
    let ip: Ipv4Addr = ip_str.parse().ok()?;
    let octets = ip.octets();
    Some(format!(
        "{:02X}{:02X}{:02X}{:02X}",
        octets[3], octets[2], octets[1], octets[0]
    ))
}

fn parse_active_ports(target_ip_hex: &str) -> Vec<u16> {
    let mut ports = Vec::new();
    if let Ok(content) = fs::read_to_string("/proc/net/tcp") {
        for line in content.lines().skip(1) {
            let tokens: Vec<&str> = line.split_whitespace().collect();
            if tokens.len() > 3
                && tokens[3].eq_ignore_ascii_case(STATE_TCP_LISTEN)
                && let Some((ip_hex, port_hex)) = tokens[1].split_once(':')
                && ip_hex.eq_ignore_ascii_case(target_ip_hex)
                && let Ok(port) = u16::from_str_radix(port_hex, 16)
                && port > 1025
            {
                ports.push(port);
            }
        }
    }
    ports
}

fn generate_canonical_config(
    auto_ips: &[String],
    address_maps: &HashMap<String, Vec<u16>>,
) -> String {
    let mut sorted_autos = auto_ips.to_vec();
    sorted_autos.sort_unstable();

    let mut static_segments: Vec<String> = address_maps
        .iter()
        .map(|(ip, ports)| {
            let mut sorted_ports = ports.clone();
            sorted_ports.sort_unstable();
            let ports_str = sorted_ports
                .iter()
                .map(std::string::ToString::to_string)
                .collect::<Vec<_>>()
                .join(",");
            format!("{ip}:[{ports_str}]")
        })
        .collect();
    static_segments.sort_unstable();

    format!(
        "auto:{};static:{}",
        sorted_autos.join(","),
        static_segments.join(";")
    )
}

fn send_control_message(control: &Mutex<Option<UnixStream>>, cmd: u8, ip_str: &str, port: u16) {
    if let Ok(mut lock) = control.lock()
        && let Some(stream) = lock.as_mut()
        && let Ok(ip) = ip_str.parse::<Ipv4Addr>()
    {
        let octets = ip.octets();
        let port_bytes = port.to_be_bytes();
        let packet = [
            cmd,
            octets[0],
            octets[1],
            octets[2],
            octets[3],
            port_bytes[0],
            port_bytes[1],
        ];
        if stream.write_all(&packet).is_err() {
            log_bridge("Error writing control message, exiting stream process.");
            std::process::exit(0);
        }
    }
}

fn forward_duplex(mut unix: UnixStream, mut tcp: TcpStream) {
    let Ok(mut unix_clone) = unix.try_clone() else {
        return;
    };
    let Ok(mut tcp_clone) = tcp.try_clone() else {
        return;
    };

    let t1 = thread::spawn(move || {
        let mut buf = [0u8; BUFFER_SIZE];
        while let Ok(n) = unix.read(&mut buf) {
            if n == 0 || tcp_clone.write_all(&buf[..n]).is_err() {
                break;
            }
        }
        let _ = tcp_clone.shutdown(Shutdown::Write);
    });

    let t2 = thread::spawn(move || {
        let mut buf = [0u8; BUFFER_SIZE];
        while let Ok(n) = tcp.read(&mut buf) {
            if n == 0 || unix_clone.write_all(&buf[..n]).is_err() {
                break;
            }
        }
        let _ = unix_clone.shutdown(Shutdown::Write);
    });

    let _ = t1.join();
    let _ = t2.join();
}

fn handle_pass_data_stream(mut unix_stream: UnixStream) {
    let mut header = [0u8; PACKET_SIZE];
    if unix_stream.read_exact(&mut header).is_err() {
        return;
    }

    let ip = Ipv4Addr::new(header[1], header[2], header[3], header[4]);
    let port = u16::from_be_bytes([header[5], header[6]]);
    let target = format!("{ip}:{port}");

    log_bridge(&format!("Forwarding data packet out to TCP {ip}:{port}"));

    if let Ok(tcp_stream) = TcpStream::connect(&target) {
        forward_duplex(unix_stream, tcp_stream);
    } else {
        log_bridge(&format!(
            "Failed to connect to outbound TCP target: {ip}:{port}"
        ));
    }
}

fn start_auto_discovery(auto_ips: Vec<String>, control_stream: Arc<Mutex<Option<UnixStream>>>) {
    thread::spawn(move || {
        let mut known_ports = HashSet::new();
        loop {
            let mut current_active = HashSet::new();
            for ip_str in &auto_ips {
                if let Some(ip_hex) = ip_to_le_hex(ip_str) {
                    for port in parse_active_ports(&ip_hex) {
                        current_active.insert((ip_str.clone(), port));
                    }
                }
            }

            for (ip_str, port) in &current_active {
                if known_ports.insert((ip_str.clone(), *port)) {
                    log_bridge(&format!("Auto-detected new bind target: {ip_str}:{port}"));
                    send_control_message(&control_stream, CONTROL_COMMAND_BIND, ip_str, *port);
                }
            }

            let stale: Vec<(String, u16)> = known_ports
                .iter()
                .filter(|item| !current_active.contains(item))
                .cloned()
                .collect();

            for (ip_str, port) in stale {
                known_ports.remove(&(ip_str.clone(), port));
                log_bridge(&format!("Removing stale bind target: {ip_str}:{port}"));
                send_control_message(&control_stream, CONTROL_COMMAND_UNBIND, &ip_str, port);
            }

            thread::sleep(Duration::from_millis(DEFAULT_LOOP_SLEEP_MS));
        }
    });
}

fn perform_pass_handshake(unix_stream: &mut UnixStream, local_config: &str) {
    let local_bytes = local_config.as_bytes();
    let Ok(local_len) = u32::try_from(local_bytes.len()) else {
        log_bridge("Error: Local configuration too large.");
        std::process::exit(1);
    };

    if unix_stream.write_all(&local_len.to_be_bytes()).is_err()
        || unix_stream.write_all(local_bytes).is_err()
    {
        log_bridge("Error: Failed to send local configuration.");
        std::process::exit(1);
    }

    let mut remote_len_bytes = [0u8; CONFIG_LEN_SIZE];
    if unix_stream.read_exact(&mut remote_len_bytes).is_err() {
        log_bridge("Error: Failed to read remote configuration length.");
        std::process::exit(1);
    }

    let remote_len = usize::try_from(u32::from_be_bytes(remote_len_bytes)).unwrap_or(0);
    if remote_len > MAX_CONFIG_LEN {
        log_bridge("Error: Remote configuration exceeds maximum size limit.");
        std::process::exit(1);
    }
    let mut remote_bytes = vec![0u8; remote_len];
    if unix_stream.read_exact(&mut remote_bytes).is_err() {
        log_bridge("Error: Failed to read remote configuration data.");
        std::process::exit(1);
    }

    let remote_config = String::from_utf8_lossy(&remote_bytes).into_owned();
    if local_config != remote_config {
        log_bridge(&format!(
            "Error: Configuration mismatch!\nLocal: {local_config}\nRemote: {remote_config}"
        ));
        std::process::exit(1);
    }

    log_bridge("Configuration handshake successful.");
}

fn run_pass_role(
    socket_path: &str,
    auto_ips: &[String],
    address_maps: &HashMap<String, Vec<u16>>,
    detach: bool,
) {
    let control_stream: Arc<Mutex<Option<UnixStream>>> = Arc::new(Mutex::new(None));
    let local_config = generate_canonical_config(auto_ips, address_maps);

    let _ = fs::remove_file(socket_path);
    log_bridge(&format!(
        "Starting PASS role. Binding UNIX socket at {socket_path}"
    ));

    let listener = match UnixListener::bind(socket_path) {
        Ok(l) => l,
        Err(e) => {
            log_bridge(&format!("Error: Failed to bind UNIX listener: {e}"));
            std::process::exit(1);
        }
    };

    log_bridge("Waiting for LISTEN role to connect...");
    if let Some(Ok(mut unix_stream)) = listener.incoming().next() {
        let mut header = [0u8; PACKET_SIZE];
        if unix_stream.read_exact(&mut header).is_ok() && header[0] == PACKET_TYPE_CONTROL {
            log_bridge("Control stream connected. Exchanging configurations...");
            perform_pass_handshake(&mut unix_stream, &local_config);

            if detach {
                log_bridge("Detaching PASS process to the background...");
                daemonize();
            }

            if let Ok(monitor_stream) = unix_stream.try_clone() {
                if let Ok(mut lock) = control_stream.lock() {
                    *lock = Some(unix_stream);
                }

                let mut ms = monitor_stream;
                thread::spawn(move || {
                    let mut buf = [0u8; HEARTBEAT_SIZE];
                    let _ = ms.read(&mut buf);
                    log_bridge("Control stream disconnected. Exiting PASS role.");
                    std::process::exit(0);
                });
            }

            if !auto_ips.is_empty() {
                log_bridge("Starting auto-port discovery thread...");
                start_auto_discovery(auto_ips.to_vec(), Arc::clone(&control_stream));
            }

            for stream in listener.incoming().flatten() {
                thread::spawn(move || handle_pass_data_stream(stream));
            }
        }
    }
}

fn spawn_listener(
    active_listeners: &Arc<Mutex<HashSet<(String, u16)>>>,
    socket_path: &str,
    ip: String,
    port: u16,
) {
    let key = (ip.clone(), port);
    if let Ok(mut active) = active_listeners.lock()
        && !active.contains(&key)
    {
        active.insert(key.clone());
        let active_clone = Arc::clone(active_listeners);
        let socket_path_deep = socket_path.to_string();

        log_bridge(&format!("Spawning TCP Listener on {ip}:{port}"));

        thread::spawn(move || {
            let listen_target = format!("{ip}:{port}");
            if let Ok(listener) = TcpListener::bind(&listen_target) {
                for incoming in listener.incoming() {
                    if let Ok(active_check) = active_clone.lock() {
                        if !active_check.contains(&key) {
                            break;
                        }
                    } else {
                        break;
                    }

                    if let Ok(tcp_stream) = incoming {
                        let source_addr = tcp_stream
                            .peer_addr()
                            .map_or_else(|_| "unknown".to_string(), |a| a.to_string());
                        log_bridge(&format!(
                            "Accepted connection on {ip}:{port} from {source_addr}"
                        ));

                        let socket_path_conn = socket_path_deep.clone();
                        let ip_parsed_str = ip.clone();

                        thread::spawn(move || {
                            if let Ok(mut unix_stream) = UnixStream::connect(&socket_path_conn)
                                && let Ok(ip_parsed) = ip_parsed_str.parse::<Ipv4Addr>()
                            {
                                let octets = ip_parsed.octets();
                                let port_bytes = port.to_be_bytes();
                                let header = [
                                    1u8,
                                    octets[0],
                                    octets[1],
                                    octets[2],
                                    octets[3],
                                    port_bytes[0],
                                    port_bytes[1],
                                ];
                                if unix_stream.write_all(&header).is_ok() {
                                    forward_duplex(unix_stream, tcp_stream);
                                }
                            }
                        });
                    }
                }
            } else {
                log_bridge(&format!("Failed to bind TCP Listener on {ip}:{port}"));
            }

            if let Ok(mut active) = active_clone.lock() {
                active.remove(&key);
            }
            log_bridge(&format!("Stopped TCP Listener on {ip}:{port}"));
        });
    }
}

fn perform_listen_handshake(stream: &mut UnixStream, local_config: &str) {
    let handshake = [0u8; PACKET_SIZE];
    if stream.write_all(&handshake).is_err() {
        log_bridge("Error: Failed to write control stream initiation packet.");
        std::process::exit(1);
    }

    let mut remote_len_bytes = [0u8; CONFIG_LEN_SIZE];
    if stream.read_exact(&mut remote_len_bytes).is_err() {
        log_bridge("Error: Failed to read remote configuration length.");
        std::process::exit(1);
    }

    let remote_len = usize::try_from(u32::from_be_bytes(remote_len_bytes)).unwrap_or(0);
    if remote_len > MAX_CONFIG_LEN {
        log_bridge("Error: Remote configuration exceeds maximum size limit.");
        std::process::exit(1);
    }
    let mut remote_bytes = vec![0u8; remote_len];
    if stream.read_exact(&mut remote_bytes).is_err() {
        log_bridge("Error: Failed to read remote configuration data.");
        std::process::exit(1);
    }

    let local_bytes = local_config.as_bytes();
    let Ok(local_len) = u32::try_from(local_bytes.len()) else {
        log_bridge("Error: Local configuration too large.");
        std::process::exit(1);
    };
    if stream.write_all(&local_len.to_be_bytes()).is_err() || stream.write_all(local_bytes).is_err()
    {
        log_bridge("Error: Failed to send local configuration.");
        std::process::exit(1);
    }

    let remote_config = String::from_utf8_lossy(&remote_bytes).into_owned();
    if local_config != remote_config {
        log_bridge(&format!(
            "Error: Configuration mismatch!\nLocal: {local_config}\nRemote: {remote_config}"
        ));
        std::process::exit(1);
    }

    log_bridge("Configuration handshake successful.");
}

fn run_listen_role(
    socket_path: &str,
    static_addresses: &HashMap<String, Vec<u16>>,
    auto_ips: &[String],
    detach: bool,
) {
    let active_listeners = Arc::new(Mutex::new(HashSet::new()));
    let local_config = generate_canonical_config(auto_ips, static_addresses);

    log_bridge(&format!(
        "Starting LISTEN role. Seeking UNIX socket at {socket_path}"
    ));

    let mut stream = loop {
        match UnixStream::connect(socket_path) {
            Ok(s) => break s,
            Err(_) => thread::sleep(Duration::from_millis(DEFAULT_LOOP_SLEEP_MS)),
        }
    };

    log_bridge("Connected to PASS role control socket. Exchanging configurations...");
    perform_listen_handshake(&mut stream, &local_config);

    if detach {
        log_bridge("Detaching LISTEN process to the background...");
        daemonize();
    }

    for (ip, ports) in static_addresses {
        for port in ports {
            spawn_listener(&active_listeners, socket_path, ip.clone(), *port);
        }
    }

    let mut cmd_buf = [0u8; CONTROL_MESSAGE_SIZE];
    while stream.read_exact(&mut cmd_buf).is_ok() {
        let cmd = cmd_buf[0];
        let ip = Ipv4Addr::new(cmd_buf[1], cmd_buf[2], cmd_buf[3], cmd_buf[4]).to_string();
        let port = u16::from_be_bytes([cmd_buf[5], cmd_buf[6]]);

        if cmd == CONTROL_COMMAND_BIND {
            log_bridge(&format!("Received dynamic BIND request for {ip}:{port}"));
            spawn_listener(&active_listeners, socket_path, ip, port);
        } else if cmd == CONTROL_COMMAND_UNBIND {
            log_bridge(&format!("Received dynamic UNBIND request for {ip}:{port}"));
            if let Ok(mut active) = active_listeners.lock() {
                active.remove(&(ip, port));
            }
        }
    }

    log_bridge("Control stream disconnected. Exiting LISTEN role.");
    std::process::exit(0);
}

struct BridgeArgs {
    role: String,
    socket_path: String,
    auto_ips: Vec<String>,
    address_maps: HashMap<String, Vec<u16>>,
    detach: bool,
}

fn parse_cli() -> BridgeArgs {
    let mut args = env::args().skip(1);
    let mut role = None;
    let mut socket_path = None;
    let mut auto_ips = Vec::new();
    let mut address_maps: HashMap<String, Vec<u16>> = HashMap::new();
    let mut detach = false;

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "-h" | "--help" => {
                print_help();
                std::process::exit(0);
            }
            "-r" | "--role" => {
                role = args.next();
            }
            "-s" | "--socket" => {
                socket_path = args.next();
            }
            "-a" | "--auto" => {
                if let Some(ip) = args.next() {
                    auto_ips.push(ip);
                }
            }
            "-d" | "--detach" => {
                detach = true;
            }
            "-l" | "--log" => {
                if let Some(l) = args.next() {
                    let _ = LOG_PATH.set(l);
                }
            }
            "--address" => {
                if let Some(addr_str) = args.next()
                    && let Some((ip, ports_part)) = addr_str.split_once(':')
                {
                    let mut ports = Vec::new();
                    if ports_part.starts_with('[') && ports_part.ends_with(']') {
                        let inner = &ports_part[1..ports_part.len() - 1];
                        for p_str in inner.split(',') {
                            if let Ok(p) = p_str.trim().parse::<u16>() {
                                ports.push(p);
                            }
                        }
                    } else if let Ok(p) = ports_part.parse::<u16>() {
                        ports.push(p);
                    }
                    address_maps
                        .entry(ip.to_string())
                        .or_default()
                        .extend(ports);
                }
            }
            _ => {
                eprintln!("Error: Unknown argument: {arg}");
                std::process::exit(1);
            }
        }
    }

    let (Some(r), Some(s)) = (role, socket_path) else {
        eprintln!("Error: Missing required arguments --role or --socket");
        print_help();
        std::process::exit(1);
    };

    BridgeArgs {
        role: r,
        socket_path: s,
        auto_ips,
        address_maps,
        detach,
    }
}

fn main() {
    let args = parse_cli();

    match args.role.as_str() {
        "pass" => run_pass_role(
            &args.socket_path,
            &args.auto_ips,
            &args.address_maps,
            args.detach,
        ),
        "listen" => run_listen_role(
            &args.socket_path,
            &args.address_maps,
            &args.auto_ips,
            args.detach,
        ),
        _ => {
            eprintln!("Error: Unknown role '{}'. Valid: pass, listen", args.role);
            std::process::exit(1);
        }
    }
}
