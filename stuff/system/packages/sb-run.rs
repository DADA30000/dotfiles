use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::env;
use std::ffi::{CString, c_void};
use std::fmt::Write as _;
use std::fs;
use std::io::{Read, Write};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::io::{AsRawFd, FromRawFd, IntoRawFd, OwnedFd, RawFd};
use std::os::unix::net::{UnixListener, UnixStream};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio, exit};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

const IPC_MAGIC: [u8; 4] = *b"SBEX";
const IPC_VERSION: u16 = 1;

const MSG_EXEC_REQUEST: u16 = 1;
const MSG_WINSIZE: u16 = 2;
const MSG_SIGNAL: u16 = 3;
const MSG_EXIT_RESPONSE: u16 = 4;

const FLAG_WAIT_EXIT: u32 = 1 << 0;
const FLAG_IS_TTY: u32 = 1 << 1;
const FLAG_HELPER: u32 = 1 << 2;
const FLAG_SECCOMP: u32 = 1 << 3;

const SOL_SOCKET: i32 = 1;
const SCM_RIGHTS: i32 = 1;

const SUBSYS_GPU: u32 = 1 << 0;
const SUBSYS_GAMEPAD: u32 = 1 << 1;

const CFG_TMPFS: u32 = 1 << 0;
const CFG_DBUS: u32 = 1 << 1;
const CFG_SHARE_PID: u32 = 1 << 2;
const CFG_IS_CLI: u32 = 1 << 3;
const CFG_LANDLOCK: u32 = 1 << 4;
const CFG_SHARE_IPC: u32 = 1 << 5;
const CFG_PORTALS: u32 = 1 << 6;
const CFG_USE_VPNIFY: u32 = 1 << 7;
const CFG_SYSTEM_DBUS: u32 = 1 << 8;
const CFG_FLATPAK_INFO: u32 = 1 << 9;
const CFG_SCOPE: u32 = 1 << 10;
const CFG_SECCOMP: u32 = 1 << 11;
const CFG_EDIT_SINGBOX: u32 = 1 << 12;
const CFG_SECCOMP_LIST: u32 = 1 << 13;
const CFG_EDIT_SECCOMP: u32 = 1 << 14;
const CFG_HELPER_REQ: u32 = 1 << 15;
const CFG_VERBOSE: u32 = 1 << 16;

const TIOCGWINSZ: usize = 0x5413;
const SYS_PIDFD_OPEN: i64 = 434;
const SO_PEERCRED: i32 = 17;
const EPOLL_CTL_ADD: i32 = 1;
const EPOLL_CTL_DEL: i32 = 2;
const EPOLLIN: u32 = 1;
const EPOLLPRI: u32 = 0x0002;
const EPOLLERR: u32 = 0x0008;
const EPOLLHUP: u32 = 0x0010;

const AUDIT_ARCH_I386: u32 = 0x4000_0003;
const AUDIT_ARCH_X86_64: u32 = 0xC000_003E;

const BPF_LD: u16 = 0x00;
const BPF_JMP: u16 = 0x05;
const BPF_RET: u16 = 0x06;
const BPF_W: u16 = 0x00;
const BPF_ABS: u16 = 0x20;
const BPF_K: u16 = 0x00;
const BPF_JA: u16 = 0x00;
const BPF_JEQ: u16 = 0x10;
const BPF_JGT: u16 = 0x20;
const BPF_JGE: u16 = 0x30;
const BPF_JSET: u16 = 0x40;

const SECCOMP_RET_KILL_PROCESS: u32 = 0x8000_0000;
const SECCOMP_RET_TRAP: u32 = 0x0003_0000;
const SECCOMP_RET_ERRNO: u32 = 0x0005_0000;
const SECCOMP_RET_USER_NOTIF: u32 = 0x7FC0_0000;
const SECCOMP_RET_ALLOW: u32 = 0x7FFF_0000;

const SECCOMP_IOCTL_NOTIF_RECV: usize = 0xC050_2100;
const SECCOMP_IOCTL_NOTIF_SEND: usize = 0xC018_2101;

static PENDING_SIGNAL: AtomicI32 = AtomicI32::new(0);
static PENDING_WINCH: AtomicI32 = AtomicI32::new(0);

extern "C" fn forward_sig_handler(sig: i32) {
    if sig == 28 {
        PENDING_WINCH.store(1, Ordering::Relaxed);
    } else {
        PENDING_SIGNAL.store(sig, Ordering::Relaxed);
    }
}

fn fail_exit(msg: &str) -> ! {
    eprintln!("[sb-run] Error: {msg}");
    exit(1);
}

// ---------------------------------------------------------------------------
// Minimal Zero-Dependency JSON Parser & Merger
// ---------------------------------------------------------------------------

#[derive(Clone, Debug)]
enum JsonValue {
    Null,
    Bool(bool),
    Int(i64),
    Str(String),
    Array(Vec<Self>),
    Object(BTreeMap<String, Self>),
}

struct JsonParser<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl<'a> JsonParser<'a> {
    const fn new(src: &'a str) -> Self {
        Self {
            bytes: src.as_bytes(),
            pos: 0,
        }
    }

    const fn skip_ws(&mut self) {
        while self.pos < self.bytes.len() && self.bytes[self.pos].is_ascii_whitespace() {
            self.pos += 1;
        }
    }

    fn peek(&mut self) -> Option<u8> {
        self.skip_ws();
        self.bytes.get(self.pos).copied()
    }

    fn expect(&mut self, ch: u8) -> Result<(), String> {
        self.skip_ws();
        if self.bytes.get(self.pos) == Some(&ch) {
            self.pos += 1;
            Ok(())
        } else {
            Err(format!("expected '{}' at offset {}", ch as char, self.pos))
        }
    }

    fn parse_string(&mut self) -> Result<String, String> {
        self.expect(b'"')?;
        let mut out = String::new();
        while self.pos < self.bytes.len() {
            let b = self.bytes[self.pos];
            self.pos += 1;
            if b == b'"' {
                return Ok(out);
            }
            if b == b'\\' {
                let esc = *self
                    .bytes
                    .get(self.pos)
                    .ok_or_else(|| "unterminated escape".to_string())?;
                self.pos += 1;
                match esc {
                    b'"' => out.push('"'),
                    b'\\' => out.push('\\'),
                    b'/' => out.push('/'),
                    b'b' => out.push('\u{0008}'),
                    b'f' => out.push('\u{000c}'),
                    b'n' => out.push('\n'),
                    b'r' => out.push('\r'),
                    b't' => out.push('\t'),
                    b'u' => {
                        if self.pos + 4 > self.bytes.len() {
                            return Err("short unicode escape".into());
                        }
                        let hex = std::str::from_utf8(&self.bytes[self.pos..self.pos + 4])
                            .map_err(|_| "invalid utf8 in escape".to_string())?;
                        let code = u32::from_str_radix(hex, 16)
                            .map_err(|_| "invalid hex in escape".to_string())?;
                        let ch = char::from_u32(code).unwrap_or('\u{FFFD}');
                        out.push(ch);
                        self.pos += 4;
                    }
                    other => out.push(other as char),
                }
            } else {
                let start = self.pos - 1;
                while self.pos < self.bytes.len()
                    && self.bytes[self.pos] != b'"'
                    && self.bytes[self.pos] != b'\\'
                {
                    self.pos += 1;
                }
                let seg = std::str::from_utf8(&self.bytes[start..self.pos])
                    .map_err(|_| "invalid utf8 in json string".to_string())?;
                out.push_str(seg);
            }
        }
        Err("unterminated string".into())
    }

    fn parse_number(&mut self) -> Result<JsonValue, String> {
        self.skip_ws();
        let start = self.pos;
        if self.bytes.get(self.pos) == Some(&b'-') {
            self.pos += 1;
        }
        while self.pos < self.bytes.len()
            && (self.bytes[self.pos].is_ascii_digit()
                || matches!(self.bytes[self.pos], b'.' | b'e' | b'E' | b'+' | b'-'))
        {
            self.pos += 1;
        }
        let s = std::str::from_utf8(&self.bytes[start..self.pos])
            .map_err(|_| "invalid number".to_string())?;
        s.parse::<i64>().map_or_else(
            |_| {
                if s.parse::<f64>().is_ok() {
                    Ok(JsonValue::Int(0))
                } else {
                    Err(format!("invalid number '{s}'"))
                }
            },
            |n| Ok(JsonValue::Int(n)),
        )
    }

    fn parse_value(&mut self) -> Result<JsonValue, String> {
        match self.peek() {
            Some(b'{') => self.parse_object(),
            Some(b'[') => self.parse_array(),
            Some(b'"') => self.parse_string().map(JsonValue::Str),
            Some(b't') if self.bytes[self.pos..].starts_with(b"true") => {
                self.pos += 4;
                Ok(JsonValue::Bool(true))
            }
            Some(b'f') if self.bytes[self.pos..].starts_with(b"false") => {
                self.pos += 5;
                Ok(JsonValue::Bool(false))
            }
            Some(b'n') if self.bytes[self.pos..].starts_with(b"null") => {
                self.pos += 4;
                Ok(JsonValue::Null)
            }
            Some(b'-' | b'0'..=b'9') => self.parse_number(),
            Some(c) => Err(format!("unexpected char '{}' at {}", c as char, self.pos)),
            None => Err("unexpected end of JSON".into()),
        }
    }

    fn parse_array(&mut self) -> Result<JsonValue, String> {
        self.expect(b'[')?;
        let mut arr = Vec::new();
        if self.peek() == Some(b']') {
            self.pos += 1;
            return Ok(JsonValue::Array(arr));
        }
        loop {
            arr.push(self.parse_value()?);
            match self.peek() {
                Some(b',') => self.pos += 1,
                Some(b']') => {
                    self.pos += 1;
                    return Ok(JsonValue::Array(arr));
                }
                _ => return Err("expected ',' or ']' in array".into()),
            }
        }
    }

    fn parse_object(&mut self) -> Result<JsonValue, String> {
        self.expect(b'{')?;
        let mut map = BTreeMap::new();
        if self.peek() == Some(b'}') {
            self.pos += 1;
            return Ok(JsonValue::Object(map));
        }
        loop {
            let key = self.parse_string()?;
            self.expect(b':')?;
            let val = self.parse_value()?;
            map.insert(key, val);
            match self.peek() {
                Some(b',') => self.pos += 1,
                Some(b'}') => {
                    self.pos += 1;
                    return Ok(JsonValue::Object(map));
                }
                _ => return Err("expected ',' or '}' in object".into()),
            }
        }
    }
}

fn parse_json(src: &str) -> Result<JsonValue, String> {
    let mut p = JsonParser::new(src);
    let val = p.parse_value()?;
    if p.peek().is_some() {
        return Err(format!("trailing bytes at offset {}", p.pos));
    }
    Ok(val)
}

impl JsonValue {
    fn as_obj(&self, ctx: &str) -> &BTreeMap<String, Self> {
        match self {
            Self::Object(m) => m,
            _ => fail_exit(&format!("config field '{ctx}' must be an object")),
        }
    }

    fn get_req(&self, key: &str, ctx: &str) -> &Self {
        self.as_obj(ctx)
            .get(key)
            .unwrap_or_else(|| fail_exit(&format!("missing required config key '{ctx}.{key}'")))
    }

    fn opt_str(&self, key: &str, ctx: &str) -> Option<String> {
        self.as_obj(ctx).get(key).map(|v| match v {
            Self::Str(s) => s.clone(),
            _ => fail_exit(&format!("config field '{ctx}.{key}' must be a string")),
        })
    }

    fn opt_bool(&self, key: &str, ctx: &str) -> Option<bool> {
        self.as_obj(ctx).get(key).map(|v| match v {
            Self::Bool(b) => *b,
            _ => fail_exit(&format!("config field '{ctx}.{key}' must be a boolean")),
        })
    }

    fn opt_str_list(&self, key: &str, ctx: &str) -> Vec<String> {
        self.as_obj(ctx)
            .get(key)
            .map_or_else(Vec::new, |v| match v {
                Self::Array(arr) => arr
                    .iter()
                    .map(|item| match item {
                        Self::Str(s) => s.clone(),
                        _ => fail_exit(&format!("non-string item in '{ctx}.{key}'")),
                    })
                    .collect(),
                _ => fail_exit(&format!("config field '{ctx}.{key}' must be an array")),
            })
    }
}

// ---------------------------------------------------------------------------
// Configuration Modes, Seccomp Policy Types & Single-Source Loader
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum WebcamMode {
    Off,
    Portal,
    Auto,
}

