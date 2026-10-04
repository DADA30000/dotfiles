#![forbid(unsafe_op_in_unsafe_fn)]

use std::ffi::{CStr, CString};
use std::fmt::Write as _;
use std::fs;
use std::io;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};

// Linux x86_64 syscall numbers
const SYS_MOVE_MOUNT: i64 = 429;
const SYS_FSOPEN: i64 = 430;
const SYS_FSCONFIG: i64 = 431;
const SYS_FSMOUNT: i64 = 432;
const SYS_MOUNT_SETATTR: i64 = 442;

// fsopen / fsconfig / fsmount flags
const FSOPEN_CLOEXEC: u32 = 0x0000_0001;
const FSCONFIG_SET_FLAG: u32 = 0;
const FSCONFIG_SET_STRING: u32 = 1;
const FSCONFIG_SET_FD: u32 = 5;
const FSCONFIG_CMD_CREATE: u32 = 6;
const FSMOUNT_CLOEXEC: u32 = 0x0000_0001;

// mount_setattr flags and attributes
const MOUNT_ATTR_RDONLY: u32 = 0x0000_0001;
const MOUNT_ATTR_NOSUID: u32 = 0x0000_0002;
const MOUNT_ATTR_NODEV: u32 = 0x0000_0004;
const MOUNT_ATTR_IDMAP: u64 = 0x0010_0000;
const AT_RECURSIVE: i32 = 0x8000;

// move_mount flags
const MOVE_MOUNT_F_EMPTY_PATH: u32 = 0x0000_0004;
const AT_FDCWD: i32 = -100;
const AT_EMPTY_PATH: i32 = 0x1000;

// Open flags
const O_RDONLY: i32 = 0;
const O_RDWR: i32 = 2;
const O_DIRECTORY: i32 = 0x10000;
const O_CLOEXEC: i32 = 0x80000;
const O_PATH: i32 = 0x0020_0000;
const O_NOFOLLOW: i32 = 0x20000;

// Loop device ioctls
const LOOP_CTL_GET_FREE: u64 = 0x4C82;
const LOOP_CONFIGURE: u64 = 0x4C0A;
const LO_FLAGS_READ_ONLY: u32 = 1;
const LO_FLAGS_AUTOCLEAR: u32 = 4;

// EROFS magic
const EROFS_SUPER_MAGIC_V1: u32 = 0xE0F5_E1E2;
const EROFS_SUPER_OFFSET: u64 = 1024;

// Clone flags
const CLONE_NEWUSER: i32 = 0x1000_0000;

#[repr(C)]
struct CloneMountAttr {
    attr_set: u64,
    attr_clr: u64,
    propagation: u64,
    userns_fd: u64,
}

#[repr(C)]
struct LoopInfo64 {
    device: u64,
    inode: u64,
    rdevice: u64,
    offset: u64,
    sizelimit: u64,
    number: u32,
    encrypt_type: u32,
    encrypt_key_size: u32,
    flags: u32,
    file_name: [u8; 64],
    crypt_name: [u8; 64],
    encrypt_key: [u8; 32],
    init: [u64; 2],
}

#[repr(C)]
struct LoopConfig {
    fd: u32,
    block_size: u32,
    info: LoopInfo64,
    __reserved: [u64; 8],
}

#[repr(C)]
struct Passwd {
    name: *mut i8,
    password: *mut i8,
    uid: u32,
    gid: u32,
    gecos: *mut i8,
    dir: *mut i8,
    shell: *mut i8,
}

#[derive(Clone, Copy)]
struct IdMap {
    container_id: u32,
    host_id: u32,
}

unsafe extern "C" {
    fn syscall(number: i64, ...) -> i64;
    fn open(pathname: *const i8, flags: i32, ...) -> i32;
    fn close(fd: i32) -> i32;
    fn ioctl(fd: i32, request: u64, ...) -> i32;
    fn pread(fd: i32, buf: *mut u8, count: usize, offset: i64) -> isize;
    fn getpwuid(uid: u32) -> *mut Passwd;
    fn pipe(pipefd: *mut i32) -> i32;
    fn fork() -> i32;
    fn unshare(flags: i32) -> i32;
    fn read(fd: i32, buf: *mut u8, count: usize) -> isize;
    fn write(fd: i32, buf: *const u8, count: usize) -> isize;
    fn waitpid(pid: i32, status: *mut i32, options: i32) -> i32;
    fn renameat2(
        olddirfd: i32,
        oldpath: *const i8,
        newdirfd: i32,
        newpath: *const i8,
        flags: u32,
    ) -> i32;
    fn unlinkat(dirfd: i32, pathname: *const i8, flags: i32) -> i32;
    fn pause();
    fn kill(pid: i32, sig: i32) -> i32;
}

