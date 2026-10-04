#![forbid(unsafe_op_in_unsafe_fn)]
#![allow(
    clippy::too_many_lines,
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss,
    clippy::cast_lossless,
    clippy::cast_possible_wrap
)]

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
const MOUNT_ATTR_RDONLY: u64 = 0x0000_0001;
const MOUNT_ATTR_NOSUID: u64 = 0x0000_0002;
const MOUNT_ATTR_NODEV: u64 = 0x0000_0004;
const MOUNT_ATTR_IDMAP: u64 = 0x0010_0000;

const MOVE_MOUNT_F_EMPTY_PATH: u32 = 0x0000_0004;
const AT_EMPTY_PATH: i32 = 0x1000;
const AT_RECURSIVE: i32 = 0x8000;
const AT_FDCWD: i32 = -100;

// Mount flags
const MS_NOSUID: u64 = 2;
const MS_NODEV: u64 = 4;
const MNT_DETACH: i32 = 2;

// Open flags
const O_RDONLY: i32 = 0;
const O_RDWR: i32 = 2;
const O_DIRECTORY: i32 = 0o200_000;
const O_CLOEXEC: i32 = 0o2_000_000;
const O_PATH: i32 = 0o10_000_000;

// Loop device ioctls
const LOOP_CTL_GET_FREE: u64 = 0x4C82;
const LOOP_CONFIGURE: u64 = 0x4C0A;
const LO_FLAGS_READ_ONLY: u32 = 1;
const LO_FLAGS_AUTOCLEAR: u32 = 4;

const CLONE_NEWUSER: i32 = 0x1000_0000;
const SIGKILL: i32 = 9;

// EROFS superblock magic at offset 1024
const EROFS_SUPER_MAGIC: u32 = 0xE0F5_E1E2;
const EROFS_SUPER_OFFSET: u64 = 1024;

#[repr(C)]
struct CloneMountAttr {
    attr_set: u64,
    attr_clr: u64,
    propagation: u64,
    userns_fd: u64,
}

#[repr(C)]
#[allow(clippy::struct_field_names)]
struct LoopInfo64 {
    lo_device: u64,
    lo_inode: u64,
    lo_rdevice: u64,
    lo_offset: u64,
    lo_sizelimit: u64,
    lo_number: u32,
    lo_encrypt_type: u32,
    lo_encrypt_key_size: u32,
    lo_flags: u32,
    lo_file_name: [u8; 64],
    lo_crypt_name: [u8; 64],
    lo_encrypt_key: [u8; 32],
    lo_init: [u64; 2],
}

#[repr(C)]
struct LoopConfig {
    fd: u32,
    block_size: u32,
    info: LoopInfo64,
    __reserved: [u64; 8],
}

#[repr(C)]
#[allow(clippy::struct_field_names)]
struct Passwd {
    pw_name: *mut i8,
    pw_passwd: *mut i8,
    pw_uid: u32,
    pw_gid: u32,
    pw_gecos: *mut i8,
    pw_dir: *mut i8,
    pw_shell: *mut i8,
}

unsafe extern "C" {
    fn syscall(number: i64, ...) -> i64;
    fn mount(
        special: *const i8,
        dir: *const i8,
        fstype: *const i8,
        flags: u64,
        data: *const i8,
    ) -> i32;
    fn umount2(special: *const i8, flags: i32) -> i32;
    fn ioctl(fd: i32, request: u64, ...) -> i32;
    fn open(path: *const i8, flags: i32, ...) -> i32;
    fn close(fd: i32) -> i32;
    fn mkdtemp(template: *mut i8) -> *mut i8;
    fn rmdir(path: *const i8) -> i32;
    fn mkdir(path: *const i8, mode: u32) -> i32;
    fn chown(path: *const i8, owner: u32, group: u32) -> i32;
    fn fork() -> i32;
    fn pipe(pipefd: *mut i32) -> i32;
    fn unshare(flags: i32) -> i32;
    fn pause() -> i32;
    fn kill(pid: i32, sig: i32) -> i32;
    fn waitpid(pid: i32, status: *mut i32, options: i32) -> i32;
    fn read(fd: i32, buf: *mut u8, count: usize) -> isize;
    fn pread(fd: i32, buf: *mut u8, count: usize, offset: i64) -> isize;
    fn write(fd: i32, buf: *const u8, count: usize) -> isize;
    fn getpwuid(uid: u32) -> *mut Passwd;
    fn exit(status: i32) -> !;
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
        if self.0 >= 0 {
            unsafe { close(self.0) };
        }
    }
}