impl WebcamMode {
    fn parse(s: &str) -> Self {
        match s {
            "auto" => Self::Auto,
            "portal" => Self::Portal,
            "off" => Self::Off,
            other => fail_exit(&format!(
                "invalid webcam mode '{other}' (expected: off, portal, auto)"
            )),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum MicMode {
    Off,
    Portal,
    Allow,
}

impl MicMode {
    fn parse(s: &str) -> Self {
        match s {
            "off" => Self::Off,
            "portal" => Self::Portal,
            "allow" => Self::Allow,
            other => fail_exit(&format!(
                "invalid microphone mode '{other}' (expected: off, portal, allow)"
            )),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
enum SeccompAction {
    Eperm,
    Enosys,
    Eacces,
    Einval,
    Enotsup,
    Kill,
    Trap,
}

impl SeccompAction {
    fn parse(s: &str) -> Self {
        match s {
            "eperm" => Self::Eperm,
            "enosys" => Self::Enosys,
            "eacces" => Self::Eacces,
            "einval" => Self::Einval,
            "enotsup" => Self::Enotsup,
            "kill" => Self::Kill,
            "trap" => Self::Trap,
            other => fail_exit(&format!(
                "invalid seccomp action '{other}' (expected: eperm, enosys, eacces, einval, enotsup, kill, trap)"
            )),
        }
    }

    const fn as_str(self) -> &'static str {
        match self {
            Self::Eperm => "eperm",
            Self::Enosys => "enosys",
            Self::Eacces => "eacces",
            Self::Einval => "einval",
            Self::Enotsup => "enotsup",
            Self::Kill => "kill",
            Self::Trap => "trap",
        }
    }

    const fn errno(self) -> Option<i32> {
        match self {
            Self::Eperm => Some(1),
            Self::Eacces => Some(13),
            Self::Einval => Some(22),
            Self::Enosys => Some(38),
            Self::Enotsup => Some(95),
            Self::Kill | Self::Trap => None,
        }
    }

    const fn bpf_ret(self) -> u32 {
        match self {
            Self::Eperm => SECCOMP_RET_ERRNO | 0x0001,
            Self::Eacces => SECCOMP_RET_ERRNO | 0x000d,
            Self::Einval => SECCOMP_RET_ERRNO | 0x0016,
            Self::Enosys => SECCOMP_RET_ERRNO | 0x0026,
            Self::Enotsup => SECCOMP_RET_ERRNO | 0x005f,
            Self::Kill => SECCOMP_RET_KILL_PROCESS,
            Self::Trap => SECCOMP_RET_TRAP,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
enum SeccompNotify {
    None,
    Log,
    Notify,
}

impl SeccompNotify {
    fn parse(s: &str) -> Self {
        match s {
            "none" => Self::None,
            "log" => Self::Log,
            "notify" => Self::Notify,
            other => fail_exit(&format!(
                "invalid seccomp notify '{other}' (expected: none, log, notify)"
            )),
        }
    }

    const fn as_str(self) -> &'static str {
        match self {
            Self::None => "none",
            Self::Log => "log",
            Self::Notify => "notify",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum SeccompOp {
    Eq,
    Ne,
    MaskNonZero,
    MaskZero,
    Lt,
    Le,
    Gt,
    Ge,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct SeccompCond {
    arg_idx: u8,
    u32_only: bool,
    op: SeccompOp,
    val: u64,
}

impl SeccompCond {
    const fn matches(self, args: [u64; 6], is_64bit: bool) -> bool {
        let raw = args[self.arg_idx as usize];
        let a = if is_64bit && !self.u32_only {
            raw
        } else {
            raw & 0xFFFF_FFFF
        };
        let v = self.val;
        match self.op {
            SeccompOp::Eq => a == v,
            SeccompOp::Ne => a != v,
            SeccompOp::MaskNonZero => (a & v) != 0,
            SeccompOp::MaskZero => (a & v) == 0,
            SeccompOp::Lt => a < v,
            SeccompOp::Le => a <= v,
            SeccompOp::Gt => a > v,
            SeccompOp::Ge => a >= v,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum SeccompVerdict {
    Allow,
    Deny {
        notify: SeccompNotify,
        action: SeccompAction,
    },
}

impl SeccompVerdict {
    const fn bpf_ret(self) -> u32 {
        match self {
            Self::Allow => SECCOMP_RET_ALLOW,
            Self::Deny {
                notify: SeccompNotify::None,
                action,
            } => action.bpf_ret(),
            Self::Deny {
                notify: SeccompNotify::Log | SeccompNotify::Notify,
                ..
            } => SECCOMP_RET_USER_NOTIF,
        }
    }
}

#[derive(Clone, Debug)]
struct SeccompRule {
    priority: i32,
    syscall: String,
    conds: Vec<SeccompCond>,
    verdict: SeccompVerdict,
}

#[derive(Clone, Debug)]
struct SeccompCliOp {
    kind: SeccompCliOpKind,
}

#[derive(Clone, Debug)]
enum SeccompCliOpKind {
    Clear,
    File(PathBuf),
    Allow(String),
    Block(String),
    Deny(SeccompNotify, SeccompAction, String),
}

fn find_explicit_config_flag() -> Option<String> {
    let args: Vec<String> = env::args().collect();
    let mut i = 1;
    while i < args.len() {
        if args[i] == "--" {
            break;
        }
        if args[i] == "--config" && i + 1 < args.len() {
            return Some(args[i + 1].clone());
        }
        if let Some(val) = args[i].strip_prefix("--config=") {
            return Some(val.to_string());
        }
        i += 1;
    }
    None
}

fn read_and_parse_json_file(path: &Path) -> JsonValue {
    let raw = fs::read_to_string(path)
        .unwrap_or_else(|e| fail_exit(&format!("failed to read '{}': {e}", path.display())));
    parse_json(&raw)
        .unwrap_or_else(|e| fail_exit(&format!("invalid JSON in '{}': {e}", path.display())))
}

fn xdg_config_path(env_key: &str, fallback_rel: &str, home: &str) -> Option<PathBuf> {
    env::var(env_key)
        .ok()
        .filter(|s| !s.is_empty())
        .map_or_else(
            || {
                if home.is_empty() {
                    None
                } else {
                    Some(PathBuf::from(home).join(fallback_rel))
                }
            },
            |d| Some(PathBuf::from(d).join("sb-run/config.json")),
        )
}

fn load_single_source_config_json() -> Option<JsonValue> {
    let explicit_flag = find_explicit_config_flag();
    let explicit_env = env::var("SB_RUN_CONFIG").ok().filter(|s| !s.is_empty());

    if let Some(spec) = explicit_flag.or(explicit_env) {
        if spec == "none" {
            return None;
        }
        let path = PathBuf::from(&spec);
        if !path.is_file() {
            fail_exit(&format!("config path '{}' does not exist", path.display()));
        }
        return Some(read_and_parse_json_file(&path));
    }

    let home = env::var("HOME").unwrap_or_default();
    let candidates = [
        xdg_config_path("XDG_CONFIG_HOME", ".config/sb-run/config.json", &home),
        xdg_config_path("XDG_DATA_HOME", ".local/share/sb-run/config.json", &home),
    ];

    for path in candidates.into_iter().flatten() {
        if path.is_file() {
            return Some(read_and_parse_json_file(&path));
        }
    }
    None
}

// ---------------------------------------------------------------------------
// IPC & Libc Primitives
// ---------------------------------------------------------------------------

#[repr(C)]
#[derive(Clone, Copy, Debug)]
struct WinSizePayload {
    row: u16,
    col: u16,
    xpixel: u16,
    ypixel: u16,
}

#[repr(C)]
#[derive(Clone, Copy, Debug)]
struct IpcHeader {
    magic: [u8; 4],
    version: u16,
    msg_type: u16,
    payload_len: u32,
    flags: u32,
    extra: [u8; 16],
}

impl IpcHeader {
    const fn new(msg_type: u16, payload_len: u32, flags: u32) -> Self {
        Self {
            magic: IPC_MAGIC,
            version: IPC_VERSION,
            msg_type,
            payload_len,
            flags,
            extra: [0; 16],
        }
    }

    fn to_bytes(self) -> [u8; 32] {
        let mut b = [0u8; 32];
        b[0..4].copy_from_slice(&self.magic);
        b[4..6].copy_from_slice(&self.version.to_le_bytes());
        b[6..8].copy_from_slice(&self.msg_type.to_le_bytes());
        b[8..12].copy_from_slice(&self.payload_len.to_le_bytes());
        b[12..16].copy_from_slice(&self.flags.to_le_bytes());
        b[16..32].copy_from_slice(&self.extra);
        b
    }

    fn from_bytes(bytes: &[u8]) -> Option<Self> {
        if bytes.len() < 32 {
            return None;
        }
        let magic: [u8; 4] = bytes[0..4].try_into().ok()?;
        let version = u16::from_le_bytes(bytes[4..6].try_into().ok()?);
        let msg_type = u16::from_le_bytes(bytes[6..8].try_into().ok()?);
        let payload_len = u32::from_le_bytes(bytes[8..12].try_into().ok()?);
        let flags = u32::from_le_bytes(bytes[12..16].try_into().ok()?);
        let extra: [u8; 16] = bytes[16..32].try_into().ok()?;

        if magic == IPC_MAGIC && version == IPC_VERSION {
            Some(Self {
                magic,
                version,
                msg_type,
                payload_len,
                flags,
                extra,
            })
        } else {
            None
        }
    }
}

#[repr(C)]
struct LibcIovec {
    iov_base: *mut c_void,
    iov_len: usize,
}

#[repr(C)]
struct LibcMsghdr {
    name: *mut c_void,
    namelen: u32,
    _pad1: u32,
    iov: *mut LibcIovec,
    iovlen: usize,
    control: *mut c_void,
    controllen: usize,
    flags: i32,
    _pad2: i32,
}

#[repr(C)]
struct LibcCmsghdr {
    len: usize,
    level: i32,
    type_: i32,
}

#[repr(C, align(8))]
struct CmsgBuffer([u8; 128]);

fn send_header_with_fds(
    sock: &UnixStream,
    header: &IpcHeader,
    fds: &[RawFd],
) -> std::io::Result<()> {
    let header_bytes = header.to_bytes();
    let mut iov = LibcIovec {
        iov_base: header_bytes.as_ptr().cast::<c_void>().cast_mut(),
        iov_len: header_bytes.len(),
    };

    let mut cmsg_buf = CmsgBuffer([0u8; 128]);
    let raw_len = if fds.is_empty() {
        0
    } else {
        size_of::<LibcCmsghdr>() + std::mem::size_of_val(fds)
    };
    let control_space = (raw_len + 7) & !7;

    let msg = LibcMsghdr {
        name: std::ptr::null_mut(),
        namelen: 0,
        _pad1: 0,
        iov: &raw mut iov,
        iovlen: 1,
        control: if fds.is_empty() {
            std::ptr::null_mut()
        } else {
            cmsg_buf.0.as_mut_ptr().cast()
        },
        controllen: control_space,
        flags: 0,
        _pad2: 0,
    };

    if !fds.is_empty() {
        let cmsghdr_ptr = msg.control.cast::<LibcCmsghdr>();
        unsafe {
            (*cmsghdr_ptr).len = raw_len;
            (*cmsghdr_ptr).level = SOL_SOCKET;
            (*cmsghdr_ptr).type_ = SCM_RIGHTS;
            let data_ptr = cmsghdr_ptr.add(1).cast::<RawFd>();
            for (i, &fd) in fds.iter().enumerate() {
                *data_ptr.add(i) = fd;
            }
        }
    }

    let n = unsafe { sendmsg(sock.as_raw_fd(), &raw const msg, 0) };
    if n < 0 {
        return Err(std::io::Error::last_os_error());
    }
    Ok(())
}

fn recv_byte_with_fd(sock: &UnixStream) -> std::io::Result<OwnedFd> {
    let mut byte = [0u8; 1];
    let mut iov = LibcIovec {
        iov_base: byte.as_mut_ptr().cast(),
        iov_len: 1,
    };
    let mut cmsg_buf = CmsgBuffer([0u8; 128]);
    let mut msg = LibcMsghdr {
        name: std::ptr::null_mut(),
        namelen: 0,
        _pad1: 0,
        iov: &raw mut iov,
        iovlen: 1,
        control: cmsg_buf.0.as_mut_ptr().cast(),
        controllen: cmsg_buf.0.len(),
        flags: 0,
        _pad2: 0,
    };
    let n = unsafe { recvmsg(sock.as_raw_fd(), &raw mut msg, 0) };
    if n <= 0 {
        return Err(std::io::Error::last_os_error());
    }
    if msg.controllen >= size_of::<LibcCmsghdr>() {
        let cmsghdr_ptr = msg.control.cast::<LibcCmsghdr>();
        unsafe {
            if !cmsghdr_ptr.is_null()
                && (*cmsghdr_ptr).len >= size_of::<LibcCmsghdr>() + size_of::<RawFd>()
                && (*cmsghdr_ptr).len <= msg.controllen
                && (*cmsghdr_ptr).level == SOL_SOCKET
                && (*cmsghdr_ptr).type_ == SCM_RIGHTS
            {
                let fd = *cmsghdr_ptr.add(1).cast::<RawFd>();
                if fd >= 0 {
                    return Ok(OwnedFd::from_raw_fd(fd));
                }
            }
        }
    }
    Err(std::io::Error::new(
        std::io::ErrorKind::InvalidData,
        "missing seccomp notif fd",
    ))
}

fn build_exec_payload(
    cwd: &str,
    args: &[String],
    env_vars: &[String],
    seccomp_bpf: Option<&[u8]>,
) -> Vec<u8> {
    let mut buf = Vec::new();
    let write_str = |b: &mut Vec<u8>, s: &str| {
        let bytes = s.as_bytes();
        let len = u32::try_from(bytes.len()).unwrap_or(0);
        b.extend_from_slice(&len.to_le_bytes());
        b.extend_from_slice(bytes);
    };

    write_str(&mut buf, cwd);
    let arg_count = u32::try_from(args.len()).unwrap_or(0);
    buf.extend_from_slice(&arg_count.to_le_bytes());
    for arg in args {
        write_str(&mut buf, arg);
    }

    let env_count = u32::try_from(env_vars.len()).unwrap_or(0);
    buf.extend_from_slice(&env_count.to_le_bytes());
    for item in env_vars {
        write_str(&mut buf, item);
    }

    if let Some(bpf) = seccomp_bpf {
        let bpf_len = u32::try_from(bpf.len()).unwrap_or(0);
        buf.extend_from_slice(&bpf_len.to_le_bytes());
        buf.extend_from_slice(bpf);
    }
    buf
}

// ---------------------------------------------------------------------------
// Configuration & CLI Argument Parsing
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq, Eq)]
enum BridgeDirection {
    FromSandbox,
    ToSandbox,
}

#[derive(Clone, Debug)]
struct BridgeRule {
    direction: BridgeDirection,
    address: String,
    ports: String,
}

struct SandboxConfig {
    app_id: String,
    custom_dir: Option<PathBuf>,
    network: String,
    wayland_mode: String,
    x11_mode: String,
    pulse_mode: String,
    pipewire_mode: String,
    microphone: MicMode,
    dbus_mode: String,
    shm_mode: String,
    tmp_mode: String,
    bridges: Vec<BridgeRule>,
    subsystems: u32,
    flags: u32,
    webcam: WebcamMode,
    pw_v4l2_bin: PathBuf,
    executor_path: PathBuf,
    dbus_talk: Vec<String>,
    dbus_own: Vec<String>,
    dbus_see: Vec<String>,
    dbus_calls: Vec<String>,
    dbus_extra_args: Vec<String>,
    system_dbus_talk: Vec<String>,
    system_dbus_own: Vec<String>,
    system_dbus_see: Vec<String>,
    system_dbus_calls: Vec<String>,
    system_dbus_extra_args: Vec<String>,
    rw_binds: Vec<String>,
    ro_binds: Vec<String>,
    dev_binds: Vec<String>,
    mkdir_dirs: Vec<String>,
    bwrap_extra_args: Vec<String>,
    extra_env: Vec<String>,
    singbox_bin: PathBuf,
    singbox_config: PathBuf,
    singbox_json: Option<String>,
    dbus_proxy_bin: PathBuf,
    way_secure_bin: PathBuf,
    pasta_bin: PathBuf,
    xwayland_satellite_bin: PathBuf,
    bwrap_bin: PathBuf,
    rust_bridge_bin: PathBuf,
    app2unit_bin: PathBuf,
    systemctl_bin: PathBuf,
    vpnify_bin: PathBuf,
    notify_send_bin: PathBuf,
    syscalls_file: PathBuf,
    seccomp_action: SeccompAction,
    seccomp_notify: SeccompNotify,
    seccomp_allow: Vec<String>,
    seccomp_deny: BTreeMap<(SeccompNotify, SeccompAction), Vec<String>>,
    seccomp_cli_ops: Vec<SeccompCliOp>,
    pasta_args: Vec<String>,
    allowed_env_vars: Vec<String>,
    ro_system_paths: Vec<String>,
    user_theme_subpaths: Vec<String>,
    xdg_config_subpaths: Vec<String>,
    xdg_data_subpaths: Vec<String>,
    nvidia_nodes: Vec<String>,
    custom_uid: Option<u32>,
    custom_gid: Option<u32>,
    inside_init: Vec<String>,
    command: Vec<String>,
}

impl SandboxConfig {
    fn defaults() -> Self {
        let mut flags =
            CFG_DBUS | CFG_LANDLOCK | CFG_SECCOMP | CFG_PORTALS | CFG_FLATPAK_INFO | CFG_SCOPE;
        if env::var("SB_RUN_VERBOSE").as_deref() == Ok("1") {
            flags |= CFG_VERBOSE;
        }

        Self {
            app_id: String::new(),
            custom_dir: None,
            network: "sandboxed".into(),
            wayland_mode: "sandboxed".into(),
            x11_mode: "off".into(),
            pulse_mode: "sandboxed".into(),
            pipewire_mode: "sandboxed".into(),
            microphone: MicMode::Off,
            dbus_mode: "sandboxed".into(),
            shm_mode: "sandboxed".into(),
            tmp_mode: "sandboxed".into(),
            bridges: Vec::new(),
            subsystems: 0,
            flags,
            webcam: WebcamMode::Off,
            pw_v4l2_bin: PathBuf::new(),
            executor_path: PathBuf::new(),
            dbus_talk: Vec::new(),
            dbus_own: Vec::new(),
            dbus_see: Vec::new(),
            dbus_calls: Vec::new(),
            dbus_extra_args: Vec::new(),
            system_dbus_talk: Vec::new(),
            system_dbus_own: Vec::new(),
            system_dbus_see: Vec::new(),
            system_dbus_calls: Vec::new(),
            system_dbus_extra_args: Vec::new(),
            rw_binds: Vec::new(),
            ro_binds: Vec::new(),
            dev_binds: Vec::new(),
            mkdir_dirs: Vec::new(),
            bwrap_extra_args: Vec::new(),
            extra_env: Vec::new(),
            singbox_bin: PathBuf::new(),
            singbox_config: PathBuf::new(),
            singbox_json: None,
            dbus_proxy_bin: PathBuf::new(),
            way_secure_bin: PathBuf::new(),
            pasta_bin: PathBuf::new(),
            xwayland_satellite_bin: PathBuf::new(),
            bwrap_bin: PathBuf::new(),
            rust_bridge_bin: PathBuf::new(),
            app2unit_bin: PathBuf::new(),
            systemctl_bin: PathBuf::new(),
            vpnify_bin: PathBuf::new(),
            notify_send_bin: PathBuf::new(),
            syscalls_file: PathBuf::new(),
            seccomp_action: SeccompAction::Eperm,
            seccomp_notify: SeccompNotify::Notify,
            seccomp_allow: Vec::new(),
            seccomp_deny: BTreeMap::new(),
            seccomp_cli_ops: Vec::new(),
            pasta_args: Vec::new(),
            allowed_env_vars: Vec::new(),
            ro_system_paths: Vec::new(),
            user_theme_subpaths: Vec::new(),
            xdg_config_subpaths: Vec::new(),
            xdg_data_subpaths: Vec::new(),
            nvidia_nodes: Vec::new(),
            custom_uid: None,
            custom_gid: None,
            inside_init: Vec::new(),
            command: Vec::new(),
        }
    }

    fn apply_json_bools(&mut self, root: &JsonValue) {
        let mut set_flag = |key: &str, bit: u32| {
            if let Some(b) = root.opt_bool(key, "config") {
                if b {
                    self.flags |= bit;
                } else {
                    self.flags &= !bit;
                }
            }
        };
        set_flag("landlock", CFG_LANDLOCK);
        set_flag("portals", CFG_PORTALS);
        set_flag("tmpfs", CFG_TMPFS);
        set_flag("share_pid", CFG_SHARE_PID);
        set_flag("share_ipc", CFG_SHARE_IPC);
        set_flag("vpnify", CFG_USE_VPNIFY);
        set_flag("flatpak_info", CFG_FLATPAK_INFO);
        set_flag("scope", CFG_SCOPE);
        set_flag("cli", CFG_IS_CLI);

        if let Some(b) = root.opt_bool("gpu", "config") {
            if b {
                self.subsystems |= SUBSYS_GPU;
            } else {
                self.subsystems &= !SUBSYS_GPU;
            }
        }
        if let Some(b) = root.opt_bool("gamepad", "config") {
            if b {
                self.subsystems |= SUBSYS_GAMEPAD;
            } else {
                self.subsystems &= !SUBSYS_GAMEPAD;
            }
        }
    }

    fn apply_json_dbus(&mut self, root: &JsonValue) {
        if let Some(dbus_v) = root.as_obj("config").get("dbus") {
            if let Some(mode) = dbus_v.opt_str("mode", "dbus") {
                self.dbus_mode = mode;
                if self.dbus_mode == "off" {
                    self.flags &= !CFG_DBUS;
                } else {
                    self.flags |= CFG_DBUS;
                }
            }
            self.dbus_talk.extend(dbus_v.opt_str_list("talks", "dbus"));
            self.dbus_own.extend(dbus_v.opt_str_list("owns", "dbus"));
            self.dbus_see.extend(dbus_v.opt_str_list("sees", "dbus"));
            self.dbus_calls.extend(dbus_v.opt_str_list("calls", "dbus"));
            self.dbus_extra_args
                .extend(dbus_v.opt_str_list("extra_args", "dbus"));
        }

        if let Some(sys_v) = root.as_obj("config").get("system_dbus") {
            if let Some(en) = sys_v.opt_bool("enable", "system_dbus") {
                if en {
                    self.flags |= CFG_SYSTEM_DBUS;
                } else {
                    self.flags &= !CFG_SYSTEM_DBUS;
                }
            }
            self.system_dbus_talk
                .extend(sys_v.opt_str_list("talks", "system_dbus"));
            self.system_dbus_own
                .extend(sys_v.opt_str_list("owns", "system_dbus"));
            self.system_dbus_see
                .extend(sys_v.opt_str_list("sees", "system_dbus"));
            self.system_dbus_calls
                .extend(sys_v.opt_str_list("calls", "system_dbus"));
            self.system_dbus_extra_args
                .extend(sys_v.opt_str_list("extra_args", "system_dbus"));
        }
    }

    fn apply_json_seccomp(&mut self, root: &JsonValue) {
        let Some(sec_v) = root.as_obj("config").get("seccomp") else {
            return;
        };
        if let Some(en) = sec_v.opt_bool("enable", "seccomp") {
            if en {
                self.flags |= CFG_SECCOMP;
            } else {
                self.flags &= !CFG_SECCOMP;
            }
        }
        if let Some(act) = sec_v.opt_str("action", "seccomp") {
            self.seccomp_action = SeccompAction::parse(&act);
        }
        if let Some(not) = sec_v.opt_str("notify", "seccomp") {
            self.seccomp_notify = SeccompNotify::parse(&not);
        }
        self.seccomp_allow
            .extend(sec_v.opt_str_list("allow", "seccomp"));

        if let Some(deny_v) = sec_v.as_obj("seccomp").get("deny") {
            for (notify_key, actions_v) in deny_v.as_obj("seccomp.deny") {
                let notify = SeccompNotify::parse(notify_key);
                let ctx = format!("seccomp.deny.{notify_key}");
                for (action_key, rules_v) in actions_v.as_obj(&ctx) {
                    let action = SeccompAction::parse(action_key);
                    let list = match rules_v {
                        JsonValue::Array(arr) => arr
                            .iter()
                            .map(|item| match item {
                                JsonValue::Str(s) => s.clone(),
                                _ => fail_exit(&format!("non-string item in '{ctx}.{action_key}'")),
                            })
                            .collect::<Vec<_>>(),
                        _ => fail_exit(&format!("'{ctx}.{action_key}' must be an array")),
                    };
                    if !list.is_empty() {
                        self.seccomp_deny
                            .entry((notify, action))
                            .or_default()
                            .extend(list);
                    }
                }
            }
        }
    }

    fn apply_json_bins_and_paths(&mut self, root: &JsonValue) {
        if let Some(paths_v) = root.as_obj("config").get("paths") {
            self.allowed_env_vars = paths_v.opt_str_list("allowed_env_vars", "paths");
            self.ro_system_paths = paths_v.opt_str_list("ro_system_paths", "paths");
            self.user_theme_subpaths = paths_v.opt_str_list("user_theme_subpaths", "paths");
            self.xdg_config_subpaths = paths_v.opt_str_list("xdg_config_subpaths", "paths");
            self.xdg_data_subpaths = paths_v.opt_str_list("xdg_data_subpaths", "paths");
            self.nvidia_nodes = paths_v.opt_str_list("nvidia_nodes", "paths");
        }

        if let Some(binds_v) = root.as_obj("config").get("binds") {
            let expand = |raw: Vec<String>| -> Vec<String> {
                raw.into_iter()
                    .map(|p| expand_env_path(&p, &self.allowed_env_vars))
                    .collect()
            };
            self.rw_binds
                .extend(expand(binds_v.opt_str_list("rw", "binds")));
            self.ro_binds
                .extend(expand(binds_v.opt_str_list("ro", "binds")));
            self.dev_binds
                .extend(expand(binds_v.opt_str_list("dev", "binds")));
            self.mkdir_dirs
                .extend(expand(binds_v.opt_str_list("mkdir", "binds")));
        }

        if let Some(env_v) = root.as_obj("config").get("env") {
            for (k, v) in env_v.as_obj("env") {
                match v {
                    JsonValue::Str(s) => {
                        let expanded = expand_env_path(s, &self.allowed_env_vars);
                        self.extra_env.push(format!("{k}={expanded}"));
                    }
                    _ => fail_exit(&format!("config field 'env.{k}' must be a string")),
                }
            }
        }

        if let Some(bins_v) = root.as_obj("config").get("bins") {
            for (k, v) in bins_v.as_obj("bins") {
                let JsonValue::Str(s) = v else {
                    fail_exit(&format!("binary path 'bins.{k}' must be a string"));
                };
                let pb = PathBuf::from(s);
                match k.as_str() {
                    "bwrap" => self.bwrap_bin = pb,
                    "sb_executor" => self.executor_path = pb,
                    "dbus_proxy" => self.dbus_proxy_bin = pb,
                    "way_secure" => self.way_secure_bin = pb,
                    "pasta" => self.pasta_bin = pb,
                    "xwayland_satellite" => self.xwayland_satellite_bin = pb,
                    "singbox" => self.singbox_bin = pb,
                    "rust_bridge" => self.rust_bridge_bin = pb,
                    "app2unit" => self.app2unit_bin = pb,
                    "systemctl" => self.systemctl_bin = pb,
                    "vpnify" => self.vpnify_bin = pb,
                    "notify_send" => self.notify_send_bin = pb,
                    "pw_v4l2" => self.pw_v4l2_bin = pb,
                    _ => {}
                }
            }
        }
    }

    fn from_optional_json(opt: Option<&JsonValue>) -> Self {
        let mut cfg = Self::defaults();
        let Some(root) = opt else {
            return cfg;
        };

        if let Some(v) = root.opt_str("network", "config") {
            cfg.network = v;
        }
        if let Some(v) = root.opt_str("wayland", "config") {
            cfg.wayland_mode = v;
        }
        if let Some(v) = root.opt_str("x11", "config") {
            cfg.x11_mode = v;
        }
        if let Some(v) = root.opt_str("pulse", "config") {
            cfg.pulse_mode = v;
        }
        if let Some(v) = root.opt_str("pipewire", "config") {
            cfg.pipewire_mode = v;
        }
        if let Some(v) = root.opt_str("microphone", "config") {
            cfg.microphone = MicMode::parse(&v);
        }
        if let Some(v) = root.opt_str("webcam", "config") {
            cfg.webcam = WebcamMode::parse(&v);
        }
        if let Some(v) = root.opt_str("shm", "config") {
            cfg.shm_mode = v;
        }
        if let Some(v) = root.opt_str("tmp", "config") {
            cfg.tmp_mode = v;
        }
        if let Some(v) = root.opt_str("singbox_config", "config") {
            cfg.singbox_config = PathBuf::from(v);
        }
        if let Some(v) = root.opt_str("syscalls_file", "config") {
            cfg.syscalls_file = PathBuf::from(v);
        }

        cfg.apply_json_bools(root);
        cfg.apply_json_dbus(root);
        cfg.apply_json_seccomp(root);
        cfg.apply_json_bins_and_paths(root);

        let expand_cfg_path = |p: &Path| -> PathBuf {
            let raw = p.to_string_lossy();
            if raw.is_empty() {
                return p.to_path_buf();
            }
            let vars: Vec<String> = if cfg.allowed_env_vars.is_empty() {
                ["HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME"]
                    .into_iter()
                    .map(String::from)
                    .collect()
            } else {
                cfg.allowed_env_vars.clone()
            };
            PathBuf::from(expand_env_path(&raw, &vars))
        };
        cfg.singbox_config = expand_cfg_path(&cfg.singbox_config);
        cfg.syscalls_file = expand_cfg_path(&cfg.syscalls_file);

        for raw in root.opt_str_list("bridges", "config") {
            if let Some(rule) = parse_bridge_arg(&raw) {
                cfg.bridges.push(rule);
            } else {
                fail_exit(&format!("invalid bridge specification '{raw}' in config"));
            }
        }
        cfg.bwrap_extra_args
            .extend(root.opt_str_list("bwrap_args", "config"));
        cfg.pasta_args
            .extend(root.opt_str_list("pasta_args", "config"));

        cfg
    }
}

#[derive(Default)]
struct HelperProcesses {
    way_secure_close_fd: Option<i32>,
    dbus_proxy: Option<Child>,
    system_dbus_proxy: Option<Child>,
    singbox_bridge: Option<Child>,
    pasta: Option<Child>,
}

fn parse_bridge_arg(arg: &str) -> Option<BridgeRule> {
    let parts: Vec<&str> = arg.splitn(3, ':').collect();
    if parts.len() < 2 {
        return None;
    }
    let direction = match parts[0].to_lowercase().as_str() {
        "from" | "from-sandbox" | "out" => BridgeDirection::FromSandbox,
        "to" | "to-sandbox" | "in" => BridgeDirection::ToSandbox,
        _ => return None,
    };

    let (address, raw_ports) = if parts.len() == 2 {
        ("127.0.0.1".to_string(), parts[1].to_string())
    } else {
        (parts[1].to_string(), parts[2].to_string())
    };
    let clean_ports = raw_ports.trim_matches(|c| c == '[' || c == ']').to_string();
    if clean_ports.is_empty() {
        return None;
    }

    Some(BridgeRule {
        direction,
        address,
        ports: clean_ports,
    })
}

fn expand_env_path(path_str: &str, allowed_env: &[String]) -> String {
    let mut result = path_str.to_string();
    if result.starts_with("~/")
        && let Ok(home) = env::var("HOME")
    {
        result = format!("{home}/{}", &result[2..]);
    }
    for k in allowed_env {
        if let Ok(v) = env::var(k) {
            let var_dollar = format!("${k}");
            let var_braced = format!("${{{k}}}");
            if result.contains(&var_dollar) {
                result = result.replace(&var_dollar, &v);
            }
            if result.contains(&var_braced) {
                result = result.replace(&var_braced, &v);
            }
        }
    }
    result
}

fn parse_subsystem_flag(args: &[String], i: &mut usize, subs: &mut u32) -> bool {
    match args[*i].as_str() {
        "--gpu" => {
            *subs |= SUBSYS_GPU;
            *i += 1;
            true
        }
        "--no-gpu" => {
            *subs &= !SUBSYS_GPU;
            *i += 1;
            true
        }
        "--gamepad" => {
            *subs |= SUBSYS_GAMEPAD;
            *i += 1;
            true
        }
        "--no-gamepad" => {
            *subs &= !SUBSYS_GAMEPAD;
            *i += 1;
            true
        }
        _ => false,
    }
}

fn parse_dbus_arg(cfg: &mut SandboxConfig, args: &[String], i: &mut usize) -> bool {
    let arg = &args[*i];
    let has_next = *i + 1 < args.len();
    if let Some(talk) = arg.strip_prefix("--system-dbus-talk=") {
        cfg.system_dbus_talk.push(talk.into());
        cfg.flags |= CFG_SYSTEM_DBUS;
        *i += 1;
    } else if let Some(own) = arg.strip_prefix("--system-dbus-own=") {
        cfg.system_dbus_own.push(own.into());
        cfg.flags |= CFG_SYSTEM_DBUS;
        *i += 1;
    } else if let Some(see) = arg.strip_prefix("--system-dbus-see=") {
        cfg.system_dbus_see.push(see.into());
        cfg.flags |= CFG_SYSTEM_DBUS;
        *i += 1;
    } else if let Some(call) = arg.strip_prefix("--system-dbus-call=") {
        cfg.system_dbus_calls.push(call.into());
        cfg.flags |= CFG_SYSTEM_DBUS;
        *i += 1;
    } else if arg == "--system-dbus-talk" && has_next {
        cfg.system_dbus_talk.push(args[*i + 1].clone());
        cfg.flags |= CFG_SYSTEM_DBUS;
        *i += 2;
    } else if arg == "--system-dbus-own" && has_next {
        cfg.system_dbus_own.push(args[*i + 1].clone());
        cfg.flags |= CFG_SYSTEM_DBUS;
        *i += 2;
    } else if arg == "--system-dbus-see" && has_next {
        cfg.system_dbus_see.push(args[*i + 1].clone());
        cfg.flags |= CFG_SYSTEM_DBUS;
        *i += 2;
    } else if arg == "--system-dbus-call" && has_next {
        cfg.system_dbus_calls.push(args[*i + 1].clone());
        cfg.flags |= CFG_SYSTEM_DBUS;
        *i += 2;
    } else if arg == "--system-dbus-arg" && has_next {
        cfg.system_dbus_extra_args.push(args[*i + 1].clone());
        cfg.flags |= CFG_SYSTEM_DBUS;
        *i += 2;
    } else if let Some(talk) = arg.strip_prefix("--dbus-talk=") {
        cfg.dbus_talk.push(talk.into());
        *i += 1;
    } else if let Some(own) = arg.strip_prefix("--dbus-own=") {
        cfg.dbus_own.push(own.into());
        *i += 1;
    } else if let Some(see) = arg.strip_prefix("--dbus-see=") {
        cfg.dbus_see.push(see.into());
        *i += 1;
    } else if let Some(call) = arg.strip_prefix("--dbus-call=") {
        cfg.dbus_calls.push(call.into());
        *i += 1;
    } else if (arg == "--talk" || arg == "--dbus-talk") && has_next {
        cfg.dbus_talk.push(args[*i + 1].clone());
        *i += 2;
    } else if (arg == "--own" || arg == "--dbus-own") && has_next {
        cfg.dbus_own.push(args[*i + 1].clone());
        *i += 2;
    } else if (arg == "--see" || arg == "--dbus-see") && has_next {
        cfg.dbus_see.push(args[*i + 1].clone());
        *i += 2;
    } else if (arg == "--call" || arg == "--dbus-call") && has_next {
        cfg.dbus_calls.push(args[*i + 1].clone());
        *i += 2;
    } else if arg == "--dbus-arg" && has_next {
        cfg.dbus_extra_args.push(args[*i + 1].clone());
        *i += 2;
    } else {
        return false;
    }
    true
}

fn parse_audio_display_arg(cfg: &mut SandboxConfig, args: &[String], i: &mut usize) -> bool {
    let has_next = *i + 1 < args.len();
    match args[*i].as_str() {
        "--pulse" if has_next => {
            cfg.pulse_mode.clone_from(&args[*i + 1]);
            *i += 2;
        }
        "--pipewire" if has_next => {
            cfg.pipewire_mode.clone_from(&args[*i + 1]);
            *i += 2;
        }
        "--microphone" if has_next => {
            cfg.microphone = MicMode::parse(&args[*i + 1]);
            *i += 2;
        }
        "--audio" => {
            cfg.pulse_mode = "sandboxed".into();
            cfg.pipewire_mode = "sandboxed".into();
            *i += 1;
        }
        "--no-audio" => {
            cfg.pulse_mode = "off".into();
            cfg.pipewire_mode = "off".into();
            *i += 1;
        }
        "--no-pulse" => {
            cfg.pulse_mode = "off".into();
            *i += 1;
        }
        "--no-pipewire" => {
            cfg.pipewire_mode = "off".into();
            *i += 1;
        }
        "--wayland" => {
            if has_next && !args[*i + 1].starts_with('-') {
                cfg.wayland_mode.clone_from(&args[*i + 1]);
                *i += 2;
            } else {
                cfg.wayland_mode = "sandboxed".into();
                *i += 1;
            }
        }
        "--no-wayland" => {
            cfg.wayland_mode = "off".into();
            *i += 1;
        }
        "--x11" => {
            if has_next && !args[*i + 1].starts_with('-') {
                cfg.x11_mode.clone_from(&args[*i + 1]);
                *i += 2;
            } else {
                cfg.x11_mode = "sandboxed".into();
                *i += 1;
            }
        }
        "--no-x11" => {
            cfg.x11_mode = "off".into();
            *i += 1;
        }
        _ => return false,
    }
    true
}

fn parse_seccomp_arg(cfg: &mut SandboxConfig, args: &[String], i: &mut usize) -> bool {
    let has_next = *i + 1 < args.len();
    match args[*i].as_str() {
        "--seccomp" => {
            cfg.flags |= CFG_SECCOMP;
            *i += 1;
        }
        "--no-seccomp" => {
            cfg.flags &= !CFG_SECCOMP;
            *i += 1;
        }
        "--seccomp-action" if has_next => {
            cfg.seccomp_action = SeccompAction::parse(&args[*i + 1]);
            *i += 2;
        }
        "--seccomp-notify" if has_next => {
            cfg.seccomp_notify = SeccompNotify::parse(&args[*i + 1]);
            *i += 2;
        }
        "--seccomp-clear" => {
            cfg.seccomp_cli_ops.push(SeccompCliOp {
                kind: SeccompCliOpKind::Clear,
            });
            *i += 1;
        }
        "--seccomp-allow" if has_next => {
            for item in args[*i + 1]
                .split(',')
                .map(str::trim)
                .filter(|s| !s.is_empty())
            {
                cfg.seccomp_cli_ops.push(SeccompCliOp {
                    kind: SeccompCliOpKind::Allow(item.to_string()),
                });
            }
            *i += 2;
        }
        "--seccomp-block" if has_next => {
            for item in args[*i + 1]
                .split(',')
                .map(str::trim)
                .filter(|s| !s.is_empty())
            {
                cfg.seccomp_cli_ops.push(SeccompCliOp {
                    kind: SeccompCliOpKind::Block(item.to_string()),
                });
            }
            *i += 2;
        }
        "--seccomp-deny" if has_next => {
            let mut parts = args[*i + 1].splitn(3, ':');
            let (Some(n_str), Some(a_str), Some(csv)) = (parts.next(), parts.next(), parts.next())
            else {
                fail_exit("--seccomp-deny requires <notify>:<action>:<CSV_RULES>");
            };
            let notify = SeccompNotify::parse(n_str.trim());
            let action = SeccompAction::parse(a_str.trim());
            for item in csv.split(',').map(str::trim).filter(|s| !s.is_empty()) {
                cfg.seccomp_cli_ops.push(SeccompCliOp {
                    kind: SeccompCliOpKind::Deny(notify, action, item.to_string()),
                });
            }
            *i += 2;
        }
        "--seccomp-file" if has_next => {
            let path = PathBuf::from(expand_env_path(&args[*i + 1], &cfg.allowed_env_vars));
            cfg.seccomp_cli_ops.push(SeccompCliOp {
                kind: SeccompCliOpKind::File(path),
            });
            cfg.flags |= CFG_SECCOMP;
            *i += 2;
        }
        "--seccomp-list" => {
            cfg.flags |= CFG_SECCOMP_LIST;
            *i += 1;
        }
        "--edit-seccomp" => {
            cfg.flags |= CFG_EDIT_SECCOMP | CFG_SECCOMP;
            *i += 1;
        }
        _ => return false,
    }
    true
}

fn parse_system_state_arg(cfg: &mut SandboxConfig, args: &[String], i: &mut usize) -> bool {
    let has_next = *i + 1 < args.len();
    match args[*i].as_str() {
        "--dbus" => {
            if has_next && !args[*i + 1].starts_with('-') {
                cfg.dbus_mode.clone_from(&args[*i + 1]);
                if cfg.dbus_mode == "off" {
                    cfg.flags &= !CFG_DBUS;
                } else {
                    cfg.flags |= CFG_DBUS;
                }
                *i += 2;
            } else {
                cfg.dbus_mode = "sandboxed".into();
                cfg.flags |= CFG_DBUS;
                *i += 1;
            }
        }
        "--no-dbus" => {
            cfg.dbus_mode = "off".into();
            cfg.flags &= !CFG_DBUS;
            *i += 1;
        }
        "--system-dbus" => {
            cfg.flags |= CFG_SYSTEM_DBUS;
            *i += 1;
        }
        "--no-system-dbus" => {
            cfg.flags &= !CFG_SYSTEM_DBUS;
            *i += 1;
        }
        "--share-ipc" => {
            cfg.flags |= CFG_SHARE_IPC;
            *i += 1;
        }
        "--unshare-ipc" => {
            cfg.flags &= !CFG_SHARE_IPC;
            *i += 1;
        }
        "--shm" if has_next => {
            cfg.shm_mode.clone_from(&args[*i + 1]);
            *i += 2;
        }
        "--tmp" if has_next => {
            cfg.tmp_mode.clone_from(&args[*i + 1]);
            *i += 2;
        }
        "--portals" => {
            cfg.flags |= CFG_PORTALS;
            *i += 1;
        }
        "--no-portals" => {
            cfg.flags &= !CFG_PORTALS;
            *i += 1;
        }
        "--flatpak-info" => {
            cfg.flags |= CFG_FLATPAK_INFO;
            *i += 1;
        }
        "--tmpfs" => {
            cfg.flags |= CFG_TMPFS;
            *i += 1;
        }
        "--no-tmpfs" => {
            cfg.flags &= !CFG_TMPFS;
            *i += 1;
        }
        "--scope" => {
            cfg.flags |= CFG_SCOPE;
            *i += 1;
        }
        "--no-scope" => {
            cfg.flags &= !CFG_SCOPE;
            *i += 1;
        }
        "--share-pid" => {
            cfg.flags |= CFG_SHARE_PID;
            *i += 1;
        }
        "--unshare-pid" => {
            cfg.flags &= !CFG_SHARE_PID;
            *i += 1;
        }
        "--landlock" => {
            cfg.flags |= CFG_LANDLOCK;
            *i += 1;
        }
        "--no-landlock" => {
            cfg.flags &= !CFG_LANDLOCK;
            *i += 1;
        }
        _ => return false,
    }
    true
}

fn parse_bind_arg(
    cfg: &mut SandboxConfig,
    args: &[String],
    i: &mut usize,
    allowed_env: &[String],
) -> bool {
    let arg = &args[*i];
    let has_next = *i + 1 < args.len();
    if let Some(val) = arg.strip_prefix("--rw=") {
        cfg.rw_binds.push(expand_env_path(val, allowed_env));
        *i += 1;
    } else if let Some(val) = arg.strip_prefix("--ro=") {
        cfg.ro_binds.push(expand_env_path(val, allowed_env));
        *i += 1;
    } else if let Some(val) = arg.strip_prefix("--dev=") {
        cfg.dev_binds.push(expand_env_path(val, allowed_env));
        *i += 1;
    } else if let Some(val) = arg.strip_prefix("--mkdir=") {
        cfg.mkdir_dirs.push(expand_env_path(val, allowed_env));
        *i += 1;
    } else if (arg == "--rw" || arg == "--bind-rw") && has_next {
        cfg.rw_binds
            .push(expand_env_path(&args[*i + 1], allowed_env));
        *i += 2;
    } else if (arg == "--ro" || arg == "--bind-ro") && has_next {
        cfg.ro_binds
            .push(expand_env_path(&args[*i + 1], allowed_env));
        *i += 2;
    } else if (arg == "--dev" || arg == "--bind-dev") && has_next {
        cfg.dev_binds
            .push(expand_env_path(&args[*i + 1], allowed_env));
        *i += 2;
    } else if arg == "--mkdir" && has_next {
        cfg.mkdir_dirs
            .push(expand_env_path(&args[*i + 1], allowed_env));
        *i += 2;
    } else {
        return false;
    }
    true
}

fn parse_bins_and_net_arg(cfg: &mut SandboxConfig, args: &[String], i: &mut usize) -> bool {
    let has_next = *i + 1 < args.len();
    let expand = |s: &str| PathBuf::from(expand_env_path(s, &cfg.allowed_env_vars));
    match args[*i].as_str() {
        "--config" if has_next => *i += 2,
        s if s.starts_with("--config=") => *i += 1,
        "--singbox-bin" if has_next => {
            cfg.singbox_bin = expand(&args[*i + 1]);
            *i += 2;
        }
        "--singbox-config" if has_next => {
            cfg.singbox_config = expand(&args[*i + 1]);
            *i += 2;
        }
        "--singbox-json" if has_next => {
            cfg.singbox_json = Some(args[*i + 1].clone());
            *i += 2;
        }
        "--edit-singbox" => {
            cfg.flags |= CFG_EDIT_SINGBOX;
            *i += 1;
        }
        "--dbus-proxy-bin" if has_next => {
            cfg.dbus_proxy_bin = expand(&args[*i + 1]);
            *i += 2;
        }
        "--way-secure-bin" if has_next => {
            cfg.way_secure_bin = expand(&args[*i + 1]);
            *i += 2;
        }
        "--pasta-bin" if has_next => {
            cfg.pasta_bin = expand(&args[*i + 1]);
            *i += 2;
        }
        "--pasta-arg" if has_next => {
            cfg.pasta_args.push(args[*i + 1].clone());
            *i += 2;
        }
        "--xwayland-satellite-bin" if has_next => {
            cfg.xwayland_satellite_bin = expand(&args[*i + 1]);
            *i += 2;
        }
        "--executor-bin" if has_next => {
            cfg.executor_path = expand(&args[*i + 1]);
            *i += 2;
        }
        "--bwrap-bin" if has_next => {
            cfg.bwrap_bin = expand(&args[*i + 1]);
            *i += 2;
        }
        "--rust-bridge-bin" if has_next => {
            cfg.rust_bridge_bin = expand(&args[*i + 1]);
            *i += 2;
        }
        "--app2unit-bin" if has_next => {
            cfg.app2unit_bin = expand(&args[*i + 1]);
            *i += 2;
        }
        "--systemctl-bin" if has_next => {
            cfg.systemctl_bin = expand(&args[*i + 1]);
            *i += 2;
        }
        "--vpnify-bin" if has_next => {
            cfg.vpnify_bin = expand(&args[*i + 1]);
            *i += 2;
        }
        "--notify-send-bin" if has_next => {
            cfg.notify_send_bin = expand(&args[*i + 1]);
            *i += 2;
        }
        "--pw-v4l2-bin" if has_next => {
            cfg.pw_v4l2_bin = expand(&args[*i + 1]);
            *i += 2;
        }
        "--syscalls-file" if has_next => {
            cfg.syscalls_file = expand(&args[*i + 1]);
            *i += 2;
        }
        "--net" if has_next => {
            cfg.network.clone_from(&args[*i + 1]);
            *i += 2;
        }
        "--no-net" => {
            cfg.network = "off".into();
            *i += 1;
        }
        _ => return false,
    }
    true
}

fn parse_misc_arg(
    cfg: &mut SandboxConfig,
    args: &[String],
    i: &mut usize,
    allowed_env: &[String],
) -> bool {
    let has_next = *i + 1 < args.len();
    match args[*i].as_str() {
        "-h" | "--help" => print_help_and_exit(),
        "--bwrap-arg" if has_next => {
            cfg.bwrap_extra_args.push(args[*i + 1].clone());
            *i += 2;
        }
        "-v" | "--verbose" => {
            cfg.flags |= CFG_VERBOSE;
            unsafe { env::set_var("SB_RUN_VERBOSE", "1") };
            *i += 1;
        }
        "--cli" => {
            cfg.flags |= CFG_IS_CLI;
            *i += 1;
        }
        "--gui" => {
            cfg.flags &= !CFG_IS_CLI;
            *i += 1;
        }
        "--vpnify" => {
            cfg.flags |= CFG_USE_VPNIFY;
            *i += 1;
        }
        "--bridge" if has_next => {
            if let Some(rule) = parse_bridge_arg(&args[*i + 1]) {
                cfg.bridges.push(rule);
            } else {
                fail_exit(&format!("invalid bridge specification '{}'", args[*i + 1]));
            }
            *i += 2;
        }
        "--inside-init" if has_next => {
            cfg.inside_init.push(args[*i + 1].clone());
            *i += 2;
        }
        "--env" if has_next => {
            cfg.extra_env.push(args[*i + 1].clone());
            *i += 2;
        }
        "--uid" if has_next => {
            cfg.custom_uid = Some(
                args[*i + 1]
                    .parse()
                    .unwrap_or_else(|_| fail_exit(&format!("invalid --uid '{}'", args[*i + 1]))),
            );
            *i += 2;
        }
        "--gid" if has_next => {
            cfg.custom_gid = Some(
                args[*i + 1]
                    .parse()
                    .unwrap_or_else(|_| fail_exit(&format!("invalid --gid '{}'", args[*i + 1]))),
            );
            *i += 2;
        }
        "--id" if has_next => {
            cfg.app_id.clone_from(&args[*i + 1]);
            *i += 2;
        }
        "--dir" if has_next => {
            cfg.custom_dir = Some(PathBuf::from(expand_env_path(&args[*i + 1], allowed_env)));
            *i += 2;
        }
        "--webcam" if has_next => {
            cfg.webcam = WebcamMode::parse(&args[*i + 1]);
            *i += 2;
        }
        _ => return false,
    }
    true
}

fn validate_subsystem_modes(cfg: &SandboxConfig) {
    let check_mode = |name: &str, val: &str, allowed: &[&str]| {
        if !allowed.contains(&val) {
            fail_exit(&format!(
                "invalid {name} mode '{val}'; allowed: {allowed:?}"
            ));
        }
    };
    check_mode(
        "network",
        &cfg.network,
        &["sandboxed", "singbox", "passthrough", "off"],
    );
    check_mode(
        "wayland",
        &cfg.wayland_mode,
        &["sandboxed", "passthrough", "off"],
    );
    check_mode("x11", &cfg.x11_mode, &["sandboxed", "passthrough", "off"]);
    check_mode(
        "pulse",
        &cfg.pulse_mode,
        &["sandboxed", "passthrough", "off"],
    );
    check_mode(
        "pipewire",
        &cfg.pipewire_mode,
        &["sandboxed", "passthrough", "off"],
    );
    check_mode("dbus", &cfg.dbus_mode, &["sandboxed", "passthrough", "off"]);
    check_mode("shm", &cfg.shm_mode, &["sandboxed", "passthrough"]);
    check_mode("tmp", &cfg.tmp_mode, &["sandboxed", "passthrough"]);
}

fn rule_syscall_name(raw: &str) -> &str {
    let after_prio = raw
        .strip_prefix('@')
        .and_then(|s| s.split_once(':'))
        .map_or(raw, |(_, rest)| rest);
    after_prio
        .split_once(':')
        .map_or(after_prio, |(name, _)| name)
}

fn apply_seccomp_cli_ops(cfg: &mut SandboxConfig) {
    let ops = std::mem::take(&mut cfg.seccomp_cli_ops);
    for op in ops {
        match op.kind {
            SeccompCliOpKind::Clear => cfg.seccomp_allow.clear(),
            SeccompCliOpKind::File(path) => {
                cfg.seccomp_allow = load_seccomp_file_list(&path);
            }
            SeccompCliOpKind::Allow(rule) => {
                if !cfg.seccomp_allow.contains(&rule) {
                    cfg.seccomp_allow.push(rule);
                }
            }
            SeccompCliOpKind::Block(rule) => {
                let is_plain = !rule.starts_with('@') && !rule.contains(':');
                if is_plain && !cfg.seccomp_allow.is_empty() {
                    cfg.seccomp_allow
                        .retain(|entry| rule_syscall_name(entry) != rule);
                } else {
                    cfg.seccomp_deny
                        .entry((cfg.seccomp_notify, cfg.seccomp_action))
                        .or_default()
                        .push(rule);
                }
            }
            SeccompCliOpKind::Deny(notify, action, rule) => {
                cfg.seccomp_deny
                    .entry((notify, action))
                    .or_default()
                    .push(rule);
            }
        }
    }
}

fn parse_cli_args(json_cfg: Option<&JsonValue>) -> SandboxConfig {
    let args: Vec<String> = env::args().collect();
    let mut cfg = SandboxConfig::from_optional_json(json_cfg);
    let mut i = 1;
    while i < args.len() {
        let allowed_env = cfg.allowed_env_vars.clone();
        let handled = parse_subsystem_flag(&args, &mut i, &mut cfg.subsystems)
            || parse_audio_display_arg(&mut cfg, &args, &mut i)
            || parse_seccomp_arg(&mut cfg, &args, &mut i)
            || parse_system_state_arg(&mut cfg, &args, &mut i)
            || parse_dbus_arg(&mut cfg, &args, &mut i)
            || parse_bind_arg(&mut cfg, &args, &mut i, &allowed_env)
            || parse_bins_and_net_arg(&mut cfg, &args, &mut i)
            || parse_misc_arg(&mut cfg, &args, &mut i, &allowed_env);
        if handled {
            continue;
        }
        if args[i] == "--" {
            cfg.command = args[i + 1..].to_vec();
            break;
        }
        if !args[i].starts_with('-') {
            cfg.command = args[i..].to_vec();
            break;
        }
        fail_exit(&format!("unrecognized option '{}'", args[i]));
    }

    apply_seccomp_cli_ops(&mut cfg);

    if cfg.app_id.is_empty() {
        let ts = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.subsec_nanos());
        let raw_name = cfg.command.first().map_or("app", |s| {
            Path::new(s)
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("app")
        });
        let safe_name: String = raw_name
            .chars()
            .map(|c| {
                if c.is_ascii_alphanumeric() || c == '_' {
                    c
                } else {
                    '_'
                }
            })
            .collect();
        cfg.app_id = format!("org.nixpak.{safe_name}_{ts:x}");
    } else if !cfg.app_id.contains('.') {
        cfg.app_id = format!("org.nixpak.{}", cfg.app_id);
    }

    validate_subsystem_modes(&cfg);
    cfg
}

fn require_binary(path: &Path, label: &str) {
    let s = path.to_string_lossy();
    if s.is_empty() {
        fail_exit(&format!("missing required {label} binary"));
    }
    if s.contains('/') {
        if !path.is_file() {
            fail_exit(&format!(
                "required {label} binary '{}' does not exist",
                path.display()
            ));
        }
        return;
    }
    if let Ok(path_env) = env::var("PATH") {
        for dir in env::split_paths(&path_env) {
            if dir.join(path).is_file() {
                return;
            }
        }
    }
    fail_exit(&format!("required {label} binary '{s}' not found in PATH"));
}

fn validate_required_binaries(cfg: &SandboxConfig) {
    require_binary(&cfg.bwrap_bin, "bwrap");
    require_binary(&cfg.executor_path, "sb-executor");
    if cfg.network == "singbox" {
        require_binary(&cfg.singbox_bin, "sing-box");
        require_binary(&cfg.rust_bridge_bin, "rust-bridge");
        if cfg.singbox_json.is_none()
            && (cfg.singbox_config.as_os_str().is_empty() || !cfg.singbox_config.is_file())
        {
            fail_exit("missing required singbox_config for network == \"singbox\"");
        }
    }
    if cfg.network == "sandboxed" {
        require_binary(&cfg.pasta_bin, "pasta");
    }
    if cfg.wayland_mode == "sandboxed" {
        require_binary(&cfg.way_secure_bin, "way-secure");
    }
    if cfg.x11_mode == "sandboxed" {
        require_binary(&cfg.xwayland_satellite_bin, "xwayland-satellite");
    }
    if cfg.dbus_mode == "sandboxed" || (cfg.flags & CFG_SYSTEM_DBUS) != 0 {
        require_binary(&cfg.dbus_proxy_bin, "xdg-dbus-proxy");
    }
    if !cfg.bridges.is_empty() {
        require_binary(&cfg.rust_bridge_bin, "rust-bridge");
    }
    if (cfg.flags & CFG_USE_VPNIFY) != 0 {
        require_binary(&cfg.vpnify_bin, "vpnify");
    }
    if cfg.webcam == WebcamMode::Portal {
        require_binary(&cfg.pw_v4l2_bin, "pw-v4l2");
    }
    if (cfg.flags & CFG_SCOPE) != 0 {
        require_binary(&cfg.app2unit_bin, "app2unit");
        require_binary(&cfg.systemctl_bin, "systemctl");
    }
    if (cfg.flags & CFG_SECCOMP) != 0
        && (cfg.syscalls_file.as_os_str().is_empty() || !cfg.syscalls_file.is_file())
    {
        fail_exit("missing required syscalls_file when seccomp is enabled");
    }
}

// ---------------------------------------------------------------------------
// $EDITOR Helper (Strictly $EDITOR, Fail-Closed)
// ---------------------------------------------------------------------------

fn run_user_editor(path: &Path) {
    let editor_raw = env::var("EDITOR")
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| fail_exit("$EDITOR is not set; cannot launch editor"));

    let mut parts = editor_raw.split_whitespace();
    let Some(cmd_bin) = parts.next() else {
        fail_exit("$EDITOR is empty");
    };
    let args: Vec<&str> = parts.collect();
    require_binary(Path::new(cmd_bin), "$EDITOR");

    let status = Command::new(cmd_bin)
        .args(&args)
        .arg(path)
        .status()
        .unwrap_or_else(|e| fail_exit(&format!("failed to execute $EDITOR ('{cmd_bin}'): {e}")));

    if !status.success() {
        fail_exit(&format!("$EDITOR exited with status {:?}", status.code()));
    }
}

// ---------------------------------------------------------------------------
// Sing-Box Configurator
// ---------------------------------------------------------------------------

fn prepare_singbox_config(cfg: &mut SandboxConfig, sandbox_runtime: &Path) {
    if let Some(ref json_str) = cfg.singbox_json {
        if let Err(e) = parse_json(json_str) {
            fail_exit(&format!("invalid --singbox-json payload: {e}"));
        }
        let target = sandbox_runtime.join("sing-box.json");
        if let Err(e) = fs::write(&target, json_str) {
            fail_exit(&format!("failed to write '{}': {e}", target.display()));
        }
        cfg.singbox_config = target;
    }

    if (cfg.flags & CFG_EDIT_SINGBOX) != 0 {
        let initial = fs::read_to_string(&cfg.singbox_config).unwrap_or_else(|e| {
            fail_exit(&format!(
                "failed to read sing-box config '{}': {e}",
                cfg.singbox_config.display()
            ))
        });
        let target = sandbox_runtime.join("sing-box-edited.json");
        if let Err(e) = fs::write(&target, &initial) {
            fail_exit(&format!("failed to write '{}': {e}", target.display()));
        }
        run_user_editor(&target);
        let edited = fs::read_to_string(&target)
            .unwrap_or_else(|e| fail_exit(&format!("failed to read edited sing-box JSON: {e}")));
        if let Err(e) = parse_json(&edited) {
            fail_exit(&format!(
                "edited sing-box config contains invalid JSON: {e}"
            ));
        }
        cfg.singbox_config = target;
        if cfg.command.is_empty() {
            println!("{}", cfg.singbox_config.display());
            exit(0);
        }
    }

    if cfg.network == "singbox" && !cfg.singbox_config.is_file() {
        fail_exit(&format!(
            "sing-box config '{}' does not exist",
            cfg.singbox_config.display()
        ));
    }
}

// ---------------------------------------------------------------------------
// Seccomp Table, BPF Compiler, and Notification Supervisor
// ---------------------------------------------------------------------------

struct SyscallTable {
    x86_64: HashMap<String, u32>,
    i386: HashMap<String, u32>,
    x86_64_names: HashMap<u32, String>,
    i386_names: HashMap<u32, String>,
}

impl SyscallTable {
    fn load(path: &Path) -> Self {
        let root = read_and_parse_json_file(path);
        let parse_arch = |arch: &str| -> (HashMap<String, u32>, HashMap<u32, String>) {
            let mut by_name = HashMap::new();
            let mut by_nr = HashMap::new();
            for (name, val) in root.get_req(arch, "syscalls").as_obj(arch) {
                if let JsonValue::Int(n) = val
                    && let Ok(nr) = u32::try_from(*n)
                {
                    by_name.insert(name.clone(), nr);
                    by_nr.entry(nr).or_insert_with(|| name.clone());
                } else {
                    fail_exit(&format!("invalid syscall number for '{arch}.{name}'"));
                }
            }
            (by_name, by_nr)
        };
        let (x86_64, x86_64_names) = parse_arch("x86_64");
        let (i386, i386_names) = parse_arch("i386");
        Self {
            x86_64,
            i386,
            x86_64_names,
            i386_names,
        }
    }

    fn resolve_name(&self, arch: u32, nr: u32) -> (&'static str, String) {
        if arch == AUDIT_ARCH_X86_64 {
            let name = self
                .x86_64_names
                .get(&nr)
                .cloned()
                .unwrap_or_else(|| format!("syscall_{nr}"));
            ("x86_64", name)
        } else if arch == AUDIT_ARCH_I386 {
            let name = self
                .i386_names
                .get(&nr)
                .cloned()
                .unwrap_or_else(|| format!("syscall_{nr}"));
            ("i386", name)
        } else {
            ("unknown", format!("syscall_{nr}"))
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy)]
struct SockFilter {
    code: u16,
    jt: u8,
    jf: u8,
    k: u32,
}

const fn bpf_stmt(code: u16, k: u32) -> SockFilter {
    SockFilter {
        code,
        jt: 0,
        jf: 0,
        k,
    }
}

const fn bpf_jump(code: u16, k: u32, jt: u8, jf: u8) -> SockFilter {
    SockFilter { code, jt, jf, k }
}

fn load_seccomp_file_list(path: &Path) -> Vec<String> {
    let raw = fs::read_to_string(path).unwrap_or_else(|e| {
        fail_exit(&format!(
            "failed to read seccomp file '{}': {e}",
            path.display()
        ))
    });
    let trimmed = raw.trim();
    if trimmed.starts_with('[') {
        let val = parse_json(trimmed).unwrap_or_else(|e| {
            fail_exit(&format!("invalid seccomp JSON '{}': {e}", path.display()))
        });
        match val {
            JsonValue::Array(arr) => arr
                .into_iter()
                .map(|item| match item {
                    JsonValue::Str(s) => s,
                    _ => fail_exit("seccomp JSON array must contain strings"),
                })
                .collect(),
            _ => fail_exit("seccomp JSON file must be a string array"),
        }
    } else {
        trimmed
            .lines()
            .map(str::trim)
            .filter(|s| !s.is_empty() && !s.starts_with('#'))
            .map(ToString::to_string)
            .collect()
    }
}

fn parse_seccomp_cond(raw: &str) -> SeccompCond {
    let cond = raw.trim();
    let Some(rest) = cond.strip_prefix("arg") else {
        fail_exit(&format!("invalid seccomp condition '{cond}'"));
    };
    let mut chars = rest.chars();
    let Some(arg_ch) = chars.next() else {
        fail_exit(&format!("missing arg index in '{cond}'"));
    };
    let Some(arg_digit) = arg_ch.to_digit(10) else {
        fail_exit(&format!("invalid arg index in '{cond}'"));
    };
    let Ok(arg_idx) = u8::try_from(arg_digit) else {
        fail_exit(&format!("invalid arg index in '{cond}'"));
    };
    if arg_idx > 5 {
        fail_exit(&format!("seccomp arg index out of range 0..=5 in '{cond}'"));
    }

    let (u32_only, after_idx) = chars.as_str().strip_prefix("_u32").map_or_else(
        || (false, chars.as_str().trim_start()),
        |rem| (true, rem.trim_start()),
    );
    let ops = [
        ("==", SeccompOp::Eq),
        ("!=", SeccompOp::Ne),
        ("!&", SeccompOp::MaskZero),
        ("<=", SeccompOp::Le),
        (">=", SeccompOp::Ge),
        ("&", SeccompOp::MaskNonZero),
        ("<", SeccompOp::Lt),
        (">", SeccompOp::Gt),
    ];
    let mut parsed_op = None;
    let mut val_str = "";
    for (sym, op) in ops {
        if let Some(rem) = after_idx.strip_prefix(sym) {
            parsed_op = Some(op);
            val_str = rem.trim();
            break;
        }
    }
    let Some(op) = parsed_op else {
        fail_exit(&format!("invalid operator in seccomp condition '{cond}'"));
    };
    if val_str.is_empty() {
        fail_exit(&format!("missing value in seccomp condition '{cond}'"));
    }
    let val = val_str
        .strip_prefix("0x")
        .or_else(|| val_str.strip_prefix("0X"))
        .map_or_else(
            || val_str.parse::<u64>(),
            |hex| u64::from_str_radix(hex, 16),
        )
        .unwrap_or_else(|_| fail_exit(&format!("invalid u64 value '{val_str}' in '{cond}'")));
    if u32_only && val > u64::from(u32::MAX) {
        fail_exit(&format!(
            "_u32 seccomp value '{val_str}' exceeds u32::MAX in '{cond}'"
        ));
    }

    SeccompCond {
        arg_idx,
        u32_only,
        op,
        val,
    }
}

fn parse_seccomp_rule(raw: &str, verdict: SeccompVerdict, table: &SyscallTable) -> SeccompRule {
    let s = raw.trim();
    if s.is_empty() {
        fail_exit("empty seccomp rule");
    }
    let (priority, rem) = s.strip_prefix('@').map_or((0, s), |after_at| {
        let Some((prio_str, rest)) = after_at.split_once(':') else {
            fail_exit(&format!(
                "invalid seccomp priority syntax in '{s}' (expected @<prio>:<syscall>)"
            ));
        };
        let prio = prio_str
            .trim()
            .parse::<i32>()
            .unwrap_or_else(|_| fail_exit(&format!("invalid priority '{prio_str}' in '{s}'")));
        (prio, rest.trim())
    });

    let (syscall, conds) = match rem.split_once(':') {
        Some((name, cond_part)) => {
            let name = name.trim();
            let cond_part = cond_part.trim();
            if cond_part.is_empty() {
                fail_exit(&format!("empty condition list in seccomp rule '{s}'"));
            }
            let conds = cond_part.split("&&").map(parse_seccomp_cond).collect();
            (name, conds)
        }
        None => (rem, Vec::new()),
    };

    if syscall.is_empty() {
        fail_exit(&format!("missing syscall name in seccomp rule '{s}'"));
    }
    if !table.x86_64.contains_key(syscall) && !table.i386.contains_key(syscall) {
        fail_exit(&format!("unknown seccomp syscall '{syscall}'"));
    }

    SeccompRule {
        priority,
        syscall: syscall.to_string(),
        conds,
        verdict,
    }
}

#[derive(Clone, Debug)]
struct CompiledRule {
    priority: i32,
    conds: Vec<SeccompCond>,
    verdict: SeccompVerdict,
}

struct SeccompPolicy {
    x86_64: HashMap<u32, Vec<CompiledRule>>,
    i386: HashMap<u32, Vec<CompiledRule>>,
    default_verdict: SeccompVerdict,
    any_log: bool,
    any_notify: bool,
}

impl SeccompPolicy {
    fn from_rules(
        rules: &[SeccompRule],
        allow_empty: bool,
        default_notify: SeccompNotify,
        default_action: SeccompAction,
        table: &SyscallTable,
    ) -> Self {
        let default_verdict = if allow_empty {
            SeccompVerdict::Allow
        } else {
            SeccompVerdict::Deny {
                notify: default_notify,
                action: default_action,
            }
        };

        let mut any_log = matches!(
            default_verdict,
            SeccompVerdict::Deny {
                notify: SeccompNotify::Log,
                ..
            }
        );
        let mut any_notify = matches!(
            default_verdict,
            SeccompVerdict::Deny {
                notify: SeccompNotify::Notify,
                ..
            }
        );

        let mut x86_64: HashMap<u32, Vec<CompiledRule>> = HashMap::new();
        let mut i386: HashMap<u32, Vec<CompiledRule>> = HashMap::new();

        for rule in rules {
            match rule.verdict {
                SeccompVerdict::Deny {
                    notify: SeccompNotify::Log,
                    ..
                } => any_log = true,
                SeccompVerdict::Deny {
                    notify: SeccompNotify::Notify,
                    ..
                } => any_notify = true,
                _ => {}
            }
            let compiled = CompiledRule {
                priority: rule.priority,
                conds: rule.conds.clone(),
                verdict: rule.verdict,
            };
            if let Some(&nr) = table.x86_64.get(&rule.syscall) {
                x86_64.entry(nr).or_default().push(compiled.clone());
            }
            if let Some(&nr) = table.i386.get(&rule.syscall) {
                i386.entry(nr).or_default().push(compiled);
            }
        }

        let sort_chain = |chain: &mut Vec<CompiledRule>| {
            chain.sort_by(|a, b| {
                b.priority
                    .cmp(&a.priority)
                    .then_with(|| a.conds.is_empty().cmp(&b.conds.is_empty()))
                    .then_with(|| {
                        let a_allow = matches!(a.verdict, SeccompVerdict::Allow);
                        let b_allow = matches!(b.verdict, SeccompVerdict::Allow);
                        a_allow.cmp(&b_allow)
                    })
            });
        };
        for chain in x86_64.values_mut() {
            sort_chain(chain);
        }
        for chain in i386.values_mut() {
            sort_chain(chain);
        }

        Self {
            x86_64,
            i386,
            default_verdict,
            any_log,
            any_notify,
        }
    }

    const fn needs_monitor(&self) -> bool {
        self.any_log || self.any_notify
    }

    const fn needs_notify_send(&self) -> bool {
        self.any_notify
    }

    fn match_verdict(&self, arch: u32, nr: u32, args: [u64; 6]) -> SeccompVerdict {
        let (map, is_64bit) = if arch == AUDIT_ARCH_X86_64 {
            (&self.x86_64, true)
        } else if arch == AUDIT_ARCH_I386 {
            (&self.i386, false)
        } else {
            return self.default_verdict;
        };
        if let Some(chain) = map.get(&nr) {
            for rule in chain {
                if rule.conds.iter().all(|c| c.matches(args, is_64bit)) {
                    return rule.verdict;
                }
            }
        }
        self.default_verdict
    }
}

fn print_seccomp_list(cfg: &SandboxConfig) {
    let mode = if cfg.seccomp_allow.is_empty() {
        "denylist"
    } else {
        "allowlist"
    };
    println!(
        "default: notify={} action={} mode={mode}",
        cfg.seccomp_notify.as_str(),
        cfg.seccomp_action.as_str()
    );
    if cfg.seccomp_allow.is_empty() {
        println!("allow: (empty)");
    } else {
        println!("allow ({}):", cfg.seccomp_allow.len());
        for rule in &cfg.seccomp_allow {
            println!("  {rule}");
        }
    }
    for notify in [
        SeccompNotify::None,
        SeccompNotify::Log,
        SeccompNotify::Notify,
    ] {
        for action in [
            SeccompAction::Eperm,
            SeccompAction::Enosys,
            SeccompAction::Eacces,
            SeccompAction::Einval,
            SeccompAction::Enotsup,
            SeccompAction::Kill,
            SeccompAction::Trap,
        ] {
            if let Some(list) = cfg.seccomp_deny.get(&(notify, action))
                && !list.is_empty()
            {
                println!("deny.{}.{}:", notify.as_str(), action.as_str());
                for rule in list {
                    println!("  {rule}");
                }
            }
        }
    }
}

fn resolve_seccomp_policy(
    cfg: &mut SandboxConfig,
    table: &SyscallTable,
    runtime: &Path,
) -> SeccompPolicy {
    if (cfg.flags & CFG_EDIT_SECCOMP) != 0 {
        let mut json_buf = String::from("[\n");
        for (idx, item) in cfg.seccomp_allow.iter().enumerate() {
            let comma = if idx + 1 < cfg.seccomp_allow.len() {
                ","
            } else {
                ""
            };
            let _ = writeln!(json_buf, "  \"{item}\"{comma}");
        }
        json_buf.push_str("]\n");

        let edit_path = runtime.join("seccomp-edit.json");
        if let Err(e) = fs::write(&edit_path, json_buf) {
            fail_exit(&format!("failed to write '{}': {e}", edit_path.display()));
        }
        run_user_editor(&edit_path);
        cfg.seccomp_allow = load_seccomp_file_list(&edit_path);
    }

    let mut rules = Vec::with_capacity(cfg.seccomp_allow.len() + 16);
    for raw in &cfg.seccomp_allow {
        rules.push(parse_seccomp_rule(raw, SeccompVerdict::Allow, table));
    }
    for (&(notify, action), list) in &cfg.seccomp_deny {
        for raw in list {
            rules.push(parse_seccomp_rule(
                raw,
                SeccompVerdict::Deny { notify, action },
                table,
            ));
        }
    }

    let policy = SeccompPolicy::from_rules(
        &rules,
        cfg.seccomp_allow.is_empty(),
        cfg.seccomp_notify,
        cfg.seccomp_action,
        table,
    );

    if (cfg.flags & CFG_SECCOMP_LIST) != 0 {
        print_seccomp_list(cfg);
        if cfg.command.is_empty() {
            exit(0);
        }
    }
    if (cfg.flags & CFG_EDIT_SECCOMP) != 0 && cfg.command.is_empty() {
        println!("{}", cfg.seccomp_allow.join(","));
        exit(0);
    }

    policy
}

fn split_u64_words(val: u64) -> (u32, u32) {
    let lo = u32::try_from(val & 0xFFFF_FFFF).unwrap_or(0);
    let hi = u32::try_from(val >> 32).unwrap_or(0);
    (lo, hi)
}

fn emit_cond_32(
    insns: &mut Vec<SockFilter>,
    lo_off: u32,
    cond: SeccompCond,
    fail_patches: &mut Vec<(usize, bool)>,
) {
    let (v_lo, v_hi) = split_u64_words(cond.val);
    match cond.op {
        SeccompOp::Eq => {
            if v_hi != 0 {
                insns.push(bpf_jump(BPF_JMP | BPF_JA, 0, 0, 0));
                fail_patches.push((insns.len() - 1, true));
            } else {
                insns.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, lo_off));
                insns.push(bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, v_lo, 0, 0));
                fail_patches.push((insns.len() - 1, false));
            }
        }
        SeccompOp::Ne => {
            if v_hi == 0 {
                insns.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, lo_off));
                insns.push(bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, v_lo, 0, 0));
                fail_patches.push((insns.len() - 1, true));
            }
        }
        SeccompOp::MaskNonZero => {
            insns.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, lo_off));
            insns.push(bpf_jump(BPF_JMP | BPF_JSET | BPF_K, v_lo, 0, 0));
            fail_patches.push((insns.len() - 1, false));
        }
        SeccompOp::MaskZero => {
            insns.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, lo_off));
            insns.push(bpf_jump(BPF_JMP | BPF_JSET | BPF_K, v_lo, 0, 0));
            fail_patches.push((insns.len() - 1, true));
        }
        SeccompOp::Gt => {
            if v_hi != 0 {
                insns.push(bpf_jump(BPF_JMP | BPF_JA, 0, 0, 0));
                fail_patches.push((insns.len() - 1, true));
            } else {
                insns.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, lo_off));
                insns.push(bpf_jump(BPF_JMP | BPF_JGT | BPF_K, v_lo, 0, 0));
                fail_patches.push((insns.len() - 1, false));
            }
        }
        SeccompOp::Ge => {
            if v_hi != 0 {
                insns.push(bpf_jump(BPF_JMP | BPF_JA, 0, 0, 0));
                fail_patches.push((insns.len() - 1, true));
            } else {
                insns.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, lo_off));
                insns.push(bpf_jump(BPF_JMP | BPF_JGE | BPF_K, v_lo, 0, 0));
                fail_patches.push((insns.len() - 1, false));
            }
        }
        SeccompOp::Lt => {
            if v_hi == 0 {
                insns.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, lo_off));
                insns.push(bpf_jump(BPF_JMP | BPF_JGE | BPF_K, v_lo, 0, 0));
                fail_patches.push((insns.len() - 1, true));
            }
        }
        SeccompOp::Le => {
            if v_hi == 0 {
                insns.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, lo_off));
                insns.push(bpf_jump(BPF_JMP | BPF_JGT | BPF_K, v_lo, 0, 0));
                fail_patches.push((insns.len() - 1, true));
            }
        }
    }
}

