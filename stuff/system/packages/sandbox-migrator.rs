use std::env;
use std::fs;
use std::io::Write;
use std::process;

struct Config {
    app_id: String,
    scope: String,
    cgroup_procs: String,
    go_pipe: String,
}

fn parse_args(args: &[String]) -> Config {
    let mut app_id = None;
    let mut scope = None;
    let mut cgroup_procs = None;
    let mut go_pipe = None;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--app-id" if i + 1 < args.len() => {
                app_id = Some(args[i + 1].clone());
                i += 2;
            }
            "--scope" if i + 1 < args.len() => {
                scope = Some(args[i + 1].clone());
                i += 2;
            }
            "--cgroup-procs" if i + 1 < args.len() => {
                cgroup_procs = Some(args[i + 1].clone());
                i += 2;
            }
            "--go-pipe" if i + 1 < args.len() => {
                go_pipe = Some(args[i + 1].clone());
                i += 2;
            }
            _ => {
                eprintln!("Invalid or incomplete argument: {}", args[i]);
                process::exit(1);
            }
        }
    }

    Config {
        app_id: app_id.expect("Missing --app-id"),
        scope: scope.expect("Missing --scope"),
        cgroup_procs: cgroup_procs.expect("Missing --cgroup-procs"),
        go_pipe: go_pipe.expect("Missing --go-pipe"),
    }
}

fn find_guest_host_pid(scope: &str, app_id: &str) -> Option<String> {
    let target_env = format!("APP_ID={app_id}");
    let target_role = b"SANDBOX_ROLE=executor";
    let entries = fs::read_dir("/proc").ok()?;

    for entry in entries.flatten() {
        let file_name = entry.file_name();
        let name_str = file_name.to_string_lossy();

        if !name_str.chars().all(|c| c.is_ascii_digit()) {
            continue;
        }

        let pid_dir = entry.path();

        // 1. Verify cgroup belongs to our exact systemd scope
        let cgroup_path = pid_dir.join("cgroup");
        if let Ok(cgroup_content) = fs::read_to_string(&cgroup_path) {
            if !cgroup_content.contains(&format!("/{scope}")) {
                continue;
            }
        } else {
            continue;
        }

        // 2. Verify exe name is strictly 'dash'
        let exe_symlink = pid_dir.join("exe");
        if let Ok(target) = fs::read_link(&exe_symlink) {
            if target.file_name().is_none_or(|f| f != "dash") {
                continue;
            }
        } else {
            continue;
        }

        // 3. Verify environ contains both exact APP_ID and SANDBOX_ROLE=executor
        let environ_path = pid_dir.join("environ");
        if let Ok(env_data) = fs::read(&environ_path) {
            let mut has_app_id = false;
            let mut has_role = false;

            for var in env_data.split(|&b| b == 0) {
                if var == target_env.as_bytes() {
                    has_app_id = true;
                } else if var == target_role {
                    has_role = true;
                }
            }

            if has_app_id && has_role {
                return Some(name_str.into_owned());
            }
        }
    }

    None
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let cfg = parse_args(&args);

    let Some(guest_host_pid) = find_guest_host_pid(&cfg.scope, &cfg.app_id) else {
        eprintln!(
            "Failed to find guest host PID for scope {} and app-id {}",
            cfg.scope, cfg.app_id
        );
        process::exit(1);
    };

    if let Err(e) = fs::write(&cfg.cgroup_procs, format!("{guest_host_pid}\n")) {
        eprintln!(
            "Failed to write PID {guest_host_pid} to {}: {e}",
            cfg.cgroup_procs
        );
        process::exit(1);
    }

    let mut pipe = match fs::OpenOptions::new().write(true).open(&cfg.go_pipe) {
        Ok(f) => f,
        Err(e) => {
            eprintln!("Failed to open go-pipe {}: {e}", cfg.go_pipe);
            process::exit(1);
        }
    };

    if let Err(e) = pipe.write_all(b"GO\n") {
        eprintln!("Failed to signal GO to pipe {}: {e}", cfg.go_pipe);
        process::exit(1);
    }

    println!("Migrated PID {guest_host_pid} to cgroup and unblocked stage 2.");
}
