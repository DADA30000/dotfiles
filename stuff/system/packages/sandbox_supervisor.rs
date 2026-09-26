use std::collections::HashSet;
use std::{env, fs, process::Command};

const SYS_RT_SIGPROCMASK: i64 = 14;
const SYS_SIGNALFD4: i64 = 289;
const SYS_PIDFD_OPEN: i64 = 434;

const SIG_BLOCK: i64 = 0;
const SFD_CLOEXEC: i64 = 0x80000;
const SFD_NONBLOCK: i64 = 0x800;

const EPOLL_CTL_ADD: i32 = 1;
const EPOLL_CTL_DEL: i32 = 2;
const EPOLLIN: u32 = 1;

#[repr(C, packed)]
#[derive(Clone, Copy)]
struct EpollEvent {
    events: u32,
    data: u64,
}

extern "C" {
    fn syscall(number: i64, ...) -> i64;
    fn epoll_create1(flags: i32) -> i32;
    fn epoll_ctl(epfd: i32, op: i32, fd: i32, event: *mut EpollEvent) -> i32;
    fn epoll_wait(epfd: i32, events: *mut EpollEvent, maxevents: i32, timeout: i32) -> i32;
    fn close(fd: i32) -> i32;
}

fn read_pids(path: &str) -> HashSet<i32> {
    fs::read_to_string(path)
        .unwrap_or_default()
        .lines()
        .filter_map(|l| l.trim().parse().ok())
        .filter(|&p| p > 0)
        .collect()
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let mut procs_path = String::new();
    let mut runner_pid = 0;
    let mut close_fd = -1;
    let mut cleanup_cmd = String::new();

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--cgroup-procs" if i + 1 < args.len() => {
                procs_path = args[i + 1].clone();
                i += 2;
            }
            "--runner-pid" if i + 1 < args.len() => {
                runner_pid = args[i + 1].parse().unwrap_or(0);
                i += 2;
            }
            "--close-fd" if i + 1 < args.len() => {
                close_fd = args[i + 1].parse().unwrap_or(-1);
                i += 2;
            }
            "--cleanup" if i + 1 < args.len() => {
                cleanup_cmd = args[i + 1].clone();
                i += 2;
            }
            _ => i += 1,
        }
    }

    if procs_path.is_empty() {
        return;
    }

    let epfd = unsafe { epoll_create1(0) };

    // Block SIGHUP (1), SIGINT (2), SIGQUIT (3), SIGTERM (15) via raw Linux syscall
    let mask: u64 = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 14);
    unsafe {
        syscall(
            SYS_RT_SIGPROCMASK,
            SIG_BLOCK,
            &mask as *const u64 as i64,
            0i64,
            8i64,
        );
    }
    let sfd = unsafe {
        syscall(
            SYS_SIGNALFD4,
            -1i64,
            &mask as *const u64 as i64,
            8i64,
            SFD_CLOEXEC | SFD_NONBLOCK,
        ) as i32
    };
    if sfd >= 0 {
        let mut ev = EpollEvent {
            events: EPOLLIN,
            data: sfd as u64,
        };
        unsafe { epoll_ctl(epfd, EPOLL_CTL_ADD, sfd, &mut ev) };
    }

    // Monitor runner_pid
    let runner_fd = if runner_pid > 0 {
        unsafe { syscall(SYS_PIDFD_OPEN, runner_pid as i64, 0) as i32 }
    } else {
        -1
    };
    if runner_fd >= 0 {
        let mut ev = EpollEvent {
            events: EPOLLIN,
            data: runner_fd as u64,
        };
        unsafe { epoll_ctl(epfd, EPOLL_CTL_ADD, runner_fd, &mut ev) };
    }

    let mut monitored = HashSet::new();
    let mut has_seen_apps = false;

    loop {
        let current_pids = read_pids(&procs_path);

        // Teardown condition: runner missing, or all apps exited after having started
        if (runner_pid > 0 && !current_pids.contains(&runner_pid))
            || (has_seen_apps && current_pids.len() <= 1)
        {
            break;
        }

        // Add newly appeared app processes to epoll
        for &pid in &current_pids {
            if pid == runner_pid {
                continue;
            }
            has_seen_apps = true;
            if monitored.contains(&pid) {
                continue;
            }
            let pfd = unsafe { syscall(SYS_PIDFD_OPEN, pid as i64, 0) as i32 };
            if pfd >= 0 {
                let mut ev = EpollEvent {
                    events: EPOLLIN,
                    data: pfd as u64,
                };
                if unsafe { epoll_ctl(epfd, EPOLL_CTL_ADD, pfd, &mut ev) } == 0 {
                    monitored.insert(pid);
                } else {
                    unsafe { close(pfd) };
                }
            }
        }

        let mut events = [EpollEvent { events: 0, data: 0 }; 16];
        let n = unsafe { epoll_wait(epfd, events.as_mut_ptr(), 16, -1) };
        if n < 0 {
            let err = std::io::Error::last_os_error();
            if err.raw_os_error() == Some(4) { // EINTR
                continue;
            }
            break;
        }

        let mut terminate = false;
        for i in 0..n as usize {
            let fd = events[i].data as i32;
            if fd == sfd || fd == runner_fd {
                terminate = true;
                break;
            }
            // An app subprocess exited: clean it up from epoll to prevent busy-spinning
            unsafe {
                epoll_ctl(epfd, EPOLL_CTL_DEL, fd, std::ptr::null_mut());
                close(fd);
            };
        }
        if terminate {
            break;
        }
    }

    if close_fd >= 0 {
        unsafe { close(close_fd) };
    }

    if !cleanup_cmd.is_empty() {
        let _ = Command::new(&cleanup_cmd).status();
    }
}