fn write_id_map(pid: i32, file: &str, id1: u32, id2: u32) -> Result<(), io::Error> {
    let path = format!("/proc/{pid}/{file}");
    let (min_id, max_id) = if id1 > id2 { (id2, id1) } else { (id1, id2) };
    let mut map = String::with_capacity(256);

    if min_id == max_id {
        map.push_str("0 0 4294967294\n");
    } else {
        if min_id > 0 {
            let _ = writeln!(map, "0 0 {min_id}");
        }
        let _ = writeln!(map, "{min_id} {max_id} 1");
        if max_id > min_id + 1 {
            let count = max_id - min_id - 1;
            let _ = writeln!(map, "{} {} {count}", min_id + 1, min_id + 1);
        }
        let _ = writeln!(map, "{max_id} {min_id} 1");
        if max_id < 4_294_967_293 {
            let next = max_id + 1;
            let count = 4_294_967_294 - max_id;
            let _ = writeln!(map, "{next} {next} {count}");
        }
    }

    fs::write(&path, map)
}

#[allow(clippy::similar_names)]
fn create_userns(
    inside_uid: u32,
    target_uid: u32,
    inside_gid: u32,
    target_gid: u32,
) -> Result<Fd, io::Error> {
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
        unsafe {
            close(pipefd[0]);
            if unshare(CLONE_NEWUSER) != 0 || write(pipefd[1], b"1".as_ptr(), 1) != 1 {
                exit(1);
            }
            close(pipefd[1]);
            pause();
            exit(0);
        }
    }

    unsafe { close(pipefd[1]) };

    let mut sync_byte = [0u8; 1];
    let n = unsafe { read(pipefd[0], sync_byte.as_mut_ptr(), 1) };
    unsafe { close(pipefd[0]) };

    if n <= 0 {
        unsafe {
            kill(pid, SIGKILL);
            waitpid(pid, std::ptr::null_mut(), 0);
        }
        return Err(io::Error::other("userns child sync failed"));
    }

    if let Err(e) = write_id_map(pid, "uid_map", inside_uid, target_uid) {
        unsafe {
            kill(pid, SIGKILL);
            waitpid(pid, std::ptr::null_mut(), 0);
        }
        return Err(e);
    }

    let setgroups_path = format!("/proc/{pid}/setgroups");
    let _ = fs::write(setgroups_path, b"deny\n");

    if let Err(e) = write_id_map(pid, "gid_map", inside_gid, target_gid) {
        unsafe {
            kill(pid, SIGKILL);
            waitpid(pid, std::ptr::null_mut(), 0);
        }
        return Err(e);
    }

    let ns_path = CString::new(format!("/proc/{pid}/ns/user"))
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;
    let userns_raw = unsafe { open(ns_path.as_ptr(), O_RDONLY | O_CLOEXEC) };

    unsafe {
        kill(pid, SIGKILL);
        waitpid(pid, std::ptr::null_mut(), 0);
    }

    Fd::new(userns_raw).ok_or_else(io::Error::last_os_error)
}

fn sanitize_and_open_image(path: &Path, target_uid: u32) -> Result<Fd, io::Error> {
    let c_path = CString::new(path.to_str().ok_or_else(|| {
        io::Error::new(io::ErrorKind::InvalidInput, "Invalid unicode in image path")
    })?)
    .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;

    let img_fd = Fd::new(unsafe { open(c_path.as_ptr(), O_RDONLY | O_CLOEXEC) })
        .ok_or_else(io::Error::last_os_error)?;

    // Stat the open file descriptor via /proc/self/fd to prevent TOCTOU symlink races
    let metadata = fs::metadata(format!("/proc/self/fd/{}", img_fd.raw()))?;
    if !metadata.is_file() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "Runtime image is not a regular file",
        ));
    }

    // Security check: Image must be owned by root (Nix store) or target user
    let owner_uid = metadata.uid();
    if owner_uid != 0 && owner_uid != target_uid {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            format!(
                "Image owner UID {owner_uid} does not match root (0) or target user ({target_uid})"
            ),
        ));
    }

    // Security check: Image must not be world-writable
    let mode = metadata.mode();
    if mode & 0o002 != 0 {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            "Runtime image must not be world-writable",
        ));
    }

    // Validate EROFS superblock magic at offset 1024
    let mut magic_buf = [0u8; 4];
    let n = unsafe {
        pread(
            img_fd.raw(),
            magic_buf.as_mut_ptr(),
            4,
            EROFS_SUPER_OFFSET as i64,
        )
    };
    if n != 4 {
        return Err(io::Error::new(
            io::ErrorKind::UnexpectedEof,
            "Failed to read EROFS superblock",
        ));
    }

    let magic = u32::from_le_bytes(magic_buf);
    if magic != EROFS_SUPER_MAGIC {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("Invalid EROFS magic: expected 0x{EROFS_SUPER_MAGIC:08X}, got 0x{magic:08X}"),
        ));
    }

    Ok(img_fd)
}

