#![forbid(unsafe_code)]

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
    let _ = cmd.spawn();
}

#[derive(Default)]
struct DesktopEntry {
    actual_exe: String,
    game_name: String,
    icon_path: String,
}

fn parse_desktop_entry(content: &str) -> DesktopEntry {
    let mut entry = DesktopEntry::default();

    for line in content.lines() {
        if let Some(v) = line.strip_prefix("X-UMU-Actual-Exe=") {
            if entry.actual_exe.is_empty() {
                entry.actual_exe = v.trim().to_string();
            }
        } else if let Some(v) = line.strip_prefix("Name=") {
            if entry.game_name.is_empty() {
                entry.game_name = v.trim().to_string();
            }
        } else if let Some(v) = line.strip_prefix("Icon=")
            && entry.icon_path.is_empty()
        {
            entry.icon_path = v.trim().to_string();
        }
    }

    entry
}

fn mark_inactive(d_file: &Path, content: &str, entry: &DesktopEntry) {
    let inactive_name = format!("{} (Inactive)", entry.game_name);
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
    let mut updated = new_lines.join("\n");
    updated.push('\n');
    let _ = fs::write(d_file, updated);

    notify(
        &entry.icon_path,
        "Game shortcut disabled",
        &format!(
            "Target executable for {} not found. Launch to re-target or remove.",
            entry.game_name
        ),
    );
}

fn restore_active(d_file: &Path, content: &str, entry: &DesktopEntry) {
    let active_name = entry
        .game_name
        .strip_suffix(" (Inactive)")
        .unwrap_or(&entry.game_name);
    let exec_cmd = format!("umu-run-wrapper \"{}\"", d_file.display());

    let mut new_lines = Vec::new();
    for line in content.lines() {
        if line.starts_with("Name=") {
            new_lines.push(format!("Name={active_name}"));
        } else if line.starts_with("Exec=") {
            new_lines.push(format!("Exec={exec_cmd}"));
        } else {
            new_lines.push(line.to_string());
        }
    }
    let mut updated = new_lines.join("\n");
    updated.push('\n');
    let _ = fs::write(d_file, updated);

    notify(
        &entry.icon_path,
        "Game shortcut restored",
        &format!("Target executable found for {active_name}."),
    );
}

fn process_desktop_file(d_file: &Path) {
    let Ok(content) = fs::read_to_string(d_file) else {
        return;
    };

    let entry = parse_desktop_entry(&content);
    let exe_path = Path::new(&entry.actual_exe);
    let is_active = !entry.game_name.ends_with(" (Inactive)");

    if !entry.actual_exe.is_empty() && !exe_path.exists() && is_active {
        mark_inactive(d_file, &content, &entry);
    } else if !entry.actual_exe.is_empty() && exe_path.exists() && !is_active {
        restore_active(d_file, &content, &entry);
    }
}

fn collect_active_icons(app_dir: &Path) -> HashSet<String> {
    let mut active = HashSet::new();
    if let Ok(entries) = fs::read_dir(app_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_file()
                && let Some(name) = path.file_name().and_then(|n| n.to_str())
                && name.starts_with("umu-")
                && name.ends_with(".desktop")
            {
                process_desktop_file(&path);
                if let Ok(content) = fs::read_to_string(&path) {
                    for line in content.lines() {
                        if let Some(v) = line.strip_prefix("Icon=") {
                            let icon = v.trim();
                            if !icon.is_empty() {
                                active.insert(icon.to_string());
                            }
                            break;
                        }
                    }
                }
            }
        }
    }
    active
}

fn main() {
    let home = env::var("HOME").unwrap_or_else(|_| "/root".to_string());
    let xdg_data = env::var("XDG_DATA_HOME").unwrap_or_else(|_| format!("{home}/.local/share"));
    let app_dir = PathBuf::from(&xdg_data).join("applications");
    let icon_dir = PathBuf::from(&xdg_data).join("icons/umu");

    let active_icons = collect_active_icons(&app_dir);

    if icon_dir.is_dir()
        && let Ok(entries) = fs::read_dir(&icon_dir)
    {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_file() {
                let path_str = path.to_string_lossy();
                let file_name = path
                    .file_name()
                    .map(|s| s.to_string_lossy())
                    .unwrap_or_default();

                let is_active = active_icons.contains(path_str.as_ref())
                    || active_icons.contains(file_name.as_ref());

                if !is_active {
                    let _ = fs::remove_file(&path);
                }
            }
        }
    }
}
