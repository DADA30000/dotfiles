use std::{
    env,
    fs::OpenOptions,
    io::Write,
    os::unix::process::CommandExt,
    process::{self, Command},
};

const SYSTEMD_PACKAGE: &str = "%{{{config.systemd.package}}}/bin/run0";

const FORWARD_ENVS: &[&str] = &["GDK_WAYLAND_DISABLE", "PATH"];

fn write_tty(msg: &[u8]) {
    if let Ok(mut tty) = OpenOptions::new().write(true).open("/dev/tty") {
        let _ = tty.write_all(msg);
        let _ = tty.flush();
    } else {
        let stderr = std::io::stderr();
        let mut handle = stderr.lock();
        let _ = handle.write_all(msg);
        let _ = handle.flush();
    }
}

fn main() {
    let args: Vec<_> = env::args_os().skip(1).collect();
    let pid = process::id();

    let is_info_query = args.iter().any(|a| {
        let s = a.to_string_lossy();
        s == "-h" || s == "--help" || s == "-V" || s == "--version"
    });

    let has_unit = args.iter().any(|a| {
        let s = a.to_string_lossy();
        s == "--unit" || s.starts_with("--unit=")
    });

    let mut cmd = Command::new(SYSTEMD_PACKAGE);
    cmd.arg0("run0");

    if !is_info_query && !has_unit {
        let unit = format!("run0-{pid}.service");
        write_tty(format!("run0: {unit}\n").as_bytes());
        cmd.arg(format!("--unit={unit}"));
    }

    if !is_info_query {
        for &var in FORWARD_ENVS {
            cmd.arg(format!("--setenv={var}"));
        }
    }

    cmd.args(&args);

    let err = cmd.exec();
    eprintln!("run0: {err}");
    process::exit(1);
}
