#![allow(
    clippy::too_many_lines,
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss,
    clippy::cast_lossless,
    clippy::cast_possible_wrap
)]

use std::collections::HashMap;
use std::ffi::CString;
use std::fs;
use std::os::raw::c_char;
use std::path::{Path, PathBuf};
use std::process::Command;

const SIGINT: i32 = 2;
const SIGTERM: i32 = 15;
const SIG_BLOCK: i32 = 0;

const SFD_NONBLOCK: i32 = 0x800;
const SFD_CLOEXEC: i32 = 0x80000;

const IN_MODIFY: u32 = 0x0000_0002;
const IN_CREATE: u32 = 0x0000_0100;
const IN_IGNORED: u32 = 0x0000_8000;
const IN_ONLYDIR: u32 = 0x0100_0000;
const IN_NONBLOCK: i32 = 0x800;
const IN_CLOEXEC: i32 = 0x80000;

const EPOLL_CTL_ADD: i32 = 1;
const EPOLLIN: u32 = 1;
const MAX_EVENTS: usize = 64;

#[repr(C)]
struct SigsetT {
    __val: [u64; 16],
}

#[repr(C, packed)]
#[derive(Clone, Copy)]
struct EpollEvent {
    events: u32,
    data: u64,
}

#[repr(C)]
struct InotifyEvent {
    wd: i32,
    mask: u32,
    cookie: u32,
    len: u32,
}

#[repr(C)]
struct SignalfdSiginfo {
    ssi_signo: u32,
    ssi_errno: i32,
    ssi_code: i32,
    ssi_pid: u32,
    ssi_uid: u32,
    ssi_fd: i32,
    ssi_tid: u32,
    ssi_band: u32,
    ssi_overrun: u32,
    ssi_trapno: u32,
    ssi_status: i32,
    ssi_int: i32,
    ssi_ptr: u64,
    ssi_utime: u64,
    ssi_stime: u64,
    _pad: [u8; 48],
}

#[repr(align(8))]
struct AlignedBuffer {
    data: [u8; 8192],
}

unsafe extern "C" {
    fn sigemptyset(set: *mut SigsetT) -> i32;
    fn sigaddset(set: *mut SigsetT, signum: i32) -> i32;
    fn sigprocmask(how: i32, set: *const SigsetT, oldset: *mut SigsetT) -> i32;
    fn signalfd(fd: i32, mask: *const SigsetT, flags: i32) -> i32;
    fn inotify_init1(flags: i32) -> i32;
    fn inotify_add_watch(fd: i32, pathname: *const c_char, mask: u32) -> i32;
    fn inotify_rm_watch(fd: i32, wd: i32) -> i32;
    fn epoll_create1(flags: i32) -> i32;
    fn epoll_ctl(epfd: i32, op: i32, fd: i32, event: *mut EpollEvent) -> i32;
    fn epoll_wait(epfd: i32, events: *mut EpollEvent, maxevents: i32, timeout: i32) -> i32;
    fn read(fd: i32, buf: *mut u8, count: usize) -> isize;
    fn close(fd: i32) -> i32;
    fn getuid() -> u32;
}

struct WatchNode {
    path: PathBuf,
    scope_name: Option<String>,
    is_events_file: bool,
}

struct CgroupWatcher {
    inotify_fd: i32,
    watches: HashMap<i32, WatchNode>,
}

impl CgroupWatcher {
    fn new(inotify_fd: i32) -> Self {
        Self {
            inotify_fd,
            watches: HashMap::new(),
        }
    }

    fn add_watch(
        &mut self,
        path: PathBuf,
        mask: u32,
        scope_name: Option<String>,
        is_events_file: bool,
    ) -> Option<i32> {
        let Ok(c_path) = CString::new(path.to_string_lossy().as_bytes()) else {
            return None;
        };
        let wd = unsafe { inotify_add_watch(self.inotify_fd, c_path.as_ptr(), mask) };
        if wd >= 0 {
            self.watches.insert(
                wd,
                WatchNode {
                    path,
                    scope_name,
                    is_events_file,
                },
            );
            Some(wd)
        } else {
            None
        }
    }