fn emit_cond_64(
    insns: &mut Vec<SockFilter>,
    lo_off: u32,
    hi_off: u32,
    cond: SeccompCond,
    fail_patches: &mut Vec<(usize, bool)>,
) {
    let (v_lo, v_hi) = split_u64_words(cond.val);
    match cond.op {
        SeccompOp::Eq => {
            insns.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, hi_off));
            insns.push(bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, v_hi, 0, 0));
            fail_patches.push((insns.len() - 1, false));
            insns.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, lo_off));
            insns.push(bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, v_lo, 0, 0));
            fail_patches.push((insns.len() - 1, false));
        }
        SeccompOp::Ne => {
            insns.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, hi_off));
            insns.push(bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, v_hi, 0, 2));
            insns.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, lo_off));
            insns.push(bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, v_lo, 0, 0));
            fail_patches.push((insns.len() - 1, true));
        }
        SeccompOp::MaskNonZero => {
            if v_hi == 0 {
                insns.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, lo_off));
                insns.push(bpf_jump(BPF_JMP | BPF_JSET | BPF_K, v_lo, 0, 0));
            } else if v_lo == 0 {
                insns.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, hi_off));
                insns.push(bpf_jump(BPF_JMP | BPF_JSET | BPF_K, v_hi, 0, 0));
            } else {
                insns.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, hi_off));
                insns.push(bpf_jump(BPF_JMP | BPF_JSET | BPF_K, v_hi, 2, 0));
                insns.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, lo_off));
                insns.push(bpf_jump(BPF_JMP | BPF_JSET | BPF_K, v_lo, 0, 0));
            }
            fail_patches.push((insns.len() - 1, false));
        }
        SeccompOp::MaskZero => {
            if v_hi != 0 {
                insns.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, hi_off));
                insns.push(bpf_jump(BPF_JMP | BPF_JSET | BPF_K, v_hi, 0, 0));
                fail_patches.push((insns.len() - 1, true));
            }
            if v_lo != 0 || v_hi == 0 {
                insns.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, lo_off));
                insns.push(bpf_jump(BPF_JMP | BPF_JSET | BPF_K, v_lo, 0, 0));
                fail_patches.push((insns.len() - 1, true));
            }
        }
        SeccompOp::Gt | SeccompOp::Ge => {
            let low_op = if cond.op == SeccompOp::Gt {
                BPF_JGT
            } else {
                BPF_JGE
            };
            insns.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, hi_off));
            insns.push(bpf_jump(BPF_JMP | BPF_JGT | BPF_K, v_hi, 3, 0));
            insns.push(bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, v_hi, 0, 0));
            fail_patches.push((insns.len() - 1, false));
            insns.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, lo_off));
            insns.push(bpf_jump(BPF_JMP | low_op | BPF_K, v_lo, 0, 0));
            fail_patches.push((insns.len() - 1, false));
        }
        SeccompOp::Lt | SeccompOp::Le => {
            let low_op = if cond.op == SeccompOp::Lt {
                BPF_JGE
            } else {
                BPF_JGT
            };
            insns.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, hi_off));
            insns.push(bpf_jump(BPF_JMP | BPF_JGT | BPF_K, v_hi, 0, 0));
            fail_patches.push((insns.len() - 1, true));
            insns.push(bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, v_hi, 0, 2));
            insns.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, lo_off));
            insns.push(bpf_jump(BPF_JMP | low_op | BPF_K, v_lo, 0, 0));
            fail_patches.push((insns.len() - 1, true));
        }
    }
}

