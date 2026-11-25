use gtk4::prelude::*;
use std::env;
use std::io::Read;
use std::process::Command;
use system_ui_helpers::{
    RustHelpersConfig, SandboxOptionsWidget, SandboxUiMode, SbRunConfig, apply_clean_theme,
};

fn build_header_inputs(
    win: &gtk4::Window,
    ui_cfg: &RustHelpersConfig,
) -> (gtk4::Label, gtk4::Box, gtk4::Box, gtk4::Entry, gtk4::Entry) {
    let exe_label = gtk4::Label::builder()
        .label("Исполняемый файл:")
        .xalign(0.0)
        .build();

    let exe_entry = gtk4::Entry::new();
    let args: Vec<String> = env::args().collect();
    if args.len() > 1 {
        exe_entry.set_text(&args[1]);
    }
    exe_entry.set_hexpand(true);

    let btn_browse = gtk4::Button::with_label("Обзор...");
    let exe_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
    exe_box.append(&exe_entry);
    exe_box.append(&btn_browse);

    let w_browse = win.clone();
    let ee_browse = exe_entry.clone();
    let id_entry = gtk4::Entry::new();
    id_entry.set_placeholder_text(Some("Авто (например: blender, app-firefox, test)"));
    id_entry.set_hexpand(true);

    let mut rng_bytes = [0u8; 4];
    if let Ok(mut f) = std::fs::File::open("/dev/urandom") {
        let _ = f.read_exact(&mut rng_bytes);
    }
    let default_id = format!(
        "{}{:02x}{:02x}{:02x}{:02x}",
        ui_cfg.sandbox_ui.tmp_id_prefix, rng_bytes[0], rng_bytes[1], rng_bytes[2], rng_bytes[3]
    );
    id_entry.set_text(&default_id);

    let id_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
    let id_label = gtk4::Label::builder()
        .label("Идентификатор (ID):")
        .xalign(0.0)
        .build();
    id_box.append(&id_label);
    id_box.append(&id_entry);

    let ie_change = id_entry.clone();
    exe_entry.connect_changed(move |e| {
        let text = e.text().to_string();
        if !text.is_empty() && ie_change.text().is_empty() {
            let p = std::path::Path::new(&text);
            if let Some(stem) = p.file_stem() {
                ie_change.set_text(&stem.to_string_lossy());
            }
        }
    });

    btn_browse.connect_clicked(move |_| {
        let dlg = gtk4::FileChooserNative::builder()
            .title("Выберите программу для запуска")
            .transient_for(&w_browse)
            .action(gtk4::FileChooserAction::Open)
            .build();
        let ee = ee_browse.clone();
        dlg.connect_response(move |d, response| {
            if response == gtk4::ResponseType::Accept
                && let Some(f) = d.file()
                && let Some(path) = f.path()
            {
                ee.set_text(&path.to_string_lossy());
            }
            d.destroy();
        });
        dlg.show();
    });

    (exe_label, exe_box, id_box, exe_entry, id_entry)
}

fn launch_sandbox(
    ui_cfg: &RustHelpersConfig,
    exe: &str,
    id: &str,
    sb_widget: &SandboxOptionsWidget,
) {
    if exe.trim().is_empty() {
        return;
    }
    let mut cmd = Command::new(&ui_cfg.bins.sb_run);
    if !id.trim().is_empty() {
        cmd.arg("--id").arg(id.trim());
    }
    for flag in sb_widget.build_sb_run_args() {
        cmd.arg(flag);
    }
    cmd.arg("--").arg(exe);
    let _ = cmd.spawn();
}

fn main() {
    let decl = SbRunConfig::load_or_exit();
    let ui_cfg = RustHelpersConfig::load_or_exit();
    gtk4::init().expect("GTK4 init failed");
    apply_clean_theme();
    let main_loop = glib::MainLoop::new(None, false);

    let win = gtk4::Window::builder()
        .title("Запуск в изолированной песочнице")
        .default_width(ui_cfg.sandbox_ui.sb_gui_width)
        .default_height(ui_cfg.sandbox_ui.sb_gui_height)
        .resizable(false)
        .build();

    let vbox = gtk4::Box::new(gtk4::Orientation::Vertical, 12);
    vbox.set_margin_top(15);
    vbox.set_margin_bottom(15);
    vbox.set_margin_start(15);
    vbox.set_margin_end(15);

    let (exe_label, exe_box, id_box, exe_entry, id_entry) = build_header_inputs(&win, &ui_cfg);
    vbox.append(&exe_label);
    vbox.append(&exe_box);
    vbox.append(&id_box);

    let sb_widget =
        SandboxOptionsWidget::new(&win, &decl, &ui_cfg, SandboxUiMode::Standalone, None);
    vbox.append(sb_widget.widget());

    let root_box = gtk4::Box::new(gtk4::Orientation::Vertical, 8);
    root_box.set_margin_top(12);
    root_box.set_margin_bottom(12);
    root_box.set_margin_start(12);
    root_box.set_margin_end(12);

    let scrolled = gtk4::ScrolledWindow::builder()
        .hscrollbar_policy(gtk4::PolicyType::Never)
        .vscrollbar_policy(gtk4::PolicyType::Automatic)
        .vexpand(true)
        .child(&vbox)
        .build();
    root_box.append(&scrolled);

    let btn_launch = gtk4::Button::with_label("Запустить в песочнице");
    btn_launch.add_css_class("suggested-action");
    root_box.append(&btn_launch);
    win.set_child(Some(&root_box));

    let ml = main_loop.clone();
    let cfg_launch = ui_cfg;
    btn_launch.connect_clicked(move |_| {
        launch_sandbox(&cfg_launch, &exe_entry.text(), &id_entry.text(), &sb_widget);
        ml.quit();
    });

    let ml_close = main_loop.clone();
    win.connect_close_request(move |_| {
        ml_close.quit();
        glib::Propagation::Proceed
    });

    win.show();
    main_loop.run();
}
