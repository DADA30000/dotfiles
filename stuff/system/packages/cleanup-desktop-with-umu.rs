#![forbid(unsafe_code)]
#![allow(
    clippy::too_many_lines,
    clippy::collapsible_if,
    clippy::manual_is_ascii_check
)]

use std::collections::HashSet;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

fn notify(icon: &str, title: &str, body: &str) {
    let mut cmd = Command::new("notify-send");
    cmd.arg("-u").arg("normal");
    if !icon.is_empty() {
        cmd.arg("-i").arg(icon);
    }
    cmd.arg(title).arg(body);
    let _ = cmd.status();
}

fn process_desktop_file(d_file: &Path) {
    let Ok(content) = fs::read_to_string(d_file) else {
        return;
    };

    let mut actual_exe = String::new();
    let mut game_name = String::new();
    let mut icon_path = String::new();
    let mut raw_args = String::new();
    let mut prefix = String::new();
    let mut gpu = String::new();
    let mut steam = String::new();
    let mut overlay = String::new();
    let mut proton = String::new();
    let mut vpn = String::new();
    let mut gameid = String::new();

    for line in content.lines() {
        if let Some(v) = line.strip_prefix("X-UMU-Actual-Exe=") {
            if actual_exe.is_empty() {
                actual_exe = v.trim().to_string();
            }
        } else if let Some(v) = line.strip_prefix("Name=") {
            if game_name.is_empty() {
                game_name = v.trim().to_string();
            }
        } else if let Some(v) = line.strip_prefix("Icon=") {
            if icon_path.is_empty() {
                icon_path = v.trim().to_string();
            }
        } else if let Some(v) = line.strip_prefix("X-UMU-Raw-Args=") {
            raw_args = v.trim().to_string();
        } else if let Some(v) = line.strip_prefix("X-UMU-Prefix-Name=") {
            prefix = v.trim().to_string();
        } else if let Some(v) = line.strip_prefix("X-UMU-GPU-Select=") {
            gpu = v.trim().to_string();
        } else if let Some(v) = line.strip_prefix("X-UMU-Steam-Integration=") {
            steam = v.trim().to_string();
        } else if let Some(v) = line.strip_prefix("X-UMU-Steam-Overlay=") {
            overlay = v.trim().to_string();
        } else if let Some(v) = line.strip_prefix("X-UMU-Proton-Type=") {
            proton = v.trim().to_string();
        } else if let Some(v) = line.strip_prefix("X-UMU-VPN=") {
            vpn = v.trim().to_string();
        } else if let Some(v) = line.strip_prefix("X-UMU-Game-ID=") {
            gameid = v.trim().to_string();
        }
    }

    if actual_exe.is_empty() {
        for line in content.lines() {
            if let Some(rest) = line.strip_prefix("Exec=") {
                if let Some(start) = rest.find("umu-run-wrapper \"") {
                    let sub = &rest[start + 17..];
                    if let Some(end) = sub.find('"') {
                        actual_exe = sub[..end].to_string();
                        break;
                    }
                }
            }
        }
    }

    let exe_path = Path::new(&actual_exe);
    let is_active = !game_name.ends_with(" (Inactive)");

    if !actual_exe.is_empty() && !exe_path.exists() && is_active {
        // Mark inactive
        let inactive_name = format!("{game_name} (Inactive)");
        let fix_exec = format!("fix-umu-path \"{}\"", d_file.display());

        let mut new_lines = Vec::new();
        for line in content.lines() {
            if line.starts_with("Name=") {
                new_lines.push(format!("Name={inactive_name}"));
            } else if line.starts_with("Exec=") {
                new_lines.push(format!("Exec={fix_exec}"));
            } else {
                new_lines.push(line.to_string());
            }
        }
        new_lines.push(String::new());
        let _ = fs::write(d_file, new_lines.join("\n"));
        notify(
            &icon_path,
            "Shortcut Inactive",
            &format!("Executable missing for {game_name}. Double-click shortcut to set new path."),
        );
    } else if !actual_exe.is_empty() && exe_path.exists() && !is_active {
        // Restore active
        let clean_name = game_name.trim_end_matches(" (Inactive)").to_string();
        let env_base = format!(
            "env GAMEID={gameid} USE_GAMEMODE=1 USE_MANGOHUD=1 PROTON_ENABLE_WAYLAND=1 \
             UMU_PREFIX_NAME={prefix} UMU_PROTON_TYPE=\"{proton}\" \
             USE_STEAM_INTEGRATION={steam} USE_STEAM_OVERLAY={overlay} \
             USE_VPN={vpn} UMU_GPU_SELECT=\"{gpu}\""
        );

        let exec_cmd = if raw_args.contains("%command%") {
            let parts: Vec<&str> = raw_args.splitn(2, "%command%").collect();
            let prefix_args = parts[0];
            let suffix_args = parts.get(1).unwrap_or(&"");
            format!("{env_base} {prefix_args} umu-run-wrapper \"{actual_exe}\" {suffix_args}")
        } else {
            format!("{env_base} umu-run-wrapper \"{actual_exe}\" {raw_args}")
        };

        let mut new_lines = Vec::new();
        for line in content.lines() {
            if line.starts_with("Name=") {
                new_lines.push(format!("Name={clean_name}"));
            } else if line.starts_with("Exec=") {
                new_lines.push(format!("Exec={exec_cmd}"));
            } else {
                new_lines.push(line.to_string());
            }
        }
        new_lines.push(String::new());
        let _ = fs::write(d_file, new_lines.join("\n"));
        notify(
            &icon_path,
            "Shortcut Reactivated",
            &format!("Restored executable for {clean_name}"),
        );
    }
}

