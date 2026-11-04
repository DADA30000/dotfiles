use std::{env::args_os, os::unix::process::CommandExt, process::Command};

fn main() {
    let _ = Command::new("run0edit").args(args_os().skip(1)).exec();
}