const RENAME_EXCHANGE: u32 = 2;

const fn libc_ebusy() -> i32 {
    16
}

struct Fd(i32);

impl Fd {
    const fn new(fd: i32) -> Option<Self> {
        if fd >= 0 { Some(Self(fd)) } else { None }
    }

    const fn raw(&self) -> i32 {
        self.0
    }
}

impl Drop for Fd {
    fn drop(&mut self) {
        unsafe { close(self.0) };
    }
}

fn write_id_map(pid: i32, map_file: &str, in_id: u32, out_id: u32) -> Result<(), io::Error> {
    let path = format!("/proc/{pid}/{map_file}");
    let mut map = String::new();

    let _ = writeln!(map, "{in_id} {out_id} 1");

    if in_id == 0 {
        if out_id > 1 {
            let count = out_id - 1;
            let _ = writeln!(map, "1 1 {count}");
        }
        if out_id < 4_294_967_294 {
            let start = out_id + 1;
            let count = 4_294_967_294 - out_id;
            let _ = writeln!(map, "{start} {start} {count}");
        }
    } else {
        let mut max_id = in_id;
        if out_id > max_id {
            max_id = out_id;
        }

        if in_id > 0 {
            let count = in_id;
            let _ = writeln!(map, "0 0 {count}");
        }

        if max_id < 4_294_967_293 {
            let next = max_id + 1;
            let count = 4_294_967_294 - max_id;
            let _ = writeln!(map, "{next} {next} {count}");
        }
    }

    fs::write(&path, map)
}

fn create_userns(uid_map: IdMap, gid_map: IdMap) -> Result<Fd, io::Error> {
    let mut pipefd = [0i32; 2];
    if unsafe { pipe(pipefd.as_mut_ptr()) } < 0 {
        return Err(io::Error::last_os_error());
    }

    let pid = unsafe { fork() };
    if pid < 0 {
        unsafe {
            close(pipefd[0]);
            close(pipefd[1]);
        }
        return Err(io::Error::last_os_error());
    }

    if pid == 0 {
        unsafe { close(pipefd[1]) };

        if unsafe { unshare(CLONE_NEWUSER) } < 0 {
            std::process::exit(1);
        }

        let mut b = 0u8;
        let _ = unsafe { read(pipefd[0], &raw mut b, 1) };
        unsafe { close(pipefd[0]) };

        if b == 1 {
            unsafe { pause() };
        }
        std::process::exit(0);
    }

    unsafe { close(pipefd[0]) };

    let setgroups_path = format!("/proc/{pid}/setgroups");
    let _ = fs::write(setgroups_path, "deny");

    if let Err(e) = write_id_map(pid, "uid_map", uid_map.container_id, uid_map.host_id) {
        unsafe {
            kill(pid, 9);
            close(pipefd[1]);
            waitpid(pid, std::ptr::null_mut(), 0);
        }
        return Err(e);
    }

    if let Err(e) = write_id_map(pid, "gid_map", gid_map.container_id, gid_map.host_id) {
        unsafe {
            kill(pid, 9);
            close(pipefd[1]);
            waitpid(pid, std::ptr::null_mut(), 0);
        }
        return Err(e);
    }

    let b = 1u8;
    unsafe { write(pipefd[1], &raw const b, 1) };
    unsafe { close(pipefd[1]) };

    let userns_path = format!("/proc/{pid}/ns/user");
    let c_path =
        CString::new(userns_path).map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;
    let userns_fd = Fd::new(unsafe { open(c_path.as_ptr(), O_RDONLY | O_CLOEXEC) })
        .ok_or_else(io::Error::last_os_error)?;

    unsafe { kill(pid, 9) };
    unsafe { waitpid(pid, std::ptr::null_mut(), 0) };

    Ok(userns_fd)
}

