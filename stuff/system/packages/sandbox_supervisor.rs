use std::collections::{HashMap, HashSet};
use std::env;
use std::fs;
use std::process::{self, Command};
use std::thread;
use std::time::Duration;

const SYS_PIDFD_OPEN: i64 = 434;
const EPOLL_CTL_ADD: i32 = 1;
const EPOLL_CTL_DEL: i32 = 2;
const EPOLLIN: u32 = 1;
const MAX_EVENTS: i32 = 64;

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

unsafe fn pidfd_open(pid: i32, flags: u32) -> i32 {
    syscall(SYS_PIDFD_OPEN, pid as i64, flags as i64) as i32
}

fn read_pids(path: &str) -> HashSet<i32> {
    let mut pids = HashSet::new();
    if let Ok(content) = fs::read_to_string(path) {
        for line in content.lines() {
            if let Ok(pid) = line.trim().parse::<i32>() {
                if pid > 0 {
                    pids.insert(pid);
                }
            }
        }
    }
    pids
}

struct SupervisorConfig {
    cgroup_procs: String,
    runner_pid: Option<i32>,
    close_fd: Option<i32>,
    cleanup_cmd: Option<String>,
}

fn parse_args() -> Result<SupervisorConfig, String> {
    let args: Vec<String> = env::args().collect();
    let mut cgroup_procs = None;
    let mut runner_pid = None;
    let mut close_fd = None;
    let mut cleanup_cmd = None;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--cgroup-procs" => {
                if i + 1 < args.len() {
                    cgroup_procs = Some(args[i + 1].clone());
                    i += 2;
                } else {
                    return Err("Missing argument for --cgroup-procs".into());
                }
            }
            "--runner-pid" => {
                if i + 1 < args.len() {
                    runner_pid = args[i + 1].parse().ok();
                    i += 2;
                } else {
                    return Err("Missing argument for --runner-pid".into());
                }
            }
            "--close-fd" => {
                if i + 1 < args.len() {
                    close_fd = args[i + 1].parse().ok();
                    i += 2;
                } else {
                    return Err("Missing argument for --close-fd".into());
                }
            }
            "--cleanup" => {
                if i + 1 < args.len() {
                    cleanup_cmd = Some(args[i + 1].clone());
                    i += 2;
                } else {
                    return Err("Missing argument for --cleanup".into());
                }
            }
            _ => {
                i += 1;
            }
        }
    }

    let cgroup_procs = cgroup_procs.ok_or("Missing required --cgroup-procs")?;
    Ok(SupervisorConfig {
        cgroup_procs,
        runner_pid,
        close_fd,
        cleanup_cmd,
    })
}

fn run_cleanup(config: &SupervisorConfig) {
    if let Some(fd) = config.close_fd {
        unsafe { close(fd) };
    }

    if let Some(ref cmd) = config.cleanup_cmd {
        // Try executing directly first; if failed, invoke via dash
        let status = Command::new(cmd).status();
        if status.is_err() {
            let _ = Command::new("dash").args(["-c", cmd]).status();
        }
    }
}

fn main() {
    let config = match parse_args() {
        Ok(c) => c,
        Err(err) => {
            eprintln!("Error: {}", err);
            process::exit(1);
        }
    };

    let epfd = unsafe { epoll_create1(0) };
    if epfd < 0 {
        run_cleanup(&config);
        process::exit(1);
    }

    // Monitor runner_pid (if specified)
    let mut runner_fd = -1;
    if let Some(r_pid) = config.runner_pid {
        if r_pid > 0 {
            runner_fd = unsafe { pidfd_open(r_pid, 0) };
            if runner_fd < 0 {
                // Runner is already dead: tear down immediately
                run_cleanup(&config);
                unsafe { close(epfd) };
                process::exit(0);
            }
            let mut ev = EpollEvent {
                events: EPOLLIN,
                data: runner_fd as u64,
            };
            unsafe {
                epoll_ctl(epfd, EPOLL_CTL_ADD, runner_fd, &mut ev);
            }
        }
    }

    let mut monitored_apps: HashMap<i32, i32> = HashMap::new(); // pid -> pidfd
    let mut has_seen_apps = false;
    let mut startup_retries = 0;

    loop {
        let current_pids = read_pids(&config.cgroup_procs);

        // Teardown condition 1: runner PID specified but missing from inside cgroup
        if let Some(r_pid) = config.runner_pid {
            if !current_pids.contains(&r_pid) {
                if !has_seen_apps && startup_retries < 10 {
                    startup_retries += 1;
                    thread::sleep(Duration::from_millis(50));
                    continue;
                }
                break;
            }
        }

        // Teardown condition 2: no apps running (<= 1 process in cgroup)
        if current_pids.len() <= 1 {
            if !has_seen_apps && startup_retries < 10 {
                startup_retries += 1;
                thread::sleep(Duration::from_millis(50));
                continue;
            }
            break;
        }

        // Clean up monitored apps that exited and left cgroup.procs
        monitored_apps.retain(|pid, &mut pfd| {
            if !current_pids.contains(pid) {
                unsafe {
                    epoll_ctl(epfd, EPOLL_CTL_DEL, pfd, std::ptr::null_mut());
                    close(pfd);
                }
                false
            } else {
                true
            }
        });

        // Add newly appeared app processes
        for &pid in &current_pids {
            if Some(pid) == config.runner_pid || monitored_apps.contains_key(&pid) {
                continue;
            }

            let pfd = unsafe { pidfd_open(pid, 0) };
            if pfd >= 0 {
                let mut ev = EpollEvent {
                    events: EPOLLIN,
                    data: pfd as u64,
                };
                if unsafe { epoll_ctl(epfd, EPOLL_CTL_ADD, pfd, &mut ev) } == 0 {
                    monitored_apps.insert(pid, pfd);
                    has_seen_apps = true;
                } else {
                    unsafe { close(pfd) };
                }
            }
        }

        // If after trying to add apps none could be monitored
        if monitored_apps.is_empty() {
            if !has_seen_apps && startup_retries < 10 {
                startup_retries += 1;
                thread::sleep(Duration::from_millis(50));
                continue;
            }
            break;
        }

        let mut events = [EpollEvent { events: 0, data: 0 }; MAX_EVENTS as usize];
        let n = unsafe { epoll_wait(epfd, events.as_mut_ptr(), MAX_EVENTS, -1) };
        if n < 0 {
            let err = std::io::Error::last_os_error();
            if err.raw_os_error() == Some(4) { // EINTR
                continue;
            }
            break;
        }

        let mut should_terminate = false;
        for i in 0..n as usize {
            let fd = events[i].data as i32;
            if fd == runner_fd {
                // Runner died
                should_terminate = true;
                break;
            }

            // An app process exited
            monitored_apps.retain(|_, &mut pfd| {
                if pfd == fd {
                    unsafe {
                        epoll_ctl(epfd, EPOLL_CTL_DEL, pfd, std::ptr::null_mut());
                        close(pfd);
                    }
                    false
                } else {
                    true
                }
            });
        }

        if should_terminate {
            break;
        }
    }

    // Teardown
    for (_, pfd) in monitored_apps {
        unsafe { close(pfd) };
    }
    if runner_fd >= 0 {
        unsafe { close(runner_fd) };
    }
    unsafe { close(epfd) };

    run_cleanup(&config);
}