fn patch_fail_jumps(insns: &mut [SockFilter], patches: &[(usize, bool)], target_idx: usize) {
    for &(idx, is_jt) in patches {
        let delta = target_idx.saturating_sub(idx + 1);
        if (insns[idx].code & 0xFF) == (BPF_JMP | BPF_JA) {
            insns[idx].k = u32::try_from(delta)
                .unwrap_or_else(|_| fail_exit("seccomp BPF jump offset overflow"));
        } else {
            let off = u8::try_from(delta)
                .unwrap_or_else(|_| fail_exit("seccomp rule condition block exceeds u8 jump"));
            if is_jt {
                insns[idx].jt = off;
            } else {
                insns[idx].jf = off;
            }
        }
    }
}

fn compile_syscall_chain(
    chain: &[CompiledRule],
    default_ret: u32,
    is_64bit: bool,
) -> Vec<SockFilter> {
    let mut block = Vec::new();
    let mut hit_unfiltered = false;

    for rule in chain {
        if rule.conds.is_empty() {
            block.push(bpf_stmt(BPF_RET | BPF_K, rule.verdict.bpf_ret()));
            hit_unfiltered = true;
            break;
        }
        let mut fail_patches = Vec::new();
        for &cond in &rule.conds {
            let lo_off = 16 + u32::from(cond.arg_idx) * 8;
            if is_64bit && !cond.u32_only {
                emit_cond_64(&mut block, lo_off, lo_off + 4, cond, &mut fail_patches);
            } else {
                emit_cond_32(&mut block, lo_off, cond, &mut fail_patches);
            }
        }
        block.push(bpf_stmt(BPF_RET | BPF_K, rule.verdict.bpf_ret()));
        let next_idx = block.len();
        patch_fail_jumps(&mut block, &fail_patches, next_idx);
    }

    if !hit_unfiltered {
        block.push(bpf_stmt(BPF_RET | BPF_K, default_ret));
    }
    block
}