fn validate_erofs_magic(fd: &Fd) -> Result<(), io::Error> {
    let mut buf = [0u8; 4];
    let n = unsafe {
        pread(
            fd.raw(),
            buf.as_mut_ptr(),
            4,
            EROFS_SUPER_OFFSET.cast_signed(),
        )
    };
    if n != 4 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "Failed to read EROFS superblock",
        ));
    }

    let magic = u32::from_le_bytes(buf);
    if magic != EROFS_SUPER_MAGIC_V1 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("Invalid EROFS magic: expected {EROFS_SUPER_MAGIC_V1:#X}, got {magic:#X}"),
        ));
    }

    Ok(())
}

fn resolve_user_home(uid: u32) -> Result<PathBuf, io::Error> {
    let pw = unsafe { getpwuid(uid) };
    if pw.is_null() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("User UID {uid} not found in passwd database"),
        ));
    }
    let raw_home_cstr = unsafe { CStr::from_ptr((*pw).dir) };
    let home_str = raw_home_cstr
        .to_str()
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    Ok(PathBuf::from(home_str))
}

fn sanitize_and_open_image(img_path: &Path, uid: u32) -> Result<Fd, io::Error> {
    let real_path = fs::canonicalize(img_path)?;
    let c_img_path = CString::new(real_path.to_string_lossy().as_bytes())
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;

    let img_fd = Fd::new(unsafe { open(c_img_path.as_ptr(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC) })
        .ok_or_else(io::Error::last_os_error)?;

    let meta = fs::metadata(&real_path)?;

    let img_uid = meta.uid();
    if img_uid != 0 && img_uid != uid {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            format!(
                "Runtime image ownership invalid: owned by UID {img_uid}, must be root (0) or user ({uid})"
            ),
        ));
    }

    if meta.mode() & 0o022 != 0 {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            "Runtime image is group- or world-writable, refusing to mount",
        ));
    }

    validate_erofs_magic(&img_fd)?;
    Ok(img_fd)
}

fn try_direct_fsopen(img_fd: &Fd) -> Result<Fd, io::Error> {
    let c_erofs = CString::new("erofs").unwrap();
    let c_source = CString::new("source").unwrap();
    let c_ro = CString::new("ro").unwrap();

    let fs_fd_raw = unsafe { syscall(SYS_FSOPEN, c_erofs.as_ptr(), FSOPEN_CLOEXEC) };
    let Ok(fd_i32) = i32::try_from(fs_fd_raw) else {
        return Err(io::Error::last_os_error());
    };
    let fs_fd = Fd::new(fd_i32).ok_or_else(io::Error::last_os_error)?;

    let set_ro = unsafe {
        syscall(
            SYS_FSCONFIG,
            fs_fd.raw(),
            FSCONFIG_SET_FLAG,
            c_ro.as_ptr(),
            std::ptr::null::<i8>(),
            0,
        )
    };
    let set_fd = unsafe {
        syscall(
            SYS_FSCONFIG,
            fs_fd.raw(),
            FSCONFIG_SET_FD,
            c_source.as_ptr(),
            std::ptr::null::<i8>(),
            img_fd.raw(),
        )
    };
    let cmd_create = unsafe {
        syscall(
            SYS_FSCONFIG,
            fs_fd.raw(),
            FSCONFIG_CMD_CREATE,
            std::ptr::null::<i8>(),
            std::ptr::null::<i8>(),
            0,
        )
    };

    if set_ro < 0 || set_fd < 0 || cmd_create < 0 {
        return Err(io::Error::last_os_error());
    }

    Ok(fs_fd)
}

