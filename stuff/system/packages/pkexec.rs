use std::{env, os::unix::process::CommandExt, process::Command};

const REAL_PKEXEC: &str = "%{{{pkgs.polkit.bin}}}/bin/pkexec";

fn main() {
    let args: Vec<_> = env::args_os().skip(1).collect();

    let is_info = args.iter().any(|a| {
        let s = a.to_string_lossy();
        s == "-h" || s == "--help" || s == "--version"
    });

    if is_info {
        let _ = Command::new(REAL_PKEXEC).args(&args).exec();
    }

    let mut run0_args = Vec::new();
    let mut cmd_args = Vec::new();
    let mut keep_cwd = false;
    let mut iter = args.into_iter();

    while let Some(arg) = iter.next() {
        let s = arg.to_string_lossy();
        if s == "--disable-internal-agent" {
            continue;
        }
        if s == "--" {
            cmd_args.extend(iter);
            break;
        }
        if s == "--keep-cwd" {
            keep_cwd = true;
        } else if s == "--user" {
            if let Some(user) = iter.next() {
                run0_args.push(format!("--user={}", user.to_string_lossy()).into());
            }
        } else if s.starts_with("--user=") || s.starts_with('-') {
            run0_args.push(arg);
        } else {
            cmd_args.push(arg);
            cmd_args.extend(iter);
            break;
        }
    }

    if !keep_cwd {
        run0_args.push("--chdir=~".into());
    }

    let runtime = env::var("XDG_RUNTIME_DIR").unwrap_or_default();
    let wayland = env::var("WAYLAND_DISPLAY").unwrap_or_default();
    run0_args.push(format!("--setenv=WAYLAND_DISPLAY={runtime}/{wayland}").into());

    for var in &[
        "--setenv=PATH",
        "--setenv=XDG_DATA_HOME",
        "--setenv=DISPLAY",
        "--setenv=GTK_THEME",
    ] {
        run0_args.push((*var).into());
    }

    run0_args.extend(cmd_args);

    let _ = Command::new("run0").args(&run0_args).exec();
}
