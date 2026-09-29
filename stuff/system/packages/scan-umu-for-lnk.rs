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

#[derive(Debug, Default)]
pub struct LnkInfo {
    pub local_base_path: String,
    pub arguments: String,
    pub icon_location: String,
}

pub fn parse_lnk(data: &[u8]) -> Option<LnkInfo> {
    if data.len() < 76 || data[0..4] != [0x4C, 0x00, 0x00, 0x00] {
        return None;
    }

    let flags = u32::from_le_bytes(data[20..24].try_into().ok()?);
    let has_idlist = (flags & 0x01) != 0;
    let has_linkinfo = (flags & 0x02) != 0;
    let has_name = (flags & 0x04) != 0;
    let has_relpath = (flags & 0x08) != 0;
    let has_workdir = (flags & 0x10) != 0;
    let has_args = (flags & 0x20) != 0;
    let has_icon = (flags & 0x40) != 0;
    let is_unicode = (flags & 0x80) != 0;

    let mut pos = 76;
    if has_idlist {
        if pos + 2 > data.len() {
            return None;
        }
        let idlist_size = u16::from_le_bytes(data[pos..pos + 2].try_into().ok()?) as usize;
        pos += 2 + idlist_size;
    }

    let mut local_base_path = String::new();
    if has_linkinfo {
        if pos + 28 > data.len() {
            return None;
        }
        let info_start = pos;
        let info_size = u32::from_le_bytes(data[pos..pos + 4].try_into().ok()?) as usize;
        let info_end = (info_start + info_size).min(data.len());
        let local_base_offset =
            u32::from_le_bytes(data[pos + 16..pos + 20].try_into().ok()?) as usize;
        if local_base_offset > 0 && info_start + local_base_offset < info_end {
            let lb_start = info_start + local_base_offset;
            if let Some(nul) = data[lb_start..info_end].iter().position(|&b| b == 0) {
                local_base_path =
                    String::from_utf8_lossy(&data[lb_start..lb_start + nul]).to_string();
            }
        }
        pos = info_end;
    }

    let read_string = |p: &mut usize| -> Option<String> {
        if *p + 2 > data.len() {
            return None;
        }
        let char_count = u16::from_le_bytes(data[*p..*p + 2].try_into().ok()?) as usize;
        *p += 2;

        if is_unicode {
            let byte_count = char_count * 2;
            if *p + byte_count > data.len() {
                return None;
            }
            let (chunks, _) = data[*p..*p + byte_count].as_chunks::<2>();
            let u16_slice: Vec<u16> = chunks
                .iter()
                .map(|&[b0, b1]| u16::from_le_bytes([b0, b1]))
                .collect();
            *p += byte_count;
            Some(
                String::from_utf16_lossy(&u16_slice)
                    .trim_end_matches('\0')
                    .to_string(),
            )
        } else {
            let byte_count = char_count;
            if *p + byte_count > data.len() {
                return None;
            }
            let s = String::from_utf8_lossy(&data[*p..*p + byte_count])
                .trim_end_matches('\0')
                .to_string();
            *p += byte_count;
            Some(s)
        }
    };

    if has_name {
        read_string(&mut pos);
    }
    if has_relpath {
        read_string(&mut pos);
    }
    if has_workdir {
        read_string(&mut pos);
    }
    let arguments = if has_args {
        read_string(&mut pos).unwrap_or_default()
    } else {
        String::new()
    };
    let icon_location = if has_icon {
        read_string(&mut pos).unwrap_or_default()
    } else {
        String::new()
    };

    Some(LnkInfo {
        local_base_path,
        arguments,
        icon_location,
    })
}

fn resolve_case_insensitive(base: &Path, rel: &str) -> Option<PathBuf> {
    let mut cur = base.to_path_buf();
    for component in rel.split('/') {
        if component.is_empty() || component == "." {
            continue;
        }
        if component == ".." {
            cur.pop();
            continue;
        }

        let exact = cur.join(component);
        if exact.exists() {
            cur = exact;
            continue;
        }

        let mut found = false;
        if let Ok(entries) = fs::read_dir(&cur) {
            for entry in entries.flatten() {
                if let Ok(name) = entry.file_name().into_string() {
                    if name.eq_ignore_ascii_case(component) {
                        cur = entry.path();
                        found = true;
                        break;
                    }
                }
            }
        }
        if !found {
            return None;
        }
    }
    if cur.is_file() {
        Some(cur)
    } else {
        None
    }
}

