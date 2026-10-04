use std::fs;
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Instant;

static RUNNING: AtomicBool = AtomicBool::new(true);

const AF_NETLINK: i32 = 16;
const SOCK_RAW: i32 = 3;
const SOCK_CLOEXEC: i32 = 0x80000;
const SOCK_NONBLOCK: i32 = 0x800;
const NETLINK_ROUTE: i32 = 0;
const RTMGRP_LINK: u32 = 1;

const POLLIN: i16 = 0x0001;

const SIGINT: i32 = 2;
const SIGTERM: i32 = 15;

#[repr(C)]
struct SockAddrNl {
    family: u16,
    pad: u16,
    pid: u32,
    groups: u32,
}

#[repr(C)]
struct PollFd {
    fd: i32,
    events: i16,
    revents: i16,
}

#[repr(C)]
struct Sigaction {
    handler: usize,
    flags: u64,
    restorer: usize,
    mask: [u64; 16],
}

unsafe extern "C" {
    fn socket(domain: i32, sock_type: i32, protocol: i32) -> i32;
    fn bind(sockfd: i32, addr: *const SockAddrNl, addrlen: u32) -> i32;
    fn poll(fds: *mut PollFd, nfds: u64, timeout: i32) -> i32;
    fn recv(sockfd: i32, buf: *mut u8, len: usize, flags: i32) -> isize;
    fn close(fd: i32) -> i32;
    fn sigaction(signum: i32, act: *const Sigaction, oldact: *mut Sigaction) -> i32;
}

extern "C" fn sig_handler(_sig: i32) {
    RUNNING.store(false, Ordering::Relaxed);
}

fn init_signals() {
    let sa = Sigaction {
        handler: sig_handler as *const () as usize,
        flags: 0,
        restorer: 0,
        mask: [0; 16],
    };
    unsafe {
        sigaction(SIGTERM, &raw const sa, std::ptr::null_mut());
        sigaction(SIGINT, &raw const sa, std::ptr::null_mut());
    }
}

fn init_netlink_socket() -> i32 {
    let nl_fd = unsafe {
        socket(
            AF_NETLINK,
            SOCK_RAW | SOCK_CLOEXEC | SOCK_NONBLOCK,
            NETLINK_ROUTE,
        )
    };
    if nl_fd < 0 {
        eprintln!("Failed to open netlink socket");
        std::process::exit(1);
    }

    let Ok(sockaddr_len) = u32::try_from(size_of::<SockAddrNl>()) else {
        unsafe { close(nl_fd) };
        std::process::exit(1);
    };

    let sa_nl = SockAddrNl {
        family: u16::try_from(AF_NETLINK).unwrap_or(0),
        pad: 0,
        pid: 0,
        groups: RTMGRP_LINK,
    };

    if unsafe { bind(nl_fd, &raw const sa_nl, sockaddr_len) } < 0 {
        eprintln!("Failed to bind netlink socket");
        unsafe { close(nl_fd) };
        std::process::exit(1);
    }

    nl_fd
}

fn run_systemctl(action: &str) {
    let _ = Command::new("systemctl")
        .args([action, "sing-box-init.service"])
        .status();
}

fn has_physical_carrier() -> bool {
    let Ok(entries) = fs::read_dir("/sys/class/net") else {
        return false;
    };

    for entry in entries.flatten() {
        let path = entry.path();
        if !path.join("device").exists() {
            continue;
        }

        if let Ok(carrier) = fs::read_to_string(path.join("carrier"))
            && carrier.trim() == "1"
        {
            return true;
        }

        if let Ok(oper) = fs::read_to_string(path.join("operstate"))
            && oper.trim().starts_with("up")
        {
            return true;
        }
    }

    false
}

fn drain_netlink(fd: i32) {
    const MSG_DONTWAIT: i32 = 0x40;
    let mut buf = [0u8; 4096];
    while unsafe { recv(fd, buf.as_mut_ptr(), buf.len(), MSG_DONTWAIT) } > 0 {}
}

fn debounce_link_events(nl_fd: i32) {
    let mut remaining_ms = 1500i32;
    while remaining_ms > 0 && RUNNING.load(Ordering::Relaxed) {
        let start = Instant::now();
        let mut debounce_pfd = PollFd {
            fd: nl_fd,
            events: POLLIN,
            revents: 0,
        };
        let d_ret = unsafe { poll(&raw mut debounce_pfd, 1, remaining_ms) };
        if d_ret > 0 && (debounce_pfd.revents & POLLIN != 0) {
            drain_netlink(nl_fd);
            remaining_ms = 1500;
        } else {
            let Ok(elapsed) = i32::try_from(start.elapsed().as_millis()) else {
                break;
            };
            remaining_ms = remaining_ms.saturating_sub(elapsed);
        }
    }
}

fn run_watcher_loop(nl_fd: i32) {
    let mut last_state: Option<bool> = None;

    while RUNNING.load(Ordering::Relaxed) {
        let connected = has_physical_carrier();

        if last_state != Some(connected) {
            last_state = Some(connected);
            if connected {
                eprintln!("[sing-box-watcher] Physical link UP. Starting sing-box-init...");
                run_systemctl("start");
            } else {
                eprintln!("[sing-box-watcher] Physical link DOWN. Stopping sing-box-init...");
                run_systemctl("stop");
            }
        }

        let mut pfd = PollFd {
            fd: nl_fd,
            events: POLLIN,
            revents: 0,
        };

        let ret = unsafe { poll(&raw mut pfd, 1, -1) };
        if ret > 0 && (pfd.revents & POLLIN != 0) {
            drain_netlink(nl_fd);
            debounce_link_events(nl_fd);
        }
    }
}

fn main() {
    init_signals();
    let nl_fd = init_netlink_socket();
    run_watcher_loop(nl_fd);
    unsafe {
        close(nl_fd);
    }
}
