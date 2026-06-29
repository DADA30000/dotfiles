use std::collections::{HashMap, HashSet};
use std::env;
use std::fs::{self, OpenOptions};
use std::io::{self, Read, Write};
use std::net::{Ipv4Addr, Shutdown, TcpListener, TcpStream};
use std::os::raw::c_char;
use std::os::unix::net::{UnixListener, UnixStream};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread;
use std::time::Duration;

extern "C" {
    fn fork() -> i32;
    fn setsid() -> i32;
    fn open(path: *const c_char, oflag: i32) -> i32;
    fn dup2(oldfd: i32, newfd: i32) -> i32;
    fn close(fd: i32) -> i32;
}

const ROLE_PASS: &str = "pass";
const ROLE_LISTEN: &str = "listen";
const PACKET_TYPE_CONTROL: u8 = 0;
const PACKET_TYPE_DATA: u8 = 1;
const CONTROL_COMMAND_BIND: u8 = 1;
const CONTROL_COMMAND_UNBIND: u8 = 2;
const PACKET_SIZE: usize = 7;
const CONFIG_LEN_SIZE: usize = 4;
const HEARTBEAT_SIZE: usize = 1;
const DEFAULT_LOOP_SLEEP_MS: u64 = 500;
const ACCEPT_RETRY_SLEEP_MS: u64 = 100;
const EXPORT_SLEEP_MS: u64 = 500;
const O_RDWR: i32 = 2;
const STDIN_FD: i32 = 0;
const STDOUT_FD: i32 = 1;
const STDERR_FD: i32 = 2;
const STATE_TCP_LISTEN: &str = "0A";

static LOG_PATH: OnceLock<String> = OnceLock::new();

fn log_bridge(msg: &str) {
    if let Some(path) = LOG_PATH.get() {
        if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) {
            let _ = writeln!(file, "{}", msg);
        }
    }
}

fn daemonize() {
    unsafe {
        if fork() < 0 {
            std::process::exit(1);
        }
        if fork() > 0 {
            std::process::exit(0);
        }
        if setsid() < 0 {
            std::process::exit(1);
        }
        if fork() < 0 {
            std::process::exit(1);
        }
        if fork() > 0 {
            std::process::exit(0);
        }

        let dev_null = b"/dev/null\0".as_ptr() as *const c_char;
        let fd = open(dev_null, O_RDWR);
        if fd != -1 {
            dup2(fd, STDIN_FD);
            dup2(fd, STDOUT_FD);
            dup2(fd, STDERR_FD);
            if fd > STDERR_FD {
                close(fd);
            }
        }
    }
}

fn print_help() {
    println!("rust-bridge\n");
    println!("Options:");
    println!("  -r, --role <pass|listen>   Specify role:");
    println!(
        "                             'pass': Listens on UNIX socket, routes connections to TCP"
    );
    println!(
        "                             'listen': Listens on TCP ports, routes connections to UNIX"
    );
    println!("  -s, --socket <path>        Path to the UNIX domain socket");
    println!("  -a, --auto <ip>            Scan active TCP ports for this IP (pass role only)");
    println!("  --address <ip:ports>       Static IP and ports to bind (listen role only)");
    println!("                             Format: IP:PORT or IP:[PORT1,PORT2]");
    println!("  -d, --detach               Detach and run in the background");
    println!("  -l, --log <path>           Optional log file path");
    println!("  -h, --help                 Display options");
}

fn handle_connection(tcp_stream: TcpStream, unix_stream: UnixStream) {
    let _ = tcp_stream.set_nodelay(true);
    if let (Ok(mut t_read), Ok(mut u_read)) = (tcp_stream.try_clone(), unix_stream.try_clone()) {
        let mut t_write = tcp_stream;
        let mut u_write = unix_stream;

        thread::spawn(move || {
            let _ = io::copy(&mut t_read, &mut u_write);
            let _ = u_write.shutdown(Shutdown::Write);
        });

        thread::spawn(move || {
            let _ = io::copy(&mut u_read, &mut t_write);
            let _ = t_write.shutdown(Shutdown::Write);
        });
    }
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
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() > 3 && parts[3].eq_ignore_ascii_case(STATE_TCP_LISTEN) {
                if let Some((ip_hex, port_hex)) = parts[1].split_once(':') {
                    if ip_hex.eq_ignore_ascii_case(target_ip_hex) {
                        if let Ok(port) = u16::from_str_radix(port_hex, 16) {
                            if port > 1025 {
                                ports.push(port);
                            }
                        }
                    }
                }
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
                .map(|p| p.to_string())
                .collect::<Vec<_>>()
                .join(",");
            format!("{}:[{}]", ip, ports_str)
        })
        .collect();
    static_segments.sort_unstable();

    format!(
        "auto:{};static:{}",
        sorted_autos.join(","),
        static_segments.join(";")
    )
}