fn setup_loop_erofs(img_fd: &Fd) -> Result<Fd, io::Error> {
    let c_erofs = CString::new("erofs").unwrap();
    let c_source = CString::new("source").unwrap();
    let c_ro = CString::new("ro").unwrap();

    let c_loop_ctl = CString::new("/dev/loop-control").unwrap();
    let loop_ctl = Fd::new(unsafe { open(c_loop_ctl.as_ptr(), O_RDWR | O_CLOEXEC) })
        .ok_or_else(io::Error::last_os_error)?;

    let dev_nr = unsafe { ioctl(loop_ctl.raw(), LOOP_CTL_GET_FREE) };
    if dev_nr < 0 {
        return Err(io::Error::last_os_error());
    }

    let loop_name = format!("/dev/loop{dev_nr}");
    let c_loop_name =
        CString::new(loop_name).map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;
    let loop_fd = Fd::new(unsafe { open(c_loop_name.as_ptr(), O_RDONLY | O_CLOEXEC) })
        .ok_or_else(io::Error::last_os_error)?;

    let Ok(u_fd) = u32::try_from(img_fd.raw()) else {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "Invalid img_fd",
        ));
    };

    let mut config: LoopConfig = unsafe { std::mem::zeroed() };
    config.fd = u_fd;
    config.info.flags = LO_FLAGS_AUTOCLEAR | LO_FLAGS_READ_ONLY;

    if unsafe { ioctl(loop_fd.raw(), LOOP_CONFIGURE, &raw const config) } < 0 {
        return Err(io::Error::last_os_error());
    }

    let fs_fd_raw = unsafe { syscall(SYS_FSOPEN, c_erofs.as_ptr(), FSOPEN_CLOEXEC) };
    let Ok(fd_i32) = i32::try_from(fs_fd_raw) else {
        return Err(io::Error::last_os_error());
    };
    let fs_fd = Fd::new(fd_i32).ok_or_else(io::Error::last_os_error)?;

    let set_ro = unsafe {
        syscall(
            SYS_FSCONFIG,
            fs_fd.raw(),
            FSCONFIG_SET_FLAG,
            c_ro.as_ptr(),
            std::ptr::null::<i8>(),
            0,
        )
    };
    let set_src = unsafe {
        syscall(
            SYS_FSCONFIG,
            fs_fd.raw(),
            FSCONFIG_SET_STRING,
            c_source.as_ptr(),
            c_loop_name.as_ptr(),
            0,
        )
    };
    if set_ro < 0 || set_src < 0 {
        return Err(io::Error::last_os_error());
    }

    let mut retries = 5;
    loop {
        let res = unsafe {
            syscall(
                SYS_FSCONFIG,
                fs_fd.raw(),
                FSCONFIG_CMD_CREATE,
                std::ptr::null::<i8>(),
                std::ptr::null::<i8>(),
                0,
            )
        };
        if res >= 0 {
            break;
        }
        let err = io::Error::last_os_error();
        if err.raw_os_error() != Some(libc_ebusy()) || retries == 0 {
            return Err(err);
        }
        retries -= 1;
        std::thread::yield_now();
    }

    Ok(fs_fd)
}

fn create_tree_fd(fs_fd: &Fd) -> Result<Fd, io::Error> {
    let tree_fd_raw = unsafe {
        syscall(
            SYS_FSMOUNT,
            fs_fd.raw(),
            FSMOUNT_CLOEXEC,
            MOUNT_ATTR_RDONLY | MOUNT_ATTR_NOSUID | MOUNT_ATTR_NODEV,
        )
    };
    let Ok(fd_i32) = i32::try_from(tree_fd_raw) else {
        return Err(io::Error::last_os_error());
    };
    Fd::new(fd_i32).ok_or_else(io::Error::last_os_error)
}

fn apply_idmap(tree_fd: &Fd, uid: u32, gid: u32) -> Result<(), io::Error> {
    let userns = create_userns(
        IdMap {
            container_id: 0,
            host_id: uid,
        },
        IdMap {
            container_id: 0,
            host_id: gid,
        },
    )?;

    let Ok(userns_u64) = u64::try_from(userns.raw()) else {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "Invalid userns fd",
        ));
    };

    let attr = CloneMountAttr {
        attr_set: MOUNT_ATTR_IDMAP,
        attr_clr: 0,
        propagation: 0,
        userns_fd: userns_u64,
    };

    let c_empty = CString::new("").unwrap();
    let res = unsafe {
        syscall(
            SYS_MOUNT_SETATTR,
            tree_fd.raw(),
            c_empty.as_ptr(),
            (AT_EMPTY_PATH | AT_RECURSIVE).cast_unsigned(),
            &raw const attr,
            std::mem::size_of::<CloneMountAttr>(),
        )
    };
    if res < 0 {
        return Err(io::Error::last_os_error());
    }

    Ok(())
}