fn resolve_default_image_path(uid: u32) -> Result<PathBuf, io::Error> {
    let pw = unsafe { getpwuid(uid) };
    if pw.is_null() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("User with UID {uid} not found"),
        ));
    }

    let home_dir_cstr = unsafe { CStr::from_ptr((*pw).pw_dir) };
    let home_dir = home_dir_cstr.to_str().map_err(|e| {
        io::Error::new(io::ErrorKind::InvalidData, format!("Invalid home dir: {e}"))
    })?;

    let p = PathBuf::from(home_dir).join(".local/share/umu/runtime.img");
    // Canonicalize if exists, resolving symlinks pointing to /nix/store
    if p.exists() {
        fs::canonicalize(p)
    } else {
        Ok(p)
    }
}

fn unmount_target(uid: u32) -> Result<(), io::Error> {
    let target = format!("/run/umu/{uid}");
    let c_target =
        CString::new(target.clone()).map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;

    let ret = unsafe { umount2(c_target.as_ptr(), MNT_DETACH) };
    if ret != 0 {
        let err = io::Error::last_os_error();
        // Ignore ENOENT (2) or EINVAL (22 - not a mount point)
        let raw = err.raw_os_error();
        if raw != Some(2) && raw != Some(22) {
            return Err(err);
        }
    }
    unsafe { rmdir(c_target.as_ptr()) };
    println!("Successfully unmounted {target}");
    Ok(())
}

struct StagingGuard<'a> {
    upper: &'a CStr,
    tmp: &'a CStr,
    active: bool,
}

impl Drop for StagingGuard<'_> {
    fn drop(&mut self) {
        if self.active {
            unsafe {
                umount2(self.tmp.as_ptr(), MNT_DETACH);
                umount2(self.upper.as_ptr(), MNT_DETACH);
                rmdir(self.tmp.as_ptr());
                rmdir(self.upper.as_ptr());
            }
        }
    }
}

