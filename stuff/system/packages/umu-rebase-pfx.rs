#![forbid(unsafe_code)]
#![allow(
    clippy::too_many_lines,
    clippy::collapsible_if,
    clippy::manual_is_ascii_check
)]

use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

// ---------------------------------------------------------------------------
// Registry (.reg) Parser & 3-Way Rebaser
// ---------------------------------------------------------------------------
#[derive(Debug, Default, Clone)]
struct RegSection {
    raw_header: String,
    values: BTreeMap<String, Vec<String>>,
}

#[derive(Debug, Default)]
struct RegFile {
    header: Vec<String>,
    sections: BTreeMap<String, RegSection>,
}

fn parse_reg(path: &Path) -> RegFile {
    let mut reg = RegFile::default();
    let Ok(content) = fs::read_to_string(path) else {
        return reg;
    };

    let lines: Vec<&str> = content.lines().collect();
    let mut i = 0;
    let n = lines.len();
    let mut current_sec: Option<String> = None;

    while i < n {
        let line = lines[i];
        let stripped = line.trim();

        if stripped.starts_with('[') && stripped.contains(']') {
            let sec_end = stripped.find(']').unwrap();
            let sec_name = stripped[..=sec_end].to_string();
            current_sec = Some(sec_name.clone());
            reg.sections.entry(sec_name).or_insert_with(|| RegSection {
                raw_header: line.to_string(),
                values: BTreeMap::new(),
            });
            i += 1;
        } else if let Some(ref sec_key) = current_sec {
            if stripped.is_empty() || stripped.starts_with("#time=") || stripped.starts_with(';') {
                i += 1;
                continue;
            }

            let mut full_val_lines = vec![line.to_string()];
            while full_val_lines.last().unwrap().ends_with('\\') && i + 1 < n {
                i += 1;
                full_val_lines.push(lines[i].to_string());
            }

            let first_line = &full_val_lines[0];
            if let Some(eq) = first_line.find('=') {
                let k = first_line[..eq].trim().to_string();
                if let Some(sec) = reg.sections.get_mut(sec_key) {
                    sec.values.insert(k, full_val_lines);
                }
            }
        } else {
            reg.header.push(line.to_string());
        }
        i += 1;
    }

    reg
}

fn rebase_reg(old_base_p: &Path, new_base_p: &Path, upper_p: &Path) {
    let old_base = if old_base_p.exists() {
        parse_reg(old_base_p)
    } else {
        RegFile::default()
    };
    let mut new_base = parse_reg(new_base_p);
    let upper = parse_reg(upper_p);

    let mut added_sections: BTreeMap<String, RegSection> = BTreeMap::new();
    let mut modified_keys: BTreeMap<String, BTreeMap<String, Vec<String>>> = BTreeMap::new();

    for (sec, data) in &upper.sections {
        if let Some(old_sec) = old_base.sections.get(sec) {
            for (k, val_lines) in &data.values {
                if let Some(old_val) = old_sec.values.get(k) {
                    if old_val != val_lines {
                        modified_keys
                            .entry(sec.clone())
                            .or_default()
                            .insert(k.clone(), val_lines.clone());
                    }
                } else {
                    modified_keys
                        .entry(sec.clone())
                        .or_default()
                        .insert(k.clone(), val_lines.clone());
                }
            }
        } else {
            added_sections.insert(sec.clone(), data.clone());
        }
    }

    for (sec, keys) in modified_keys {
        if let Some(new_sec) = new_base.sections.get_mut(&sec) {
            for (k, val) in keys {
                new_sec.values.insert(k, val);
            }
        } else {
            added_sections.insert(
                sec.clone(),
                RegSection {
                    raw_header: sec,
                    values: keys,
                },
            );
        }
    }

    for (sec, data) in added_sections {
        let target = new_base.sections.entry(sec).or_insert_with(|| RegSection {
            raw_header: data.raw_header,
            values: BTreeMap::new(),
        });
        for (k, val) in data.values {
            target.values.insert(k, val);
        }
    }

    let mut out = String::new();
    out.push_str(&new_base.header.join("\n"));
    out.push('\n');

    for (_sec, data) in new_base.sections {
        out.push('\n');
        out.push_str(&data.raw_header);
        out.push('\n');
        for (_k, val_lines) in data.values {
            out.push_str(&val_lines.join("\n"));
            out.push('\n');
        }
    }

    let tmp_path = upper_p.with_extension("reg.tmp");
    if fs::write(&tmp_path, out).is_ok() {
        let _ = fs::rename(&tmp_path, upper_p);
    }
}