fn mount_runtime(uid: u32, img_path: &Path) -> Result<(), io::Error> {
    let pw = unsafe { getpwuid(uid) };
    let gid = if pw.is_null() {
        100
    } else {
        unsafe { (*pw).gid }
    };

    let target_dir = PathBuf::from(format!("/run/umu/{uid}"));
    let target_dir_str = target_dir.to_string_lossy();
    let c_target = CString::new(target_dir_str.as_bytes())
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;

    let work_dir = PathBuf::from("/run/umu");
    let c_work = CString::new(work_dir.to_string_lossy().as_bytes())
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;

    fs::create_dir_all(&target_dir)?;
    fs::create_dir_all(&work_dir)?;

    let img_fd = sanitize_and_open_image(img_path, uid)?;

    let tmp_path = format!("/run/umu/mnt_{uid}_{}", std::process::id());
    let tmp_path_cstr = CString::new(tmp_path.clone())
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;

    fs::create_dir_all(&tmp_path)?;

    let target_fd = Fd::new(unsafe { open(c_target.as_ptr(), O_PATH | O_DIRECTORY | O_CLOEXEC) })
        .ok_or_else(io::Error::last_os_error)?;
    let work_fd = Fd::new(unsafe { open(c_work.as_ptr(), O_PATH | O_DIRECTORY | O_CLOEXEC) })
        .ok_or_else(io::Error::last_os_error)?;

    let fs_fd = match try_direct_fsopen(&img_fd) {
        Ok(fd) => fd,
        Err(_) => setup_loop_erofs(&img_fd)?,
    };

    let tree_fd = create_tree_fd(&fs_fd)?;
    drop(fs_fd);

    apply_idmap(&tree_fd, uid, gid)?;

    let c_empty = CString::new("").unwrap();
    if unsafe {
        syscall(
            SYS_MOVE_MOUNT,
            tree_fd.raw(),
            c_empty.as_ptr(),
            AT_FDCWD,
            tmp_path_cstr.as_ptr(),
            MOVE_MOUNT_F_EMPTY_PATH,
        )
    } < 0
    {
        let _ = fs::remove_dir(&tmp_path);
        return Err(io::Error::last_os_error());
    }

    let target_name = format!("{uid}");
    let c_target_name =
        CString::new(target_name).map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;

    let tmp_name = format!("mnt_{uid}_{}", std::process::id());
    let c_tmp_name =
        CString::new(tmp_name).map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;

    let res = unsafe {
        renameat2(
            work_fd.raw(),
            c_tmp_name.as_ptr(),
            work_fd.raw(),
            c_target_name.as_ptr(),
            RENAME_EXCHANGE,
        )
    };

    if res < 0 {
        let _ = unsafe { unlinkat(work_fd.raw(), c_tmp_name.as_ptr(), 0x200) };
        return Err(io::Error::last_os_error());
    }

    let _ = unsafe { unlinkat(work_fd.raw(), c_tmp_name.as_ptr(), 0x200) };
    drop(target_fd);
    drop(work_fd);

    println!("Runtime mounted successfully for UID {uid} at {target_dir_str}");
    Ok(())
}

fn print_usage(prog_name: &str) {
    eprintln!("Usage: {prog_name} <UID> [path/to/runtime.img]");
    eprintln!("Secure mount helper for UMU read-only EROFS runtime image with ID mapping.");
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let prog_name = args.first().map_or("mount-umu", String::as_str);

    if args.len() < 2 {
        print_usage(prog_name);
        std::process::exit(1);
    }

    let Ok(uid) = args[1].parse::<u32>() else {
        eprintln!("Error: Invalid UID '{}'", args[1]);
        std::process::exit(1);
    };

    let img_path = if args.len() >= 3 {
        PathBuf::from(&args[2])
    } else {
        match resolve_user_home(uid) {
            Ok(home) => home.join(".local/share/umu/runtime.img"),
            Err(e) => {
                eprintln!("Error: Could not resolve home directory for UID {uid}: {e}");
                std::process::exit(1);
            }
        }
    };

    if !img_path.exists() {
        eprintln!("Error: Image not found at {}", img_path.display());
        std::process::exit(1);
    }

    if let Err(e) = mount_runtime(uid, &img_path) {
        eprintln!("Error mounting runtime image for UID {uid}: {e}");
        std::process::exit(1);
    }
}