fn run_pass_role(
    socket_path: String,
    auto_ips: Vec<String>,
    address_maps: HashMap<String, Vec<u16>>,
    detach: bool,
) {
    let control_stream: Arc<Mutex<Option<UnixStream>>> = Arc::new(Mutex::new(None));
    let control_stream_scan = Arc::clone(&control_stream);
    let local_config = generate_canonical_config(&auto_ips, &address_maps);

    let _ = fs::remove_file(&socket_path);

    match UnixListener::bind(&socket_path) {
        Ok(listener) => {
            if let Some(Ok(mut unix_stream)) = listener.incoming().next() {
                let mut header = [0u8; PACKET_SIZE];
                if unix_stream.read_exact(&mut header).is_ok() && header[0] == PACKET_TYPE_CONTROL {
                    let local_bytes = local_config.as_bytes();
                    let local_len = local_bytes.len() as u32;

                    if unix_stream.write_all(&local_len.to_be_bytes()).is_err()
                        || unix_stream.write_all(local_bytes).is_err()
                    {
                        std::process::exit(1);
                    }

                    let mut remote_len_bytes = [0u8; CONFIG_LEN_SIZE];
                    if unix_stream.read_exact(&mut remote_len_bytes).is_err() {
                        std::process::exit(1);
                    }

                    let remote_len = u32::from_be_bytes(remote_len_bytes) as usize;
                    let mut remote_bytes = vec![0u8; remote_len];
                    if unix_stream.read_exact(&mut remote_bytes).is_err() {
                        std::process::exit(1);
                    }

                    let remote_config = String::from_utf8_lossy(&remote_bytes).into_owned();
                    if local_config != remote_config {
                        std::process::exit(1);
                    }

                    if detach {
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
                            std::process::exit(0);
                        });
                    }

                    if !auto_ips.is_empty() {
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
                                    if !known_ports.contains(&(ip_str.clone(), *port)) {
                                        known_ports.insert((ip_str.clone(), *port));
                                        send_control_message(
                                            &control_stream_scan,
                                            CONTROL_COMMAND_BIND,
                                            ip_str,
                                            *port,
                                        );
                                    }
                                }

                                let to_remove: Vec<(String, u16)> = known_ports
                                    .iter()
                                    .cloned()
                                    .filter(|x| !current_active.contains(x))
                                    .collect();

                                for (ip_str, port) in to_remove {
                                    known_ports.remove(&(ip_str.clone(), port));
                                    send_control_message(
                                        &control_stream_scan,
                                        CONTROL_COMMAND_UNBIND,
                                        &ip_str,
                                        port,
                                    );
                                }

                                thread::sleep(Duration::from_millis(EXPORT_SLEEP_MS));
                            }
                        });
                    }

                    for subsequent_stream in listener.incoming().flatten() {
                        let mut data_unix_stream = subsequent_stream;
                        thread::spawn(move || {
                            let mut data_header = [0u8; PACKET_SIZE];
                            if data_unix_stream.read_exact(&mut data_header).is_ok()
                                && data_header[0] == PACKET_TYPE_DATA
                            {
                                let ip = Ipv4Addr::new(
                                    data_header[1],
                                    data_header[2],
                                    data_header[3],
                                    data_header[4],
                                );
                                let port = u16::from_be_bytes([data_header[5], data_header[6]]);
                                let target = format!("{}:{}", ip, port);

                                if let Ok(tcp_stream) = TcpStream::connect(&target) {
                                    handle_connection(tcp_stream, data_unix_stream);
                                }
                            }
                        });
                    }
                } else {
                    std::process::exit(1);
                }
            }
        }
        Err(_) => std::process::exit(1),
    }

    fn send_control_message(control: &Mutex<Option<UnixStream>>, cmd: u8, ip_str: &str, port: u16) {
        if let Ok(mut lock) = control.lock() {
            if let Some(stream) = lock.as_mut() {
                if let Ok(ip) = ip_str.parse::<Ipv4Addr>() {
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
                        std::process::exit(0);
                    }
                }
            }
        }
    }
}