fn prune_stale_icons(icon_dir: &Path, desktop_dir: &Path) {
    let Ok(icon_entries) = fs::read_dir(icon_dir) else {
        return;
    };

    // Gather all text from all desktop files in memory once
    let mut all_desktop_content = String::new();
    let mut desktop_stems = HashSet::new();

    if let Ok(d_entries) = fs::read_dir(desktop_dir) {
        for entry in d_entries.flatten() {
            let path = entry.path();
            if path.is_file() {
                if let Some(stem) = path.file_stem().and_then(|s| s.to_str()) {
                    desktop_stems.insert(stem.to_string());
                }
                if let Ok(c) = fs::read_to_string(&path) {
                    all_desktop_content.push_str(&c);
                    all_desktop_content.push('\n');
                }
            }
        }
    }

    for entry in icon_entries.flatten() {
        let i_path = entry.path();
        if !i_path.is_file() {
            continue;
        }

        let Some(file_name) = i_path.file_name().and_then(|n| n.to_str()) else {
            continue;
        };
        let Some(base) = i_path.file_stem().and_then(|s| s.to_str()) else {
            continue;
        };

        let i_path_str = i_path.to_string_lossy();
        let is_referenced = all_desktop_content.contains(i_path_str.as_ref())
            || desktop_stems.contains(base)
            || desktop_stems.contains(&format!("{base}-umu"));

        if !is_referenced {
            notify(
                &i_path_str,
                "Cleanup",
                &format!("Removing stale icon {file_name}"),
            );
            let _ = fs::remove_file(&i_path);
        }
    }
}

fn main() {
    let home = env::var("HOME").unwrap_or_else(|_| "/home/l0lk3k".to_string());
    let xdg_data_home = env::var("XDG_DATA_HOME")
        .map_or_else(|_| PathBuf::from(&home).join(".local/share"), PathBuf::from);

    let desktop_dir = xdg_data_home.join("applications");
    let icon_dir = xdg_data_home.join("icons/umu");

    if let Ok(entries) = fs::read_dir(&desktop_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_file() {
                if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                    if name.starts_with("umu-") && name.ends_with(".desktop") {
                        process_desktop_file(&path);
                    }
                }
            }
        }
    }

    if icon_dir.is_dir() {
        prune_stale_icons(&icon_dir, &desktop_dir);
    }
}