fn compile_arch_filter(
    insns: &mut Vec<SockFilter>,
    chains: &HashMap<u32, Vec<CompiledRule>>,
    default_ret: u32,
    is_64bit: bool,
) {
    insns.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, 0));

    let mut nrs: Vec<u32> = chains.keys().copied().collect();
    nrs.sort_unstable();

    for nr in nrs {
        let Some(chain) = chains.get(&nr) else {
            continue;
        };
        let block = compile_syscall_chain(chain, default_ret, is_64bit);
        let block_len = block.len();
        if let Ok(skip_u8) = u8::try_from(block_len) {
            insns.push(bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, nr, 0, skip_u8));
        } else {
            let skip_u32 = u32::try_from(block_len)
                .unwrap_or_else(|_| fail_exit("seccomp syscall block too large"));
            insns.push(bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, nr, 0, 1));
            insns.push(bpf_stmt(BPF_JMP | BPF_JA, skip_u32));
        }
        insns.extend_from_slice(&block);
    }

    insns.push(bpf_stmt(BPF_RET | BPF_K, default_ret));
}

fn compile_seccomp_bpf(policy: &SeccompPolicy) -> Vec<u8> {
    let default_ret = policy.default_verdict.bpf_ret();

    let mut x64_insns = Vec::new();
    compile_arch_filter(&mut x64_insns, &policy.x86_64, default_ret, true);

    let mut i386_insns = Vec::new();
    compile_arch_filter(&mut i386_insns, &policy.i386, default_ret, false);

    let x64_skip = u32::try_from(x64_insns.len())
        .unwrap_or_else(|_| fail_exit("seccomp BPF program too large"));

    let mut insns = Vec::with_capacity(5 + x64_insns.len() + i386_insns.len());
    insns.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, 4));
    insns.push(bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, AUDIT_ARCH_X86_64, 3, 0));
    insns.push(bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, AUDIT_ARCH_I386, 1, 0));
    insns.push(bpf_stmt(BPF_RET | BPF_K, default_ret));
    insns.push(bpf_stmt(BPF_JMP | BPF_JA, x64_skip));

    insns.extend_from_slice(&x64_insns);
    insns.extend_from_slice(&i386_insns);

    if insns.len() > 4096 {
        fail_exit("compiled seccomp BPF exceeds 4096 instructions");
    }

    let mut bytes = Vec::with_capacity(insns.len() * 8);
    for f in insns {
        bytes.extend_from_slice(&f.code.to_ne_bytes());
        bytes.push(f.jt);
        bytes.push(f.jf);
        bytes.extend_from_slice(&f.k.to_ne_bytes());
    }
    bytes
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct SeccompData {
    nr: i32,
    arch: u32,
    instruction_pointer: u64,
    args: [u64; 6],
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct SeccompNotif {
    id: u64,
    pid: u32,
    flags: u32,
    data: SeccompData,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct SeccompNotifResp {
    id: u64,
    val: i64,
    error: i32,
    flags: u32,
}

fn format_utc_timestamp() -> String {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs());
    let days = (secs / 86_400).cast_signed();
    let rem = secs % 86_400;
    let hour = rem / 3_600;
    let minute = (rem % 3_600) / 60;
    let second = rem % 60;

    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097).cast_unsigned();
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe.cast_signed() + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = y + i64::from(m <= 2);
    format!("{year:04}-{m:02}-{d:02}T{hour:02}:{minute:02}:{second:02}Z")
}

fn append_seccomp_log(
    ctx: &SeccompMonitorCtx<'_>,
    req: &SeccompNotif,
    arch_str: &str,
    syscall_name: &str,
    nr: u32,
    action: SeccompAction,
) {
    if let Some(parent) = ctx.log_path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Ok(mut file) = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(ctx.log_path)
    {
        let ts = format_utc_timestamp();
        let args = req.data.args;
        let _ = writeln!(
            file,
            "[{ts}] app={} pid={} arch={arch_str} syscall={syscall_name}({nr}) action={} args=[{:#x},{:#x},{:#x},{:#x},{:#x},{:#x}]",
            ctx.app_id,
            req.pid,
            action.as_str(),
            args[0],
            args[1],
            args[2],
            args[3],
            args[4],
            args[5],
        );
    }
}

#[derive(Clone, Copy)]
struct NotifStats {
    replace_id: Option<u32>,
    count: u64,
}

fn send_seccomp_notification(
    ctx: &SeccompMonitorCtx<'_>,
    req: &SeccompNotif,
    arch_str: &str,
    syscall_name: &str,
    nr: u32,
    action: SeccompAction,
    stats: NotifStats,
) -> Option<u32> {
    let mut cmd = Command::new(ctx.notify_bin);
    cmd.args(["-u", "critical", "-p"]);
    if let Some(id) = stats.replace_id {
        cmd.args(["-r", &id.to_string()]);
    }
    let summary = format!("Seccomp blocked ({})", ctx.app_id);
    let args = req.data.args;
    let body = format!(
        "Syscall: {syscall_name} ({arch_str}:{nr}) action={} [x{}]\nargs=[{:#x},{:#x},{:#x},{:#x},{:#x},{:#x}]",
        action.as_str(),
        stats.count,
        args[0],
        args[1],
        args[2],
        args[3],
        args[4],
        args[5],
    );
    cmd.arg(&summary).arg(&body);
    let out = cmd.output().ok()?;
    String::from_utf8_lossy(&out.stdout)
        .trim()
        .parse::<u32>()
        .ok()
        .or(stats.replace_id)
}

struct SeccompMonitorCtx<'a> {
    table: &'a SyscallTable,
    policy: &'a SeccompPolicy,
    notify_bin: &'a Path,
    log_path: &'a Path,
    app_id: &'a str,
}

fn handle_seccomp_notif_fd(
    fd: i32,
    ctx: &SeccompMonitorCtx<'_>,
    counts: &mut HashMap<(u32, u32), (Option<u32>, u64)>,
) -> bool {
    let mut req = SeccompNotif::default();
    let r = unsafe {
        ioctl(
            fd,
            SECCOMP_IOCTL_NOTIF_RECV,
            (&raw mut req).cast::<c_void>(),
        )
    };
    if r < 0 {
        let err = std::io::Error::last_os_error().raw_os_error().unwrap_or(0);
        return err == 2 || err == 9 || err == 19; // ENOENT / EBADF / ENODEV -> closed
    }

    let nr_u32 = u32::try_from(req.data.nr).unwrap_or(0);
    let verdict = ctx
        .policy
        .match_verdict(req.data.arch, nr_u32, req.data.args);

    let (error_code, kill_sig) = match verdict {
        SeccompVerdict::Allow => (0, None),
        SeccompVerdict::Deny { action, .. } => action.errno().map_or_else(
            || (-1, Some(if action == SeccompAction::Kill { 9 } else { 31 })),
            |errno| (-errno, None),
        ),
    };

    let mut resp = SeccompNotifResp {
        id: req.id,
        val: 0,
        error: error_code,
        flags: 0,
    };
    let _ = unsafe {
        ioctl(
            fd,
            SECCOMP_IOCTL_NOTIF_SEND,
            (&raw mut resp).cast::<c_void>(),
        )
    };
    if let Some(sig) = kill_sig
        && let Ok(pid_i32) = i32::try_from(req.pid)
    {
        unsafe { kill(pid_i32, sig) };
    }

    if let SeccompVerdict::Deny { notify, action } = verdict {
        let (arch_str, name) = ctx.table.resolve_name(req.data.arch, nr_u32);
        match notify {
            SeccompNotify::Notify => {
                let entry = counts.entry((req.data.arch, nr_u32)).or_insert((None, 0));
                entry.1 += 1;
                entry.0 = send_seccomp_notification(
                    ctx,
                    &req,
                    arch_str,
                    &name,
                    nr_u32,
                    action,
                    NotifStats {
                        replace_id: entry.0,
                        count: entry.1,
                    },
                );
            }
            SeccompNotify::Log => {
                append_seccomp_log(ctx, &req, arch_str, &name, nr_u32, action);
            }
            SeccompNotify::None => {}
        }
    }
    false
}

struct SeccompMonitorHandle {
    stop: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
}

impl SeccompMonitorHandle {
    fn shutdown(&mut self) {
        self.stop.store(true, Ordering::Release);
        if let Some(h) = self.thread.take() {
            let _ = h.join();
        }
    }
}

fn start_seccomp_monitor(
    runtime: &Path,
    table: Arc<SyscallTable>,
    policy: Arc<SeccompPolicy>,
    notify_bin: PathBuf,
    log_path: PathBuf,
    app_id: String,
) -> SeccompMonitorHandle {
    let sock_path = runtime.join("seccomp.sock");
    let _ = fs::remove_file(&sock_path);
    let listener = UnixListener::bind(&sock_path)
        .unwrap_or_else(|e| fail_exit(&format!("failed to bind seccomp socket: {e}")));
    let _ = listener.set_nonblocking(true);

    let stop = Arc::new(AtomicBool::new(false));
    let stop_flag = Arc::clone(&stop);

    let handle = thread::spawn(move || {
        let Some(epoll) = Epoll::new() else {
            return;
        };
        let listen_fd = listener.as_raw_fd();
        epoll.add(listen_fd);
        let mut notif_fds: BTreeSet<i32> = BTreeSet::new();
        let mut counts: HashMap<(u32, u32), (Option<u32>, u64)> = HashMap::new();
        let mut events = [EpollEvent { events: 0, data: 0 }; 16];
        let ctx = SeccompMonitorCtx {
            table: &table,
            policy: &policy,
            notify_bin: &notify_bin,
            log_path: &log_path,
            app_id: &app_id,
        };

        while !stop_flag.load(Ordering::Acquire) {
            let n = match epoll.wait(&mut events, 100) {
                Ok(n) => n,
                Err(4) => continue,
                Err(_) => break,
            };
            for ev in &events[..n] {
                let Ok(fd) = i32::try_from(ev.data) else {
                    continue;
                };
                if fd == listen_fd {
                    while let Ok((mut stream, _)) = listener.accept() {
                        if let Ok(owned) = recv_byte_with_fd(&stream) {
                            let nfd = owned.into_raw_fd();
                            if epoll.add(nfd) {
                                notif_fds.insert(nfd);
                            } else {
                                unsafe { close(nfd) };
                            }
                        }
                        let _ = stream.write_all(b"A");
                    }
                    continue;
                }
                if (ev.events & (EPOLLHUP | EPOLLERR)) != 0 && (ev.events & EPOLLIN) == 0 {
                    epoll.del_and_close(fd);
                    notif_fds.remove(&fd);
                    continue;
                }
                if handle_seccomp_notif_fd(fd, &ctx, &mut counts) {
                    epoll.del_and_close(fd);
                    notif_fds.remove(&fd);
                }
            }
        }
        for fd in notif_fds {
            epoll.del_and_close(fd);
        }
    });

    SeccompMonitorHandle {
        stop,
        thread: Some(handle),
    }
}

// ---------------------------------------------------------------------------
// Running Sandbox Connection & CLI Forwarding
// ---------------------------------------------------------------------------

fn get_token_for_app(app_id: &str) -> Option<[u8; 16]> {
    let uid = libc_getuid();
    let runtime_base = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| format!("/run/user/{uid}"));
    let token_path = PathBuf::from(format!("{runtime_base}/sb-tokens/{app_id}.token"));
    if let Ok(bytes) = fs::read(&token_path)
        && bytes.len() == 16
    {
        bytes.try_into().ok()
    } else {
        None
    }
}

fn create_token_for_app(app_id: &str) -> [u8; 16] {
    let uid = libc_getuid();
    let runtime_base = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| format!("/run/user/{uid}"));
    let tokens_dir = PathBuf::from(format!("{runtime_base}/sb-tokens"));
    let _ = fs::create_dir_all(&tokens_dir);
    let _ = fs::set_permissions(&tokens_dir, fs::Permissions::from_mode(0o700));
    let token_path = tokens_dir.join(format!("{app_id}.token"));

    let mut token = [0u8; 16];
    if let Ok(mut f) = fs::File::open("/dev/urandom") {
        let _ = f.read_exact(&mut token);
    }
    let _ = fs::write(&token_path, token);
    let _ = fs::set_permissions(&token_path, fs::Permissions::from_mode(0o600));
    token
}

fn cleanup_token_for_app(app_id: &str) {
    let uid = libc_getuid();
    let runtime_base = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| format!("/run/user/{uid}"));
    let _ = fs::remove_file(format!("{runtime_base}/sb-tokens/{app_id}.token"));
}

fn bytes_to_hex(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        let _ = write!(s, "{b:02x}");
    }
    s
}

fn try_connect_running_sandbox(
    ipc_sock: &Path,
    cfg: &SandboxConfig,
    seccomp_bpf: Option<&[u8]>,
) -> Option<i32> {
    let mut stream = UnixStream::connect(ipc_sock).ok()?;
    let cwd = env::current_dir().map_or_else(|_| "/".into(), |p| p.to_string_lossy().to_string());
    let env_vars: Vec<String> = env::vars().map(|(k, v)| format!("{k}={v}")).collect();
    let active_bpf = if (cfg.flags & CFG_HELPER_REQ) != 0 {
        None
    } else {
        seccomp_bpf
    };
    let payload = build_exec_payload(&cwd, &cfg.command, &env_vars, active_bpf);
    let payload_len = u32::try_from(payload.len()).unwrap_or(0);

    let is_cli = (cfg.flags & CFG_IS_CLI) != 0;
    let is_tty = unsafe { isatty(0) == 1 };
    let mut flags = 0u32;
    if (cfg.flags & CFG_HELPER_REQ) != 0 {
        flags |= FLAG_HELPER;
    }
    if is_cli {
        flags |= FLAG_WAIT_EXIT;
    }
    if is_tty {
        flags |= FLAG_IS_TTY;
    }
    if active_bpf.is_some() {
        flags |= FLAG_SECCOMP;
    }

    let mut header = IpcHeader::new(MSG_EXEC_REQUEST, payload_len, flags);
    if let Some(token) = get_token_for_app(&cfg.app_id) {
        header.extra = token;
    }
    let fds = if is_cli { vec![0, 1, 2] } else { Vec::new() };
    if send_header_with_fds(&stream, &header, &fds).is_err() {
        return None;
    }
    if stream.write_all(&payload).is_err() {
        return None;
    }
    let _ = stream.flush();

    if !is_cli {
        return Some(0);
    }
    Some(wait_for_cli_exit_response(&mut stream, is_tty))
}

fn forward_cli_events(stream: &mut UnixStream, is_tty: bool) {
    if is_tty && PENDING_WINCH.swap(0, Ordering::Relaxed) != 0 {
        send_initial_winsize(stream);
    }
    let sig = PENDING_SIGNAL.swap(0, Ordering::Relaxed);
    if sig != 0
        && let Ok(sig_len) = u32::try_from(size_of::<i32>())
    {
        let sig_hdr = IpcHeader::new(MSG_SIGNAL, sig_len, 0);
        let _ = stream.write_all(&sig_hdr.to_bytes());
        let _ = stream.write_all(&sig.to_le_bytes());
        let _ = stream.flush();
    }
}

fn send_initial_winsize(stream: &mut UnixStream) {
    let mut ws = WinSizePayload {
        row: 0,
        col: 0,
        xpixel: 0,
        ypixel: 0,
    };
    if unsafe { ioctl(0, TIOCGWINSZ, &raw mut ws.row) } == 0
        && let Ok(ws_len) = u32::try_from(size_of::<WinSizePayload>())
    {
        let ws_hdr = IpcHeader::new(MSG_WINSIZE, ws_len, 0);
        let _ = stream.write_all(&ws_hdr.to_bytes());
        let ws_ptr = (&raw const ws).cast::<u8>();
        let ws_bytes = unsafe { std::slice::from_raw_parts(ws_ptr, size_of::<WinSizePayload>()) };
        let _ = stream.write_all(ws_bytes);
        let _ = stream.flush();
    }
}

fn parse_exit_status(raw_status: i32) -> i32 {
    let term_sig = raw_status & 0x7f;
    if term_sig != 0 {
        unsafe { raise(term_sig) };
        128 + term_sig
    } else {
        (raw_status >> 8) & 0xff
    }
}

fn wait_for_cli_exit_response(stream: &mut UnixStream, is_tty: bool) -> i32 {
    if is_tty {
        send_initial_winsize(stream);
    }
    unsafe {
        signal(2, forward_sig_handler as *const () as usize);
        signal(15, forward_sig_handler as *const () as usize);
        signal(28, forward_sig_handler as *const () as usize);
    }
    let _ = stream.set_read_timeout(Some(Duration::from_millis(50)));

    let mut resp_header_buf = [0u8; size_of::<IpcHeader>()];
    let mut header_read = 0;
    let exit_code = loop {
        forward_cli_events(stream, is_tty);
        match stream.read(&mut resp_header_buf[header_read..]) {
            Ok(0) => break 1,
            Ok(n) => {
                header_read += n;
                if header_read >= size_of::<IpcHeader>() {
                    break 0;
                }
            }
            Err(ref e)
                if e.kind() == std::io::ErrorKind::WouldBlock
                    || e.kind() == std::io::ErrorKind::TimedOut => {}
            Err(_) => break 1,
        }
    };

    unsafe {
        signal(2, 0);
        signal(15, 0);
        signal(28, 0);
    }
    let _ = stream.set_read_timeout(None);

    if exit_code != 0 {
        return 1;
    }
    let Some(resp_hdr) = IpcHeader::from_bytes(&resp_header_buf) else {
        return 1;
    };
    if resp_hdr.msg_type != MSG_EXIT_RESPONSE {
        return 1;
    }
    let mut status_buf = [0u8; 4];
    if stream.read_exact(&mut status_buf).is_err() {
        return 1;
    }
    parse_exit_status(i32::from_le_bytes(status_buf))
}

fn print_help_and_exit() -> ! {
    println!(
        "Usage: sb-run [OPTIONS] [-- COMMAND [ARGS...]]\n\n\
        Options:\n\
          -h, --help                 Show this help message and exit\n\
          --config <PATH|none>       Use specific config JSON or 'none'\n\
          --id <APP_ID>              Sandbox application identifier\n\
          --dir <PATH>               Custom home directory persistence path\n\
          --net <MODE>               Network: sandboxed | singbox | passthrough | off\n\
          --singbox-config <PATH>    Custom sing-box config JSON file\n\
          --singbox-json <JSON>      Inline sing-box config JSON string\n\
          --edit-singbox             Edit sing-box config in $EDITOR before launch\n\
          --seccomp / --no-seccomp   Enable/disable seccomp syscall filter\n\
          --seccomp-action <ACT>     Default action: eperm | enosys | eacces | einval | enotsup | kill | trap\n\
          --seccomp-notify <MODE>    Default notify: notify | log | none\n\
          --seccomp-allow <RULES>    Allow comma-separated rules ([@prio:]syscall[:cond])\n\
          --seccomp-block <RULES>    Block syscalls or add default deny rules\n\
          --seccomp-deny <N:A:RULES> Add deny rules for notify:action:rules\n\
          --seccomp-clear            Clear seccomp allow list before subsequent allow/file\n\
          --seccomp-file <PATH>      Custom allowed syscalls file (JSON array or lines)\n\
          --seccomp-list             Print effective seccomp rules and policy\n\
          --edit-seccomp             Edit allowed syscalls in $EDITOR\n\
          --gpu / --no-gpu           Toggle GPU acceleration\n\
          --gamepad / --no-gamepad   Toggle gamepad/controller access\n\
          --pulse <MODE>             PulseAudio: sandboxed | passthrough | off\n\
          --pipewire <MODE>          PipeWire: sandboxed | passthrough | off\n\
          --microphone <MODE>        Microphone: off | portal | allow\n\
          --wayland <MODE>           Wayland: sandboxed | passthrough | off\n\
          --x11 <MODE>               X11: sandboxed | passthrough | off\n\
          --webcam <MODE>            Webcam: auto | portal | off\n\
          --dbus <MODE>              D-Bus: sandboxed | passthrough | off\n\
          --dbus-talk/own/see <NAME> D-Bus session policy rules\n\
          --landlock / --no-landlock Toggle Landlock signal scoping\n\
          --tmpfs / --share-pid      Ephemeral home / shared host PID namespace\n\
          --portals / --no-portals   Toggle XDG portals\n\
          --shm <MODE> / --tmp <M>   sandboxed | passthrough\n\
          --ro / --rw / --dev <P>    Bind mounts\n\
          --env <KEY=VAL>            Set environment variable\n\
          --bwrap-arg <ARG>          Raw argument for Bubblewrap"
    );
    exit(0);
}

// ---------------------------------------------------------------------------
// Bubblewrap & Subsystem Bind Builders
// ---------------------------------------------------------------------------

fn add_base_and_theme_binds(
    cmd: &mut Command,
    cfg: &SandboxConfig,
    home: &str,
    xdg_config: &str,
    xdg_data: &str,
) {
    for path in &cfg.ro_system_paths {
        if Path::new(path).exists() {
            cmd.arg("--ro-bind-try").arg(path).arg(path);
        }
    }
    for sub in &cfg.user_theme_subpaths {
        let p = format!("{home}/{sub}");
        if Path::new(&p).exists() {
            cmd.arg("--ro-bind-try").arg(&p).arg(&p);
        }
    }
    for sub in &cfg.xdg_config_subpaths {
        let p = format!("{xdg_config}/{sub}");
        if Path::new(&p).exists() {
            cmd.arg("--ro-bind-try").arg(&p).arg(&p);
        }
    }
    for sub in &cfg.xdg_data_subpaths {
        let p = format!("{xdg_data}/{sub}");
        if Path::new(&p).exists() {
            cmd.arg("--ro-bind-try").arg(&p).arg(&p);
        }
    }
}

fn add_gpu_binds(cmd: &mut Command, cfg: &SandboxConfig) {
    cmd.arg("--dev-bind").arg("/dev/dri").arg("/dev/dri");
    for node in &cfg.nvidia_nodes {
        if Path::new(node).exists() {
            cmd.arg("--dev-bind").arg(node).arg(node);
        }
    }
    for ro in [
        "/run/opengl-driver",
        "/run/opengl-driver-32",
        "/sys/dev/char",
        "/sys/devices/pci0000:00",
        "/sys/class/drm",
        "/sys/devices",
        "/sys/bus/pci",
    ] {
        if Path::new(ro).exists() {
            cmd.arg("--ro-bind-try").arg(ro).arg(ro);
        }
    }
}