    fn remove_watch(&mut self, wd: i32) {
        if self.watches.remove(&wd).is_some() {
            unsafe {
                inotify_rm_watch(self.inotify_fd, wd);
            }
        }
    }

    fn check_and_kill(&mut self, wd: i32, events_path: &Path, scope_name: &str) {
        if !Path::new(scope_name)
            .extension()
            .is_some_and(|ext| ext.eq_ignore_ascii_case("scope"))
        {
            return;
        }

        let Ok(content) = fs::read_to_string(events_path) else {
            return;
        };

        let mut breached = false;
        for line in content.lines() {
            if let Some(val) = line
                .strip_prefix("max ")
                .and_then(|v| v.trim().parse::<i64>().ok())
                && val > 0
            {
                breached = true;
                break;
            }
        }

        if !breached {
            return;
        }

        if wd >= 0 {
            self.remove_watch(wd);
        }

        eprintln!(
            "CRITICAL: {scope_name} breached TasksMax! Enforcing full teardown via systemctl stop."
        );

        let _ = Command::new("systemctl")
            .args(["--user", "stop", "--no-block", scope_name])
            .spawn()
            .and_then(|mut child| child.wait());
    }

    fn watch_path_recursive(&mut self, dir_path: &Path) {
        self.add_watch(dir_path.to_path_buf(), IN_CREATE | IN_ONLYDIR, None, false);

        let events_file = dir_path.join("pids.events");
        if events_file.exists() {
            let scope_name = dir_path
                .file_name()
                .map(|s| s.to_string_lossy().into_owned());

            if let Some(scope) = &scope_name {
                let fwd = self.add_watch(events_file.clone(), IN_MODIFY, Some(scope.clone()), true);
                if let Some(wd) = fwd {
                    self.check_and_kill(wd, &events_file, scope);
                }
            }
        }

        if let Ok(entries) = fs::read_dir(dir_path) {
            for entry in entries.flatten() {
                if entry.file_type().is_ok_and(|ft| ft.is_dir()) {
                    let sub_path = entry.path();
                    self.watch_path_recursive(&sub_path);
                }
            }
        }
    }
}

