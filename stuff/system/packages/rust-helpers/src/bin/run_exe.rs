use gtk4::prelude::*;
use std::env;
use std::path::Path;
use std::process::Command;
use system_ui_helpers::{
    RustHelpersConfig, UmuOptionsWidget, UmuShortcutData, apply_clean_theme,
    extract_default_icon_for_exe, resolve_actual_exe_from_lnk, save_shortcut_to_desktop,
};

fn run_application(cfg: &RustHelpersConfig, options: &UmuOptionsWidget) {
    let data = options.get_data();
    let envs = options.build_launch_envs();

    let (actual_exe, _) = if data.exe.to_lowercase().ends_with(".lnk") {
        resolve_actual_exe_from_lnk(cfg, &data.exe, &data.prefix)
    } else {
        (data.exe.clone(), String::new())
    };

    let target_exe = &actual_exe;
    let raw_args = &data.args;
    let wrapper = &cfg.bins.umu_run_wrapper;
    let scanner = &cfg.bins.scan_umu_for_lnk;

    let cmd_str = if raw_args.contains("%command%") {
        let parts: Vec<&str> = raw_args.splitn(2, "%command%").collect();
        format!(
            "{} {wrapper} \"{target_exe}\" {}",
            parts[0].trim(),
            parts.get(1).unwrap_or(&"").trim()
        )
    } else {
        format!("{wrapper} \"{target_exe}\" {}", raw_args.trim())
    };

    Command::new("sh")
        .arg("-c")
        .arg(format!("{cmd_str}; {scanner}"))
        .envs(&envs)
        .spawn()
        .ok();
}

fn extract_default_name(filepath: &str) -> String {
    if filepath.is_empty() {
        return String::new();
    }
    if filepath.to_lowercase().ends_with(".lnk") {
        Path::new(filepath)
            .file_stem()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string()
    } else {
        Path::new(filepath)
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string()
    }
}

fn build_initial_data(cfg: &RustHelpersConfig, filepath: &str) -> UmuShortcutData {
    let d = &cfg.shortcut_defaults;
    let prefix_name = env::var("UMU_PREFIX_NAME")
        .ok()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| d.prefix.clone());
    let default_icon = if filepath.is_empty() {
        d.icon.clone()
    } else {
        extract_default_icon_for_exe(cfg, filepath, &prefix_name).unwrap_or_else(|| d.icon.clone())
    };
    let default_name = extract_default_name(filepath);

    let mut orig_args = env::var("UMU_RAW_ARGS").unwrap_or_default();
    let mut lnk_path = String::new();
    if !filepath.is_empty() && filepath.to_lowercase().ends_with(".lnk") {
        lnk_path.push_str(filepath);
        if let Ok(out) = Command::new(&cfg.bins.exiftool)
            .args(["-s3", "-CommandLineArguments", filepath])
            .output()
        {
            let args_out = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !args_out.is_empty() && args_out != "-" {
                orig_args = args_out;
            }
        }
    }

    let mut initial_paths = env::var("UMU_EXTRA_PATHS").unwrap_or_default();
    if initial_paths.trim().is_empty()
        && !filepath.is_empty()
        && let Some(parent) = Path::new(filepath).parent()
        && parent.exists()
    {
        initial_paths = format!("--rw \"{}\"", parent.to_string_lossy());
    }

    let mut data = UmuShortcutData::from_defaults(cfg);
    data.name = default_name;
    data.exe = filepath.to_string();
    data.icon = default_icon;
    data.args = orig_args;
    data.prefix = prefix_name;
    data.gameid = env::var("GAMEID").unwrap_or_default();
    data.perf.gamemode = env::var("USE_GAMEMODE").map_or(d.perf.gamemode, |v| v == "1");
    data.perf.mangohud = env::var("USE_MANGOHUD").map_or(d.perf.mangohud, |v| v == "1");
    data.display.wayland = env::var("PROTON_ENABLE_WAYLAND").map_or(d.wayland, |v| v == "1");
    data.display.overlay =
        env::var("USE_STEAM_OVERLAY").map_or(d.steam.steam_overlay, |v| v == "1");
    data.display.xwayland_mode = env::var("UMU_X11_MODE")
        .ok()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| d.x11.clone());
    data.steam.steam =
        env::var("USE_STEAM_INTEGRATION").map_or(d.steam.steam_integration, |v| v == "1");
    data.isolation.vpn = env::var("USE_VPN").map_or(d.isolation.vpn, |v| v == "1");
    data.isolation.sandbox = env::var("USE_SANDBOX").map_or(d.isolation.sandbox, |v| v == "1");
    data.isolation.gamepad = env::var("USE_GAMEPAD").map_or(d.isolation.gamepad, |v| v == "1");
    data.extra_paths = initial_paths;
    data.lnk_path = lnk_path;
    data
}

fn main() {
    let cfg = RustHelpersConfig::load_or_exit();
    let args: Vec<String> = env::args().collect();
    let filepath = if args.len() > 1 { args[1].as_str() } else { "" };

    if gtk4::init().is_err() {
        eprintln!("Не удалось инициализировать GTK4");
        return;
    }
    apply_clean_theme();

    let initial_data = build_initial_data(&cfg, filepath);

    let main_loop = glib::MainLoop::new(None, false);

    let initial_width = if initial_data.isolation.sandbox {
        cfg.sandbox_ui.umu_width_expanded
    } else {
        cfg.sandbox_ui.umu_width_collapsed
    };
    let win = gtk4::Window::builder()
        .title("UMU Launcher")
        .default_width(initial_width)
        .resizable(false)
        .build();

    let vbox = gtk4::Box::new(gtk4::Orientation::Vertical, 12);
    vbox.set_margin_top(15);
    vbox.set_margin_bottom(15);
    vbox.set_margin_start(15);
    vbox.set_margin_end(15);
    win.set_child(Some(&vbox));

    let options_widget = UmuOptionsWidget::new(&win, &cfg, Some(&initial_data));
    vbox.append(options_widget.widget());

    let bbox = gtk4::Box::new(gtk4::Orientation::Horizontal, 10);
    bbox.set_halign(gtk4::Align::End);

    let btn_run = gtk4::Button::with_label("Запустить");
    btn_run.add_css_class("suggested-action");
    let btn_create = gtk4::Button::with_label("Создать ярлык");
    let btn_cancel = gtk4::Button::with_label("Отмена");

    bbox.append(&btn_run);
    bbox.append(&btn_create);
    bbox.append(&btn_cancel);
    vbox.append(&bbox);

    let ml_run = main_loop.clone();
    let opt_run = options_widget.clone();
    let cfg_run = cfg.clone();
    btn_run.connect_clicked(move |_| {
        run_application(&cfg_run, &opt_run);
        ml_run.quit();
    });

    let ml_create = main_loop.clone();
    let opt_create = options_widget;
    let cfg_create = cfg;
    btn_create.connect_clicked(move |_| {
        let data = opt_create.get_data();
        let _ = save_shortcut_to_desktop(&cfg_create, &data, None);
        ml_create.quit();
    });

    let ml_cancel = main_loop.clone();
    btn_cancel.connect_clicked(move |_| {
        ml_cancel.quit();
    });

    let ml_win = main_loop.clone();
    win.connect_close_request(move |_| {
        ml_win.quit();
        glib::Propagation::Proceed
    });

    win.present();
    main_loop.run();
}