fn add_audio_display_binds(
    cmd: &mut Command,
    cfg: &SandboxConfig,
    runtime_dir: &str,
    sandbox_runtime: &Path,
) {
    match cfg.pulse_mode.as_str() {
        "sandboxed" => {
            let sock_name = match cfg.microphone {
                MicMode::Off => "restricted-nomic",
                MicMode::Portal => "restricted-mic-portal",
                MicMode::Allow => "restricted",
            };
            let src = format!("{runtime_dir}/pulse/{sock_name}");
            let dst = format!("{runtime_dir}/pulse/native");
            if Path::new(&src).exists() {
                cmd.arg("--ro-bind-try").arg(&src).arg(&dst);
            }
        }
        "passthrough" => {
            let p = format!("{runtime_dir}/pulse/native");
            if Path::new(&p).exists() {
                cmd.arg("--ro-bind-try").arg(&p).arg(&p);
            }
        }
        _ => {}
    }

    match cfg.pipewire_mode.as_str() {
        "sandboxed" => {
            let sock_name = match cfg.microphone {
                MicMode::Off => "pipewire-0-restricted-nomic",
                MicMode::Portal => "pipewire-0-restricted-mic-portal",
                MicMode::Allow => "pipewire-0-restricted",
            };
            let src = format!("{runtime_dir}/{sock_name}");
            let dst = format!("{runtime_dir}/pipewire-0");
            if Path::new(&src).exists() {
                cmd.arg("--ro-bind-try").arg(&src).arg(&dst);
            }
        }
        "passthrough" => {
            let p = format!("{runtime_dir}/pipewire-0");
            if Path::new(&p).exists() {
                cmd.arg("--ro-bind-try").arg(&p).arg(&p);
            }
        }
        _ => {}
    }

    match cfg.wayland_mode.as_str() {
        "sandboxed" => {
            let wayland_disp = env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "wayland-0".into());
            let wayland_sock = format!("{runtime_dir}/{wayland_disp}");
            let wayland_filtered = sandbox_runtime.join("wayland-secure");
            if !wayland_filtered.exists() {
                fail_exit(&format!(
                    "sandboxed Wayland requested but '{}' does not exist",
                    wayland_filtered.display()
                ));
            }
            cmd.arg("--ro-bind")
                .arg(&wayland_filtered)
                .arg(&wayland_sock);
            cmd.arg("--setenv")
                .arg("WAYLAND_DISPLAY")
                .arg(&wayland_disp);
        }
        "passthrough" => {
            let wayland_disp = env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "wayland-0".into());
            let wayland_sock = format!("{runtime_dir}/{wayland_disp}");
            if Path::new(&wayland_sock).exists() {
                cmd.arg("--ro-bind-try")
                    .arg(&wayland_sock)
                    .arg(&wayland_sock);
            }
            cmd.arg("--setenv")
                .arg("WAYLAND_DISPLAY")
                .arg(&wayland_disp);
        }
        _ => {}
    }

    if cfg.x11_mode == "passthrough" && Path::new("/tmp/.X11-unix").exists() {
        cmd.arg("--ro-bind")
            .arg("/tmp/.X11-unix")
            .arg("/tmp/.X11-unix");
        let disp = env::var("DISPLAY").unwrap_or_else(|_| ":0".into());
        cmd.arg("--setenv").arg("DISPLAY").arg(&disp);
    } else if cfg.x11_mode == "sandboxed" {
        cmd.arg("--setenv").arg("DISPLAY").arg(":0");
    }
}

fn add_subsystem_binds(
    cmd: &mut Command,
    cfg: &SandboxConfig,
    runtime_dir: &str,
    sandbox_runtime: &Path,
) {
    if (cfg.subsystems & SUBSYS_GPU) != 0 {
        add_gpu_binds(cmd, cfg);
    }
    add_audio_display_binds(cmd, cfg, runtime_dir, sandbox_runtime);

    let wivrn_socket = format!("{runtime_dir}/wivrn");
    if Path::new(&wivrn_socket).exists() {
        cmd.arg("--ro-bind-try")
            .arg(&wivrn_socket)
            .arg(&wivrn_socket);
    }
    if (cfg.subsystems & SUBSYS_GAMEPAD) != 0 {
        if Path::new("/dev/input").exists() {
            cmd.arg("--dev-bind-try")
                .arg("/dev/input")
                .arg("/dev/input");
        }
        if Path::new("/dev/uinput").exists() {
            cmd.arg("--dev-bind-try")
                .arg("/dev/uinput")
                .arg("/dev/uinput");
        }
    }
    if cfg.webcam != WebcamMode::Off {
        cmd.arg("--ro-bind-try")
            .arg("/sys/class/video4linux")
            .arg("/sys/class/video4linux");
    }
    if cfg.webcam == WebcamMode::Auto {
        let sys_v4l = Path::new("/sys/class/video4linux");
        if let Ok(entries) = fs::read_dir(sys_v4l) {
            for entry in entries.flatten() {
                let name = entry.file_name();
                let name_str = name.to_string_lossy();
                if name_str.starts_with("video") {
                    let dev_node = format!("/dev/{name_str}");
                    if Path::new(&dev_node).exists() {
                        cmd.arg("--dev-bind-try").arg(&dev_node).arg(&dev_node);
                    }
                }
            }
        }
    }
}

fn add_ipc_and_dbus_binds(
    cmd: &mut Command,
    cfg: &SandboxConfig,
    runtime: &str,
    sandbox_runtime: &Path,
) {
    cmd.arg("--ro-bind")
        .arg(&cfg.executor_path)
        .arg(format!("{runtime}/bin/sb-executor"));

    if cfg.dbus_mode == "sandboxed" {
        let dbus_proxy_sock = sandbox_runtime.join("nixpak-bus");
        cmd.arg("--bind-try")
            .arg(&dbus_proxy_sock)
            .arg(format!("{runtime}/nixpak-bus"));
        cmd.arg("--bind-try")
            .arg(&dbus_proxy_sock)
            .arg(format!("{runtime}/bus"));
        cmd.arg("--setenv")
            .arg("DBUS_SESSION_BUS_ADDRESS")
            .arg(format!("unix:path={runtime}/nixpak-bus"));
    } else if cfg.dbus_mode == "passthrough" {
        if let Ok(session_bus) = env::var("DBUS_SESSION_BUS_ADDRESS") {
            if let Some(path) = session_bus.strip_prefix("unix:path=") {
                cmd.arg("--bind-try").arg(path).arg(path);
                cmd.arg("--bind-try")
                    .arg(path)
                    .arg(format!("{runtime}/bus"));
            }
            cmd.arg("--setenv")
                .arg("DBUS_SESSION_BUS_ADDRESS")
                .arg(&session_bus);
        }
    } else {
        cmd.arg("--unsetenv").arg("DBUS_SESSION_BUS_ADDRESS");
    }

    if (cfg.flags & CFG_SYSTEM_DBUS) != 0 {
        let host_sys_proxy = sandbox_runtime.join("nixpak-system-bus");
        let in_sandbox_sys_proxy = format!("{runtime}/nixpak-system-bus");
        cmd.arg("--bind-try")
            .arg(&host_sys_proxy)
            .arg(&in_sandbox_sys_proxy);
        cmd.arg("--bind-try")
            .arg(&host_sys_proxy)
            .arg("/run/dbus/system_bus_socket");
        cmd.arg("--setenv")
            .arg("DBUS_SYSTEM_BUS_ADDRESS")
            .arg(format!("unix:path={in_sandbox_sys_proxy}"));
    }
}

fn create_flatpak_info(sandbox_runtime: &Path, cfg: &SandboxConfig) -> PathBuf {
    let instance_id = format!("nixpak-app-{}", cfg.app_id);
    let uid = libc_getuid();
    let runtime_base = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| format!("/run/user/{uid}"));
    let flatpak_dir = PathBuf::from(format!("{runtime_base}/.flatpak/{instance_id}"));
    let _ = fs::create_dir_all(&flatpak_dir);

    let info_path = sandbox_runtime.join("flatpak-info");
    let mut content = format!(
        "[Application]\nname={}\nruntime=runtime/com.nixpak.Platform/x86_64/1\n\n[Context]\n",
        cfg.app_id
    );
    let mut shared = Vec::new();
    if (cfg.flags & CFG_SHARE_IPC) != 0 {
        shared.push("ipc");
    }
    if cfg.network == "passthrough" {
        shared.push("network");
    }
    if !shared.is_empty() {
        let _ = writeln!(content, "shared={};", shared.join(";"));
    }

    let _ = write!(
        content,
        "\n[Instance]\ninstance-id={instance_id}\napp-path=/app\nruntime-path=/usr\n\n[Session Bus Policy]\n"
    );

    for talk in &cfg.dbus_talk {
        let _ = writeln!(content, "{talk}=talk");
    }
    for own in &cfg.dbus_own {
        let _ = writeln!(content, "{own}=own");
    }
    for see in &cfg.dbus_see {
        let _ = writeln!(content, "{see}=see");
    }

    let _ = fs::write(&info_path, &content);
    let _ = fs::write(flatpak_dir.join("info"), &content);
    unsafe { env::set_var("FLATPAK_METADATA_FILE", flatpak_dir.join("info")) };
    info_path
}

fn add_network_bwrap_args(cmd: &mut Command, cfg: &SandboxConfig, sandbox_runtime: &Path) {
    if cfg.network == "singbox" {
        cmd.arg("--unshare-net");
        cmd.arg("--uid").arg("0").arg("--gid").arg("0");
        for cap in [
            "CAP_NET_ADMIN",
            "CAP_SETFCAP",
            "CAP_NET_RAW",
            "CAP_NET_BIND_SERVICE",
        ] {
            cmd.arg("--cap-add").arg(cap);
        }
        cmd.arg("--dir").arg("/dev/net");
        cmd.arg("--dev-bind-try")
            .arg("/dev/net/tun")
            .arg("/dev/net/tun");
        cmd.arg("--ro-bind-try")
            .arg("/etc/resolv.conf")
            .arg("/etc/resolv.conf");
    } else if cfg.network == "sandboxed" {
        cmd.arg("--unshare-net");
        let resolv_path = sandbox_runtime.join("resolv.conf");
        let _ = fs::write(&resolv_path, "nameserver 192.168.1.1\n");
        cmd.arg("--ro-bind")
            .arg(&resolv_path)
            .arg("/etc/resolv.conf");
    } else if cfg.network != "passthrough" {
        cmd.arg("--unshare-net");
    }
}

fn add_custom_binds_and_env(
    cmd: &mut Command,
    cfg: &SandboxConfig,
    sandbox_runtime: &Path,
    runtime: &str,
) {
    if cfg.network == "singbox" {
        let runtime_sb_cfg = sandbox_runtime.join("sing-box.json");
        if cfg.singbox_config != runtime_sb_cfg {
            if !runtime_sb_cfg.exists() {
                let _ = fs::write(&runtime_sb_cfg, "");
            }
            cmd.arg("--ro-bind")
                .arg(&cfg.singbox_config)
                .arg(format!("{runtime}/sing-box.json"));
        }
    }
    for d in &cfg.mkdir_dirs {
        cmd.arg("--dir").arg(d);
    }
    for b in &cfg.ro_binds {
        let (src, dst) = b.split_once(':').unwrap_or((b.as_str(), b.as_str()));
        cmd.arg("--ro-bind-try").arg(src).arg(dst);
    }
    for b in &cfg.rw_binds {
        let (src, dst) = b.split_once(':').unwrap_or((b.as_str(), b.as_str()));
        if let Some(parent) = Path::new(src).parent() {
            let _ = fs::create_dir_all(parent);
        }
        cmd.arg("--bind-try").arg(src).arg(dst);
    }
    for b in &cfg.dev_binds {
        let (src, dst) = b.split_once(':').unwrap_or((b.as_str(), b.as_str()));
        cmd.arg("--dev-bind-try").arg(src).arg(dst);
    }
    for item in &cfg.extra_env {
        if let Some((k, v)) = item.split_once('=') {
            cmd.arg("--setenv").arg(k).arg(v);
        }
    }
    for arg in &cfg.bwrap_extra_args {
        cmd.arg(arg);
    }
}

fn add_bwrap_pre_exec(
    cmd: &mut Command,
    pasta_sync: Option<(i32, i32)>,
    extra_info_fd: Option<i32>,
    use_landlock: bool,
) {
    let cgroup = env::var("MY_CGROUP").ok();
    let c_path = cgroup.and_then(|cg| CString::new(format!("{cg}/helpers/cgroup.procs")).ok());

    unsafe {
        cmd.pre_exec(move || {
            if let Some((r_block, w_info)) = pasta_sync {
                let _ = fcntl(r_block, 2, 0);
                let _ = fcntl(w_info, 2, 0);
            }
            if let Some(w_info) = extra_info_fd {
                let _ = fcntl(w_info, 2, 0);
            }
            if let Some(ref path) = c_path {
                let fd = open(path.as_ptr(), 1);
                if fd >= 0 {
                    let pid = getpid();
                    let mut n = u32::try_from(pid).unwrap_or(0);
                    let mut buf = [0u8; 32];
                    let mut rev = [0u8; 16];
                    let mut r_idx = if n == 0 {
                        rev[0] = b'0';
                        1
                    } else {
                        let mut count = 0;
                        while n > 0 {
                            rev[count] = b'0' + u8::try_from(n % 10).unwrap_or(0);
                            n /= 10;
                            count += 1;
                        }
                        count
                    };
                    let mut idx = 0;
                    while r_idx > 0 {
                        r_idx -= 1;
                        buf[idx] = rev[r_idx];
                        idx += 1;
                    }
                    buf[idx] = b'\n';
                    idx += 1;
                    let _ = write(fd, buf.as_ptr().cast(), idx);
                    let _ = close(fd);
                }
            }
            if use_landlock {
                apply_landlock_signal_scoping();
            }
            Ok(())
        });
    }
}

fn add_bwrap_executor_args(
    cmd: &mut Command,
    cfg: &SandboxConfig,
    runtime: &str,
    auth_token_hex: &str,
    has_seccomp: bool,
) {
    cmd.arg(format!("{runtime}/bin/sb-executor"))
        .arg("--socket")
        .arg(format!("{runtime}/ipc.sock"))
        .arg("--ready-pipe")
        .arg(format!("{runtime}/ready_pipe"))
        .arg("--token")
        .arg(auth_token_hex);

    if (cfg.flags & CFG_SCOPE) != 0 {
        cmd.arg("--migrator-socket")
            .arg(format!("{runtime}/migrator.sock"));
    }

    if has_seccomp {
        cmd.arg("--seccomp-socket")
            .arg(format!("{runtime}/seccomp.sock"));
    }

    if cfg.network == "singbox" {
        cmd.arg("--singbox-bin")
            .arg(&cfg.singbox_bin)
            .arg("--singbox-config")
            .arg(format!("{runtime}/sing-box.json"))
            .arg("--singbox-sock")
            .arg(format!("{runtime}/sing-box.sock"))
            .arg("--orig-uid")
            .arg(libc_getuid().to_string())
            .arg("--orig-gid")
            .arg(libc_getgid().to_string());
    }

    if cfg.x11_mode == "sandboxed" {
        cmd.arg("--x11-mode")
            .arg("sandboxed")
            .arg("--xwayland-bin")
            .arg(&cfg.xwayland_satellite_bin);
    }

    for init_cmd in &cfg.inside_init {
        cmd.arg("--inside-init").arg(init_cmd);
    }
}

#[derive(Clone, Copy)]
struct BwrapLaunchOpts {
    pasta_sync: Option<(i32, i32)>,
    extra_info_fd: Option<i32>,
    has_seccomp: bool,
}

fn build_bwrap_command(
    cfg: &SandboxConfig,
    sandbox_runtime: &Path,
    sandbox_home: &Path,
    auth_token_hex: &str,
    opts: BwrapLaunchOpts,
) -> Command {
    let mut cmd = if (cfg.flags & CFG_USE_VPNIFY) != 0 {
        let mut v = Command::new(&cfg.vpnify_bin);
        v.arg(&cfg.bwrap_bin);
        v
    } else {
        Command::new(&cfg.bwrap_bin)
    };

    if let Some((r_block, w_info)) = opts.pasta_sync {
        cmd.arg("--block-fd").arg(r_block.to_string());
        cmd.arg("--info-fd").arg(w_info.to_string());
    } else if let Some(w_info) = opts.extra_info_fd {
        cmd.arg("--info-fd").arg(w_info.to_string());
    }

    let home = env::var("HOME").unwrap_or_else(|_| "/home/user".into());
    let runtime = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/run/user/1000".into());
    let xdg_config = env::var("XDG_CONFIG_HOME").unwrap_or_else(|_| format!("{home}/.config"));
    let xdg_data = env::var("XDG_DATA_HOME").unwrap_or_else(|_| format!("{home}/.local/share"));

    cmd.arg("--die-with-parent");
    if let Some(uid) = cfg.custom_uid {
        cmd.arg("--unshare-user").arg("--uid").arg(uid.to_string());
        if let Some(gid) = cfg.custom_gid {
            cmd.arg("--gid").arg(gid.to_string());
        }
    } else {
        cmd.arg("--unshare-user-try");
    }
    if (cfg.flags & CFG_SHARE_IPC) == 0 {
        cmd.arg("--unshare-ipc");
    }
    if (cfg.flags & CFG_SHARE_PID) == 0 {
        cmd.arg("--unshare-pid");
    }
    cmd.arg("--unshare-uts").arg("--unshare-cgroup-try");
    cmd.arg("--proc").arg("/proc").arg("--dev").arg("/dev");

    add_network_bwrap_args(&mut cmd, cfg, sandbox_runtime);

    cmd.arg("--bind-try").arg(sandbox_home).arg(&home);
    cmd.arg("--bind-try").arg(sandbox_runtime).arg(&runtime);

    if cfg.shm_mode == "passthrough" {
        cmd.arg("--bind-try").arg("/dev/shm").arg("/dev/shm");
    } else {
        let shm_dir = sandbox_runtime.join("shm");
        let _ = fs::create_dir_all(&shm_dir);
        cmd.arg("--bind-try").arg(&shm_dir).arg("/dev/shm");
    }

    if cfg.tmp_mode == "passthrough" {
        cmd.arg("--bind-try").arg("/tmp").arg("/tmp");
    } else {
        let tmp_dir = sandbox_runtime.join("tmp");
        let _ = fs::create_dir_all(&tmp_dir);
        cmd.arg("--bind-try").arg(&tmp_dir).arg("/tmp");
    }

    let _ = fs::create_dir_all(sandbox_runtime.join("bin"));
    if let Ok(p) = env::var("XDG_RUNTIME_DIR") {
        let host_sesatt = format!("{p}/sesatt/{}", cfg.app_id);
        let in_sandbox_sesatt = format!("{runtime}/sesatt/{}", cfg.app_id);
        let _ = fs::create_dir_all(&host_sesatt);
        cmd.arg("--bind-try")
            .arg(&host_sesatt)
            .arg(&in_sandbox_sesatt);

        let host_doc = format!("{p}/doc/by-app/{}", cfg.app_id);
        cmd.arg("--bind-try")
            .arg(&host_doc)
            .arg(format!("{runtime}/doc"));
    }

    add_base_and_theme_binds(&mut cmd, cfg, &home, &xdg_config, &xdg_data);
    add_subsystem_binds(&mut cmd, cfg, &runtime, sandbox_runtime);
    add_ipc_and_dbus_binds(&mut cmd, cfg, &runtime, sandbox_runtime);

    let sandbox_marker = sandbox_runtime.join(".sb-sandbox");
    let _ = fs::write(&sandbox_marker, format!("{}\n", cfg.app_id));
    cmd.arg("--ro-bind")
        .arg(&sandbox_marker)
        .arg("/.sb-sandbox");
    cmd.arg("--setenv").arg("SB_SANDBOX").arg(&cfg.app_id);

    if (cfg.flags & CFG_FLATPAK_INFO) != 0 {
        let flatpak_info_path = create_flatpak_info(sandbox_runtime, cfg);
        cmd.arg("--ro-bind")
            .arg(&flatpak_info_path)
            .arg("/.flatpak-info");
    }

    if (cfg.flags & CFG_PORTALS) != 0 {
        let portal_mime = format!("{xdg_config}/mimeapps.list");
        if Path::new(&portal_mime).exists() {
            cmd.arg("--ro-bind-try").arg(&portal_mime).arg(&portal_mime);
        }
    }

    if (cfg.flags & CFG_VERBOSE) != 0 {
        cmd.arg("--setenv").arg("SB_RUN_VERBOSE").arg("1");
    }

    add_custom_binds_and_env(&mut cmd, cfg, sandbox_runtime, &runtime);
    add_bwrap_executor_args(&mut cmd, cfg, &runtime, auth_token_hex, opts.has_seccomp);
    add_bwrap_pre_exec(
        &mut cmd,
        opts.pasta_sync,
        opts.extra_info_fd,
        (cfg.flags & CFG_LANDLOCK) != 0,
    );
    cmd
}

// ---------------------------------------------------------------------------
// Helpers, Bridges, D-Bus Proxies, Way-Secure, Pasta
// ---------------------------------------------------------------------------

fn wait_for_file_created(dir: &Path, file_name: &str, timeout_ms: i32) -> bool {
    let full_path = dir.join(file_name);
    if full_path.exists() {
        return true;
    }
    let Ok(c_dir) = CString::new(dir.as_os_str().as_bytes()) else {
        return false;
    };
    let ifd = unsafe { inotify_init1(0x0008_0000) };
    if ifd < 0 {
        return full_path.exists();
    }
    let wd = unsafe { inotify_add_watch(ifd, c_dir.as_ptr(), 0x0000_0100) };
    if wd < 0 || full_path.exists() {
        let _ = unsafe { close(ifd) };
        return full_path.exists();
    }
    let mut pfd = PollFd {
        fd: ifd,
        events: 0x0001,
        revents: 0,
    };
    let mut remaining = timeout_ms;
    while remaining > 0 {
        let start = Instant::now();
        let res = unsafe { poll(&raw mut pfd, 1, remaining) };
        if res > 0 {
            let mut buf = [0u8; 1024];
            let _ = unsafe { read(ifd, buf.as_mut_ptr().cast(), buf.len()) };
            if full_path.exists() {
                let _ = unsafe { close(ifd) };
                return true;
            }
        } else if res == 0 {
            break;
        }
        let elapsed = u32::try_from(start.elapsed().as_millis()).unwrap_or(0);
        remaining -= i32::try_from(elapsed).unwrap_or(remaining);
    }
    let _ = unsafe { close(ifd) };
    full_path.exists()
}

fn move_bridge_listener_to_helpers(cgroup_path: &Path, runner_pid: u32) -> Option<i32> {
    let inside_procs = cgroup_path.join("inside/cgroup.procs");
    let helpers_procs = cgroup_path.join("helpers/cgroup.procs");
    let runner_i32 = i32::try_from(runner_pid).unwrap_or(0);

    for _ in 0..50 {
        for pid in read_pids_from_file(&inside_procs) {
            if pid != runner_i32
                && let Ok(cmd) = fs::read_to_string(format!("/proc/{pid}/cmdline"))
                && cmd.contains("rust-bridge")
            {
                let _ = fs::write(&helpers_procs, format!("{pid}\n"));
                return Some(pid);
            }
        }
        thread::sleep(Duration::from_millis(10));
    }
    None
}