// ---------------------------------------------------------------------------
// INI / Config File Parser & Rebaser
// ---------------------------------------------------------------------------
#[derive(Debug, Default, Clone)]
struct IniSection {
    raw_header: String,
    lines: Vec<String>,
}

fn parse_ini(path: &Path) -> BTreeMap<String, IniSection> {
    let mut sections = BTreeMap::new();
    let current_sec = "DEFAULT".to_string();
    sections.insert(
        current_sec.clone(),
        IniSection {
            raw_header: String::new(),
            lines: Vec::new(),
        },
    );

    let Ok(content) = fs::read_to_string(path) else {
        return sections;
    };

    let mut active = current_sec;
    for line in content.lines() {
        let stripped = line.trim();
        if stripped.starts_with('[') && stripped.ends_with(']') {
            active = stripped.to_string();
            sections
                .entry(active.clone())
                .or_insert_with(|| IniSection {
                    raw_header: line.to_string(),
                    lines: Vec::new(),
                });
        } else if let Some(sec) = sections.get_mut(&active) {
            sec.lines.push(line.to_string());
        }
    }

    sections
}

fn rebase_ini(old_base_p: &Path, new_base_p: &Path, upper_p: &Path) {
    let _old_base = if old_base_p.exists() {
        parse_ini(old_base_p)
    } else {
        BTreeMap::new()
    };
    let mut new_base = parse_ini(new_base_p);
    let upper = parse_ini(upper_p);

    for (sec, data) in upper {
        if let Some(new_sec) = new_base.get_mut(&sec) {
            for line in data.lines {
                let s_line = line.trim();
                if s_line.is_empty() || s_line.starts_with(';') || s_line.starts_with('#') {
                    continue;
                }
                if let Some(eq) = s_line.find('=') {
                    let key = s_line[..eq].trim();
                    let mut replaced = false;
                    for target in &mut new_sec.lines {
                        let t_trim = target.trim();
                        if let Some(t_eq) = t_trim.find('=') {
                            if t_trim[..t_eq].trim().eq_ignore_ascii_case(key) {
                                target.clone_from(&line);
                                replaced = true;
                                break;
                            }
                        }
                    }
                    if !replaced {
                        new_sec.lines.push(line);
                    }
                } else if !new_sec.lines.iter().any(|l| l.trim() == s_line) {
                    new_sec.lines.push(line);
                }
            }
        } else {
            new_base.insert(sec, data);
        }
    }

    let mut out = String::new();
    for (_sec, data) in new_base {
        if !data.raw_header.is_empty() {
            out.push_str(&data.raw_header);
            out.push('\n');
        }
        for l in data.lines {
            out.push_str(&l);
            out.push('\n');
        }
    }

    let tmp_path = upper_p.with_extension("ini.tmp");
    if fs::write(&tmp_path, out).is_ok() {
        let _ = fs::rename(&tmp_path, upper_p);
    }
}

// ---------------------------------------------------------------------------
// File Tree Walker & Upper Sanitization
// ---------------------------------------------------------------------------
fn collect_files(dir: &Path, results: &mut Vec<PathBuf>) {
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
            collect_files(&path, results);
        } else if ft.is_file() {
            results.push(path);
        }
    }
}

fn remove_empty_dirs(dir: &Path) {
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
            remove_empty_dirs(&path);
            let _ = fs::remove_dir(&path);
        }
    }
}