fn resolve_actual_exe(prefix: &Path, win_path: &str) -> Option<PathBuf> {
    if win_path.is_empty() || win_path == "-" {
        return None;
    }

    let norm = win_path.replace('\\', "/");
    let (drive, path_no_drive) = if norm.len() >= 2 && norm.as_bytes()[1] == b':' {
        let drive_char = norm.chars().next()?.to_ascii_lowercase();
        let rest = &norm[2..];
        (Some(drive_char), rest)
    } else {
        (None, norm.as_str())
    };

    let path_rel = path_no_drive.trim_start_matches('/');

    // 1. Z: maps directly to root /
    if drive == Some('z') {
        let cand = PathBuf::from(format!("/{path_rel}"));
        if cand.is_file() {
            return Some(cand);
        }
        if let Some(ci) = resolve_case_insensitive(Path::new("/"), path_rel) {
            return Some(ci);
        }
    }

    // 2. dosdevices/<drive>:
    if let Some(d) = drive {
        let dosdevice = prefix.join("dosdevices").join(format!("{d}:"));
        if dosdevice.is_dir() {
            let cand = dosdevice.join(path_rel);
            if cand.is_file() {
                return Some(cand);
            }
            if let Some(ci) = resolve_case_insensitive(&dosdevice, path_rel) {
                return Some(ci);
            }
        }
    }

    // 3. direct filesystem path if absolute
    let direct = PathBuf::from(path_no_drive);
    if direct.is_file() {
        return Some(direct);
    }

    // 4. drive_c in upper or base prefix
    for check_root in ["upper/drive_c", "drive_c"] {
        let root = prefix.join(check_root);
        let cand = root.join(path_rel);
        if cand.is_file() {
            return Some(cand);
        }
        if let Some(ci) = resolve_case_insensitive(&root, path_rel) {
            return Some(ci);
        }
    }

    None
}

fn collect_existing_lnk_paths(desktop_dir: &Path) -> HashSet<String> {
    let mut set = HashSet::new();
    let Ok(entries) = fs::read_dir(desktop_dir) else {
        return set;
    };

    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_file() {
            if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                if name.starts_with("umu-") && name.ends_with(".desktop") {
                    if let Ok(content) = fs::read_to_string(&path) {
                        for line in content.lines() {
                            if let Some(lnk) = line.strip_prefix("X-UMU-Lnk-Path=") {
                                let trimmed = lnk.trim();
                                if !trimmed.is_empty() {
                                    set.insert(trimmed.to_string());
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    set
}

fn scan_dir_for_lnks(dir: &Path, results: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let Ok(ft) = entry.file_type() else {
            continue;
        };
        if ft.is_symlink() {
            continue;
        }
        let path = entry.path();
        if ft.is_dir() {
            scan_dir_for_lnks(&path, results);
        } else if ft.is_file() {
            if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
                if ext.eq_ignore_ascii_case("lnk") {
                    results.push(path);
                }
            }
        }
    }
}

fn main() {
    let home = env::var("HOME").unwrap_or_else(|_| "/home/l0lk3k".to_string());
    let prefix_name = env::var("UMU_PREFIX_NAME").unwrap_or_else(|_| "default".to_string());
    let prefix_path = match env::var("WINEPREFIX") {
        Ok(val) if !val.is_empty() => PathBuf::from(val),
        _ => PathBuf::from(&home).join(".umu").join(&prefix_name),
    };

    // Clean up dead/stale shortcuts first
    let _ = Command::new("cleanup-desktop-with-umu").status();

    let xdg_data_home = env::var("XDG_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(&home).join(".local/share"));
    let desktop_dir = xdg_data_home.join("applications");

    let existing_lnks = collect_existing_lnk_paths(&desktop_dir);

    // Identify search roots across prefix and overlay upper
    let mut search_roots = Vec::new();
    for sub in ["drive_c", "upper/drive_c"] {
        let base_users = prefix_path.join(sub).join("users");
        if let Ok(entries) = fs::read_dir(&base_users) {
            for entry in entries.flatten() {
                let user_dir = entry.path();
                if user_dir.is_dir() {
                    let desk = user_dir.join("Desktop");
                    if desk.is_dir() {
                        search_roots.push(desk);
                    }
                    let start_menu = user_dir
                        .join("AppData/Roaming/Microsoft/Windows/Start Menu/Programs");
                    if start_menu.is_dir() {
                        search_roots.push(start_menu);
                    }
                }
            }
        }

        let pdata = prefix_path
            .join(sub)
            .join("ProgramData/Microsoft/Windows/Start Menu/Programs");
        if pdata.is_dir() {
            search_roots.push(pdata);
        }
    }

    if search_roots.is_empty() {
        return;
    }

    let mut lnk_files = Vec::new();
    for root in &search_roots {
        scan_dir_for_lnks(root, &mut lnk_files);
    }

    for lnk in lnk_files {
        let lnk_str = lnk.to_string_lossy().to_string();
        if existing_lnks.contains(&lnk_str) {
            continue;
        }

        let Ok(data) = fs::read(&lnk) else {
            continue;
        };
        let Some(info) = parse_lnk(&data) else {
            continue;
        };

        if let Some(actual_exe) = resolve_actual_exe(&prefix_path, &info.local_base_path) {
            let actual_exe_str = actual_exe.to_string_lossy().to_string();
            let icon_resolved = resolve_actual_exe(&prefix_path, &info.icon_location)
                .map(|p| p.to_string_lossy().to_string())
                .unwrap_or_default();

            let _ = Command::new("create-desktop-with-umu")
                .arg(&actual_exe_str)
                .arg(&lnk_str)
                .arg(&info.arguments)
                .arg("")
                .arg(&icon_resolved)
                .status();
        }
    }
}
