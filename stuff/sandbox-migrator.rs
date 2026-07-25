use std::env;
use std::fs;
use std::io::Write;
use std::path::Path;
use std::process;

fn main() {
    let args: Vec<String> = env::args().collect();
    let mut app_id = None;
    let mut scope = None;
    let mut cgroup_procs = None;
    let mut go_pipe = None;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--app-id" => {
                app_id = Some(&args[i + 1]);
                i += 2;
            }
            "--scope" => {
                scope = Some(&args[i + 1]);
                i += 2;
            }
            "--cgroup-procs" => {
                cgroup_procs = Some(&args[i + 1]);
                i += 2;
            }
            "--go-pipe" => {
                go_pipe = Some(&args[i + 1]);
                i += 2;
            }
            _ => {
                eprintln!("Unknown argument: {}", args[i]);
                process::exit(1);
            }
        }
    }

    let app_id = app_id.expect("Missing --app-id");
    let scope = scope.expect("Missing --scope");
    let cgroup_procs = cgroup_procs.expect("Missing --cgroup-procs");
    let go_pipe = go_pipe.expect("Missing --go-pipe");

    let target_marker = format!("# nixpak-sandbox-bootstrap-marker:{}", app_id);
    let mut guest_host_pid = None;

    if let Ok(entries) = fs::read_dir("/proc") {
        for entry in entries {
            if let Ok(entry) = entry {
                let file_name = entry.file_name();
                let name_str = file_name.to_string_lossy();

                // Check if numeric directory (PID)
                if name_str.chars().all(|c| c.is_digit(10)) {
                    let pid_dir = entry.path();

                    // 1. Verify cgroup belongs to our exact systemd scope
                    let cgroup_path = pid_dir.join("cgroup");
                    if let Ok(cgroup_content) = fs::read_to_string(&cgroup_path) {
                        if !cgroup_content.contains(&format!("/{}", scope)) {
                            continue;
                        }
                    } else {
                        continue;
                    }

                    // 2. Verify exe name is strictly 'dash'
                    let exe_symlink = pid_dir.join("exe");
                    if let Ok(target) = fs::read_link(&exe_symlink) {
                        if let Some(filename) = target.file_name() {
                            if filename != "dash" {
                                continue;
                            }
                        } else {
                            continue;
                        }
                    } else {
                        continue;
                    }

                    // 3. Verify cmdline argument structure and bootstrap comment
                    let cmdline_path = pid_dir.join("cmdline");
                    if let Ok(cmdline_bytes) = fs::read(&cmdline_path) {
                        let parts: Vec<&[u8]> = cmdline_bytes.split(|&b| b == 0).collect();
                        if parts.len() >= 3 {
                            let arg0 = String::from_utf8_lossy(parts[0]);
                            let arg1 = String::from_utf8_lossy(parts[1]);
                            let arg2 = String::from_utf8_lossy(parts[2]);

                            if (arg0.ends_with("/dash") || arg0 == "dash") && arg1 == "-c" {
                                if arg2.contains(&target_marker) {
                                    guest_host_pid = Some(name_str.into_owned());
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    let guest_host_pid = match guest_host_pid {
        Some(pid) => pid,
        None => {
            eprintln!(
                "Error: Failed to find process with bootstrap marker under scope {}",
                scope
            );
            process::exit(1);
        }
    };

    if let Err(e) = fs::write(cgroup_procs, format!("{}\n", guest_host_pid)) {
        eprintln!(
            "Error: Failed to write PID {} to {}: {}",
            guest_host_pid, cgroup_procs, e
        );
        process::exit(1);
    }

    let mut pipe = match fs::OpenOptions::new().write(true).open(go_pipe) {
        Ok(file) => file,
        Err(e) => {
            eprintln!("Error: Failed to open go-pipe {}: {}", go_pipe, e);
            process::exit(1);
        }
    };

    if let Err(e) = pipe.write_all(b"go\n") {
        eprintln!("Error: Failed to write to go-pipe: {}", e);
        process::exit(1);
    }

    println!("{}", guest_host_pid);
}
