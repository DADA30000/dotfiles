#![forbid(unsafe_code)]

use std::fs::{self, Permissions};
use std::io::{BufRead, BufReader, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;
use std::process::Command;
use std::thread;

const SOCKET_PATH: &str = "/run/hwcontrol.sock";
const FAN_MODE_PATH: &str = "/sys/devices/platform/aorus_laptop/fan_mode";

fn has_fan() -> bool {
    Path::new(FAN_MODE_PATH).exists()
}

fn set_fan_mode(mode: &str) -> Result<&'static str, &'static str> {
    match mode {
        "quiet" => fs::write(FAN_MODE_PATH, b"3\n").map(|_| "ok").map_err(|_| "write error"),
        "auto" => fs::write(FAN_MODE_PATH, b"0\n").map(|_| "ok").map_err(|_| "write error"),
        "max" => fs::write(FAN_MODE_PATH, b"5\n").map(|_| "ok").map_err(|_| "write error"),
        _ => Err("invalid fan mode"),
    }
}

fn get_fan_mode() -> &'static str {
    if let Ok(content) = fs::read_to_string(FAN_MODE_PATH) {
        match content.trim() {
            "5" => "max",
            "3" => "quiet",
            "0" => "auto",
            _ => "auto",
        }
    } else {
        "unknown"
    }
}

fn has_nv() -> bool {
    if let Ok(entries) = fs::read_dir("/sys/bus/pci/devices") {
        for entry in entries.flatten() {
            let vendor_path = entry.path().join("vendor");
            if let Ok(vendor) = fs::read_to_string(vendor_path) {
                if vendor.trim().eq_ignore_ascii_case("0x10de") {
                    return true;
                }
            }
        }
    }
    false
}

fn set_nv_blocked(block: bool) -> Result<&'static str, &'static str> {
    let mode = if block { 0o000 } else { 0o666 };
    let mut matched = false;
    if let Ok(entries) = fs::read_dir("/dev") {
        for entry in entries.flatten() {
            if let Ok(file_type) = entry.file_type() {
                if file_type.is_dir() {
                    continue;
                }
            }
            let name = entry.file_name();
            let name_str = name.to_string_lossy();
            if name_str.starts_with("nvidia") {
                let path = entry.path();
                let perms = Permissions::from_mode(mode);
                if fs::set_permissions(&path, perms).is_ok() {
                    matched = true;
                }
            }
        }
    }
    if matched {
        Ok("ok")
    } else {
        Err("no nvidia devices found")
    }
}

fn get_nv_status() -> &'static str {
    if let Ok(entries) = fs::read_dir("/dev") {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let name_str = name.to_string_lossy();
            if name_str.starts_with("nvidia") {
                if let Ok(metadata) = entry.metadata() {
                    if (metadata.permissions().mode() & 0o777) == 0 {
                        return "blocked";
                    }
                }
            }
        }
    }
    "unblocked"
}

fn has_smu() -> bool {
    Path::new("/sys/kernel/ryzen_smu_drv").exists() || Path::new("/sys/kernel/ryzen_smu").exists()
}

fn is_amd_cpu() -> bool {
    if let Ok(content) = fs::read_to_string("/proc/cpuinfo") {
        content.contains("AuthenticAMD")
    } else {
        false
    }
}

fn has_ryzen() -> bool {
    is_amd_cpu() && has_smu()
}

fn set_ryzen_max() -> Result<&'static str, &'static str> {
    let status = Command::new("ryzenadj")
        .args([
            "--stapm-limit=999999999999999999",
            "--fast-limit=999999999999999999",
            "--slow-limit=999999999999999999",
        ])
        .status();
    match status {
        Ok(s) if s.success() => Ok("ok"),
        _ => Err("ryzenadj execution failed"),
    }
}

fn get_ryzen_limits() -> String {
    let output = Command::new("ryzenadj").arg("-i").output();
    if let Ok(out) = output {
        if out.status.success() {
            let text = String::from_utf8_lossy(&out.stdout);
            let mut stapm = None;
            let mut fast = None;
            let mut slow = None;
            for line in text.lines() {
                if line.contains("STAPM LIMIT") {
                    let parts: Vec<&str> = line.split('|').map(|s| s.trim()).collect();
                    if parts.len() >= 3 {
                        stapm = parts[2].parse::<f64>().ok();
                    }
                } else if line.contains("PPT LIMIT FAST") {
                    let parts: Vec<&str> = line.split('|').map(|s| s.trim()).collect();
                    if parts.len() >= 3 {
                        fast = parts[2].parse::<f64>().ok();
                    }
                } else if line.contains("PPT LIMIT SLOW") {
                    let parts: Vec<&str> = line.split('|').map(|s| s.trim()).collect();
                    if parts.len() >= 3 {
                        slow = parts[2].parse::<f64>().ok();
                    }
                }
            }
            if let (Some(s), Some(f), Some(sl)) = (stapm, fast, slow) {
                return format!("{:.3} {:.3} {:.3}", s, f, sl);
            }
        }
    }
    "unknown".to_string()
}

fn handle_client(mut stream: UnixStream) {
    let mut reader = BufReader::new(match stream.try_clone() {
        Ok(s) => s,
        Err(_) => return,
    });
    let mut line = String::new();
    if reader.read_line(&mut line).is_ok() {
        let cmd = line.trim();
        let response = match cmd {
            "fan quiet" => set_fan_mode("quiet").unwrap_or("error").to_string(),
            "fan auto" => set_fan_mode("auto").unwrap_or("error").to_string(),
            "fan max" => set_fan_mode("max").unwrap_or("error").to_string(),
            "fan get" => get_fan_mode().to_string(),

            "nv block" => set_nv_blocked(true).unwrap_or("error").to_string(),
            "nv unblock" => set_nv_blocked(false).unwrap_or("error").to_string(),
            "nv status" => get_nv_status().to_string(),

            "ryzen max" | "ryzen unlock" => set_ryzen_max().unwrap_or("error").to_string(),
            "ryzen get" => get_ryzen_limits(),

            "check" => format!(
                "has_fan:{} has_nv:{} has_ryzen:{}",
                if has_fan() { 1 } else { 0 },
                if has_nv() { 1 } else { 0 },
                if has_ryzen() { 1 } else { 0 }
            ),
            "ping" => "pong".to_string(),
            _ => "unknown command".to_string(),
        };
        let _ = writeln!(stream, "{}", response);
    }
}

fn main() {
    let _ = fs::remove_file(SOCKET_PATH);
    let listener = match UnixListener::bind(SOCKET_PATH) {
        Ok(l) => l,
        Err(e) => {
            eprintln!("Failed to bind {}: {}", SOCKET_PATH, e);
            std::process::exit(1);
        }
    };

    if let Err(e) = fs::set_permissions(SOCKET_PATH, Permissions::from_mode(0o666)) {
        eprintln!("Failed to set permissions on {}: {}", SOCKET_PATH, e);
    }

    for stream in listener.incoming() {
        match stream {
            Ok(s) => {
                thread::spawn(|| handle_client(s));
            }
            Err(e) => {
                eprintln!("Connection error: {}", e);
            }
        }
    }
}