fn setup_bridges(
    cfg: &SandboxConfig,
    sandbox_runtime: &Path,
    ipc_sock: &Path,
    cgroup_path: Option<&Path>,
    runner_pid: u32,
) -> Vec<i32> {
    if cfg.network == "passthrough" {
        return Vec::new();
    }
    let mut pids = Vec::new();
    let runtime = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/run/user/1000".into());

    for (idx, bridge) in cfg.bridges.iter().enumerate() {
        let sock_name = format!("bridge_{idx}.sock");
        let host_sock = sandbox_runtime.join(&sock_name);
        let in_sandbox_sock = format!("{runtime}/{sock_name}");
        let _ = fs::remove_file(&host_sock);
        let addr_spec = format!("{}:[{}]", bridge.address, bridge.ports);

        match bridge.direction {
            BridgeDirection::FromSandbox => {
                if let Ok(c) = Command::new(&cfg.rust_bridge_bin)
                    .args(["-r", "pass", "--address", &addr_spec, "-s"])
                    .arg(&host_sock)
                    .spawn()
                    && let Ok(p) = i32::try_from(c.id())
                {
                    pids.push(p);
                }
                wait_for_file_created(sandbox_runtime, &sock_name, 500);
                let mut bridge_cfg = SandboxConfig::for_helper_stub(cfg);
                bridge_cfg.command = vec![
                    cfg.rust_bridge_bin.to_string_lossy().to_string(),
                    "-r".into(),
                    "listen".into(),
                    "--address".into(),
                    addr_spec,
                    "-s".into(),
                    in_sandbox_sock,
                    "-d".into(),
                ];
                let _ = try_connect_running_sandbox(ipc_sock, &bridge_cfg, None);
                if let Some(p) =
                    cgroup_path.and_then(|cg| move_bridge_listener_to_helpers(cg, runner_pid))
                {
                    pids.push(p);
                }
            }
            BridgeDirection::ToSandbox => {
                let mut bridge_cfg = SandboxConfig::for_helper_stub(cfg);
                bridge_cfg.command = vec![
                    cfg.rust_bridge_bin.to_string_lossy().to_string(),
                    "-r".into(),
                    "pass".into(),
                    "--address".into(),
                    addr_spec.clone(),
                    "-s".into(),
                    in_sandbox_sock,
                ];
                let _ = try_connect_running_sandbox(ipc_sock, &bridge_cfg, None);
                wait_for_file_created(sandbox_runtime, &sock_name, 500);
                if let Ok(c) = Command::new(&cfg.rust_bridge_bin)
                    .args(["-r", "listen", "--address", &addr_spec, "-s"])
                    .arg(&host_sock)
                    .arg("-d")
                    .spawn()
                    && let Ok(p) = i32::try_from(c.id())
                {
                    pids.push(p);
                }
            }
        }
    }
    pids
}

impl SandboxConfig {
    fn for_helper_stub(parent: &Self) -> Self {
        Self {
            app_id: parent.app_id.clone(),
            custom_dir: None,
            network: parent.network.clone(),
            wayland_mode: parent.wayland_mode.clone(),
            x11_mode: parent.x11_mode.clone(),
            pulse_mode: parent.pulse_mode.clone(),
            pipewire_mode: parent.pipewire_mode.clone(),
            microphone: parent.microphone,
            dbus_mode: parent.dbus_mode.clone(),
            shm_mode: parent.shm_mode.clone(),
            tmp_mode: parent.tmp_mode.clone(),
            bridges: Vec::new(),
            subsystems: 0,
            flags: CFG_HELPER_REQ | (parent.flags & CFG_VERBOSE),
            webcam: WebcamMode::Off,
            pw_v4l2_bin: parent.pw_v4l2_bin.clone(),
            executor_path: PathBuf::new(),
            dbus_talk: Vec::new(),
            dbus_own: Vec::new(),
            dbus_see: Vec::new(),
            dbus_calls: Vec::new(),
            dbus_extra_args: Vec::new(),
            system_dbus_talk: Vec::new(),
            system_dbus_own: Vec::new(),
            system_dbus_see: Vec::new(),
            system_dbus_calls: Vec::new(),
            system_dbus_extra_args: Vec::new(),
            rw_binds: Vec::new(),
            ro_binds: Vec::new(),
            dev_binds: Vec::new(),
            mkdir_dirs: Vec::new(),
            bwrap_extra_args: Vec::new(),
            extra_env: Vec::new(),
            singbox_bin: parent.singbox_bin.clone(),
            singbox_config: parent.singbox_config.clone(),
            singbox_json: None,
            dbus_proxy_bin: parent.dbus_proxy_bin.clone(),
            way_secure_bin: parent.way_secure_bin.clone(),
            pasta_bin: parent.pasta_bin.clone(),
            xwayland_satellite_bin: parent.xwayland_satellite_bin.clone(),
            bwrap_bin: parent.bwrap_bin.clone(),
            rust_bridge_bin: parent.rust_bridge_bin.clone(),
            app2unit_bin: parent.app2unit_bin.clone(),
            systemctl_bin: parent.systemctl_bin.clone(),
            vpnify_bin: parent.vpnify_bin.clone(),
            notify_send_bin: parent.notify_send_bin.clone(),
            syscalls_file: parent.syscalls_file.clone(),
            seccomp_action: parent.seccomp_action,
            seccomp_notify: parent.seccomp_notify,
            seccomp_allow: Vec::new(),
            seccomp_deny: BTreeMap::new(),
            seccomp_cli_ops: Vec::new(),
            pasta_args: Vec::new(),
            allowed_env_vars: Vec::new(),
            ro_system_paths: Vec::new(),
            user_theme_subpaths: Vec::new(),
            xdg_config_subpaths: Vec::new(),
            xdg_data_subpaths: Vec::new(),
            nvidia_nodes: Vec::new(),
            custom_uid: None,
            custom_gid: None,
            inside_init: Vec::new(),
            command: Vec::new(),
        }
    }
}

fn start_way_secure(cfg: &SandboxConfig, sandbox_runtime: &Path) -> Option<i32> {
    if cfg.wayland_mode != "sandboxed" {
        return None;
    }
    let sock_path = sandbox_runtime.join("wayland-secure");
    let _ = fs::remove_file(&sock_path);
    let _ = fs::remove_file(sandbox_runtime.join("wayland-secure.lock"));

    let mut ready_pipe = [0i32; 2];
    let mut close_pipe = [0i32; 2];
    if unsafe { pipe(ready_pipe.as_mut_ptr()) } != 0
        || unsafe { pipe(close_pipe.as_mut_ptr()) } != 0
    {
        fail_exit("failed to create pipes for way-secure");
    }
    let [ready_r, ready_w] = ready_pipe;
    let [close_r, close_w] = close_pipe;

    let mut cmd = Command::new(&cfg.way_secure_bin);
    if (cfg.flags & CFG_VERBOSE) == 0 {
        cmd.stdout(Stdio::null()).stderr(Stdio::null());
    }
    cmd.args(["--socket-path"])
        .arg(&sock_path)
        .args(["-a", &cfg.app_id, "-e", "flatpak", "-r"])
        .arg(ready_w.to_string())
        .arg("-c")
        .arg(close_r.to_string());

    unsafe {
        cmd.pre_exec(move || {
            let _ = fcntl(ready_w, 2, 0);
            let _ = fcntl(close_r, 2, 0);
            prctl(1, 15, 0, 0, 0);
            Ok(())
        });
    }

    match cmd.spawn() {
        Ok(mut child) => {
            unsafe {
                close(ready_w);
                close(close_r);
            }
            let mut buf = [0u8; 8];
            let n = unsafe { read(ready_r, buf.as_mut_ptr().cast(), 8) };
            unsafe { close(ready_r) };
            if n <= 0 && !sock_path.exists() {
                let _ = child.kill();
                unsafe { close(close_w) };
                fail_exit(&format!(
                    "way-secure failed before readiness on '{}'",
                    sock_path.display()
                ));
            }
            let _ = child.wait();
            Some(close_w)
        }
        Err(err) => {
            unsafe {
                close(ready_w);
                close(ready_r);
                close(close_r);
                close(close_w);
            }
            fail_exit(&format!("failed to spawn way-secure: {err}"));
        }
    }
}

fn spawn_dbus_proxy_bwrap(
    cfg: &SandboxConfig,
    bus_addr: &str,
    proxy_sock: &Path,
    flatpak_info: &Path,
    extra_rules: &[String],
) -> Option<Child> {
    let _ = fs::remove_file(proxy_sock);
    let mut proxy_cmd = Command::new(&cfg.bwrap_bin);
    proxy_cmd
        .args(["--die-with-parent", "--ro-bind", "/etc", "/etc"])
        .args(["--ro-bind", "/nix/store", "/nix/store"])
        .args([
            "--bind", "/var", "/var", "--bind", "/tmp", "/tmp", "--bind", "/run", "/run",
        ])
        .arg("--ro-bind-try")
        .arg(flatpak_info)
        .arg("/.flatpak-info")
        .arg("--")
        .arg(&cfg.dbus_proxy_bin)
        .arg(bus_addr)
        .arg(proxy_sock)
        .arg("--filter");

    for r in extra_rules {
        proxy_cmd.arg(r);
    }
    if (cfg.flags & CFG_VERBOSE) == 0 {
        proxy_cmd.stdout(Stdio::null()).stderr(Stdio::null());
    }
    unsafe {
        proxy_cmd.pre_exec(|| {
            prctl(1, 15, 0, 0, 0);
            Ok(())
        });
    }

    match proxy_cmd.spawn() {
        Ok(child) => {
            if let Some(parent) = proxy_sock.parent()
                && let Some(name) = proxy_sock.file_name().and_then(|n| n.to_str())
            {
                wait_for_file_created(parent, name, 1000);
            }
            Some(child)
        }
        Err(err) => fail_exit(&format!("failed to spawn xdg-dbus-proxy via bwrap: {err}")),
    }
}

fn start_session_dbus_proxy(
    cfg: &SandboxConfig,
    proxy_sock: &Path,
    flatpak_info: &Path,
) -> Option<Child> {
    let session_bus = env::var("DBUS_SESSION_BUS_ADDRESS")
        .unwrap_or_else(|_| fail_exit("DBUS_SESSION_BUS_ADDRESS not set for sandboxed dbus"));
    let mut rules = Vec::new();
    if !cfg.app_id.is_empty() {
        rules.push(format!("--own={}", cfg.app_id));
        rules.push(format!("--own={}.*", cfg.app_id));
    }
    for talk in &cfg.dbus_talk {
        rules.push(format!("--talk={talk}"));
    }
    for own in &cfg.dbus_own {
        rules.push(format!("--own={own}"));
    }
    for see in &cfg.dbus_see {
        rules.push(format!("--see={see}"));
    }
    for call in &cfg.dbus_calls {
        if call.starts_with("--call=") {
            rules.push(call.clone());
        } else {
            rules.push(format!("--call={call}"));
        }
    }
    rules.extend(cfg.dbus_extra_args.iter().cloned());
    spawn_dbus_proxy_bwrap(cfg, &session_bus, proxy_sock, flatpak_info, &rules)
}

fn start_system_dbus_proxy(
    cfg: &SandboxConfig,
    proxy_sock: &Path,
    flatpak_info: &Path,
) -> Option<Child> {
    if !Path::new("/run/dbus/system_bus_socket").exists() {
        return None;
    }
    let mut rules = Vec::new();
    for talk in &cfg.system_dbus_talk {
        rules.push(format!("--talk={talk}"));
    }
    for own in &cfg.system_dbus_own {
        rules.push(format!("--own={own}"));
    }
    for see in &cfg.system_dbus_see {
        rules.push(format!("--see={see}"));
    }
    for call in &cfg.system_dbus_calls {
        if call.starts_with("--call=") {
            rules.push(call.clone());
        } else {
            rules.push(format!("--call={call}"));
        }
    }
    rules.extend(cfg.system_dbus_extra_args.iter().cloned());
    spawn_dbus_proxy_bwrap(
        cfg,
        "unix:path=/run/dbus/system_bus_socket",
        proxy_sock,
        flatpak_info,
        &rules,
    )
}

fn start_pasta(cfg: &SandboxConfig, child_pid: u32) -> Option<Child> {
    if cfg.network != "sandboxed" {
        return None;
    }
    let mut cmd = Command::new(&cfg.pasta_bin);
    if (cfg.flags & CFG_VERBOSE) == 0 {
        cmd.stdout(Stdio::null()).stderr(Stdio::null());
    }
    cmd.args(&cfg.pasta_args);
    cmd.arg(child_pid.to_string());
    match cmd.spawn() {
        Ok(child) => Some(child),
        Err(err) => fail_exit(&format!("failed to spawn pasta: {err}")),
    }
}

fn resolve_sandbox_home(cfg: &SandboxConfig, runtime_base: &str) -> PathBuf {
    cfg.custom_dir.as_ref().map_or_else(
        || {
            if (cfg.flags & CFG_TMPFS) != 0 {
                let p = PathBuf::from(format!("{runtime_base}/sb-run/{}/home", cfg.app_id));
                let _ = fs::create_dir_all(&p);
                p
            } else {
                let home = env::var("HOME").unwrap_or_else(|_| "/home/user".into());
                let p = PathBuf::from(format!("{home}/.nixpak/{}/home", cfg.app_id));
                let _ = fs::create_dir_all(&p);
                p
            }
        },
        |dir| {
            let _ = fs::create_dir_all(dir);
            dir.clone()
        },
    )
}

fn cleanup_session(
    cfg: &SandboxConfig,
    paths: &SandboxPaths,
    bridge_pids: &[i32],
    mut helpers: HelperProcesses,
    seccomp_mon: Option<&mut SeccompMonitorHandle>,
) {
    if let Some(mon) = seccomp_mon {
        mon.shutdown();
    }
    if let Some(fd) = helpers.way_secure_close_fd {
        unsafe { close(fd) };
    }
    for c in [&mut helpers.dbus_proxy, &mut helpers.system_dbus_proxy]
        .into_iter()
        .flatten()
    {
        if let Ok(pid_i32) = i32::try_from(c.id()) {
            unsafe {
                kill(-pid_i32, 15);
                kill(pid_i32, 15);
            }
        }
        let _ = c.kill();
        let _ = c.wait();
    }
    for c in [&mut helpers.singbox_bridge, &mut helpers.pasta]
        .into_iter()
        .flatten()
    {
        let _ = c.kill();
        let _ = c.wait();
    }
    for pid in bridge_pids {
        unsafe { kill(*pid, 15) };
    }
    for idx in 0..cfg.bridges.len() {
        let _ = fs::remove_file(paths.runtime.join(format!("bridge_{idx}.sock")));
    }
    for name in [
        "wayland-secure",
        "wayland-secure.lock",
        "migrator.sock",
        "sing-box.sock",
        "seccomp.sock",
    ] {
        let _ = fs::remove_file(paths.runtime.join(name));
    }
    let _ = fs::remove_file(&paths.ipc_sock);
    cleanup_token_for_app(&cfg.app_id);

    let uid = libc_getuid();
    let runtime_base = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| format!("/run/user/{uid}"));
    let _ = fs::remove_dir_all(format!("{runtime_base}/.flatpak/nixpak-app-{}", cfg.app_id));
    if (cfg.flags & CFG_TMPFS) != 0 {
        let _ = fs::remove_dir_all(&paths.runtime);
        let _ = fs::remove_dir_all(&paths.home);
    }
    if let Ok(scope) = env::var("MY_SCOPE")
        && scope_matches_app(&scope, cfg)
    {
        let _ = Command::new(&cfg.systemctl_bin)
            .args(["--user", "--no-block", "stop", &scope])
            .spawn();
    }
}

// ---------------------------------------------------------------------------
// Epoll, Cgroup Scope Monitor, Bwrap Sync
// ---------------------------------------------------------------------------

#[repr(C)]
#[derive(Clone, Copy)]
struct EpollEvent {
    events: u32,
    data: u64,
}

struct Epoll(i32);

impl Epoll {
    fn new() -> Option<Self> {
        let fd = unsafe { epoll_create1(0) };
        if fd >= 0 { Some(Self(fd)) } else { None }
    }

    fn add(&self, fd: i32) -> bool {
        let Ok(data) = u64::try_from(fd) else {
            return false;
        };
        let mut ev = EpollEvent {
            events: EPOLLIN,
            data,
        };
        unsafe { epoll_ctl(self.0, EPOLL_CTL_ADD, fd, &raw mut ev) == 0 }
    }

    fn add_pri(&self, fd: i32) -> bool {
        let Ok(data) = u64::try_from(fd) else {
            return false;
        };
        let mut ev = EpollEvent {
            events: EPOLLPRI | EPOLLERR,
            data,
        };
        unsafe { epoll_ctl(self.0, EPOLL_CTL_ADD, fd, &raw mut ev) == 0 }
    }

    fn del_and_close(&self, fd: i32) {
        unsafe {
            epoll_ctl(self.0, EPOLL_CTL_DEL, fd, std::ptr::null_mut());
            close(fd);
        }
    }

    fn wait(&self, events: &mut [EpollEvent], timeout_ms: i32) -> Result<usize, i32> {
        let Ok(len) = i32::try_from(events.len()) else {
            return Err(0);
        };
        let n = unsafe { epoll_wait(self.0, events.as_mut_ptr(), len, timeout_ms) };
        if n < 0 {
            Err(std::io::Error::last_os_error().raw_os_error().unwrap_or(0))
        } else {
            usize::try_from(n).map_err(|_| 0)
        }
    }
}

impl Drop for Epoll {
    fn drop(&mut self) {
        unsafe { close(self.0) };
    }
}

fn pidfd_open(pid: i32) -> Option<i32> {
    if pid <= 0 {
        return None;
    }
    let res = unsafe { syscall(SYS_PIDFD_OPEN, i64::from(pid), 0) };
    let fd = i32::try_from(res).ok()?;
    if fd >= 0 { Some(fd) } else { None }
}

fn read_pids_from_file(path: &Path) -> BTreeSet<i32> {
    fs::read_to_string(path)
        .unwrap_or_default()
        .lines()
        .filter_map(|l| l.trim().parse().ok())
        .filter(|&p| p > 0)
        .collect()
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct UCred {
    pid: i32,
    uid: u32,
    gid: u32,
}

fn handle_migration(listener: &UnixListener, inside_procs: Option<&Path>) -> Option<i32> {
    let Ok((mut stream, _)) = listener.accept() else {
        return None;
    };
    let mut ucred = UCred::default();
    let mut len = u32::try_from(size_of::<UCred>()).unwrap_or(0);
    let res = unsafe {
        getsockopt(
            stream.as_raw_fd(),
            SOL_SOCKET,
            SO_PEERCRED,
            (&raw mut ucred).cast(),
            &raw mut len,
        )
    };
    if let Some(p) = inside_procs
        && res == 0
        && ucred.pid > 0
    {
        let _ = fs::write(p, format!("{}\n", ucred.pid));
    }
    let _ = stream.write_all(b"G");
    let _ = stream.flush();
    if res == 0 && ucred.pid > 0 {
        Some(ucred.pid)
    } else {
        None
    }
}

struct MonitorContext<'a> {
    epoll: &'a Epoll,
    cgroup_events_fd: i32,
    child_fd: i32,
    migrator_fd: i32,
    migrator_listener: Option<&'a UnixListener>,
    procs_path: &'a Path,
}

fn process_epoll_events(
    ctx: &MonitorContext<'_>,
    events: &[EpollEvent],
    monitored: &mut BTreeSet<i32>,
) -> bool {
    for event in events {
        let Ok(fd) = i32::try_from(event.data) else {
            continue;
        };
        if fd == ctx.child_fd {
            return true;
        }
        if ctx.migrator_fd >= 0 && fd == ctx.migrator_fd {
            if let Some(l) = ctx.migrator_listener
                && let Some(pid) = handle_migration(l, Some(ctx.procs_path))
                && let Some(pfd) = pidfd_open(pid)
            {
                if ctx.epoll.add(pfd) {
                    monitored.insert(pid);
                } else {
                    unsafe { close(pfd) };
                }
            }
            continue;
        }
        if fd == ctx.cgroup_events_fd {
            let mut drain_buf = [0u8; 256];
            unsafe {
                lseek(ctx.cgroup_events_fd, 0, 0);
                read(
                    ctx.cgroup_events_fd,
                    drain_buf.as_mut_ptr().cast(),
                    drain_buf.len(),
                );
            };
            continue;
        }
        ctx.epoll.del_and_close(fd);
    }
    false
}

struct ScopeMonitorArgs<'a> {
    bridge_pids: &'a [i32],
    helpers: HelperProcesses,
    seccomp_mon: Option<SeccompMonitorHandle>,
    child: &'a mut Child,
    migrator_listener: Option<&'a UnixListener>,
    initial_seen: bool,
}

fn monitor_scope_and_cleanup(
    cfg: &SandboxConfig,
    paths: &SandboxPaths,
    mut args: ScopeMonitorArgs<'_>,
) {
    if let Ok(cgroup_path) = env::var("MY_CGROUP") {
        let procs_path = PathBuf::from(&cgroup_path).join("inside/cgroup.procs");
        let events_path = PathBuf::from(&cgroup_path).join("inside/cgroup.events");
        let mut has_seen_apps = args.initial_seen;

        if let Some(epoll) = Epoll::new() {
            let c_events = CString::new(events_path.into_os_string().as_bytes()).ok();
            let cgroup_events_fd = c_events.map_or(-1, |p| unsafe { open(p.as_ptr(), 0) });
            if cgroup_events_fd >= 0 {
                let mut drain_buf = [0u8; 256];
                unsafe {
                    lseek(cgroup_events_fd, 0, 0);
                    read(
                        cgroup_events_fd,
                        drain_buf.as_mut_ptr().cast(),
                        drain_buf.len(),
                    );
                };
                epoll.add_pri(cgroup_events_fd);
            }

            let child_i32 = i32::try_from(args.child.id()).unwrap_or(0);
            let child_fd = pidfd_open(child_i32).unwrap_or(-1);
            if child_fd >= 0 {
                epoll.add(child_fd);
            }
            let migrator_fd = args.migrator_listener.map_or(-1, AsRawFd::as_raw_fd);
            if migrator_fd >= 0 {
                epoll.add(migrator_fd);
            }

            let ctx = MonitorContext {
                epoll: &epoll,
                cgroup_events_fd,
                child_fd,
                migrator_fd,
                migrator_listener: args.migrator_listener,
                procs_path: &procs_path,
            };
            let mut monitored = BTreeSet::new();

            loop {
                let inside_pids = read_pids_from_file(&procs_path);
                if (has_seen_apps || args.migrator_listener.is_some()) && inside_pids.is_empty() {
                    break;
                }
                for &pid in &inside_pids {
                    has_seen_apps = true;
                    if monitored.contains(&pid) {
                        continue;
                    }
                    if let Some(pfd) = pidfd_open(pid) {
                        if epoll.add(pfd) {
                            monitored.insert(pid);
                        } else {
                            unsafe { close(pfd) };
                        }
                    }
                }
                let mut events = [EpollEvent { events: 0, data: 0 }; 16];
                let n = match epoll.wait(&mut events, -1) {
                    Ok(n) => n,
                    Err(4) => continue,
                    Err(_) => break,
                };
                if process_epoll_events(&ctx, &events[..n], &mut monitored) {
                    break;
                }
            }
            if cgroup_events_fd >= 0 {
                unsafe { close(cgroup_events_fd) };
            }
        } else {
            let _ = args.child.wait();
        }
    } else {
        let _ = args.child.wait();
    }

    cleanup_session(
        cfg,
        paths,
        args.bridge_pids,
        args.helpers,
        args.seccomp_mon.as_mut(),
    );
}

