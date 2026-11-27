use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::env;
use std::ffi::{CString, c_void};
use std::fmt::Write as _;
use std::fs;
use std::io::{Read, Write};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::os::unix::io::{AsRawFd, FromRawFd, IntoRawFd, OwnedFd, RawFd};
use std::os::unix::net::{UnixListener, UnixStream};
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio, exit};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::Instant;

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
const CFG_FLATPAK_PORTAL: u32 = 1 << 17;

const CLONE_NEWIPC: i32 = 0x0800_0000;
const CLONE_NEWNET: i32 = 0x4000_0000;
const CLONE_NEWUSER: i32 = 0x1000_0000;
const MFD_CLOEXEC: u32 = 1;
const MSG_CMSG_CLOEXEC: i32 = 0x4000_0000;
const O_RDONLY: i32 = 0;
const O_NOFOLLOW: i32 = 0x2_0000;
const O_CLOEXEC: i32 = 0x8_0000;
const O_PATH: i32 = 0x20_0000;
const F_DUPFD_CLOEXEC: i32 = 1030;
const F_SETFD: i32 = 2;

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

const EFD_CLOEXEC: i32 = 0x8_0000;
const EFD_NONBLOCK: i32 = 0x800;
const SFD_CLOEXEC: i32 = 0x8_0000;
const SFD_NONBLOCK: i32 = 0x800;
const SIG_BLOCK: i32 = 0;
const SIG_SETMASK: i32 = 2;
const SIGINT: i32 = 2;
const SIGTERM: i32 = 15;
const SIGWINCH: i32 = 28;
const POLLIN: i16 = 0x0001;
const EINTR: i32 = 4;