fn main() {
    let mut mask = SigsetT { __val: [0; 16] };
    unsafe {
        sigemptyset(&raw mut mask);
        sigaddset(&raw mut mask, SIGTERM);
        sigaddset(&raw mut mask, SIGINT);
        if sigprocmask(SIG_BLOCK, &raw const mask, std::ptr::null_mut()) < 0 {
            eprintln!("Failed to block signals");
            std::process::exit(1);
        }
    }

    let sfd = unsafe { signalfd(-1, &raw const mask, SFD_NONBLOCK | SFD_CLOEXEC) };
    if sfd < 0 {
        eprintln!("Failed to create signalfd");
        std::process::exit(1);
    }

    let args: Vec<String> = std::env::args().collect();
    let cgroup_root = if args.len() > 1 {
        PathBuf::from(&args[1])
    } else {
        let uid = unsafe { getuid() };
        PathBuf::from(format!(
            "/sys/fs/cgroup/user.slice/user-{uid}.slice/user@{uid}.service"
        ))
    };

    eprintln!(
        "Cgroup Executioner active (Inotify + signalfd). Root: {}",
        cgroup_root.display()
    );

    let inotify_fd = unsafe { inotify_init1(IN_CLOEXEC | IN_NONBLOCK) };
    if inotify_fd < 0 {
        eprintln!("Failed to initialize inotify");
        unsafe { close(sfd) };
        std::process::exit(1);
    }

    let epfd = unsafe { epoll_create1(0) };
    if epfd < 0 {
        eprintln!("Failed to initialize epoll");
        unsafe {
            close(inotify_fd);
            close(sfd);
        }
        std::process::exit(1);
    }

    let mut ev_sig = EpollEvent {
        events: EPOLLIN,
        data: sfd as u64,
    };
    unsafe {
        epoll_ctl(epfd, EPOLL_CTL_ADD, sfd, &raw mut ev_sig);
    }

    let mut ev_ino = EpollEvent {
        events: EPOLLIN,
        data: inotify_fd as u64,
    };
    unsafe {
        epoll_ctl(epfd, EPOLL_CTL_ADD, inotify_fd, &raw mut ev_ino);
    }

    let mut watcher = CgroupWatcher::new(inotify_fd);
    watcher.watch_path_recursive(&cgroup_root);

    let mut events = [EpollEvent { events: 0, data: 0 }; MAX_EVENTS];
    let mut aligned_buf = AlignedBuffer { data: [0u8; 8192] };
    let mut running = true;

    while running {
        let n = unsafe { epoll_wait(epfd, events.as_mut_ptr(), MAX_EVENTS as i32, -1) };
        if n < 0 {
            continue;
        }

        for event in events.iter().take(n as usize) {
            let fd = event.data as i32;
            if fd == sfd {
                let mut fdsi = std::mem::MaybeUninit::<SignalfdSiginfo>::uninit();
                let s = unsafe {
                    read(
                        sfd,
                        fdsi.as_mut_ptr().cast::<u8>(),
                        size_of::<SignalfdSiginfo>(),
                    )
                };
                if s == size_of::<SignalfdSiginfo>() as isize {
                    running = false;
                    break;
                }
            } else if fd == inotify_fd {
                loop {
                    let len = unsafe {
                        read(
                            inotify_fd,
                            aligned_buf.data.as_mut_ptr(),
                            aligned_buf.data.len(),
                        )
                    };
                    if len <= 0 {
                        break;
                    }

                    let mut offset = 0usize;
                    let total = len as usize;
                    let event_header_size = size_of::<InotifyEvent>();

                    while offset + event_header_size <= total {
                        let in_ev = unsafe {
                            std::ptr::read_unaligned(
                                aligned_buf.data[offset..].as_ptr().cast::<InotifyEvent>(),
                            )
                        };
                        let name_len = in_ev.len as usize;
                        let next_offset = offset + event_header_size + name_len;

                        if in_ev.mask & IN_IGNORED != 0 {
                            watcher.remove_watch(in_ev.wd);
                            offset = next_offset;
                            continue;
                        }

                        let (is_events_file, path, scope_name) =
                            if let Some(node) = watcher.watches.get(&in_ev.wd) {
                                (
                                    node.is_events_file,
                                    node.path.clone(),
                                    node.scope_name.clone(),
                                )
                            } else {
                                offset = next_offset;
                                continue;
                            };

                        if is_events_file && (in_ev.mask & IN_MODIFY != 0) {
                            if let Some(scope) = scope_name {
                                watcher.check_and_kill(in_ev.wd, &path, &scope);
                            }
                        } else if !is_events_file && (in_ev.mask & IN_CREATE != 0) && name_len > 0 {
                            let name_bytes = &aligned_buf.data
                                [offset + event_header_size..offset + event_header_size + name_len];
                            let c_str = name_bytes
                                .iter()
                                .position(|&b| b == 0)
                                .map_or(name_bytes, |pos| &name_bytes[..pos]);
                            if let Ok(name_str) = std::str::from_utf8(c_str) {
                                let new_path = path.join(name_str);
                                if new_path.is_dir() {
                                    watcher.watch_path_recursive(&new_path);
                                }
                            }
                        }

                        offset = next_offset;
                    }
                }
            }
        }
    }

    unsafe {
        close(epfd);
        close(inotify_fd);
        close(sfd);
    }
}