fn mount_runtime(uid: u32, img_path: &Path) -> Result<(), io::Error> {
    let pw = unsafe { getpwuid(uid) };
    let gid = if pw.is_null() {
        uid
    } else {
        unsafe { (*pw).pw_gid }
    };

    let target_dir = format!("/run/umu/{uid}");
    let c_target_dir = CString::new(target_dir.clone())
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;

    // Detach any previous stale mount on target
    unsafe {
        let check_fd = open(c_target_dir.as_ptr(), O_PATH | O_DIRECTORY | O_CLOEXEC);
        if check_fd >= 0 {
            close(check_fd);
            umount2(c_target_dir.as_ptr(), MNT_DETACH);
        }
    }

    let c_base = CString::new("/run/umu").unwrap();
    unsafe {
        mkdir(c_base.as_ptr(), 0o755);
        mkdir(c_target_dir.as_ptr(), 0o700);
        chown(c_target_dir.as_ptr(), uid, gid);
    }

    let target_fd =
        Fd::new(unsafe { open(c_target_dir.as_ptr(), O_PATH | O_DIRECTORY | O_CLOEXEC) })
            .ok_or_else(io::Error::last_os_error)?;

    // Create temporary staging directories
    let mut upper_tmp_bytes = b"/run/umu/.up-XXXXXX\0".to_vec();
    let mut tmp_path_bytes = b"/run/umu/.tmp-XXXXXX\0".to_vec();

    if unsafe { mkdtemp(upper_tmp_bytes.as_mut_ptr().cast()).is_null() } {
        return Err(io::Error::last_os_error());
    }
    if unsafe { mkdtemp(tmp_path_bytes.as_mut_ptr().cast()).is_null() } {
        unsafe { rmdir(upper_tmp_bytes.as_ptr().cast()) };
        return Err(io::Error::last_os_error());
    }

    let upper_tmp_cstr = unsafe { CStr::from_ptr(upper_tmp_bytes.as_ptr().cast()) };
    let tmp_path_cstr = unsafe { CStr::from_ptr(tmp_path_bytes.as_ptr().cast()) };

    let mut guard = StagingGuard {
        upper: upper_tmp_cstr,
        tmp: tmp_path_cstr,
        active: true,
    };

    // Mount tmpfs for upper/workdir
    let mount_opts = CString::new(format!("mode=0700,uid={uid},gid={gid}"))
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;
    let c_tmpfs = CString::new("tmpfs").unwrap();
    if unsafe {
        mount(
            c_tmpfs.as_ptr(),
            upper_tmp_cstr.as_ptr(),
            c_tmpfs.as_ptr(),
            MS_NODEV | MS_NOSUID,
            mount_opts.as_ptr(),
        )
    } != 0
    {
        return Err(io::Error::last_os_error());
    }

    let upper_path = format!("{}/upper", upper_tmp_cstr.to_str().unwrap());
    let work_path = format!("{}/work", upper_tmp_cstr.to_str().unwrap());
    let c_upper =
        CString::new(upper_path).map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;
    let c_work =
        CString::new(work_path).map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;

    unsafe {
        mkdir(c_upper.as_ptr(), 0o700);
        chown(c_upper.as_ptr(), uid, gid);
        mkdir(c_work.as_ptr(), 0o700);
        chown(c_work.as_ptr(), uid, gid);
    }

    let upper_fd = Fd::new(unsafe { open(c_upper.as_ptr(), O_PATH | O_DIRECTORY | O_CLOEXEC) })
        .ok_or_else(io::Error::last_os_error)?;
    let work_fd = Fd::new(unsafe { open(c_work.as_ptr(), O_PATH | O_DIRECTORY | O_CLOEXEC) })
        .ok_or_else(io::Error::last_os_error)?;

    // Open and validate image
    let img_fd = sanitize_and_open_image(img_path, uid)?;

    // Attempt direct fd mount with modern kernel fsopen API
    let c_erofs = CString::new("erofs").unwrap();
    let c_source = CString::new("source").unwrap();
    let c_ro = CString::new("ro").unwrap();

    let mut fs_fd_raw = unsafe { syscall(SYS_FSOPEN, c_erofs.as_ptr(), FSOPEN_CLOEXEC) as i32 };
    let mut needs_loop = fs_fd_raw < 0;

    if !needs_loop {
        let set_ro = unsafe {
            syscall(
                SYS_FSCONFIG,
                fs_fd_raw,
                FSCONFIG_SET_FLAG,
                c_ro.as_ptr(),
                std::ptr::null::<i8>(),
                0,
            )
        };
        let set_fd = unsafe {
            syscall(
                SYS_FSCONFIG,
                fs_fd_raw,
                FSCONFIG_SET_FD,
                c_source.as_ptr(),
                std::ptr::null::<i8>(),
                img_fd.raw(),
            )
        };
        let cmd_create = unsafe {
            syscall(
                SYS_FSCONFIG,
                fs_fd_raw,
                FSCONFIG_CMD_CREATE,
                std::ptr::null::<i8>(),
                std::ptr::null::<i8>(),
                0,
            )
        };

        if set_ro < 0 || set_fd < 0 || cmd_create < 0 {
            needs_loop = true;
        }
    }

    if needs_loop {
        if fs_fd_raw >= 0 {
            unsafe { close(fs_fd_raw) };
        }

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

        let mut config: LoopConfig = unsafe { std::mem::zeroed() };
        config.fd = img_fd.raw() as u32;
        config.info.lo_flags = LO_FLAGS_AUTOCLEAR | LO_FLAGS_READ_ONLY;

        if unsafe { ioctl(loop_fd.raw(), LOOP_CONFIGURE, &raw const config) } < 0 {
            return Err(io::Error::last_os_error());
        }

        fs_fd_raw = unsafe { syscall(SYS_FSOPEN, c_erofs.as_ptr(), FSOPEN_CLOEXEC) as i32 };
        if fs_fd_raw < 0 {
            return Err(io::Error::last_os_error());
        }

        let set_ro = unsafe {
            syscall(
                SYS_FSCONFIG,
                fs_fd_raw,
                FSCONFIG_SET_FLAG,
                c_ro.as_ptr(),
                std::ptr::null::<i8>(),
                0,
            )
        };
        let set_src = unsafe {
            syscall(
                SYS_FSCONFIG,
                fs_fd_raw,
                FSCONFIG_SET_STRING,
                c_source.as_ptr(),
                c_loop_name.as_ptr(),
                0,
            )
        };
        if set_ro < 0 || set_src < 0 {
            unsafe { close(fs_fd_raw) };
            return Err(io::Error::last_os_error());
        }

        let mut retries = 5;
        loop {
            let res = unsafe {
                syscall(
                    SYS_FSCONFIG,
                    fs_fd_raw,
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
    }

    let fs_fd = Fd::new(fs_fd_raw).ok_or_else(io::Error::last_os_error)?;

    let tree_fd_raw = unsafe {
        syscall(
            SYS_FSMOUNT,
            fs_fd.raw(),
            FSMOUNT_CLOEXEC,
            MOUNT_ATTR_RDONLY | MOUNT_ATTR_NOSUID | MOUNT_ATTR_NODEV,
        ) as i32
    };
    drop(fs_fd);

    let tree_fd = Fd::new(tree_fd_raw).ok_or_else(io::Error::last_os_error)?;

    // Set up ID-mapping: map image UID 0 to target user UID
    let userns = create_userns(0, uid, 0, gid)?;
    let attr = CloneMountAttr {
        attr_set: MOUNT_ATTR_IDMAP,
        attr_clr: 0,
        propagation: 0,
        userns_fd: userns.raw() as u64,
    };
    let c_empty = CString::new("").unwrap();
    let res = unsafe {
        syscall(
            SYS_MOUNT_SETATTR,
            tree_fd.raw(),
            c_empty.as_ptr(),
            (AT_EMPTY_PATH | AT_RECURSIVE) as u32,
            &raw const attr,
            std::mem::size_of::<CloneMountAttr>(),
        )
    };
    if res < 0 {
        return Err(io::Error::last_os_error());
    }

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
    } != 0
    {
        return Err(io::Error::last_os_error());
    }
    drop(tree_fd);

    let opts = CString::new(format!(
        "lowerdir={},upperdir=/proc/self/fd/{},workdir=/proc/self/fd/{},index=on,metacopy=on,redirect_dir=on",
        tmp_path_cstr.to_str().unwrap(),
        upper_fd.raw(),
        work_fd.raw()
    ))
    .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;

    let target_proc = CString::new(format!("/proc/self/fd/{}", target_fd.raw()))
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;
    let c_overlay = CString::new("overlay").unwrap();

    let ret = unsafe {
        mount(
            c_overlay.as_ptr(),
            target_proc.as_ptr(),
            c_overlay.as_ptr(),
            MS_NOSUID | MS_NODEV,
            opts.as_ptr(),
        )
    };
    if ret != 0 {
        return Err(io::Error::last_os_error());
    }

    // Ephemeral Detach: Unlink temporary lower & upper mounts from VFS namespace
    unsafe {
        umount2(tmp_path_cstr.as_ptr(), MNT_DETACH);
        umount2(upper_tmp_cstr.as_ptr(), MNT_DETACH);
        rmdir(tmp_path_cstr.as_ptr());
        rmdir(upper_tmp_cstr.as_ptr());
    }

    // Mark guard inactive since cleanup succeeded normally
    guard.active = false;

    println!("Successfully mounted UMU runtime overlay at {target_dir}");
    Ok(())
}

const fn libc_ebusy() -> i32 {
    16 // EBUSY on Linux
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: mount-umu [-u] <uid> [img_path]");
        std::process::exit(1);
    }

    if args[1] == "-u" || args[1] == "--unmount" {
        if args.len() < 3 {
            eprintln!("Usage: mount-umu -u <uid>");
            std::process::exit(1);
        }
        let Ok(uid) = args[2].parse::<u32>() else {
            eprintln!("Invalid UID: {}", args[2]);
            std::process::exit(1);
        };
        if let Err(e) = unmount_target(uid) {
            eprintln!("Failed to unmount: {e}");
            std::process::exit(1);
        }
        return;
    }

    let Ok(uid) = args[1].parse::<u32>() else {
        eprintln!("Invalid UID: {}", args[1]);
        std::process::exit(1);
    };

    let img_path = if args.len() >= 3 {
        PathBuf::from(&args[2])
    } else {
        match resolve_default_image_path(uid) {
            Ok(p) => p,
            Err(e) => {
                eprintln!("Could not determine default image path: {e}");
                std::process::exit(1);
            }
        }
    };

    if !img_path.exists() {
        eprintln!("Image file does not exist: {}", img_path.display());
        std::process::exit(1);
    }

    if let Err(e) = mount_runtime(uid, &img_path) {
        eprintln!("Failed to mount UMU runtime overlay: {e}");
        std::process::exit(1);
    }
}
