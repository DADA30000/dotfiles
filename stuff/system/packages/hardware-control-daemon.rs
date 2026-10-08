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
const AORUS_CHARGE_LIMIT_PATH: &str = "/sys/devices/platform/aorus_laptop/charge_limit";

fn has_battery_cap() -> bool {
    Path::new(AORUS_CHARGE_LIMIT_PATH).exists()
        || Path::new("/sys/class/power_supply/BAT1/charge_control_end_threshold").exists()
        || Path::new("/sys/class/power_supply/BAT0/charge_control_end_threshold").exists()
}

fn set_battery_cap(cap: u32) -> Result<&'static str, &'static str> {
    if Path::new(AORUS_CHARGE_LIMIT_PATH).exists() {
        fs::write(AORUS_CHARGE_LIMIT_PATH, format!("{cap}\n").as_bytes())
            .map(|()| "ok")
            .map_err(|_| "write error")
    } else if let Ok(entries) = fs::read_dir("/sys/class/power_supply") {
        for entry in entries.flatten() {
            let threshold_path = entry.path().join("charge_control_end_threshold");
            if threshold_path.exists() {
                return fs::write(threshold_path, format!("{cap}\n").as_bytes())
                    .map(|()| "ok")
                    .map_err(|_| "write error");
            }
        }
        Err("no battery threshold file found")
    } else {
        Err("not supported")
    }
}

fn has_fan() -> bool {
    Path::new(FAN_MODE_PATH).exists()
}

fn set_fan_mode(mode: &str) -> Result<&'static str, &'static str> {
    match mode {
        "quiet" => fs::write(FAN_MODE_PATH, b"3\n")
            .map(|()| "ok")
            .map_err(|_| "write error"),
        "auto" => fs::write(FAN_MODE_PATH, b"0\n")
            .map(|()| "ok")
            .map_err(|_| "write error"),
        "max" => fs::write(FAN_MODE_PATH, b"5\n")
            .map(|()| "ok")
            .map_err(|_| "write error"),
        _ => Err("invalid fan mode"),
    }
}

fn get_fan_mode() -> &'static str {
    fs::read_to_string(FAN_MODE_PATH).map_or("unknown", |content| match content.trim() {
        "5" => "max",
        "3" => "quiet",
        _ => "auto",
    })
}

fn has_nv() -> bool {
    if let Ok(entries) = fs::read_dir("/sys/bus/pci/devices") {
        for entry in entries.flatten() {
            let vendor_path = entry.path().join("vendor");
            if let Ok(vendor) = fs::read_to_string(vendor_path)
                && vendor.trim().eq_ignore_ascii_case("0x10de")
            {
                return true;
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
            if entry.file_type().is_ok_and(|ft| ft.is_dir()) {
                continue;
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
            if name_str.starts_with("nvidia")
                && let Ok(metadata) = entry.metadata()
                && metadata.permissions().mode().trailing_zeros() >= 9
            {
                return "blocked";
            }
        }
    }
    "unblocked"
}

fn has_smu() -> bool {
    Path::new("/sys/kernel/ryzen_smu_drv").exists() || Path::new("/sys/kernel/ryzen_smu").exists()
}

fn is_amd_cpu() -> bool {
    fs::read_to_string("/proc/cpuinfo").is_ok_and(|content| content.contains("AuthenticAMD"))
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
    if let Ok(out) = output
        && out.status.success()
    {
        let text = String::from_utf8_lossy(&out.stdout);
        let mut stapm = None;
        let mut fast = None;
        let mut slow = None;
        for line in text.lines() {
            if line.contains("STAPM LIMIT") {
                let parts: Vec<&str> = line.split('|').map(str::trim).collect();
                if parts.len() >= 3 {
                    stapm = parts[2].parse::<f64>().ok();
                }
            } else if line.contains("PPT LIMIT FAST") {
                let parts: Vec<&str> = line.split('|').map(str::trim).collect();
                if parts.len() >= 3 {
                    fast = parts[2].parse::<f64>().ok();
                }
            } else if line.contains("PPT LIMIT SLOW") {
                let parts: Vec<&str> = line.split('|').map(str::trim).collect();
                if parts.len() >= 3 {
                    slow = parts[2].parse::<f64>().ok();
                }
            }
        }
        if let (Some(s), Some(f), Some(sl)) = (stapm, fast, slow) {
            return format!("{s:.3} {f:.3} {sl:.3}");
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
        let response = if cmd.starts_with("battery ") {
            let val_str = cmd.trim_start_matches("battery ").trim();
            let val_str = val_str.trim_start_matches("set ").trim();
            val_str.parse::<u32>().map_or_else(
                |_| "invalid value".to_string(),
                |cap| set_battery_cap(cap).unwrap_or("error").to_string(),
            )
        } else {
            match cmd {
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
                    "has_fan:{} has_nv:{} has_ryzen:{} has_battery:{}",
                    usize::from(has_fan()),
                    usize::from(has_nv()),
                    usize::from(has_ryzen()),
                    usize::from(has_battery_cap()),
                ),
                "ping" => "pong".to_string(),
                _ => "unknown command".to_string(),
            }
        };
        let _ = writeln!(stream, "{response}");
    }
}

fn main() {
    let _ = fs::remove_file(SOCKET_PATH);
    let listener = match UnixListener::bind(SOCKET_PATH) {
        Ok(l) => l,
        Err(e) => {
            eprintln!("Failed to bind {SOCKET_PATH}: {e}");
            std::process::exit(1);
        }
    };

    if let Err(e) = fs::set_permissions(SOCKET_PATH, Permissions::from_mode(0o666)) {
        eprintln!("Failed to set permissions on {SOCKET_PATH}: {e}");
    }

    for stream in listener.incoming() {
        match stream {
            Ok(s) => {
                thread::spawn(|| handle_client(s));
            }
            Err(e) => {
                eprintln!("Connection error: {e}");
            }
        }
    }
}