fn run_listen_role(
    socket_path: String,
    static_addresses: HashMap<String, Vec<u16>>,
    auto_ips: Vec<String>,
    detach: bool,
) {
    let active_listeners = Arc::new(Mutex::new(HashSet::new()));
    let active_listeners_clone = Arc::clone(&active_listeners);
    let local_config = generate_canonical_config(&auto_ips, &static_addresses);

    let mut stream = loop {
        match UnixStream::connect(&socket_path) {
            Ok(s) => break s,
            Err(_) => thread::sleep(Duration::from_millis(DEFAULT_LOOP_SLEEP_MS)),
        }
    };

    let handshake = [0u8; PACKET_SIZE];
    if stream.write_all(&handshake).is_err() {
        std::process::exit(1);
    }

    let mut remote_len_bytes = [0u8; CONFIG_LEN_SIZE];
    if stream.read_exact(&mut remote_len_bytes).is_err() {
        std::process::exit(1);
    }
    let remote_len = u32::from_be_bytes(remote_len_bytes) as usize;
    let mut remote_bytes = vec![0u8; remote_len];
    if stream.read_exact(&mut remote_bytes).is_err() {
        std::process::exit(1);
    }
    let remote_config = String::from_utf8_lossy(&remote_bytes).into_owned();

    let local_bytes = local_config.as_bytes();
    let local_len = local_bytes.len() as u32;
    if stream.write_all(&local_len.to_be_bytes()).is_err() || stream.write_all(local_bytes).is_err()
    {
        std::process::exit(1);
    }

    if local_config != remote_config {
        std::process::exit(1);
    }

    if detach {
        daemonize();
    }

    for (ip, ports) in static_addresses {
        for port in ports {
            spawn_listener(&active_listeners_clone, &socket_path, ip.clone(), port);
        }
    }

    let mut buf = [0u8; PACKET_SIZE];
    while stream.read_exact(&mut buf).is_ok() {
        let cmd = buf[0];
        let ip = Ipv4Addr::new(buf[1], buf[2], buf[3], buf[4]).to_string();
        let port = u16::from_be_bytes([buf[5], buf[6]]);

        if cmd == CONTROL_COMMAND_BIND {
            spawn_listener(&active_listeners, &socket_path, ip, port);
        } else if cmd == CONTROL_COMMAND_UNBIND {
            if let Ok(mut active) = active_listeners.lock() {
                active.remove(&(ip, port));
            }
        }
    }

    std::process::exit(0);

    fn spawn_listener(
        active_listeners: &Arc<Mutex<HashSet<(String, u16)>>>,
        socket_path: &str,
        ip: String,
        port: u16,
    ) {
        let key = (ip.clone(), port);
        if let Ok(mut active) = active_listeners.lock() {
            if !active.contains(&key) {
                active.insert(key.clone());
                let active_clone = Arc::clone(active_listeners);
                let socket_path_clone = socket_path.to_string();

                thread::spawn(move || {
                    let listen_target = format!("{}:{}", ip, port);
                    if let Ok(listener) = TcpListener::bind(&listen_target) {
                        let _ = listener.set_nonblocking(true);
                        loop {
                            let is_active = active_clone
                                .lock()
                                .map(|a| a.contains(&key))
                                .unwrap_or(false);

                            if !is_active {
                                break;
                            }

                            match listener.accept() {
                                Ok((tcp_stream, _)) => {
                                    let socket_path_deep = socket_path_clone.clone();
                                    let ip_parsed_str = ip.clone();
                                    thread::spawn(move || {
                                        if let Ok(mut unix_stream) =
                                            UnixStream::connect(&socket_path_deep)
                                        {
                                            if let Ok(ip_parsed) = ip_parsed_str.parse::<Ipv4Addr>()
                                            {
                                                let octets = ip_parsed.octets();
                                                let port_bytes = port.to_be_bytes();
                                                let header = [
                                                    PACKET_TYPE_DATA,
                                                    octets[0],
                                                    octets[1],
                                                    octets[2],
                                                    octets[3],
                                                    port_bytes[0],
                                                    port_bytes[1],
                                                ];
                                                if unix_stream.write_all(&header).is_ok() {
                                                    handle_connection(tcp_stream, unix_stream);
                                                }
                                            }
                                        }
                                    });
                                }
                                Err(ref e) if e.kind() == io::ErrorKind::WouldBlock => {
                                    thread::sleep(Duration::from_millis(ACCEPT_RETRY_SLEEP_MS));
                                }
                                Err(_) => break,
                            }
                        }
                    }
                    if let Ok(mut a) = active_clone.lock() {
                        a.remove(&key);
                    }
                });
            }
        }
    }
}

fn main() {
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
                if let Some(r) = args.next() {
                    role = Some(r);
                } else {
                    std::process::exit(1);
                }
            }
            "-s" | "--socket" => {
                if let Some(s) = args.next() {
                    socket_path = Some(s);
                } else {
                    std::process::exit(1);
                }
            }
            "-a" | "--auto" => {
                if let Some(ip) = args.next() {
                    auto_ips.push(ip);
                } else {
                    std::process::exit(1);
                }
            }
            "-d" | "--detach" => {
                detach = true;
            }
            "-l" | "--log" => {
                if let Some(l) = args.next() {
                    let _ = LOG_PATH.set(l);
                } else {
                    std::process::exit(1);
                }
            }
            "--address" => {
                if let Some(addr_str) = args.next() {
                    if let Some((ip, ports_part)) = addr_str.split_once(':') {
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
                } else {
                    std::process::exit(1);
                }
            }
            _ => std::process::exit(1),
        }
    }

    let role = match role {
        Some(r) if r == ROLE_PASS || r == ROLE_LISTEN => r,
        _ => std::process::exit(1),
    };

    let socket_path = match socket_path {
        Some(s) => s,
        None => std::process::exit(1),
    };

    if address_maps.is_empty() {
        std::process::exit(1);
    }

    if role == ROLE_PASS {
        run_pass_role(socket_path, auto_ips, address_maps, detach);
    } else {
        run_listen_role(socket_path, address_maps, auto_ips, detach);
    }
}