#[repr(C)]
#[derive(Clone, Copy)]
struct SigSet([u64; 16]);

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
        self.as_obj(ctx).get(key).and_then(|v| match v {
            Self::Null => None,
            Self::Str(s) => Some(s.clone()),
            _ => fail_exit(&format!(
                "config field '{ctx}.{key}' must be a string or null"
            )),
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

#[derive(Clone, Debug)]
struct FhsEnvSpec {
    rootfs: PathBuf,
    container_init: PathBuf,
    real_init: PathBuf,
    bwrap_scripts: Vec<String>,
    glibc_dirs: Vec<PathBuf>,
    etc_binds: Vec<String>,
    ld_so_conf: String,
    zoneinfo: bool,
}

impl FhsEnvSpec {
    fn load(path: &Path) -> Self {
        let json = read_and_parse_json_file(path);
        let rootfs = PathBuf::from(
            json.opt_str("rootfs", "fhs_env")
                .unwrap_or_else(|| fail_exit("fhs_env missing 'rootfs'")),
        );
        let container_init = PathBuf::from(
            json.opt_str("container_init", "fhs_env")
                .unwrap_or_else(|| fail_exit("fhs_env missing 'container_init'")),
        );
        let real_init = PathBuf::from(
            json.opt_str("real_init", "fhs_env")
                .unwrap_or_else(|| fail_exit("fhs_env missing 'real_init'")),
        );
        let bwrap_scripts = json.opt_str_list("bwrap_scripts", "fhs_env");
        let glibc_dirs = json
            .opt_str_list("glibc_dirs", "fhs_env")
            .into_iter()
            .map(PathBuf::from)
            .collect();
        let etc_binds = json.opt_str_list("etc_binds", "fhs_env");
        let ld_so_conf = json.opt_str("ld_so_conf", "fhs_env").unwrap_or_default();
        let zoneinfo = json.opt_bool("zoneinfo", "fhs_env").unwrap_or(false);
        Self {
            rootfs,
            container_init,
            real_init,
            bwrap_scripts,
            glibc_dirs,
            etc_binds,
            ld_so_conf,
            zoneinfo,
        }
    }
}

#[derive(Clone)]
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
    pasta_dns: String,
    singbox_bridge: String,
    allowed_env_vars: Vec<String>,
    ro_system_paths: Vec<String>,
    user_theme_subpaths: Vec<String>,
    xdg_config_subpaths: Vec<String>,
    xdg_data_subpaths: Vec<String>,
    nvidia_nodes: Vec<String>,
    gpu_dev_nodes: Vec<String>,
    gpu_ro_paths: Vec<String>,
    gamepad_dev_nodes: Vec<String>,
    webcam_sys_path: String,
    portal_etc_paths: Vec<String>,
    extra_runtime_ro_binds: Vec<String>,
    custom_uid: Option<u32>,
    custom_gid: Option<u32>,
    fhs_env: Option<FhsEnvSpec>,
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
            pasta_dns: String::new(),
            singbox_bridge: String::new(),
            allowed_env_vars: Vec::new(),
            ro_system_paths: Vec::new(),
            user_theme_subpaths: Vec::new(),
            xdg_config_subpaths: Vec::new(),
            xdg_data_subpaths: Vec::new(),
            nvidia_nodes: Vec::new(),
            gpu_dev_nodes: Vec::new(),
            gpu_ro_paths: Vec::new(),
            gamepad_dev_nodes: Vec::new(),
            webcam_sys_path: String::new(),
            portal_etc_paths: Vec::new(),
            extra_runtime_ro_binds: Vec::new(),
            custom_uid: None,
            custom_gid: None,
            fhs_env: None,
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
        set_flag("flatpak_portal", CFG_FLATPAK_PORTAL);
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
            self.gpu_dev_nodes = paths_v.opt_str_list("gpu_dev_nodes", "paths");
            self.gpu_ro_paths = paths_v.opt_str_list("gpu_ro_paths", "paths");
            self.gamepad_dev_nodes = paths_v.opt_str_list("gamepad_dev_nodes", "paths");
            self.webcam_sys_path = paths_v
                .opt_str("webcam_sys_path", "paths")
                .unwrap_or_default();
            self.portal_etc_paths = paths_v.opt_str_list("portal_etc_paths", "paths");
            self.extra_runtime_ro_binds = paths_v.opt_str_list("extra_runtime_ro_binds", "paths");
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
        if let Some(v) = root.opt_str("fhs_env", "config") {
            let expanded = expand_env_path(&v, &cfg.allowed_env_vars);
            cfg.fhs_env = Some(FhsEnvSpec::load(Path::new(&expanded)));
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
        if let Some(v) = root.opt_str("pasta_dns", "config") {
            cfg.pasta_dns = v;
        }
        if let Some(v) = root.opt_str("singbox_bridge", "config") {
            cfg.singbox_bridge = v;
        }

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
        "--flatpak-portal" => {
            cfg.flags |= CFG_FLATPAK_PORTAL;
            *i += 1;
        }
        "--no-flatpak-portal" => {
            cfg.flags &= !CFG_FLATPAK_PORTAL;
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
        "--fhs-env" if has_next => {
            let expanded = expand_env_path(&args[*i + 1], allowed_env);
            cfg.fhs_env = Some(FhsEnvSpec::load(Path::new(&expanded)));
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

fn rule_allows_userns(raw: &str) -> bool {
    let name = rule_syscall_name(raw);
    name == "unshare" || ((name == "clone" || name == "clone3") && !raw.contains("!&0x7e020080"))
}

fn seccomp_allows_userns(cfg: &SandboxConfig) -> bool {
    if (cfg.flags & CFG_SECCOMP) == 0 {
        return true;
    }
    if cfg.seccomp_allow.is_empty() {
        let blocked_in = |notify: SeccompNotify, action: SeccompAction, needle: &str| {
            cfg.seccomp_deny
                .get(&(notify, action))
                .is_some_and(|rules| rules.iter().any(|r| rule_syscall_name(r) == needle))
        };
        let blocked_unshare = [
            SeccompNotify::None,
            SeccompNotify::Log,
            SeccompNotify::Notify,
        ]
        .into_iter()
        .any(|n| {
            [
                SeccompAction::Eperm,
                SeccompAction::Enosys,
                SeccompAction::Eacces,
                SeccompAction::Kill,
                SeccompAction::Trap,
            ]
            .into_iter()
            .any(|a| blocked_in(n, a, "unshare"))
        });
        return !blocked_unshare;
    }
    cfg.seccomp_allow.iter().any(|r| rule_allows_userns(r))
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
    stop_efd: OwnedFd,
    thread: Option<JoinHandle<()>>,
}

impl SeccompMonitorHandle {
    fn shutdown(&mut self) {
        if let Some(h) = self.thread.take() {
            let val = 1u64.to_ne_bytes();
            let _ = unsafe { write(self.stop_efd.as_raw_fd(), val.as_ptr().cast(), val.len()) };
            let _ = h.join();
        }
    }
}

impl Drop for SeccompMonitorHandle {
    fn drop(&mut self) {
        self.shutdown();
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

    let efd_raw = unsafe { eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK) };
    if efd_raw < 0 {
        fail_exit(&format!(
            "failed to create seccomp stop eventfd: {}",
            std::io::Error::last_os_error()
        ));
    }
    let stop_efd = unsafe { OwnedFd::from_raw_fd(efd_raw) };
    let stop_raw = stop_efd.as_raw_fd();

    let handle = thread::spawn(move || {
        let Some(epoll) = Epoll::new() else {
            return;
        };
        let listen_fd = listener.as_raw_fd();
        epoll.add(listen_fd);
        epoll.add(stop_raw);
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

        let mut stopping = false;
        while !stopping {
            let n = match epoll.wait(&mut events, -1) {
                Ok(n) => n,
                Err(4) => continue,
                Err(_) => break,
            };
            for ev in &events[..n] {
                let Ok(fd) = i32::try_from(ev.data) else {
                    continue;
                };
                if fd == stop_raw {
                    stopping = true;
                    break;
                }
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
        stop_efd,
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
    let uid = libc_getuid();
    let runtime_dir = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| format!("/run/user/{uid}"));
    let mut env_vars: Vec<String> = env::vars()
        .filter(|(k, _)| !(cfg.dbus_mode == "sandboxed" && k == "DBUS_SESSION_BUS_ADDRESS"))
        .map(|(k, v)| format!("{k}={v}"))
        .collect();
    if cfg.dbus_mode == "sandboxed" {
        env_vars.push(format!(
            "DBUS_SESSION_BUS_ADDRESS=unix:path={runtime_dir}/nixpak-bus"
        ));
    }
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

struct SigMaskGuard {
    old_mask: SigSet,
}

impl Drop for SigMaskGuard {
    fn drop(&mut self) {
        unsafe { sigprocmask(SIG_SETMASK, &raw const self.old_mask, std::ptr::null_mut()) };
    }
}

fn forward_cli_signals(sig_fd: RawFd, stream: &mut UnixStream, is_tty: bool) {
    let mut buf = [0u8; 128];
    loop {
        let n = unsafe { read(sig_fd, buf.as_mut_ptr().cast(), buf.len()) };
        if n < 4 {
            break;
        }
        let sig_u32 = u32::from_ne_bytes([buf[0], buf[1], buf[2], buf[3]]);
        let Ok(sig) = i32::try_from(sig_u32) else {
            continue;
        };
        if sig == SIGWINCH {
            if is_tty {
                send_initial_winsize(stream);
            }
        } else if let Ok(sig_len) = u32::try_from(size_of::<i32>()) {
            let sig_hdr = IpcHeader::new(MSG_SIGNAL, sig_len, 0);
            let _ = stream.write_all(&sig_hdr.to_bytes());
            let _ = stream.write_all(&sig.to_le_bytes());
            let _ = stream.flush();
        }
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

    let mut mask = SigSet([0u64; 16]);
    let mut old_mask = SigSet([0u64; 16]);
    unsafe {
        sigemptyset(&raw mut mask);
        sigaddset(&raw mut mask, SIGINT);
        sigaddset(&raw mut mask, SIGTERM);
        sigaddset(&raw mut mask, SIGWINCH);
        sigprocmask(SIG_BLOCK, &raw const mask, &raw mut old_mask);
    }
    let mask_guard = SigMaskGuard { old_mask };

    let sfd_raw = unsafe { signalfd(-1, &raw const mask, SFD_CLOEXEC | SFD_NONBLOCK) };
    if sfd_raw < 0 {
        return 1;
    }
    let sig_fd = unsafe { OwnedFd::from_raw_fd(sfd_raw) };
    let stream_fd = stream.as_raw_fd();

    let mut resp_header_buf = [0u8; size_of::<IpcHeader>()];
    let mut header_read = 0;
    let exit_code = loop {
        let mut poll_fds = [
            PollFd {
                fd: stream_fd,
                events: POLLIN,
                revents: 0,
            },
            PollFd {
                fd: sig_fd.as_raw_fd(),
                events: POLLIN,
                revents: 0,
            },
        ];
        let n = unsafe { poll(poll_fds.as_mut_ptr(), 2, -1) };
        if n < 0 {
            if std::io::Error::last_os_error().raw_os_error() == Some(EINTR) {
                continue;
            }
            break 1;
        }
        if (poll_fds[1].revents & POLLIN) != 0 {
            forward_cli_signals(sig_fd.as_raw_fd(), stream, is_tty);
        }
        if poll_fds[0].revents != 0 {
            match stream.read(&mut resp_header_buf[header_read..]) {
                Ok(0) => break 1,
                Ok(bytes_n) => {
                    header_read += bytes_n;
                    if header_read >= size_of::<IpcHeader>() {
                        break 0;
                    }
                }
                Err(ref e) if e.kind() == std::io::ErrorKind::Interrupted => {}
                Err(_) => break 1,
            }
        }
    };

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
    drop(mask_guard);
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
          --flatpak-portal           Enable org.freedesktop.portal.Flatpak sub-sandbox portal\n\
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

fn collect_fhs_etc_splits(cfg: &SandboxConfig, fhs: &FhsEnvSpec) -> BTreeSet<String> {
    let mut splits = BTreeSet::new();
    let targets = cfg.ro_system_paths.iter().map(String::as_str).chain(
        cfg.ro_binds
            .iter()
            .chain(cfg.rw_binds.iter())
            .map(|s| s.split_once(':').map_or(s.as_str(), |(_, dst)| dst)),
    );
    for target in targets {
        if let Some(rest) = target.strip_prefix("/etc/")
            && let Some((sub, _)) = rest.split_once('/')
            && !sub.is_empty()
            && !matches!(sub, "fonts" | "ssl")
            && !fhs.etc_binds.iter().any(|e| e == target)
            && fhs.rootfs.join("etc").join(sub).is_dir()
        {
            splits.insert(sub.to_string());
        }
    }
    splits
}

fn add_fhs_etc_entries(
    cmd: &mut Command,
    rootfs_etc: &Path,
    split_dirs: &BTreeSet<String>,
) -> BTreeSet<String> {
    let mut ignored = BTreeSet::new();
    let Ok(entries) = fs::read_dir(rootfs_etc) else {
        return ignored;
    };
    for entry in entries.flatten() {
        let name = entry.file_name();
        let name_str = name.to_string_lossy();
        if matches!(name_str.as_ref(), "fonts" | "ssl") {
            continue;
        }
        let dest = format!("/etc/{name_str}");
        let p = entry.path();
        if split_dirs.contains(name_str.as_ref()) && p.is_dir() && !p.is_symlink() {
            cmd.arg("--dir").arg(&dest);
            if let Ok(sub_entries) = fs::read_dir(&p) {
                for se in sub_entries.flatten() {
                    let sp = se.path();
                    let sdest = format!("{dest}/{}", se.file_name().to_string_lossy());
                    cmd.arg(if sp.is_symlink() {
                        "--symlink"
                    } else {
                        "--ro-bind"
                    })
                    .arg(&sp)
                    .arg(&sdest);
                }
            }
        } else {
            cmd.arg(if p.is_symlink() {
                "--symlink"
            } else {
                "--ro-bind"
            })
            .arg(&p)
            .arg(&dest);
        }
        ignored.insert(dest);
    }
    ignored
}

fn add_fhs_env_mounts(
    cmd: &mut Command,
    fhs: &FhsEnvSpec,
    split_dirs: &BTreeSet<String>,
    parent_etc_dir: Option<&Path>,
    cache_src_dir: Option<&Path>,
    network: &str,
    resolv_override: Option<&Path>,
) {
    cmd.arg("--ro-bind").arg("/etc").arg("/.host-etc");
    if let Some(etc_dir) = parent_etc_dir {
        let _ = fs::remove_dir_all(etc_dir);
        let _ = fs::create_dir_all(etc_dir);
        if !fhs.ld_so_conf.is_empty() {
            let _ = fs::write(etc_dir.join("ld.so.conf"), &fhs.ld_so_conf);
        }
        cmd.arg("--bind").arg(etc_dir).arg("/etc");
    } else {
        cmd.arg("--tmpfs").arg("/etc");
    }

    if let Ok(entries) = fs::read_dir(&fhs.rootfs) {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let name_str = name.to_string_lossy();
            if name_str == "etc" {
                continue;
            }
            let dest = format!("/{name_str}");
            let p = entry.path();
            if let Ok(target) = fs::read_link(&p) {
                cmd.arg("--symlink").arg(target).arg(&dest);
            } else {
                cmd.arg("--ro-bind").arg(&p).arg(&dest);
            }
        }
    }

    let etc_ignored = add_fhs_etc_entries(cmd, &fhs.rootfs.join("etc"), split_dirs);
    for host_etc in &fhs.etc_binds {
        if host_etc == "/etc/resolv.conf" {
            if network == "off" {
                continue;
            }
            if let Some(r) = resolv_override
                && r.exists()
            {
                cmd.arg("--ro-bind").arg(r).arg("/etc/resolv.conf");
                continue;
            }
        }
        if !etc_ignored.contains(host_etc)
            && Path::new(host_etc).exists()
            && let Some(rel) = host_etc.strip_prefix("/etc/")
        {
            cmd.arg("--symlink")
                .arg(format!("/.host-etc/{rel}"))
                .arg(host_etc);
        }
    }

    if let Some(src_dir) = cache_src_dir {
        for name in ["ld.so.conf", "ld.so.cache"] {
            let p = src_dir.join(name);
            if p.exists() {
                cmd.arg("--ro-bind").arg(&p).arg(format!("/etc/{name}"));
            }
        }
    }

    for g in &fhs.glibc_dirs {
        let g_etc = g.join("etc");
        cmd.arg("--tmpfs")
            .arg(&g_etc)
            .arg("--symlink")
            .arg("/etc/ld.so.conf")
            .arg(g_etc.join("ld.so.conf"))
            .arg("--symlink")
            .arg("/etc/ld.so.cache")
            .arg(g_etc.join("ld.so.cache"));
        let rpc = g_etc.join("rpc");
        if rpc.exists() {
            cmd.arg("--ro-bind").arg(&rpc).arg(&rpc);
        }
        cmd.arg("--remount-ro").arg(&g_etc);
    }

    cmd.arg("--symlink").arg(&fhs.real_init).arg("/init");
    if fhs.zoneinfo && Path::new("/etc/zoneinfo").exists() {
        cmd.arg("--ro-bind")
            .arg("/etc/zoneinfo")
            .arg("/usr/share/zoneinfo");
    }
}

fn add_system_and_fhs_binds(
    cmd: &mut Command,
    cfg: &SandboxConfig,
    parent_etc_dir: Option<&Path>,
    cache_src_dir: Option<&Path>,
    network: &str,
    resolv_override: Option<&Path>,
) {
    let Some(ref fhs) = cfg.fhs_env else {
        for path in &cfg.ro_system_paths {
            if Path::new(path).exists() {
                cmd.arg("--ro-bind-try").arg(path).arg(path);
            }
        }
        return;
    };

    let split_dirs = collect_fhs_etc_splits(cfg, fhs);
    for path in &cfg.ro_system_paths {
        if path != "/bin"
            && path != "/usr/bin"
            && !path.starts_with("/etc")
            && Path::new(path).exists()
        {
            cmd.arg("--ro-bind-try").arg(path).arg(path);
        }
    }
    add_fhs_env_mounts(
        cmd,
        fhs,
        &split_dirs,
        parent_etc_dir,
        cache_src_dir,
        network,
        resolv_override,
    );
    for path in &cfg.ro_system_paths {
        if let Some(rest) = path.strip_prefix("/etc/")
            && let Some((sub, _)) = rest.split_once('/')
            && split_dirs.contains(sub)
            && Path::new(path).exists()
        {
            cmd.arg("--ro-bind-try").arg(path).arg(path);
        }
    }
}

fn add_user_theme_binds(
    cmd: &mut Command,
    cfg: &SandboxConfig,
    home: &str,
    xdg_config: &str,
    xdg_data: &str,
) {
    let mut bind_subs = |base: &str, subs: &[String]| {
        for sub in subs {
            let p = format!("{base}/{sub}");
            if Path::new(&p).exists() {
                cmd.arg("--ro-bind-try").arg(&p).arg(&p);
            }
        }
    };
    bind_subs(home, &cfg.user_theme_subpaths);
    bind_subs(xdg_config, &cfg.xdg_config_subpaths);
    bind_subs(xdg_data, &cfg.xdg_data_subpaths);
}

fn add_gpu_binds(cmd: &mut Command, cfg: &SandboxConfig) {
    for node in cfg.gpu_dev_nodes.iter().chain(cfg.nvidia_nodes.iter()) {
        if Path::new(node).exists() {
            cmd.arg("--dev-bind").arg(node).arg(node);
        }
    }
    for ro in &cfg.gpu_ro_paths {
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

    for rel in &cfg.extra_runtime_ro_binds {
        let p = format!("{runtime_dir}/{rel}");
        if Path::new(&p).exists() {
            cmd.arg("--ro-bind-try").arg(&p).arg(&p);
        }
    }
    if (cfg.subsystems & SUBSYS_GAMEPAD) != 0 {
        add_gamepad_binds(cmd, cfg);
    }
    if cfg.webcam != WebcamMode::Off && !cfg.webcam_sys_path.is_empty() {
        cmd.arg("--ro-bind-try")
            .arg(&cfg.webcam_sys_path)
            .arg(&cfg.webcam_sys_path);
    }
    if cfg.webcam == WebcamMode::Auto
        && !cfg.webcam_sys_path.is_empty()
        && let Ok(entries) = fs::read_dir(&cfg.webcam_sys_path)
    {
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

fn add_gamepad_binds(cmd: &mut Command, cfg: &SandboxConfig) {
    for node in &cfg.gamepad_dev_nodes {
        if Path::new(node).exists() {
            cmd.arg("--dev-bind-try").arg(node).arg(node);
        }
    }
}

fn add_shared_runtime_binds(cmd: &mut Command, cfg: &SandboxConfig, sandbox_runtime: &Path) {
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
}

fn add_session_dbus_binds(
    cmd: &mut Command,
    cfg: &SandboxConfig,
    runtime: &str,
    sandbox_runtime: &Path,
    set_env: bool,
) {
    if cfg.dbus_mode == "sandboxed" {
        let dbus_proxy_sock = sandbox_runtime.join("nixpak-bus");
        cmd.arg("--bind-try")
            .arg(&dbus_proxy_sock)
            .arg(format!("{runtime}/nixpak-bus"));
        cmd.arg("--bind-try")
            .arg(&dbus_proxy_sock)
            .arg(format!("{runtime}/bus"));
        if set_env {
            cmd.arg("--setenv")
                .arg("DBUS_SESSION_BUS_ADDRESS")
                .arg(format!("unix:path={runtime}/nixpak-bus"));
        }
    } else if cfg.dbus_mode == "passthrough" {
        if let Ok(session_bus) = env::var("DBUS_SESSION_BUS_ADDRESS") {
            if let Some(path) = session_bus.strip_prefix("unix:path=") {
                cmd.arg("--bind-try").arg(path).arg(path);
                cmd.arg("--bind-try")
                    .arg(path)
                    .arg(format!("{runtime}/bus"));
            }
            if set_env {
                cmd.arg("--setenv")
                    .arg("DBUS_SESSION_BUS_ADDRESS")
                    .arg(&session_bus);
            }
        }
    } else if set_env {
        cmd.arg("--unsetenv").arg("DBUS_SESSION_BUS_ADDRESS");
    }
}

fn add_session_and_system_dbus_binds(
    cmd: &mut Command,
    cfg: &SandboxConfig,
    runtime: &str,
    sandbox_runtime: &Path,
    set_env: bool,
) {
    add_session_dbus_binds(cmd, cfg, runtime, sandbox_runtime, set_env);

    if (cfg.flags & CFG_SYSTEM_DBUS) != 0 {
        let host_sys_proxy = sandbox_runtime.join("nixpak-system-bus");
        let in_sandbox_sys_proxy = format!("{runtime}/nixpak-system-bus");
        cmd.arg("--bind-try")
            .arg(&host_sys_proxy)
            .arg(&in_sandbox_sys_proxy);
        cmd.arg("--bind-try")
            .arg(&host_sys_proxy)
            .arg("/run/dbus/system_bus_socket");
        if set_env {
            cmd.arg("--setenv")
                .arg("DBUS_SYSTEM_BUS_ADDRESS")
                .arg(format!("unix:path={in_sandbox_sys_proxy}"));
        }
    }
}

fn add_sesatt_doc_mime_binds(
    cmd: &mut Command,
    cfg: &SandboxConfig,
    runtime: &str,
    xdg_config: &str,
) {
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

    if (cfg.flags & CFG_PORTALS) != 0 {
        let portal_mime = format!("{xdg_config}/mimeapps.list");
        if Path::new(&portal_mime).exists() {
            cmd.arg("--ro-bind-try").arg(&portal_mime).arg(&portal_mime);
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
    add_session_and_system_dbus_binds(cmd, cfg, runtime, sandbox_runtime, true);
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
    if cfg.network != "off" {
        shared.push("network");
    }
    if !shared.is_empty() {
        let _ = writeln!(content, "shared={};", shared.join(";"));
    }
    if cfg.shm_mode != "off" {
        let _ = writeln!(content, "features=per-app-dev-shm;");
    }

    let _ = write!(
        content,
        "\n[Instance]\ninstance-id={instance_id}\napp-path=/app\nruntime-path=/usr\nflatpak-version=1.18.4\n\n[Session Bus Policy]\n"
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
        if !cfg.pasta_dns.is_empty() {
            let resolv_path = sandbox_runtime.join("resolv.conf");
            let _ = fs::write(&resolv_path, format!("nameserver {}\n", cfg.pasta_dns));
            cmd.arg("--ro-bind")
                .arg(&resolv_path)
                .arg("/etc/resolv.conf");
        }
    } else if cfg.network != "passthrough" {
        cmd.arg("--unshare-net");
    }
}

fn is_system_usr_etc_path(path: &str) -> bool {
    ["/usr", "/bin", "/sbin", "/lib", "/lib32", "/lib64", "/etc"]
        .iter()
        .any(|p| path == *p || path.starts_with(&format!("{p}/")))
}

fn add_custom_bind_flags(
    cmd: &mut Command,
    cfg: &SandboxConfig,
    skip_sys_usr_etc: bool,
    create_parents: bool,
) {
    for d in &cfg.mkdir_dirs {
        if !skip_sys_usr_etc || !is_system_usr_etc_path(d) {
            cmd.arg("--dir").arg(d);
        }
    }
    for b in &cfg.ro_binds {
        let (src, dst) = b.split_once(':').unwrap_or((b.as_str(), b.as_str()));
        if !skip_sys_usr_etc || !is_system_usr_etc_path(dst) {
            cmd.arg("--ro-bind-try").arg(src).arg(dst);
        }
    }
    for b in &cfg.rw_binds {
        let (src, dst) = b.split_once(':').unwrap_or((b.as_str(), b.as_str()));
        if skip_sys_usr_etc && is_system_usr_etc_path(dst) {
            continue;
        }
        if create_parents && let Some(parent) = Path::new(src).parent() {
            let _ = fs::create_dir_all(parent);
        }
        cmd.arg("--bind-try").arg(src).arg(dst);
    }
    for b in &cfg.dev_binds {
        let (src, dst) = b.split_once(':').unwrap_or((b.as_str(), b.as_str()));
        if !skip_sys_usr_etc || !is_system_usr_etc_path(dst) {
            cmd.arg("--dev-bind-try").arg(src).arg(dst);
        }
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
    add_custom_bind_flags(cmd, cfg, false, true);
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
        if !cfg.singbox_bridge.is_empty() {
            cmd.arg("--singbox-bridge").arg(&cfg.singbox_bridge);
        }
    }

    if cfg.x11_mode == "sandboxed" {
        cmd.arg("--x11-mode")
            .arg("sandboxed")
            .arg("--xwayland-bin")
            .arg(&cfg.xwayland_satellite_bin);
    }

    if cfg.fhs_env.is_some() {
        cmd.arg("--inside-init").arg("/bin/ldconfig 2>/dev/null");
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

fn add_bwrap_ns_and_user_args(cmd: &mut Command, cfg: &SandboxConfig) {
    let disable_userns = (cfg.flags & CFG_FLATPAK_PORTAL) != 0 && !seccomp_allows_userns(cfg);
    cmd.arg("--die-with-parent");
    if let Some(uid) = cfg.custom_uid {
        cmd.arg("--unshare-user").arg("--uid").arg(uid.to_string());
        if let Some(gid) = cfg.custom_gid {
            cmd.arg("--gid").arg(gid.to_string());
        }
        if disable_userns && cfg.network != "singbox" {
            cmd.arg("--disable-userns");
        }
    } else if disable_userns && cfg.network != "singbox" {
        cmd.arg("--unshare-user").arg("--disable-userns");
    } else {
        cmd.arg("--unshare-user-try");
    }
    if (cfg.flags & CFG_SHARE_IPC) == 0 {
        cmd.arg("--unshare-ipc");
    }
    if (cfg.flags & CFG_SHARE_PID) == 0 {
        cmd.arg("--unshare-pid").arg("--as-pid-1");
    }
    cmd.arg("--unshare-uts").arg("--unshare-cgroup-try");
    cmd.arg("--proc").arg("/proc").arg("--dev").arg("/dev");
    cmd.arg("--dir")
        .arg("/run")
        .arg("--ro-bind-try")
        .arg("/proc/self/ns/user")
        .arg("/run/.userns");
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

    add_bwrap_ns_and_user_args(&mut cmd, cfg);

    add_network_bwrap_args(&mut cmd, cfg, sandbox_runtime);

    cmd.arg("--bind-try").arg(sandbox_home).arg(&home);
    cmd.arg("--bind-try").arg(sandbox_runtime).arg(&runtime);
    add_shared_runtime_binds(&mut cmd, cfg, sandbox_runtime);

    let _ = fs::create_dir_all(sandbox_runtime.join("bin"));
    add_sesatt_doc_mime_binds(&mut cmd, cfg, &runtime, &xdg_config);

    let fhs_etc_dir = sandbox_runtime.join("fhs-etc");
    let resolv_override = (cfg.network == "sandboxed").then(|| sandbox_runtime.join("resolv.conf"));
    add_system_and_fhs_binds(
        &mut cmd,
        cfg,
        Some(&fhs_etc_dir),
        None,
        &cfg.network,
        resolv_override.as_deref(),
    );
    add_user_theme_binds(&mut cmd, cfg, &home, &xdg_config, &xdg_data);
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
    if (cfg.flags & (CFG_FLATPAK_INFO | CFG_FLATPAK_PORTAL)) != 0 {
        let run_host = sandbox_runtime.join("run-host");
        let _ = fs::create_dir_all(&run_host);
        let _ = fs::write(run_host.join("container-manager"), "flatpak\n");
        cmd.arg("--ro-bind").arg(&run_host).arg("/run/host");
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

fn setup_bridges(cfg: &SandboxConfig, sandbox_runtime: &Path, ipc_sock: &Path) -> Vec<i32> {
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
            pasta_dns: String::new(),
            singbox_bridge: String::new(),
            allowed_env_vars: Vec::new(),
            ro_system_paths: Vec::new(),
            user_theme_subpaths: Vec::new(),
            xdg_config_subpaths: Vec::new(),
            xdg_data_subpaths: Vec::new(),
            nvidia_nodes: Vec::new(),
            gpu_dev_nodes: Vec::new(),
            gpu_ro_paths: Vec::new(),
            gamepad_dev_nodes: Vec::new(),
            webcam_sys_path: String::new(),
            portal_etc_paths: Vec::new(),
            extra_runtime_ro_binds: Vec::new(),
            custom_uid: None,
            custom_gid: None,
            fhs_env: None,
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
    sandbox_marker: &Path,
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
        .arg("--ro-bind-try")
        .arg(sandbox_marker)
        .arg("/.sb-sandbox")
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
    sandbox_marker: &Path,
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
    if (cfg.flags & CFG_FLATPAK_PORTAL) != 0
        && !cfg
            .dbus_talk
            .iter()
            .any(|t| t == "org.freedesktop.portal.Flatpak")
    {
        rules.push("--talk=org.freedesktop.portal.Flatpak".into());
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
    spawn_dbus_proxy_bwrap(
        cfg,
        &session_bus,
        proxy_sock,
        flatpak_info,
        sandbox_marker,
        &rules,
    )
}

fn start_system_dbus_proxy(
    cfg: &SandboxConfig,
    proxy_sock: &Path,
    flatpak_info: &Path,
    sandbox_marker: &Path,
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
        sandbox_marker,
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
    portal: Option<&mut FlatpakPortalHandle>,
) {
    if let Some(p) = portal {
        p.shutdown();
    }
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
        "flatpak-portal.sock",
    ] {
        let _ = fs::remove_file(paths.runtime.join(name));
    }
    let _ = fs::remove_dir_all(paths.runtime.join("fhs-etc"));
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

#[repr(C, packed)]
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
    portal: Option<FlatpakPortalHandle>,
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
        args.portal.as_mut(),
    );
}

// ---------------------------------------------------------------------------
// Per-Sandbox org.freedesktop.portal.Flatpak Handler
// ---------------------------------------------------------------------------

const PORTAL_OP_SPAWN: u8 = 1;
const PORTAL_OP_SIGNAL: u8 = 2;
const PORTAL_OP_KILL: u8 = 3;
const PORTAL_EVT_STARTED: u8 = 1;
const PORTAL_EVT_EXITED: u8 = 2;

const FLATPAK_SPAWN_CLEAR_ENV: u32 = 1 << 0;
const FLATPAK_SPAWN_SANDBOX: u32 = 1 << 2;
const FLATPAK_SPAWN_NO_NETWORK: u32 = 1 << 3;
const FLATPAK_SPAWN_WATCH_BUS: u32 = 1 << 4;
const FLATPAK_SPAWN_EXPOSE_PIDS: u32 = 1 << 5;
const FLATPAK_SPAWN_NOTIFY_START: u32 = 1 << 6;
const FLATPAK_SPAWN_EMPTY_APP: u32 = 1 << 8;

const FLATPAK_SANDBOX_SHARE_DISPLAY: u32 = 1 << 0;
const FLATPAK_SANDBOX_SHARE_SOUND: u32 = 1 << 1;
const FLATPAK_SANDBOX_SHARE_GPU: u32 = 1 << 2;
const FLATPAK_SANDBOX_ALLOW_DBUS: u32 = 1 << 3;
const FLATPAK_SANDBOX_SHARE_INPUT: u32 = 1 << 5;
const FLATPAK_SANDBOX_SHARE_SHM: u32 = 1 << 8;

#[repr(C, align(8))]
struct PortalCmsgBuffer([u8; 1024]);

struct BufCursor<'a> {
    data: &'a [u8],
    pos: usize,
}

impl<'a> BufCursor<'a> {
    const fn new(data: &'a [u8]) -> Self {
        Self { data, pos: 0 }
    }

    fn read_u8(&mut self) -> Result<u8, String> {
        let b = *self
            .data
            .get(self.pos)
            .ok_or_else(|| "unexpected EOF reading u8".to_string())?;
        self.pos += 1;
        Ok(b)
    }

    fn read_u32(&mut self) -> Result<u32, String> {
        if self.pos + 4 > self.data.len() {
            return Err("unexpected EOF reading u32".into());
        }
        let val = u32::from_le_bytes([
            self.data[self.pos],
            self.data[self.pos + 1],
            self.data[self.pos + 2],
            self.data[self.pos + 3],
        ]);
        self.pos += 4;
        Ok(val)
    }

    fn read_str(&mut self) -> Result<String, String> {
        let len = usize::try_from(self.read_u32()?).map_err(|_| "length overflow".to_string())?;
        if self.pos + len > self.data.len() {
            return Err("unexpected EOF reading string".into());
        }
        let s = String::from_utf8(self.data[self.pos..self.pos + len].to_vec())
            .map_err(|_| "invalid utf8 string".to_string())?;
        self.pos += len;
        Ok(s)
    }

    fn read_str_list(&mut self) -> Result<Vec<String>, String> {
        let count = usize::try_from(self.read_u32()?).map_err(|_| "count overflow".to_string())?;
        if count > 4096 {
            return Err("string list too large".into());
        }
        let mut out = Vec::with_capacity(count);
        for _ in 0..count {
            out.push(self.read_str()?);
        }
        Ok(out)
    }
}

struct PortalSpawnReq {
    caller_pid: u32,
    flags: u32,
    sandbox_flags: u32,
    cwd: String,
    argv: Vec<String>,
    envs: Vec<String>,
    unset_env: Vec<String>,
    sandbox_expose: Vec<String>,
    sandbox_expose_ro: Vec<String>,
    fds: Vec<(i32, OwnedFd)>,
    expose_rw_fds: Vec<OwnedFd>,
    expose_ro_fds: Vec<OwnedFd>,
    usr_fd: Option<OwnedFd>,
    app_fd: Option<OwnedFd>,
}

struct PortalContext {
    cfg: SandboxConfig,
    paths: SandboxPaths,
    runner_pid: u32,
    seccomp_bpf: Option<Vec<u8>>,
    seccomp_sock_path: Option<PathBuf>,
    parent_userns_disabled: bool,
    flatpak_info_path: PathBuf,
    sandbox_marker_path: PathBuf,
}

struct PortalChild {
    pid: u32,
    child: Child,
    pidfd: i32,
    client_stream: UnixStream,
    watch_bus: bool,
}

struct FlatpakPortalHandle {
    stop_efd: OwnedFd,
    thread: Option<JoinHandle<()>>,
}

impl FlatpakPortalHandle {
    fn shutdown(&mut self) {
        if let Some(h) = self.thread.take() {
            let val = 1u64.to_ne_bytes();
            let _ = unsafe { write(self.stop_efd.as_raw_fd(), val.as_ptr().cast(), val.len()) };
            let _ = h.join();
        }
    }
}

impl Drop for FlatpakPortalHandle {
    fn drop(&mut self) {
        self.shutdown();
    }
}

fn recv_portal_packet(stream: &mut UnixStream) -> std::io::Result<(Vec<u8>, Vec<OwnedFd>)> {
    let mut chunk = vec![0u8; 65536];
    let mut iov = LibcIovec {
        iov_base: chunk.as_mut_ptr().cast(),
        iov_len: chunk.len(),
    };
    let mut cmsg_buf = PortalCmsgBuffer([0u8; 1024]);
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

    let n = unsafe { recvmsg(stream.as_raw_fd(), &raw mut msg, MSG_CMSG_CLOEXEC) };
    if n <= 0 {
        return Err(std::io::Error::last_os_error());
    }
    let recvd = usize::try_from(n).unwrap_or(0);
    if recvd < 4 {
        return Err(std::io::Error::new(
            std::io::ErrorKind::UnexpectedEof,
            "incomplete portal packet length",
        ));
    }

    let mut fds = Vec::new();
    if msg.controllen >= size_of::<LibcCmsghdr>() {
        let cmsg = msg.control.cast::<LibcCmsghdr>();
        unsafe {
            if !cmsg.is_null()
                && (*cmsg).len >= size_of::<LibcCmsghdr>()
                && (*cmsg).len <= msg.controllen
                && (*cmsg).level == SOL_SOCKET
                && (*cmsg).type_ == SCM_RIGHTS
            {
                let count = ((*cmsg).len - size_of::<LibcCmsghdr>()) / size_of::<RawFd>();
                let ptr = cmsg.add(1).cast::<RawFd>();
                for idx in 0..count {
                    let fd = *ptr.add(idx);
                    if fd >= 0 {
                        fds.push(OwnedFd::from_raw_fd(fd));
                    }
                }
            }
        }
    }

    let body_len =
        usize::try_from(u32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]])).unwrap_or(0);
    if body_len > 4 * 1024 * 1024 {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "oversized portal packet",
        ));
    }

    let mut body = Vec::with_capacity(body_len);
    let initial_body = &chunk[4..recvd];
    if initial_body.len() >= body_len {
        body.extend_from_slice(&initial_body[..body_len]);
    } else {
        body.extend_from_slice(initial_body);
        let rem = body_len - body.len();
        let start = body.len();
        body.resize(body_len, 0);
        stream.read_exact(&mut body[start..start + rem])?;
    }
    Ok((body, fds))
}

fn parse_spawn_request(data: &[u8], fds: Vec<OwnedFd>) -> Result<PortalSpawnReq, String> {
    let mut cur = BufCursor::new(data);
    let caller_pid = cur.read_u32()?;
    let flags = cur.read_u32()?;
    let sandbox_flags = cur.read_u32()?;
    let cwd = cur.read_str()?;
    let argv = cur.read_str_list()?;
    let envs = cur.read_str_list()?;
    let unset_env = cur.read_str_list()?;
    let sandbox_expose = cur.read_str_list()?;
    let sandbox_expose_ro = cur.read_str_list()?;

    let fd_count = usize::try_from(cur.read_u32()?).map_err(|_| "fd count overflow".to_string())?;
    let mut dest_fds = Vec::with_capacity(fd_count);
    for _ in 0..fd_count {
        let d = cur.read_u32()?;
        let di = i32::try_from(d).map_err(|_| "dest fd out of range".to_string())?;
        dest_fds.push(di);
    }
    let rw_fd_count =
        usize::try_from(cur.read_u32()?).map_err(|_| "rw count overflow".to_string())?;
    let readonly_fd_count =
        usize::try_from(cur.read_u32()?).map_err(|_| "ro count overflow".to_string())?;
    let has_usr = cur.read_u8()? != 0;
    let has_app = cur.read_u8()? != 0;

    let expected_fds =
        fd_count + rw_fd_count + readonly_fd_count + usize::from(has_usr) + usize::from(has_app);
    if fds.len() != expected_fds {
        return Err(format!(
            "portal fd count mismatch: expected {expected_fds}, got {}",
            fds.len()
        ));
    }

    let mut fd_iter = fds.into_iter();
    let mut mapped_fds = Vec::with_capacity(fd_count);
    for dest in dest_fds {
        if let Some(f) = fd_iter.next() {
            mapped_fds.push((dest, f));
        }
    }
    let expose_rw_fds: Vec<OwnedFd> = fd_iter.by_ref().take(rw_fd_count).collect();
    let readonly_expose_fds: Vec<OwnedFd> = fd_iter.by_ref().take(readonly_fd_count).collect();
    let usr_fd = if has_usr { fd_iter.next() } else { None };
    let app_fd = if has_app { fd_iter.next() } else { None };

    Ok(PortalSpawnReq {
        caller_pid,
        flags,
        sandbox_flags,
        cwd,
        argv,
        envs,
        unset_env,
        sandbox_expose,
        sandbox_expose_ro,
        fds: mapped_fds,
        expose_rw_fds,
        expose_ro_fds: readonly_expose_fds,
        usr_fd,
        app_fd,
    })
}

fn read_proc_nspid(pid: u32) -> Vec<u32> {
    let Ok(content) = fs::read_to_string(format!("/proc/{pid}/status")) else {
        return Vec::new();
    };
    for line in content.lines() {
        if let Some(rest) = line.strip_prefix("NSpid:") {
            return rest
                .split_whitespace()
                .filter_map(|t| t.parse::<u32>().ok())
                .collect();
        }
    }
    Vec::new()
}

fn resolve_relpid(child_pid: u32, caller_depth: usize) -> u32 {
    if caller_depth == 0 {
        return 0;
    }
    let child_ns = read_proc_nspid(child_pid);
    child_ns.get(caller_depth - 1).copied().unwrap_or(0)
}

fn verify_caller_sandbox(caller_pid: u32, app_id: &str) -> Result<(), String> {
    let marker = fs::read_to_string(format!("/proc/{caller_pid}/root/.sb-sandbox"))
        .map_err(|e| format!("unable to verify caller sandbox: {e}"))?;
    if marker.trim() != app_id {
        return Err("caller sandbox app_id mismatch".into());
    }
    Ok(())
}

fn fd_dev_ino(fd: RawFd) -> Option<(u64, u64)> {
    let dup = unsafe { fcntl(fd, F_DUPFD_CLOEXEC, 0) };
    if dup < 0 {
        return None;
    }
    let file = unsafe { fs::File::from_raw_fd(dup) };
    let meta = file.metadata().ok()?;
    Some((meta.dev(), meta.ino()))
}

fn open_matching_inode(path: &str, expected: (u64, u64)) -> Option<OwnedFd> {
    let c_p = CString::new(path).ok()?;
    let raw = unsafe { open(c_p.as_ptr(), O_PATH | O_NOFOLLOW | O_CLOEXEC) };
    if raw < 0 {
        return None;
    }
    let owned = unsafe { OwnedFd::from_raw_fd(raw) };
    if fd_dev_ino(owned.as_raw_fd()) == Some(expected) {
        Some(owned)
    } else {
        None
    }
}

fn map_path_prefix(path: &str, pairs: &[(String, String)]) -> Option<String> {
    let mut best_len = 0usize;
    let mut best: Option<String> = None;
    for (from, to) in pairs {
        if path == from && from.len() >= best_len {
            best_len = from.len();
            best = Some(to.clone());
        } else if let Some(rest) = path.strip_prefix(from)
            && rest.starts_with('/')
            && from.len() >= best_len
        {
            best_len = from.len();
            best = Some(format!("{to}{rest}"));
        }
    }
    best
}

fn sandbox_mount_pairs(ctx: &PortalContext) -> Vec<(String, String)> {
    let home = env::var("HOME").unwrap_or_else(|_| "/home/user".into());
    let runtime = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/run/user/1000".into());
    let mut pairs = Vec::new();
    if ctx.cfg.tmp_mode != "passthrough" {
        pairs.push((
            ctx.paths.runtime.join("tmp").to_string_lossy().into_owned(),
            "/tmp".into(),
        ));
    }
    if ctx.cfg.shm_mode != "passthrough" {
        pairs.push((
            ctx.paths.runtime.join("shm").to_string_lossy().into_owned(),
            "/dev/shm".into(),
        ));
    }
    pairs.push((ctx.paths.runtime.to_string_lossy().into_owned(), runtime));
    pairs.push((ctx.paths.home.to_string_lossy().into_owned(), home));
    for spec in ctx.cfg.rw_binds.iter().chain(ctx.cfg.ro_binds.iter()) {
        if let Some((src, dst)) = spec.split_once(':') {
            pairs.push((src.to_string(), dst.to_string()));
        }
    }
    pairs
}

fn resolve_sandbox_fd(fd: RawFd, ctx: &PortalContext) -> Option<(OwnedFd, String)> {
    let resolved = fs::read_link(format!("/proc/self/fd/{fd}")).ok()?;
    let raw = resolved.to_string_lossy();
    if !raw.starts_with('/') || raw.ends_with(" (deleted)") {
        return None;
    }
    let expected = fd_dev_ino(fd)?;
    let host_to_guest = sandbox_mount_pairs(ctx);
    let mut guest_to_host: Vec<(String, String)> = host_to_guest
        .iter()
        .map(|(h, g)| (g.clone(), h.clone()))
        .collect();
    guest_to_host.sort_by_key(|a| std::cmp::Reverse(a.0.len()));

    for (guest_p, host_p) in &guest_to_host {
        let candidate = if raw.as_ref() == guest_p {
            Some(host_p.clone())
        } else if let Some(rest) = raw.strip_prefix(guest_p)
            && rest.starts_with('/')
        {
            Some(format!("{host_p}{rest}"))
        } else {
            None
        };
        if let Some(host_path) = candidate
            && let Some(host_fd) = open_matching_inode(&host_path, expected)
        {
            return Some((host_fd, raw.into_owned()));
        }
    }

    if let Some(host_fd) = open_matching_inode(&raw, expected) {
        let guest = map_path_prefix(&raw, &host_to_guest).unwrap_or_else(|| raw.into_owned());
        return Some((host_fd, guest));
    }
    None
}

fn is_descendant_of(mut pid: u32, ancestor: u32) -> bool {
    if pid == ancestor {
        return true;
    }
    for _ in 0..32 {
        let Ok(status) = fs::read_to_string(format!("/proc/{pid}/status")) else {
            return false;
        };
        let parent_pid = status
            .lines()
            .find_map(|l| l.strip_prefix("PPid:"))
            .and_then(|v| v.trim().parse::<u32>().ok())
            .unwrap_or(0);
        if parent_pid == ancestor {
            return true;
        }
        if parent_pid <= 1 || parent_pid == pid {
            return false;
        }
        pid = parent_pid;
    }
    false
}

fn collect_descendants_bfs(root: u32) -> Vec<u32> {
    let mut result = Vec::new();
    let mut visited = BTreeSet::new();
    let mut queue = std::collections::VecDeque::new();
    visited.insert(root);
    queue.push_back(root);
    while let Some(pid) = queue.pop_front() {
        let Ok(tasks) = fs::read_dir(format!("/proc/{pid}/task")) else {
            continue;
        };
        for entry in tasks.flatten() {
            let children_path = entry.path().join("children");
            let Ok(children) = fs::read_to_string(children_path) else {
                continue;
            };
            for tok in children.split_whitespace() {
                if let Ok(child_pid) = tok.parse::<u32>()
                    && visited.insert(child_pid)
                {
                    result.push(child_pid);
                    queue.push_back(child_pid);
                }
            }
        }
    }
    result
}

fn resolve_effective_caller_pid(ctx: &PortalContext, caller_pid: u32) -> u32 {
    if is_descendant_of(caller_pid, ctx.runner_pid) {
        return caller_pid;
    }

    let host_userns = fs::read_link("/proc/self/ns/user").ok();
    let runner_userns = fs::read_link(format!("/proc/{}/ns/user", ctx.runner_pid)).ok();
    let runner_u1 = fs::read_link(format!("/proc/{}/root/run/.userns", ctx.runner_pid)).ok();
    let runner_mntns = fs::read_link(format!("/proc/{}/ns/mnt", ctx.runner_pid)).ok();
    let mut candidates = collect_descendants_bfs(ctx.runner_pid);
    if let Ok(cg) = env::var("MY_CGROUP") {
        let mut inside: Vec<i32> =
            read_pids_from_file(&PathBuf::from(format!("{cg}/inside/cgroup.procs")))
                .into_iter()
                .collect();
        inside.sort_unstable();
        for p in inside {
            if let Ok(pu) = u32::try_from(p)
                && pu != ctx.runner_pid
                && !candidates.contains(&pu)
            {
                candidates.push(pu);
            }
        }
    }

    let mut fallback: Option<u32> = None;
    for pid in candidates {
        let p_userns = fs::read_link(format!("/proc/{pid}/ns/user")).ok();
        let comm = fs::read_to_string(format!("/proc/{pid}/comm")).unwrap_or_default();
        let name = comm.trim();
        let is_init_daemon =
            runner_u1.is_some() && runner_userns != runner_u1 && p_userns == runner_u1;
        if p_userns.is_none()
            || p_userns == host_userns
            || is_init_daemon
            || matches!(
                name,
                "bwrap"
                    | "sb-executor"
                    | "sing-box"
                    | "xwayland-satell"
                    | ".xwayland-satel"
                    | "Xwayland"
                    | "rust-bridge"
            )
        {
            continue;
        }
        let p_mntns = fs::read_link(format!("/proc/{pid}/ns/mnt")).ok();
        if p_mntns.is_some() && p_mntns != runner_mntns {
            return pid;
        }
        if fallback.is_none() {
            fallback = Some(pid);
        }
    }
    fallback.unwrap_or(ctx.runner_pid)
}

fn build_spawn_env(
    ctx: &PortalContext,
    req: &PortalSpawnReq,
    eff_pid: u32,
) -> Vec<(String, String)> {
    let mut map = BTreeMap::new();
    let is_sandbox = (req.flags & FLATPAK_SPAWN_SANDBOX) != 0;
    if (req.flags & FLATPAK_SPAWN_CLEAR_ENV) == 0
        && let Ok(bytes) = fs::read(format!("/proc/{eff_pid}/environ"))
    {
        for entry in bytes.split(|&b| b == 0) {
            if let Ok(s) = std::str::from_utf8(entry)
                && let Some((k, v)) = s.split_once('=')
            {
                if k == "LD_PRELOAD" {
                    continue;
                }
                if is_sandbox {
                    let allow_disp = (req.sandbox_flags & FLATPAK_SANDBOX_SHARE_DISPLAY) != 0;
                    let allow_snd = (req.sandbox_flags & FLATPAK_SANDBOX_SHARE_SOUND) != 0;
                    let allow_dbus = (req.sandbox_flags & FLATPAK_SANDBOX_ALLOW_DBUS) != 0;
                    if (!allow_disp && (k == "DISPLAY" || k == "WAYLAND_DISPLAY"))
                        || (!allow_snd && (k == "PULSE_SERVER" || k == "PULSE_COOKIE"))
                        || (!allow_dbus && k == "DBUS_SESSION_BUS_ADDRESS")
                    {
                        continue;
                    }
                }
                map.insert(k.to_string(), v.to_string());
            }
        }
    }
    for key in &req.unset_env {
        map.remove(key);
    }
    for entry in &req.envs {
        if let Some((k, v)) = entry.split_once('=') {
            map.insert(k.to_string(), v.to_string());
        }
    }
    map.insert("SB_SANDBOX".into(), ctx.cfg.app_id.clone());
    map.into_iter().collect()
}

fn alloc_high_fd(raw: RawFd, high_next: &mut i32, remaps: &mut Vec<(RawFd, i32)>) -> String {
    let target = *high_next;
    *high_next += 1;
    remaps.push((raw, target));
    target.to_string()
}

fn setup_usr_fd_mounts(
    cmd: &mut Command,
    ctx: &PortalContext,
    usr_fd: RawFd,
    no_network: bool,
    owned: &mut Vec<OwnedFd>,
    remaps: &mut Vec<(RawFd, i32)>,
    high_next: &mut i32,
) {
    let usr_proc = format!("/proc/self/fd/{usr_fd}");
    let usr_arg = alloc_high_fd(usr_fd, high_next, remaps);
    cmd.arg("--ro-bind-fd").arg(usr_arg).arg("/usr");

    for sub in ["bin", "lib", "lib32", "lib64", "sbin"] {
        if Path::new(&format!("{usr_proc}/{sub}")).exists() {
            cmd.arg("--symlink")
                .arg(format!("usr/{sub}"))
                .arg(format!("/{sub}"));
        }
    }

    let skip = [
        "passwd",
        "group",
        "machine-id",
        "resolv.conf",
        "host.conf",
        "hosts",
        "gai.conf",
        "localtime",
        "timezone",
        "pkcs11",
    ];
    let etc_dir = format!("{usr_proc}/etc");
    if let Ok(entries) = fs::read_dir(&etc_dir) {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let name_str = name.to_string_lossy();
            if skip.contains(&name_str.as_ref()) {
                continue;
            }
            let p = entry.path();
            let dest = format!("/etc/{name_str}");
            if let Ok(target) = fs::read_link(&p) {
                cmd.arg("--symlink").arg(target).arg(&dest);
            } else if let Ok(c_p) = CString::new(p.as_os_str().as_bytes()) {
                let raw = unsafe { open(c_p.as_ptr(), O_PATH | O_NOFOLLOW | O_CLOEXEC) };
                if raw >= 0 {
                    let arg = alloc_high_fd(raw, high_next, remaps);
                    owned.push(unsafe { OwnedFd::from_raw_fd(raw) });
                    cmd.arg("--ro-bind-fd").arg(arg).arg(&dest);
                }
            }
        }
    }
    let has_usr_os_release = Path::new(&format!("{usr_proc}/etc/os-release")).exists()
        || Path::new(&format!("{usr_proc}/lib/os-release")).exists();
    for sys_etc in &ctx.cfg.portal_etc_paths {
        if sys_etc == "/etc/os-release" && has_usr_os_release {
            continue;
        }
        if sys_etc == "/etc/resolv.conf" {
            if no_network || ctx.cfg.network == "off" {
                continue;
            }
            if ctx.cfg.network == "sandboxed" {
                let r = ctx.paths.runtime.join("resolv.conf");
                if r.exists() {
                    cmd.arg("--ro-bind").arg(&r).arg("/etc/resolv.conf");
                    continue;
                }
            }
        }
        if Path::new(sys_etc).exists() {
            cmd.arg("--ro-bind-try").arg(sys_etc).arg(sys_etc);
        }
    }
    for sys_ro in ctx
        .cfg
        .ro_system_paths
        .iter()
        .filter(|p| {
            *p == "/etc/profiles" || (*p != "/bin" && *p != "/usr/bin" && !p.starts_with("/etc"))
        })
        .chain(
            ctx.cfg
                .gpu_ro_paths
                .iter()
                .filter(|p| !p.starts_with("/sys/")),
        )
    {
        if Path::new(sys_ro).exists() {
            cmd.arg("--ro-bind-try").arg(sys_ro).arg(sys_ro);
        }
    }
}

fn add_portal_isolated_sandbox_binds(
    cmd: &mut Command,
    ctx: &PortalContext,
    req: &PortalSpawnReq,
    home: &str,
    runtime: &str,
) {
    cmd.arg("--dir").arg(home);
    cmd.arg("--dir").arg(runtime);
    cmd.arg("--tmpfs").arg("/tmp");
    if (req.sandbox_flags & FLATPAK_SANDBOX_SHARE_SHM) != 0 {
        if ctx.cfg.shm_mode == "passthrough" {
            cmd.arg("--bind-try").arg("/dev/shm").arg("/dev/shm");
        } else {
            let shm_dir = ctx.paths.runtime.join("shm");
            cmd.arg("--bind-try").arg(&shm_dir).arg("/dev/shm");
        }
    }
    if (req.sandbox_flags & FLATPAK_SANDBOX_SHARE_DISPLAY) != 0 {
        if ctx.cfg.wayland_mode == "sandboxed" {
            let wd = env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "wayland-0".into());
            let wf = ctx.paths.runtime.join("wayland-secure");
            cmd.arg("--ro-bind-try")
                .arg(&wf)
                .arg(format!("{runtime}/{wd}"));
        } else if ctx.cfg.wayland_mode == "passthrough" {
            let wd = env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "wayland-0".into());
            let ws = format!("{runtime}/{wd}");
            cmd.arg("--ro-bind-try").arg(&ws).arg(&ws);
        }
        if ctx.cfg.x11_mode == "passthrough" {
            cmd.arg("--ro-bind-try")
                .arg("/tmp/.X11-unix")
                .arg("/tmp/.X11-unix");
        } else if ctx.cfg.x11_mode == "sandboxed" {
            let x11_dir = ctx.paths.runtime.join("tmp/.X11-unix");
            if x11_dir.exists() {
                cmd.arg("--ro-bind-try").arg(&x11_dir).arg("/tmp/.X11-unix");
            }
        }
    }
    if (req.sandbox_flags & FLATPAK_SANDBOX_SHARE_SOUND) != 0 {
        add_audio_display_binds(cmd, &ctx.cfg, runtime, &ctx.paths.runtime);
    }
    if (req.sandbox_flags & FLATPAK_SANDBOX_SHARE_GPU) != 0
        && (ctx.cfg.subsystems & SUBSYS_GPU) != 0
    {
        add_gpu_binds(cmd, &ctx.cfg);
    }
    if (req.sandbox_flags & FLATPAK_SANDBOX_ALLOW_DBUS) != 0 {
        add_session_dbus_binds(cmd, &ctx.cfg, runtime, &ctx.paths.runtime, false);
    }
    if (req.sandbox_flags & FLATPAK_SANDBOX_SHARE_INPUT) != 0
        && (ctx.cfg.subsystems & SUBSYS_GAMEPAD) != 0
    {
        add_gamepad_binds(cmd, &ctx.cfg);
    }
}

fn add_portal_sandbox_binds(cmd: &mut Command, ctx: &PortalContext, req: &PortalSpawnReq) {
    let home = env::var("HOME").unwrap_or_else(|_| "/home/user".into());
    let runtime = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/run/user/1000".into());
    if (req.flags & FLATPAK_SPAWN_SANDBOX) != 0 {
        add_portal_isolated_sandbox_binds(cmd, ctx, req, &home, &runtime);
        return;
    }

    cmd.arg("--bind-try").arg(&ctx.paths.home).arg(&home);
    cmd.arg("--bind-try").arg(&ctx.paths.runtime).arg(&runtime);
    if req.usr_fd.is_some() {
        cmd.arg("--tmpfs")
            .arg(format!("{runtime}/pressure-vessel"))
            .arg("--dir")
            .arg(format!("{runtime}/pressure-vessel/ldso"));
        let host_ldso = ctx.paths.runtime.join("pressure-vessel/ldso");
        for name in ["runtime-ld.so.conf", "runtime-ld.so.cache"] {
            if let Ok(target) = fs::read_link(host_ldso.join(name)) {
                cmd.arg("--symlink")
                    .arg(target)
                    .arg(format!("{runtime}/pressure-vessel/ldso/{name}"));
            }
        }
    }
    let xdg_config = env::var("XDG_CONFIG_HOME").unwrap_or_else(|_| format!("{home}/.config"));
    let xdg_data = env::var("XDG_DATA_HOME").unwrap_or_else(|_| format!("{home}/.local/share"));
    add_user_theme_binds(cmd, &ctx.cfg, &home, &xdg_config, &xdg_data);
    add_custom_bind_flags(cmd, &ctx.cfg, req.usr_fd.is_some(), false);
    add_shared_runtime_binds(cmd, &ctx.cfg, &ctx.paths.runtime);
    add_sesatt_doc_mime_binds(cmd, &ctx.cfg, &runtime, &xdg_config);
    add_subsystem_binds(cmd, &ctx.cfg, &runtime, &ctx.paths.runtime);
    add_session_and_system_dbus_binds(cmd, &ctx.cfg, &runtime, &ctx.paths.runtime, false);
    for arg in &ctx.cfg.bwrap_extra_args {
        cmd.arg(arg);
    }
}

fn add_portal_exposed_items(
    cmd: &mut Command,
    ctx: &PortalContext,
    req: &PortalSpawnReq,
    owned: &mut Vec<OwnedFd>,
    remaps: &mut Vec<(RawFd, i32)>,
    high_next: &mut i32,
) -> Result<(), String> {
    let base_sandbox_dir = ctx
        .paths
        .home
        .parent()
        .unwrap_or(&ctx.paths.runtime)
        .join("sandbox");

    for (rel, rw) in req
        .sandbox_expose
        .iter()
        .map(|s| (s, true))
        .chain(req.sandbox_expose_ro.iter().map(|s| (s, false)))
    {
        if rel.is_empty() || rel.contains('/') || rel.contains("..") {
            return Err(format!("invalid sandbox-expose item '{rel}'"));
        }
        let host_item = base_sandbox_dir.join(rel);
        if host_item.exists() {
            let flag = if rw { "--bind" } else { "--ro-bind" };
            cmd.arg(flag).arg(&host_item).arg(&host_item);
        }
    }

    for (fd, rw) in req
        .expose_rw_fds
        .iter()
        .map(|f| (f.as_raw_fd(), true))
        .chain(req.expose_ro_fds.iter().map(|f| (f.as_raw_fd(), false)))
    {
        let Some((host_fd, dest)) = resolve_sandbox_fd(fd, ctx) else {
            continue;
        };
        if req.usr_fd.is_none() && (dest == "/nix/store" || dest.starts_with("/nix/store/")) {
            continue;
        }
        let arg = alloc_high_fd(host_fd.as_raw_fd(), high_next, remaps);
        owned.push(host_fd);
        let flag = if rw { "--bind-fd" } else { "--ro-bind-fd" };
        cmd.arg(flag).arg(arg).arg(dest);
    }
    Ok(())
}

fn make_seccomp_memfd(bpf: &[u8]) -> Option<OwnedFd> {
    let raw = unsafe { memfd_create(c"sb-seccomp".as_ptr(), MFD_CLOEXEC) };
    if raw < 0 {
        return None;
    }
    let mut file = unsafe { fs::File::from_raw_fd(raw) };
    if file.write_all(bpf).is_err() {
        return None;
    }
    let fd = file.into_raw_fd();
    unsafe { lseek(fd, 0, 0) };
    Some(unsafe { OwnedFd::from_raw_fd(fd) })
}

fn open_ro_cloexec(path: &str) -> Option<OwnedFd> {
    let c_p = CString::new(path).ok()?;
    let fd = unsafe { open(c_p.as_ptr(), O_RDONLY | O_CLOEXEC) };
    if fd >= 0 {
        Some(unsafe { OwnedFd::from_raw_fd(fd) })
    } else {
        None
    }
}

struct PortalBwrapSetup {
    cmd: Command,
    owned: Vec<OwnedFd>,
    remaps: Vec<(RawFd, i32)>,
    info_r: OwnedFd,
    u1_raw: i32,
    netns_raw: i32,
    ipcns_raw: i32,
    high_next: i32,
}

fn add_portal_ns_args(
    cmd: &mut Command,
    ctx: &PortalContext,
    req: &PortalSpawnReq,
    eff_pid: u32,
    owned: &mut Vec<OwnedFd>,
    remaps: &mut Vec<(RawFd, i32)>,
    high_next: &mut i32,
) -> (i32, i32, i32) {
    let is_sandbox = (req.flags & FLATPAK_SPAWN_SANDBOX) != 0;
    let u1_path = format!("/proc/{}/root/run/.userns", ctx.runner_pid);
    let u2_path = format!("/proc/{eff_pid}/ns/user");
    let pidns_path = format!("/proc/{eff_pid}/ns/pid");
    let netns_path = format!("/proc/{eff_pid}/ns/net");
    let ipcns_path = format!("/proc/{}/ns/ipc", ctx.runner_pid);

    let host_netns = fs::read_link("/proc/self/ns/net").ok();
    let eff_netns = fs::read_link(&netns_path).ok();
    let share_custom_net = (req.flags & FLATPAK_SPAWN_NO_NETWORK) == 0
        && eff_netns.is_some()
        && eff_netns != host_netns;

    let host_ipcns = fs::read_link("/proc/self/ns/ipc").ok();
    let runner_ipcns = fs::read_link(&ipcns_path).ok();
    let join_sandbox_ipc = !is_sandbox
        && (ctx.cfg.flags & CFG_SHARE_IPC) == 0
        && runner_ipcns.is_some()
        && runner_ipcns != host_ipcns;

    if (ctx.cfg.flags & CFG_VERBOSE) != 0 {
        eprintln!(
            "[sb-run] portal eff_pid={eff_pid} caller_pid={} share_custom_net={share_custom_net} join_sandbox_ipc={join_sandbox_ipc} u1_exists={}",
            req.caller_pid,
            Path::new(&u1_path).exists()
        );
    }

    let mut preexec_u1 = -1;
    let mut preexec_net = -1;
    let mut preexec_ipc = -1;

    if (share_custom_net || join_sandbox_ipc)
        && let Some(u1) = open_ro_cloexec(&u1_path)
    {
        preexec_u1 = u1.as_raw_fd();
        let u1_id = fd_dev_ino(preexec_u1);
        owned.push(u1);
        if share_custom_net && let Some(nns) = open_ro_cloexec(&netns_path) {
            preexec_net = nns.as_raw_fd();
            owned.push(nns);
        }
        if join_sandbox_ipc && let Some(ipc) = open_ro_cloexec(&ipcns_path) {
            preexec_ipc = ipc.as_raw_fd();
            owned.push(ipc);
        }
        if let Some(u2) = open_ro_cloexec(&u2_path)
            && fd_dev_ino(u2.as_raw_fd()) != u1_id
        {
            cmd.arg("--userns2")
                .arg(alloc_high_fd(u2.as_raw_fd(), high_next, remaps));
            owned.push(u2);
            if ctx.parent_userns_disabled {
                cmd.arg("--assert-userns-disabled");
            }
        } else if !ctx.parent_userns_disabled {
            cmd.arg("--unshare-user")
                .arg("--uid")
                .arg(libc_getuid().to_string())
                .arg("--gid")
                .arg(libc_getgid().to_string());
        }
    } else if let Some(u1) = open_ro_cloexec(&u1_path) {
        let u1_id = fd_dev_ino(u1.as_raw_fd());
        cmd.arg("--userns")
            .arg(alloc_high_fd(u1.as_raw_fd(), high_next, remaps));
        owned.push(u1);
        if let Some(u2) = open_ro_cloexec(&u2_path)
            && fd_dev_ino(u2.as_raw_fd()) != u1_id
        {
            cmd.arg("--userns2")
                .arg(alloc_high_fd(u2.as_raw_fd(), high_next, remaps));
            owned.push(u2);
        }
        if ctx.parent_userns_disabled {
            cmd.arg("--assert-userns-disabled");
        }
    }

    if (req.flags & FLATPAK_SPAWN_NO_NETWORK) != 0 {
        cmd.arg("--unshare-net");
    }
    if is_sandbox && (ctx.cfg.flags & CFG_SHARE_IPC) == 0 {
        cmd.arg("--unshare-ipc");
    }

    let host_pidns = fs::read_link("/proc/self/ns/pid").ok();
    let eff_pidns = fs::read_link(&pidns_path).ok();
    if eff_pidns.is_some()
        && eff_pidns != host_pidns
        && let Some(pns) = open_ro_cloexec(&pidns_path)
    {
        cmd.arg("--pidns")
            .arg(alloc_high_fd(pns.as_raw_fd(), high_next, remaps));
        owned.push(pns);
    }
    if (req.flags & FLATPAK_SPAWN_EXPOSE_PIDS) != 0 || is_sandbox {
        cmd.arg("--unshare-pid");
    }
    cmd.arg("--unshare-uts")
        .arg("--unshare-cgroup-try")
        .arg("--proc")
        .arg("/proc")
        .arg("--dev")
        .arg("/dev");

    (preexec_u1, preexec_net, preexec_ipc)
}

fn add_parent_usr_mounts(
    cmd: &mut Command,
    eff_pid: u32,
    owned: &mut Vec<OwnedFd>,
    remaps: &mut Vec<(RawFd, i32)>,
    high_next: &mut i32,
) {
    let mut best_root: Option<String> = None;
    let mut glibc_etcs: Vec<String> = Vec::new();
    if let Ok(mi) = fs::read_to_string(format!("/proc/{eff_pid}/mountinfo")) {
        for line in mi.lines() {
            let fields: Vec<&str> = line.split(' ').collect();
            if fields.len() < 5 {
                continue;
            }
            if fields[4] == "/usr" {
                best_root = Some(fields[3].to_string());
            } else if fields[3] == "/"
                && fields[4].starts_with("/nix/store/")
                && fields[4].ends_with("/etc")
                && fields[4].contains("-glibc-")
                && !glibc_etcs.iter().any(|p| p == fields[4])
            {
                glibc_etcs.push(fields[4].to_string());
            }
        }
    }

    for g_etc in glibc_etcs {
        cmd.arg("--tmpfs")
            .arg(&g_etc)
            .arg("--symlink")
            .arg("/etc/ld.so.conf")
            .arg(format!("{g_etc}/ld.so.conf"))
            .arg("--symlink")
            .arg("/etc/ld.so.cache")
            .arg(format!("{g_etc}/ld.so.cache"));
        let rpc = format!("{g_etc}/rpc");
        if Path::new(&rpc).exists() {
            cmd.arg("--ro-bind").arg(&rpc).arg(&rpc);
        }
        cmd.arg("--remount-ro").arg(&g_etc);
    }

    let Ok(parent_usr_raw) = open_ro_path(&format!("/proc/{eff_pid}/root/usr")) else {
        return;
    };
    let expected = fd_dev_ino(parent_usr_raw.as_raw_fd());

    let mut candidates = Vec::new();
    if let Some(root) = best_root {
        if root.starts_with("/store/") {
            candidates.push(format!("/nix{root}"));
        } else if root == "/" {
            candidates.push("/usr".into());
        } else {
            candidates.push(root);
        }
    }
    candidates.push("/usr".into());

    let host_usr = expected.and_then(|exp| {
        candidates
            .into_iter()
            .find_map(|c| open_matching_inode(&c, exp))
    });
    let Some(host_fd) = host_usr else {
        return;
    };
    let proc_path = format!("/proc/self/fd/{}", host_fd.as_raw_fd());
    let arg = alloc_high_fd(host_fd.as_raw_fd(), high_next, remaps);
    cmd.arg("--ro-bind-fd").arg(arg).arg("/run/parent/usr");
    for sub in ["bin", "lib", "lib32", "lib64", "sbin", "etc"] {
        if Path::new(&format!("{proc_path}/{sub}")).exists() {
            cmd.arg("--symlink")
                .arg(format!("usr/{sub}"))
                .arg(format!("/run/parent/{sub}"));
        }
    }
    owned.push(host_fd);
}

fn open_ro_path(path: &str) -> Result<OwnedFd, std::io::Error> {
    let c_p = CString::new(path).map_err(|_| std::io::Error::from_raw_os_error(22))?;
    let raw = unsafe { open(c_p.as_ptr(), O_PATH | O_CLOEXEC) };
    if raw >= 0 {
        Ok(unsafe { OwnedFd::from_raw_fd(raw) })
    } else {
        Err(std::io::Error::last_os_error())
    }
}

fn add_portal_rootfs_and_metadata(
    cmd: &mut Command,
    ctx: &PortalContext,
    req: &PortalSpawnReq,
    owned: &mut Vec<OwnedFd>,
    remaps: &mut Vec<(RawFd, i32)>,
    high_next: &mut i32,
) -> Result<(), String> {
    let portal_net = if (req.flags & FLATPAK_SPAWN_NO_NETWORK) != 0 {
        "off"
    } else {
        ctx.cfg.network.as_str()
    };
    let resolv = (portal_net == "sandboxed").then(|| ctx.paths.runtime.join("resolv.conf"));
    if let Some(ref ufd) = req.usr_fd {
        let (host_ufd, _) = resolve_sandbox_fd(ufd.as_raw_fd(), ctx)
            .ok_or_else(|| "unable to resolve usr-fd on host".to_string())?;
        let raw = host_ufd.as_raw_fd();
        owned.push(host_ufd);
        setup_usr_fd_mounts(
            cmd,
            ctx,
            raw,
            (req.flags & FLATPAK_SPAWN_NO_NETWORK) != 0,
            owned,
            remaps,
            high_next,
        );
        add_parent_usr_mounts(cmd, ctx.runner_pid, owned, remaps, high_next);
    } else {
        let fhs_etc = ctx.paths.runtime.join("fhs-etc");
        add_system_and_fhs_binds(
            cmd,
            &ctx.cfg,
            None,
            Some(&fhs_etc),
            portal_net,
            resolv.as_deref(),
        );
        if ctx.cfg.fhs_env.is_none() {
            if let Some(ref r) = resolv
                && r.exists()
            {
                cmd.arg("--ro-bind").arg(r).arg("/etc/resolv.conf");
            } else if portal_net == "singbox" && Path::new("/etc/resolv.conf").exists() {
                cmd.arg("--ro-bind-try")
                    .arg("/etc/resolv.conf")
                    .arg("/etc/resolv.conf");
            }
        }
    }
    if let Some(ref afd) = req.app_fd {
        let (host_afd, _) = resolve_sandbox_fd(afd.as_raw_fd(), ctx)
            .ok_or_else(|| "unable to resolve app-fd on host".to_string())?;
        cmd.arg("--ro-bind-fd")
            .arg(alloc_high_fd(host_afd.as_raw_fd(), high_next, remaps))
            .arg("/app");
        owned.push(host_afd);
    } else if (req.flags & FLATPAK_SPAWN_EMPTY_APP) != 0 {
        cmd.arg("--dir").arg("/app");
    }

    add_portal_sandbox_binds(cmd, ctx, req);
    cmd.arg("--ro-bind")
        .arg(&ctx.sandbox_marker_path)
        .arg("/.sb-sandbox");
    if (ctx.cfg.flags & CFG_FLATPAK_INFO) != 0 {
        cmd.arg("--ro-bind")
            .arg(&ctx.flatpak_info_path)
            .arg("/.flatpak-info");
    }
    if (ctx.cfg.flags & (CFG_FLATPAK_INFO | CFG_FLATPAK_PORTAL)) != 0 {
        let run_host = ctx.paths.runtime.join("run-host");
        if run_host.is_dir() {
            cmd.arg("--ro-bind").arg(&run_host).arg("/run/host");
        }
    }
    add_portal_exposed_items(cmd, ctx, req, owned, remaps, high_next)
}

fn prepare_portal_bwrap(
    ctx: &PortalContext,
    req: &PortalSpawnReq,
    eff_pid: u32,
) -> Result<PortalBwrapSetup, String> {
    let mut info_fds = [0i32; 2];
    if unsafe { pipe(info_fds.as_mut_ptr()) } != 0 {
        return Err("failed to create info pipe".into());
    }
    let info_r = unsafe { OwnedFd::from_raw_fd(info_fds[0]) };
    let info_w = unsafe { OwnedFd::from_raw_fd(info_fds[1]) };

    let mut owned: Vec<OwnedFd> = Vec::new();
    let mut remaps: Vec<(RawFd, i32)> = Vec::new();
    let max_dest = req.fds.iter().map(|(d, _)| *d).max().unwrap_or(2);
    let max_req_src = req
        .fds
        .iter()
        .map(|(_, f)| f.as_raw_fd())
        .max()
        .unwrap_or(2);
    let mut high_next = max_dest.max(max_req_src).max(63) + 64;

    let mut cmd = Command::new(&ctx.cfg.bwrap_bin);
    cmd.stdin(Stdio::null());
    if (ctx.cfg.flags & CFG_VERBOSE) == 0 {
        cmd.stdout(Stdio::null()).stderr(Stdio::null());
    }
    cmd.arg("--die-with-parent");
    cmd.arg("--info-fd").arg(alloc_high_fd(
        info_w.as_raw_fd(),
        &mut high_next,
        &mut remaps,
    ));
    owned.push(info_w);

    let (u1_raw, netns_raw, ipcns_raw) = add_portal_ns_args(
        &mut cmd,
        ctx,
        req,
        eff_pid,
        &mut owned,
        &mut remaps,
        &mut high_next,
    );
    add_portal_rootfs_and_metadata(&mut cmd, ctx, req, &mut owned, &mut remaps, &mut high_next)?;

    cmd.arg("--clearenv");
    for (k, v) in build_spawn_env(ctx, req, eff_pid) {
        cmd.arg("--setenv").arg(k).arg(v);
    }
    if !req.cwd.is_empty() {
        cmd.arg("--chdir").arg(&req.cwd);
    }
    if req.argv.is_empty() {
        return Err("portal spawn requires non-empty argv".into());
    }
    if let (Some(bpf), Some(sock_path)) = (&ctx.seccomp_bpf, &ctx.seccomp_sock_path) {
        let mfd =
            make_seccomp_memfd(bpf).ok_or_else(|| "failed to create seccomp memfd".to_string())?;
        let stream = UnixStream::connect(sock_path)
            .map_err(|e| format!("failed to connect seccomp socket: {e}"))?;
        let stream_fd = OwnedFd::from(stream);
        cmd.arg("--ro-bind")
            .arg(&ctx.cfg.executor_path)
            .arg("/.sb-executor");
        let bpf_arg = alloc_high_fd(mfd.as_raw_fd(), &mut high_next, &mut remaps);
        let sock_arg = alloc_high_fd(stream_fd.as_raw_fd(), &mut high_next, &mut remaps);
        owned.push(mfd);
        owned.push(stream_fd);
        cmd.arg("--")
            .arg("/.sb-executor")
            .arg("--seccomp-exec")
            .arg(bpf_arg)
            .arg(sock_arg)
            .arg("--");
    } else {
        if let Some(ref bpf) = ctx.seccomp_bpf
            && let Some(mfd) = make_seccomp_memfd(bpf)
        {
            cmd.arg("--seccomp")
                .arg(alloc_high_fd(mfd.as_raw_fd(), &mut high_next, &mut remaps));
            owned.push(mfd);
        }
        cmd.arg("--");
    }

    for a in &req.argv {
        cmd.arg(a);
    }

    Ok(PortalBwrapSetup {
        cmd,
        owned,
        remaps,
        info_r,
        u1_raw,
        netns_raw,
        ipcns_raw,
        high_next,
    })
}

fn safe_dup2_pairs(pairs: &[(i32, i32)], scratch_start: i32) -> std::io::Result<i32> {
    let mut work: Vec<(i32, i32)> = pairs.to_vec();
    let mut scratch = scratch_start;
    for idx in 0..work.len() {
        let to_fd = work[idx].0;
        for item in work.iter_mut().skip(idx + 1) {
            if item.1 == to_fd {
                let tmp = unsafe { fcntl(item.1, F_DUPFD_CLOEXEC, scratch) };
                if tmp < 0 {
                    return Err(std::io::Error::last_os_error());
                }
                scratch = tmp + 1;
                item.1 = tmp;
            }
        }
    }
    for &(to_fd, from_fd) in &work {
        if from_fd != to_fd && unsafe { libc_dup2(from_fd, to_fd) } < 0 {
            return Err(std::io::Error::last_os_error());
        }
        unsafe { fcntl(to_fd, F_SETFD, 0) };
    }
    Ok(scratch)
}

fn spawn_portal_bwrap(
    ctx: &PortalContext,
    req: PortalSpawnReq,
) -> Result<(u32, Child, i32, u32), String> {
    verify_caller_sandbox(req.caller_pid, &ctx.cfg.app_id)?;
    let eff_pid = resolve_effective_caller_pid(ctx, req.caller_pid);
    let caller_depth = read_proc_nspid(eff_pid).len();
    let mut setup = prepare_portal_bwrap(ctx, &req, eff_pid)?;

    let child_fd_pairs: Vec<(i32, i32)> =
        req.fds.iter().map(|(d, f)| (*d, f.as_raw_fd())).collect();
    let remaps: Vec<(i32, i32)> = setup.remaps.drain(..).map(|(s, d)| (d, s)).collect();
    let max_remap = remaps.iter().map(|&(d, s)| d.max(s)).max().unwrap_or(0);
    let scratch_base = setup.high_next.max(max_remap) + 64;
    let u1_raw = setup.u1_raw;
    let netns_raw = setup.netns_raw;
    let ipcns_raw = setup.ipcns_raw;
    let is_sandbox = (req.flags & FLATPAK_SPAWN_SANDBOX) != 0;
    let use_landlock = (ctx.cfg.flags & CFG_LANDLOCK) != 0
        && (is_sandbox
            || ((ctx.cfg.flags & CFG_SHARE_PID) != 0
                && (req.flags & FLATPAK_SPAWN_EXPOSE_PIDS) == 0));

    unsafe {
        setup.cmd.pre_exec(move || {
            if u1_raw >= 0 && setns(u1_raw, CLONE_NEWUSER) != 0 {
                return Err(std::io::Error::last_os_error());
            }
            if netns_raw >= 0 && setns(netns_raw, CLONE_NEWNET) != 0 {
                return Err(std::io::Error::last_os_error());
            }
            if ipcns_raw >= 0 && setns(ipcns_raw, CLONE_NEWIPC) != 0 {
                return Err(std::io::Error::last_os_error());
            }
            let next_scratch = safe_dup2_pairs(&remaps, scratch_base)?;
            let _ = safe_dup2_pairs(&child_fd_pairs, next_scratch)?;
            if use_landlock {
                apply_landlock_signal_scoping();
            }
            prctl(1, 15, 0, 0, 0);
            Ok(())
        });
    }

    let child = setup
        .cmd
        .spawn()
        .map_err(|e| format!("failed to spawn portal bwrap: {e}"))?;
    drop(setup.owned);
    drop(req.usr_fd);
    drop(req.app_fd);
    drop(req.expose_rw_fds);
    drop(req.expose_ro_fds);
    drop(req.fds);

    let data = read_info_fd_data(setup.info_r.into_raw_fd());
    let Some(child_pid) = parse_child_pid_from_info(&data) else {
        let mut child = child;
        let _ = child.kill();
        let _ = child.wait();
        return Err("portal bwrap failed before reporting child-pid".into());
    };
    if let Ok(cg) = env::var("MY_CGROUP") {
        let _ = fs::write(
            format!("{cg}/inside/cgroup.procs"),
            format!("{child_pid}\n"),
        );
    }
    let relpid = if (req.flags & FLATPAK_SPAWN_NOTIFY_START) != 0 {
        resolve_relpid(child_pid, caller_depth)
    } else {
        0
    };
    let pidfd = pidfd_open(i32::try_from(child.id()).unwrap_or(0)).unwrap_or(-1);

    Ok((child_pid, child, pidfd, relpid))
}

fn write_portal_event(stream: &mut UnixStream, kind: u8, pid: u32, val: u32) {
    let mut buf = [0u8; 9];
    buf[0] = kind;
    buf[1..5].copy_from_slice(&pid.to_le_bytes());
    buf[5..9].copy_from_slice(&val.to_le_bytes());
    let _ = stream.write_all(&buf);
    let _ = stream.flush();
}

fn send_portal_err(stream: &mut UnixStream, msg: &str) {
    let bytes = msg.as_bytes();
    let mut err_buf = Vec::with_capacity(5 + bytes.len());
    err_buf.push(0);
    err_buf.extend_from_slice(&u32::try_from(bytes.len()).unwrap_or(0).to_le_bytes());
    err_buf.extend_from_slice(bytes);
    let _ = stream.write_all(&err_buf);
}

fn handle_portal_connection(
    mut stream: UnixStream,
    ctx: &PortalContext,
    epoll: &Epoll,
    children: &mut HashMap<u32, PortalChild>,
    pidfd_to_pid: &mut HashMap<i32, u32>,
    client_to_pid: &mut HashMap<i32, u32>,
) {
    let Ok((body, fds)) = recv_portal_packet(&mut stream) else {
        return;
    };
    if body.is_empty() {
        return;
    }
    match body[0] {
        PORTAL_OP_SPAWN => match parse_spawn_request(&body[1..], fds) {
            Ok(req) => {
                let notify_start = (req.flags & FLATPAK_SPAWN_NOTIFY_START) != 0;
                let watch_bus = (req.flags & FLATPAK_SPAWN_WATCH_BUS) != 0;
                match spawn_portal_bwrap(ctx, req) {
                    Ok((pid, child, pidfd, relpid)) => {
                        let mut ack = [0u8; 5];
                        ack[0] = 1;
                        ack[1..5].copy_from_slice(&pid.to_le_bytes());
                        let _ = stream.write_all(&ack);
                        let _ = stream.flush();
                        if notify_start {
                            write_portal_event(&mut stream, PORTAL_EVT_STARTED, pid, relpid);
                        }
                        let cfd = stream.as_raw_fd();
                        if pidfd >= 0 && epoll.add(pidfd) {
                            pidfd_to_pid.insert(pidfd, pid);
                        }
                        if epoll.add(cfd) {
                            client_to_pid.insert(cfd, pid);
                        }
                        children.insert(
                            pid,
                            PortalChild {
                                pid,
                                child,
                                pidfd,
                                client_stream: stream,
                                watch_bus,
                            },
                        );
                    }
                    Err(msg) => send_portal_err(&mut stream, &msg),
                }
            }
            Err(msg) => send_portal_err(&mut stream, &msg),
        },
        PORTAL_OP_SIGNAL if body.len() >= 10 => {
            let pid = u32::from_le_bytes([body[1], body[2], body[3], body[4]]);
            let sig = u32::from_le_bytes([body[5], body[6], body[7], body[8]]);
            let to_pg = body[9] != 0;
            let res: i32 = if let (Some(pc), Ok(pid_i), Ok(sig_i)) =
                (children.get(&pid), i32::try_from(pid), i32::try_from(sig))
            {
                let _ = pc;
                let r = unsafe { kill(if to_pg { -pid_i } else { pid_i }, sig_i) };
                if r == 0 { 0 } else { -1 }
            } else {
                -1
            };
            let _ = stream.write_all(&res.to_le_bytes());
        }
        _ => {}
    }
}

fn remove_portal_child(
    pid: u32,
    epoll: &Epoll,
    children: &mut HashMap<u32, PortalChild>,
    pidfd_to_pid: &mut HashMap<i32, u32>,
    client_to_pid: &mut HashMap<i32, u32>,
    kill_it: bool,
) {
    let Some(mut pc) = children.remove(&pid) else {
        return;
    };
    let cfd = pc.client_stream.as_raw_fd();
    client_to_pid.remove(&cfd);
    epoll_del_only(epoll.0, cfd);
    if pc.pidfd >= 0 {
        pidfd_to_pid.remove(&pc.pidfd);
        epoll.del_and_close(pc.pidfd);
    }
    if kill_it {
        if let Ok(p_i) = i32::try_from(pc.pid) {
            unsafe { kill(-p_i, 9) };
        }
        let _ = pc.child.kill();
    }
    let wait_status = pc.child.wait().map_or(0, |s| s.into_raw().cast_unsigned());
    if !kill_it {
        write_portal_event(
            &mut pc.client_stream,
            PORTAL_EVT_EXITED,
            pc.pid,
            wait_status,
        );
    }
}

fn epoll_del_only(epfd: i32, fd: i32) {
    unsafe { epoll_ctl(epfd, EPOLL_CTL_DEL, fd, std::ptr::null_mut()) };
}

fn run_portal_loop(listener: &UnixListener, stop_raw: i32, ctx: &PortalContext) {
    let Some(epoll) = Epoll::new() else {
        return;
    };
    let listen_fd = listener.as_raw_fd();
    epoll.add(listen_fd);
    epoll.add(stop_raw);

    let mut children: HashMap<u32, PortalChild> = HashMap::new();
    let mut pidfd_to_pid: HashMap<i32, u32> = HashMap::new();
    let mut client_to_pid: HashMap<i32, u32> = HashMap::new();
    let mut events = [EpollEvent { events: 0, data: 0 }; 32];
    let mut stopping = false;

    while !stopping {
        let n = match epoll.wait(&mut events, -1) {
            Ok(n) => n,
            Err(4) => continue,
            Err(_) => break,
        };
        for ev in &events[..n] {
            let Ok(fd) = i32::try_from(ev.data) else {
                continue;
            };
            if fd == stop_raw {
                stopping = true;
                break;
            }
            if fd == listen_fd {
                while let Ok((s, _)) = listener.accept() {
                    handle_portal_connection(
                        s,
                        ctx,
                        &epoll,
                        &mut children,
                        &mut pidfd_to_pid,
                        &mut client_to_pid,
                    );
                }
                continue;
            }
            if let Some(&pid) = pidfd_to_pid.get(&fd) {
                remove_portal_child(
                    pid,
                    &epoll,
                    &mut children,
                    &mut pidfd_to_pid,
                    &mut client_to_pid,
                    false,
                );
                continue;
            }
            if let Some(&pid) = client_to_pid.get(&fd) {
                let mut byte = [0u8; 1];
                let should_kill = if let Some(pc) = children.get_mut(&pid) {
                    let r = unsafe { read(fd, byte.as_mut_ptr().cast(), 1) };
                    (r == 1 && byte[0] == PORTAL_OP_KILL) || (r <= 0 && pc.watch_bus)
                } else {
                    false
                };
                if should_kill {
                    remove_portal_child(
                        pid,
                        &epoll,
                        &mut children,
                        &mut pidfd_to_pid,
                        &mut client_to_pid,
                        true,
                    );
                } else {
                    client_to_pid.remove(&fd);
                    epoll_del_only(epoll.0, fd);
                }
            }
        }
    }

    let rem_pids: Vec<u32> = children.keys().copied().collect();
    for pid in rem_pids {
        remove_portal_child(
            pid,
            &epoll,
            &mut children,
            &mut pidfd_to_pid,
            &mut client_to_pid,
            true,
        );
    }
}

fn start_flatpak_portal(
    cfg: &SandboxConfig,
    paths: &SandboxPaths,
    runner_pid: u32,
    seccomp_bpf: Option<Vec<u8>>,
    has_seccomp_mon: bool,
) -> Option<FlatpakPortalHandle> {
    if (cfg.flags & CFG_FLATPAK_PORTAL) == 0 {
        return None;
    }
    let sock_path = paths.runtime.join("flatpak-portal.sock");
    let _ = fs::remove_file(&sock_path);
    let listener = UnixListener::bind(&sock_path)
        .unwrap_or_else(|e| fail_exit(&format!("failed to bind flatpak portal socket: {e}")));
    let _ = fs::set_permissions(&sock_path, fs::Permissions::from_mode(0o600));
    let _ = listener.set_nonblocking(true);

    let efd_raw = unsafe { eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK) };
    if efd_raw < 0 {
        fail_exit("failed to create portal stop eventfd");
    }
    let stop_efd = unsafe { OwnedFd::from_raw_fd(efd_raw) };
    let stop_raw = stop_efd.as_raw_fd();

    let ctx = PortalContext {
        cfg: cfg.clone(),
        paths: paths.clone(),
        runner_pid,
        seccomp_bpf,
        seccomp_sock_path: has_seccomp_mon.then(|| paths.runtime.join("seccomp.sock")),
        parent_userns_disabled: !seccomp_allows_userns(cfg) && cfg.network != "singbox",
        flatpak_info_path: paths.runtime.join("flatpak-info"),
        sandbox_marker_path: paths.runtime.join(".sb-sandbox"),
    };
    let handle = thread::spawn(move || run_portal_loop(&listener, stop_raw, &ctx));
    Some(FlatpakPortalHandle {
        stop_efd,
        thread: Some(handle),
    })
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

#[derive(Clone)]
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
    let sandbox_marker_path = sandbox_runtime.join(".sb-sandbox");
    let _ = fs::write(&sandbox_marker_path, format!("{}\n", cfg.app_id));

    if cfg.dbus_mode == "sandboxed" {
        let proxy_sock = sandbox_runtime.join("nixpak-bus");
        helpers.dbus_proxy =
            start_session_dbus_proxy(cfg, &proxy_sock, &flatpak_info_path, &sandbox_marker_path);
    }
    if (cfg.flags & CFG_SYSTEM_DBUS) != 0 {
        let sys_proxy_sock = sandbox_runtime.join("nixpak-system-bus");
        helpers.system_dbus_proxy = start_system_dbus_proxy(
            cfg,
            &sys_proxy_sock,
            &flatpak_info_path,
            &sandbox_marker_path,
        );
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
    if let Some(ref fhs) = cfg.fhs_env {
        let init_str = fhs.container_init.to_string_lossy().into_owned();
        for arg in &mut cfg.command {
            let matches_bwrap = fhs.bwrap_scripts.iter().any(|b| b == arg)
                || fs::canonicalize(&*arg).is_ok_and(|c| {
                    let cs = c.to_string_lossy();
                    fhs.bwrap_scripts.iter().any(|b| b == cs.as_ref())
                });
            if matches_bwrap {
                arg.clone_from(&init_str);
            }
        }
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

fn start_seccomp_monitor_if_needed(
    cfg: &SandboxConfig,
    paths: &SandboxPaths,
    table: Option<Arc<SyscallTable>>,
    policy: Option<Arc<SeccompPolicy>>,
) -> Option<SeccompMonitorHandle> {
    match (table, policy) {
        (Some(t), Some(p)) if p.needs_monitor() => {
            let log_path = paths
                .home
                .parent()
                .unwrap_or(&paths.runtime)
                .join("logs/seccomp.log");
            Some(start_seccomp_monitor(
                &paths.runtime,
                t,
                p,
                cfg.notify_send_bin.clone(),
                log_path,
                cfg.app_id.clone(),
            ))
        }
        _ => None,
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

    let mut seccomp_mon =
        start_seccomp_monitor_if_needed(&cfg, &paths, syscall_table, seccomp_policy);

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
    let mut flatpak_portal = start_flatpak_portal(
        &cfg,
        &paths,
        runner_pid,
        seccomp_bpf.clone(),
        seccomp_mon.is_some(),
    );

    let bridge_pids = if cfg.bridges.is_empty() {
        Vec::new()
    } else {
        setup_bridges(&cfg, &paths.runtime, &paths.ipc_sock)
    };

    if cfg.command.is_empty() {
        let status = child.wait().map_or(1, |s| s.code().unwrap_or(1));
        cleanup_session(
            &cfg,
            &paths,
            &bridge_pids,
            helpers,
            seccomp_mon.as_mut(),
            flatpak_portal.as_mut(),
        );
        exit(status);
    }

    if (cfg.flags & CFG_IS_CLI) != 0 {
        let migrator_thread =
            migrator_listener.map(|l| thread::spawn(move || migrate_first_process(Some(&l))));
        let exit_code =
            try_connect_running_sandbox(&paths.ipc_sock, &cfg, seccomp_bpf.as_deref()).unwrap_or(1);
        if let Some(h) = migrator_thread {
            let _ = h.join();
        }
        let _ = child.kill();
        let _ = child.wait();
        cleanup_session(
            &cfg,
            &paths,
            &bridge_pids,
            helpers,
            seccomp_mon.as_mut(),
            flatpak_portal.as_mut(),
        );
        exit(exit_code);
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
            portal: flatpak_portal,
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
    fn eventfd(initval: u32, flags: i32) -> i32;
    fn memfd_create(name: *const i8, flags: u32) -> i32;
    fn setns(fd: i32, nstype: i32) -> i32;
    #[link_name = "dup2"]
    fn libc_dup2(oldfd: i32, newfd: i32) -> i32;
    fn sigemptyset(set: *mut SigSet) -> i32;
    fn sigaddset(set: *mut SigSet, signum: i32) -> i32;
    fn sigprocmask(how: i32, set: *const SigSet, oldset: *mut SigSet) -> i32;
    fn signalfd(fd: i32, mask: *const SigSet, flags: i32) -> i32;
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