// ---------------------------------------------------------------------------
// Main Delta Rebase Engine
// ---------------------------------------------------------------------------
fn main() {
    let args: Vec<String> = env::args().collect();
    let mut old_base = String::new();
    let mut new_base = String::new();
    let mut upper = String::new();
    let mut home = env::var("HOME").unwrap_or_default();

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--old-base" if i + 1 < args.len() => {
                old_base.clone_from(&args[i + 1]);
                i += 1;
            }
            "--new-base" if i + 1 < args.len() => {
                new_base.clone_from(&args[i + 1]);
                i += 1;
            }
            "--upper" if i + 1 < args.len() => {
                upper.clone_from(&args[i + 1]);
                i += 1;
            }
            "--home" if i + 1 < args.len() => {
                home.clone_from(&args[i + 1]);
                i += 1;
            }
            _ => {}
        }
        i += 1;
    }

    if new_base.is_empty() || upper.is_empty() {
        eprintln!(
            "Usage: umu-rebase-pfx --new-base <dir> --upper <dir> [--old-base <dir>] [--home <dir>]"
        );
        std::process::exit(1);
    }

    let upper_dir = PathBuf::from(&upper);
    let new_base_dir = PathBuf::from(&new_base);
    let old_base_dir = if old_base.is_empty() {
        None
    } else {
        Some(PathBuf::from(&old_base))
    };

    if !upper_dir.exists() {
        return;
    }

    // 1. 3-way merge on configuration files found in new_base
    let mut base_files = Vec::new();
    collect_files(&new_base_dir, &mut base_files);

    for full_new in base_files {
        let Ok(rel) = full_new.strip_prefix(&new_base_dir) else {
            continue;
        };
        let full_upper = upper_dir.join(rel);

        if !full_upper.exists() || full_upper.is_symlink() {
            continue;
        }

        let full_old = old_base_dir.as_ref().map(|b| b.join(rel));
        let ext = full_new
            .extension()
            .and_then(|e| e.to_str())
            .unwrap_or("")
            .to_ascii_lowercase();

        if ext == "reg" {
            let empty_path = PathBuf::new();
            rebase_reg(
                full_old.as_deref().unwrap_or(&empty_path),
                &full_new,
                &full_upper,
            );
        } else if matches!(ext.as_str(), "ini" | "cfg" | "conf") {
            let empty_path = PathBuf::new();
            rebase_ini(
                full_old.as_deref().unwrap_or(&empty_path),
                &full_new,
                &full_upper,
            );
        }
    }

    // 2. Remove duplicate/obsolete Proton runtime binaries from upper/drive_c/windows
    let upper_win = upper_dir.join("drive_c/windows");
    if upper_win.exists() {
        let mut win_files = Vec::new();
        collect_files(&upper_win, &mut win_files);

        for full_upper in win_files {
            let Ok(rel) = full_upper.strip_prefix(&upper_dir) else {
                continue;
            };
            let in_old = old_base_dir.as_ref().is_some_and(|b| b.join(rel).exists());
            let in_new = new_base_dir.join(rel).exists();

            if in_old || in_new {
                let _ = fs::remove_file(&full_upper);
            }
        }

        remove_empty_dirs(&upper_win);
    }

    // 3. Synchronize config_info with host paths
    let new_config_info = new_base_dir.join("config_info");
    if new_config_info.exists() {
        if let Ok(mut content) = fs::read_to_string(&new_config_info) {
            let proton_root = new_base_dir.parent().and_then(Path::parent).map_or_else(
                || PathBuf::from(&home).join(".local/share/umu/proton"),
                |p| p.join("proton"),
            );
            let proton_root_str = proton_root.to_string_lossy();

            content = content.replace("@UMU_USER_HOME@/.local/share/umu/proton", &proton_root_str);
            if !home.is_empty() {
                content =
                    content.replace(&format!("{home}/.local/share/umu/proton"), &proton_root_str);
                content = content.replace("@UMU_USER_HOME@", &home);
                // Also replace any lingering build home references
                if let Some(pos) = content.find("/build/") {
                    if let Some(end) = content[pos..].find("_home") {
                        let target = &content[pos..pos + end + 5];
                        content = content.replace(target, &home);
                    }
                }
            }
            let mut lines: Vec<&str> = content.lines().collect();
            for i in 0..lines.len() {
                if lines[i].ends_with("/default_pfx/") && i + 1 < lines.len() {
                    lines[i + 1] = "1.0";
                }
            }
            let _ = fs::write(upper_dir.join("config_info"), lines.join("\n"));
        }
    }

    // 4. Set .update-timestamp to 1 matching EROFS normalized timestamps
    let _ = fs::write(upper_dir.join(".update-timestamp"), "1");

    // 5. Set version
    let new_ver_file = new_base_dir.join("version");
    if new_ver_file.exists() {
        if let Ok(ver) = fs::read_to_string(&new_ver_file) {
            let _ = fs::write(upper_dir.join("version"), format!("{}\n", ver.trim()));
        }
    }

    // 6. Remove transient Proton state files
    for meta in ["tracked_files", "pfx.lock"] {
        let p = upper_dir.join(meta);
        if p.exists() {
            let _ = fs::remove_file(p);
        }
    }
}
