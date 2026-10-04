#![allow(
    clippy::too_many_lines,
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss,
    clippy::cast_lossless,
    clippy::cast_possible_wrap,
    clippy::struct_field_names
)]

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
    nl_family: u16,
    nl_pad: u16,
    nl_pid: u32,
    nl_groups: u32,
}

#[repr(C)]
struct PollFd {
    fd: i32,
    events: i16,
    revents: i16,
}

#[repr(C)]
struct Sigaction {
    sa_handler: usize,
    sa_flags: u64,
    sa_restorer: usize,
    sa_mask: [u64; 16],
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
        // Ignore virtual network devices (tun0, lo, veth, etc.)
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

fn main() {
    let sa = Sigaction {
        sa_handler: sig_handler as *const () as usize,
        sa_flags: 0,
        sa_restorer: 0,
        sa_mask: [0; 16],
    };
    unsafe {
        sigaction(SIGTERM, &raw const sa, std::ptr::null_mut());
        sigaction(SIGINT, &raw const sa, std::ptr::null_mut());
    }

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

    let sa_nl = SockAddrNl {
        nl_family: AF_NETLINK as u16,
        nl_pad: 0,
        nl_pid: 0,
        nl_groups: RTMGRP_LINK,
    };

    if unsafe { bind(nl_fd, &raw const sa_nl, size_of::<SockAddrNl>() as u32) } < 0 {
        eprintln!("Failed to bind netlink socket");
        unsafe { close(nl_fd) };
        std::process::exit(1);
    }

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

            // Debounce 1.5s to absorb link flapping / DHCP negotiation
            let mut remaining_ms = 1500;
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
                    remaining_ms = 1500; // Reset debounce timer on new events
                } else {
                    let elapsed = start.elapsed().as_millis() as i32;
                    remaining_ms = remaining_ms.saturating_sub(elapsed);
                }
            }
        }
    }

    unsafe {
        close(nl_fd);
    }
}
