use std::{
    env,
    fs::OpenOptions,
    io::Write,
    os::unix::process::CommandExt,
    process::{self, Command},
};

const SYSTEMD_PACKAGE: &str = "%{{{config.systemd.package}}}/bin/run0";
const SH_CLEAR_HOOK: &str = "printf '\\r\\033[2K'; if [ $# -eq 0 ]; then exec \"${SHELL:-/bin/sh}\" -l; else exec \"$@\"; fi";

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

    let mut cmd = Command::new(SYSTEMD_PACKAGE);
    cmd.arg0("run0");

    if is_info_query {
        cmd.args(&args);
    } else {
        let mut run0_opts = Vec::new();
        let mut cmd_args = Vec::new();
        let mut iter = args.into_iter();

        while let Some(arg) = iter.next() {
            let s = arg.to_string_lossy();
            if s == "--" {
                cmd_args.extend(iter);
                break;
            } else if s.starts_with('-') {
                let takes_separate_arg = s == "-u"
                    || s == "-g"
                    || s == "-D"
                    || s == "--user"
                    || s == "--group"
                    || s == "--chdir"
                    || s == "--machine"
                    || s == "--unit"
                    || s == "--property"
                    || s == "--description"
                    || s == "--slice"
                    || s == "--nice"
                    || s == "--setenv"
                    || s == "--background"
                    || s == "--shell-prompt-prefix"
                    || s == "--lightweight"
                    || s == "--area";

                run0_opts.push(arg);
                if takes_separate_arg {
                    run0_opts.extend(iter.next());
                }
            } else {
                cmd_args.push(arg);
                cmd_args.extend(iter);
                break;
            }
        }

        let has_unit = run0_opts.iter().any(|a| {
            let s = a.to_string_lossy();
            s == "--unit" || s.starts_with("--unit=")
        });

        if !has_unit {
            let unit = format!("run0-{pid}.service");
            write_tty(format!("run0: {unit}").as_bytes());
            cmd.arg(format!("--unit={unit}"));
        }

        cmd.args(&run0_opts);
        cmd.arg("--")
            .arg("/bin/sh")
            .arg("-c")
            .arg(SH_CLEAR_HOOK)
            .arg("--")
            .args(&cmd_args);
    }

    let err = cmd.exec();
    eprintln!("run0: {err}");
    process::exit(1);
}