fn parse_child_pid_from_info(buf: &[u8]) -> Option<u32> {
    let s = std::str::from_utf8(buf).ok()?;
    let idx = s.find("\"child-pid\":")?;
    let rem = s[idx + "\"child-pid\":".len()..].trim_start();
    let num_str: String = rem.chars().take_while(char::is_ascii_digit).collect();
    num_str.parse().ok()
}

fn write_bwrap_info(app_id: &str, data: &[u8]) {
    let instance_id = format!("nixpak-app-{app_id}");
    let uid = libc_getuid();
    let runtime_base = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| format!("/run/user/{uid}"));
    let flatpak_dir = PathBuf::from(format!("{runtime_base}/.flatpak/{instance_id}"));
    let _ = fs::create_dir_all(&flatpak_dir);
    let _ = fs::write(flatpak_dir.join("bwrapinfo.json"), data);
}

fn read_info_fd_data(r_fd: i32) -> Vec<u8> {
    let mut data = Vec::new();
    let mut chunk = [0u8; 256];
    while !data.contains(&b'}') {
        let n = unsafe { read(r_fd, chunk.as_mut_ptr().cast(), chunk.len()) };
        if n <= 0 {
            break;
        }
        if let Ok(u_len) = usize::try_from(n) {
            data.extend_from_slice(&chunk[..u_len]);
        }
    }
    unsafe { close(r_fd) };
    data
}

fn handle_pasta_sync(
    pasta_sync_fds: Option<([i32; 2], [i32; 2])>,
    cfg: &SandboxConfig,
) -> (Option<Child>, u32) {
    let Some(([r_block, w_block], [r_info, w_info])) = pasta_sync_fds else {
        return (None, 0);
    };
    unsafe {
        close(r_block);
        close(w_info);
    };
    let data = read_info_fd_data(r_info);
    let runner_pid = parse_child_pid_from_info(&data).unwrap_or(0);
    if runner_pid > 0 {
        write_bwrap_info(&cfg.app_id, &data);
    }
    let pasta_child = if runner_pid > 0 {
        start_pasta(cfg, runner_pid)
    } else {
        None
    };
    let _ = unsafe { write(w_block, b"x".as_ptr().cast(), 1) };
    unsafe { close(w_block) };
    (pasta_child, runner_pid)
}

struct SandboxPaths {
    runtime: PathBuf,
    home: PathBuf,
    ipc_sock: PathBuf,
    ready_pipe: PathBuf,
}

fn prepare_sandbox_paths(cfg: &SandboxConfig) -> SandboxPaths {
    let uid = libc_getuid();
    let runtime_base = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| format!("/run/user/{uid}"));
    let sandbox_dir = PathBuf::from(format!("{runtime_base}/.nixpak/{}", cfg.app_id));
    let sandbox_runtime = sandbox_dir.join("runtime");
    let _ = fs::create_dir_all(&sandbox_runtime);
    let mut ipc_sock = sandbox_runtime.join("ipc.sock");
    if !ipc_sock.exists() {
        let alt = PathBuf::from(format!("{runtime_base}/sb-run/{}/ipc.sock", cfg.app_id));
        if alt.exists() {
            ipc_sock = alt;
        }
    }
    let sandbox_home = resolve_sandbox_home(cfg, &runtime_base);
    let ready_pipe = sandbox_runtime.join("ready_pipe");
    let _ = fs::remove_file(&ready_pipe);
    if let Ok(c_pipe) = CString::new(ready_pipe.as_os_str().as_bytes()) {
        unsafe { mkfifo(c_pipe.as_ptr(), 0o600) };
    }
    SandboxPaths {
        runtime: sandbox_runtime,
        home: sandbox_home,
        ipc_sock,
        ready_pipe,
    }
}

fn spawn_initial_helpers(cfg: &SandboxConfig, sandbox_runtime: &Path) -> HelperProcesses {
    let mut helpers = HelperProcesses::default();
    let flatpak_info_path = create_flatpak_info(sandbox_runtime, cfg);

    if cfg.dbus_mode == "sandboxed" {
        let proxy_sock = sandbox_runtime.join("nixpak-bus");
        helpers.dbus_proxy = start_session_dbus_proxy(cfg, &proxy_sock, &flatpak_info_path);
    }
    if (cfg.flags & CFG_SYSTEM_DBUS) != 0 {
        let sys_proxy_sock = sandbox_runtime.join("nixpak-system-bus");
        helpers.system_dbus_proxy =
            start_system_dbus_proxy(cfg, &sys_proxy_sock, &flatpak_info_path);
    }
    helpers.way_secure_close_fd = start_way_secure(cfg, sandbox_runtime);

    if cfg.network == "singbox" {
        let sb_bridge_sock = sandbox_runtime.join("sing-box.sock");
        let _ = fs::remove_file(&sb_bridge_sock);
        let mut bridge_cmd = Command::new(&cfg.rust_bridge_bin);
        bridge_cmd.args(["-r", "pass", "--address", "127.0.0.1:[1919,2121]", "-s"]);
        bridge_cmd.arg(&sb_bridge_sock);
        unsafe {
            bridge_cmd.pre_exec(|| {
                prctl(1, 15, 0, 0, 0);
                Ok(())
            });
        }
        helpers.singbox_bridge = Some(
            bridge_cmd
                .spawn()
                .unwrap_or_else(|e| fail_exit(&format!("failed to spawn rust-bridge: {e}"))),
        );
    }
    helpers
}

const SYS_LANDLOCK_CREATE_RULESET: i64 = 444;
const SYS_LANDLOCK_RESTRICT_SELF: i64 = 446;
const LANDLOCK_SCOPE_SIGNAL: u64 = 1 << 0;
const PR_SET_NO_NEW_PRIVS: i32 = 38;

#[repr(C)]
struct LandlockRulesetAttr {
    handled_access_fs: u64,
    handled_access_net: u64,
    scoped: u64,
}

fn apply_landlock_signal_scoping() {
    let attr = LandlockRulesetAttr {
        handled_access_fs: 0,
        handled_access_net: 0,
        scoped: LANDLOCK_SCOPE_SIGNAL,
    };
    let fd = unsafe {
        syscall(
            SYS_LANDLOCK_CREATE_RULESET,
            (&raw const attr as usize).cast_signed(),
            size_of::<LandlockRulesetAttr>(),
            0,
        )
    };
    if fd >= 0
        && let Ok(fd_i32) = i32::try_from(fd)
    {
        unsafe {
            let _ = prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0);
            let _ = syscall(SYS_LANDLOCK_RESTRICT_SELF, fd, 0);
            close(fd_i32);
        }
    }
}

fn systemd_unescape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars().peekable();
    while let Some(ch) = chars.next() {
        if ch == '\\' && chars.peek() == Some(&'x') {
            chars.next();
            if let (Some(c1), Some(c2)) = (chars.next(), chars.next()) {
                let buf = [c1 as u8, c2 as u8];
                if let Ok(hex_str) = std::str::from_utf8(&buf)
                    && let Ok(byte) = u8::from_str_radix(hex_str, 16)
                {
                    out.push(byte as char);
                    continue;
                }
                out.push_str("\\x");
                out.push(c1);
                out.push(c2);
                continue;
            }
        }
        out.push(ch);
    }
    out
}

fn scope_matches_app(scope_str: &str, cfg: &SandboxConfig) -> bool {
    systemd_unescape(scope_str).contains(&cfg.app_id)
}

fn ensure_app2unit_scope(cfg: &SandboxConfig) {
    if (cfg.flags & CFG_SCOPE) == 0 || cfg.app_id.is_empty() {
        return;
    }
    let Ok(cgroup_content) = fs::read_to_string("/proc/self/cgroup") else {
        return;
    };
    let line = cgroup_content.lines().next().unwrap_or("");
    let mut rel_path = line.strip_prefix("0::").unwrap_or(line).trim();
    while let Some(parent) = rel_path.strip_suffix("/helpers") {
        rel_path = parent;
    }
    while let Some(parent) = rel_path.strip_suffix("/inside") {
        rel_path = parent;
    }
    if scope_matches_app(rel_path, cfg) {
        return;
    }

    let args: Vec<String> = env::args().collect();
    let current_exe = env::current_exe().unwrap_or_else(|_| PathBuf::from(&args[0]));
    let Ok(c_app2unit) = CString::new(cfg.app2unit_bin.as_os_str().as_bytes()) else {
        return;
    };
    let Ok(c_a) = CString::new("-a") else { return };
    let Ok(c_app_id) = CString::new(cfg.app_id.as_bytes()) else {
        return;
    };
    let Ok(c_dashdash) = CString::new("--") else {
        return;
    };
    let Ok(c_exe) = CString::new(current_exe.as_os_str().as_bytes()) else {
        return;
    };

    let mut c_args = vec![c_app2unit.clone(), c_a, c_app_id.clone(), c_dashdash, c_exe];
    if (cfg.flags & CFG_VERBOSE) != 0
        && !args.iter().any(|a| a == "-v" || a == "--verbose")
        && let Ok(c_v_flag) = CString::new("-v")
    {
        c_args.push(c_v_flag);
    }
    if !args.iter().any(|a| a == "--id" || a.starts_with("--id="))
        && let Ok(c_id_flag) = CString::new("--id")
    {
        c_args.push(c_id_flag);
        c_args.push(c_app_id);
    }
    for a in &args[1..] {
        if let Ok(ca) = CString::new(a.as_bytes()) {
            c_args.push(ca);
        }
    }
    let mut c_ptrs: Vec<*const i8> = c_args.iter().map(|cs| cs.as_ptr()).collect();
    c_ptrs.push(std::ptr::null());
    unsafe { execvp(c_app2unit.as_ptr(), c_ptrs.as_ptr()) };
}

fn setup_cgroup_and_scope(cfg: &SandboxConfig) {
    if (cfg.flags & CFG_SCOPE) == 0 {
        return;
    }
    if env::var("MY_CGROUP").is_ok() && env::var("MY_SCOPE").is_ok() {
        return;
    }
    let Ok(cgroup_content) = fs::read_to_string("/proc/self/cgroup") else {
        return;
    };
    let line = cgroup_content.lines().next().unwrap_or("");
    let mut rel_path = line.strip_prefix("0::").unwrap_or(line).trim();
    if rel_path.is_empty() || rel_path == "/" {
        return;
    }
    while let Some(parent) = rel_path.strip_suffix("/helpers") {
        rel_path = parent;
    }
    while let Some(parent) = rel_path.strip_suffix("/inside") {
        rel_path = parent;
    }
    if !scope_matches_app(rel_path, cfg) {
        return;
    }

    let cgroup_path = PathBuf::from(format!("/sys/fs/cgroup{rel_path}"));
    let scope_name = cgroup_path
        .file_name()
        .and_then(|n| n.to_str())
        .map(String::from);

    let helpers_dir = cgroup_path.join("helpers");
    let inside_dir = cgroup_path.join("inside");
    let _ = fs::create_dir_all(&helpers_dir);
    let _ = fs::create_dir_all(&inside_dir);

    for p in read_pids_from_file(&cgroup_path.join("cgroup.procs")) {
        let _ = fs::write(helpers_dir.join("cgroup.procs"), format!("{p}\n"));
    }
    let pid = unsafe { getpid() };
    let _ = fs::write(helpers_dir.join("cgroup.procs"), format!("{pid}\n"));

    if let Some(parent) = cgroup_path.parent() {
        let _ = fs::write(
            parent.join("cgroup.subtree_control"),
            "+memory +pids +cpu +io\n",
        );
    }
    let _ = fs::write(
        cgroup_path.join("cgroup.subtree_control"),
        "+memory +pids +cpu +io\n",
    );

    unsafe {
        env::set_var("MY_CGROUP", &cgroup_path);
        if let Some(ref sc) = scope_name {
            env::set_var("MY_SCOPE", sc);
        }
    }
}

fn ensure_start_time() {
    if env::var_os("START_TIME").is_none() {
        let now_ns = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_nanos());
        unsafe { env::set_var("START_TIME", now_ns.to_string()) };
    }
}

fn spawn_bwrap_session(
    cfg: &SandboxConfig,
    paths: &SandboxPaths,
    token_hex: &str,
    has_seccomp_socket: bool,
    helpers: &mut HelperProcesses,
) -> (Child, u32) {
    let pasta_sync_fds = if cfg.network == "sandboxed" {
        let mut block_fds = [0i32; 2];
        let mut info_fds = [0i32; 2];
        let _ = unsafe { pipe(block_fds.as_mut_ptr()) };
        let _ = unsafe { pipe(info_fds.as_mut_ptr()) };
        Some((block_fds, info_fds))
    } else {
        None
    };
    let pasta_sync_pass = pasta_sync_fds.map(|([r_b, _], [_, w_i])| (r_b, w_i));
    let (extra_info_r, extra_info_w) = if pasta_sync_fds.is_none() {
        let mut fds = [0i32; 2];
        if unsafe { pipe(fds.as_mut_ptr()) } == 0 {
            (Some(fds[0]), Some(fds[1]))
        } else {
            (None, None)
        }
    } else {
        (None, None)
    };

    let mut bwrap = build_bwrap_command(
        cfg,
        &paths.runtime,
        &paths.home,
        token_hex,
        BwrapLaunchOpts {
            pasta_sync: pasta_sync_pass,
            extra_info_fd: extra_info_w,
            has_seccomp: has_seccomp_socket,
        },
    );
    let child = bwrap.spawn().unwrap_or_else(|err| {
        cleanup_token_for_app(&cfg.app_id);
        fail_exit(&format!("failed to spawn bwrap: {err}"));
    });
    let extra_runner_pid = extra_info_r.map_or(0, |r_fd| {
        if let Some(w) = extra_info_w {
            unsafe { close(w) };
        }
        let data = read_info_fd_data(r_fd);
        if data.is_empty() {
            0
        } else {
            write_bwrap_info(&cfg.app_id, &data);
            parse_child_pid_from_info(&data).unwrap_or(0)
        }
    });

    let (pasta_child, pasta_runner_pid) = handle_pasta_sync(pasta_sync_fds, cfg);
    helpers.pasta = pasta_child;
    let runner_pid = if pasta_runner_pid > 0 {
        pasta_runner_pid
    } else {
        extra_runner_pid
    };

    if let Ok(mut pipe_file) = fs::File::open(&paths.ready_pipe) {
        let mut buf = [0u8; 16];
        let _ = pipe_file.read(&mut buf);
    }
    let _ = fs::remove_file(&paths.ready_pipe);

    if let Ok(cgroup) = env::var("MY_CGROUP")
        && runner_pid > 0
    {
        let _ = fs::write(
            format!("{cgroup}/helpers/cgroup.procs"),
            format!("{runner_pid}\n"),
        );
    }

    (child, runner_pid)
}

fn setup_migrator_and_handle_initial(runtime: &Path, cfg: &SandboxConfig) -> Option<UnixListener> {
    if (cfg.flags & CFG_SCOPE) == 0 {
        return None;
    }
    let migrator_sock = runtime.join("migrator.sock");
    let _ = fs::remove_file(&migrator_sock);
    let listener = UnixListener::bind(&migrator_sock).ok();
    if let Some(ref l) = listener {
        let _ = l.set_nonblocking(true);
    }
    listener
}

fn migrate_first_process(listener: Option<&UnixListener>) -> bool {
    let inside_procs = env::var("MY_CGROUP")
        .ok()
        .map(|cg| PathBuf::from(format!("{cg}/inside/cgroup.procs")));
    if let Some(l) = listener {
        let mut pfd = PollFd {
            fd: l.as_raw_fd(),
            events: 1,
            revents: 0,
        };
        if unsafe { poll(&raw mut pfd, 1, 5000) } > 0 {
            return handle_migration(l, inside_procs.as_deref()).is_some();
        }
    }
    false
}

fn init_config(raw_args: &[String]) -> SandboxConfig {
    for arg in raw_args.iter().skip(1) {
        if arg == "--" {
            break;
        }
        if arg == "-h" || arg == "--help" {
            print_help_and_exit();
        }
    }
    let json_cfg = load_single_source_config_json();
    let mut cfg = parse_cli_args(json_cfg.as_ref());
    if (cfg.flags & CFG_VERBOSE) != 0 && raw_args.len() > 1 {
        eprintln!("[sb-run] Flags: {}", raw_args[1..].join(" "));
    }
    validate_required_binaries(&cfg);

    if cfg.webcam == WebcamMode::Portal {
        if cfg.pipewire_mode == "off" {
            cfg.pipewire_mode = "sandboxed".into();
        }
        cfg.command
            .insert(0, cfg.pw_v4l2_bin.to_string_lossy().into_owned());
    }
    cfg
}

struct PreparedSeccomp {
    table: Option<Arc<SyscallTable>>,
    policy: Option<Arc<SeccompPolicy>>,
    bpf: Option<Vec<u8>>,
}

fn prepare_seccomp_state(cfg: &mut SandboxConfig) -> PreparedSeccomp {
    if (cfg.flags & CFG_SECCOMP) == 0 {
        if (cfg.flags & CFG_SECCOMP_LIST) != 0 {
            print_seccomp_list(cfg);
            if cfg.command.is_empty() {
                exit(0);
            }
        }
        return PreparedSeccomp {
            table: None,
            policy: None,
            bpf: None,
        };
    }

    let table = Arc::new(SyscallTable::load(&cfg.syscalls_file));
    if (cfg.flags & CFG_SECCOMP_LIST) != 0
        && (cfg.flags & CFG_EDIT_SECCOMP) == 0
        && cfg.command.is_empty()
    {
        let _ = resolve_seccomp_policy(cfg, &table, Path::new("/tmp"));
        exit(0);
    }
    let paths_tmp = prepare_sandbox_paths(cfg);
    let policy = Arc::new(resolve_seccomp_policy(cfg, &table, &paths_tmp.runtime));
    if policy.needs_notify_send() {
        require_binary(&cfg.notify_send_bin, "notify-send");
    }
    let bpf = compile_seccomp_bpf(&policy);
    PreparedSeccomp {
        table: Some(table),
        policy: Some(policy),
        bpf: Some(bpf),
    }
}

fn main() {
    ensure_start_time();
    let raw_args: Vec<String> = env::args().collect();
    let mut cfg = init_config(&raw_args);
    let PreparedSeccomp {
        table: syscall_table,
        policy: seccomp_policy,
        bpf: seccomp_bpf,
    } = prepare_seccomp_state(&mut cfg);
    let paths = prepare_sandbox_paths(&cfg);
    prepare_singbox_config(&mut cfg, &paths.runtime);

    if let Some(exit_code) =
        try_connect_running_sandbox(&paths.ipc_sock, &cfg, seccomp_bpf.as_deref())
    {
        exit(exit_code);
    }

    ensure_app2unit_scope(&cfg);
    setup_cgroup_and_scope(&cfg);

    let mut seccomp_mon = match (syscall_table, seccomp_policy) {
        (Some(table), Some(policy)) if policy.needs_monitor() => {
            let log_path = paths
                .home
                .parent()
                .unwrap_or(&paths.runtime)
                .join("logs/seccomp.log");
            Some(start_seccomp_monitor(
                &paths.runtime,
                table,
                policy,
                cfg.notify_send_bin.clone(),
                log_path,
                cfg.app_id.clone(),
            ))
        }
        _ => None,
    };

    let mut helpers = spawn_initial_helpers(&cfg, &paths.runtime);
    let migrator_listener = setup_migrator_and_handle_initial(&paths.runtime, &cfg);

    let auth_token = create_token_for_app(&cfg.app_id);
    let token_hex = bytes_to_hex(&auth_token);
    let (mut child, runner_pid) = spawn_bwrap_session(
        &cfg,
        &paths,
        &token_hex,
        seccomp_mon.is_some(),
        &mut helpers,
    );

    let cgroup_opt = env::var("MY_CGROUP").ok().map(PathBuf::from);
    let bridge_pids = if cfg.bridges.is_empty() {
        Vec::new()
    } else {
        setup_bridges(
            &cfg,
            &paths.runtime,
            &paths.ipc_sock,
            cgroup_opt.as_deref(),
            runner_pid,
        )
    };

    if cfg.command.is_empty() {
        let status = child.wait().map_or(1, |s| s.code().unwrap_or(1));
        cleanup_session(&cfg, &paths, &bridge_pids, helpers, seccomp_mon.as_mut());
        exit(status);
    }

    if (cfg.flags & CFG_IS_CLI) != 0 {
        let migrator_thread =
            migrator_listener.map(|l| thread::spawn(move || migrate_first_process(Some(&l))));
        let _ = try_connect_running_sandbox(&paths.ipc_sock, &cfg, seccomp_bpf.as_deref());
        if let Some(h) = migrator_thread {
            let _ = h.join();
        }
        let _ = child.kill();
        let _ = child.wait();
        cleanup_session(&cfg, &paths, &bridge_pids, helpers, seccomp_mon.as_mut());
        exit(0);
    }

    let _ = try_connect_running_sandbox(&paths.ipc_sock, &cfg, seccomp_bpf.as_deref());
    let initial_seen = migrate_first_process(migrator_listener.as_ref());

    monitor_scope_and_cleanup(
        &cfg,
        &paths,
        ScopeMonitorArgs {
            bridge_pids: &bridge_pids,
            helpers,
            seccomp_mon,
            child: &mut child,
            migrator_listener: migrator_listener.as_ref(),
            initial_seen,
        },
    );
    exit(0);
}

unsafe extern "C" {
    fn syscall(number: i64, ...) -> i64;
    fn getuid() -> u32;
    fn getgid() -> u32;
    fn getpid() -> i32;
    fn open(path: *const i8, flags: i32, ...) -> i32;
    fn write(fd: i32, buf: *const c_void, count: usize) -> isize;
    fn close(fd: i32) -> i32;
    fn lseek(fd: i32, offset: i64, whence: i32) -> i64;
    fn read(fd: i32, buf: *mut c_void, count: usize) -> isize;
    fn pipe(pipefd: *mut i32) -> i32;
    fn poll(fds: *mut PollFd, nfds: usize, timeout: i32) -> i32;
    fn fcntl(fd: i32, cmd: i32, arg: i32) -> i32;
    fn inotify_init1(flags: i32) -> i32;
    fn inotify_add_watch(fd: i32, pathname: *const i8, mask: u32) -> i32;
    fn prctl(option: i32, arg2: u64, arg3: u64, arg4: u64, arg5: u64) -> i32;
    fn epoll_create1(flags: i32) -> i32;
    fn epoll_ctl(epfd: i32, op: i32, fd: i32, event: *mut EpollEvent) -> i32;
    fn epoll_wait(epfd: i32, events: *mut EpollEvent, maxevents: i32, timeout: i32) -> i32;
    fn execvp(file: *const i8, argv: *const *const i8) -> i32;
    fn sendmsg(sockfd: i32, msg: *const LibcMsghdr, flags: i32) -> isize;
    fn recvmsg(sockfd: i32, msg: *mut LibcMsghdr, flags: i32) -> isize;
    fn isatty(fd: i32) -> i32;
    fn raise(sig: i32) -> i32;
    fn mkfifo(pathname: *const i8, mode: u32) -> i32;
    fn ioctl(fd: i32, request: usize, ...) -> i32;
    fn signal(sig: i32, handler: usize) -> usize;
    fn kill(pid: i32, sig: i32) -> i32;
    fn getsockopt(
        sockfd: i32,
        level: i32,
        optname: i32,
        optval: *mut c_void,
        optlen: *mut u32,
    ) -> i32;
}

#[repr(C)]
struct PollFd {
    fd: i32,
    events: i16,
    revents: i16,
}

fn libc_getuid() -> u32 {
    unsafe { getuid() }
}

fn libc_getgid() -> u32 {
    unsafe { getgid() }
}
