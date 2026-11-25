use gtk4::prelude::*;
use std::env;
use std::path::Path;
use std::process::Command;
use system_ui_helpers::{
    RustHelpersConfig, apply_clean_theme, read_desktop_prop, write_desktop_props,
};

fn apply_path_update(cfg: &RustHelpersConfig, desktop_path: &str, clean_name: &str, new_exe: &str) {
    let exec_cmd = format!("{} \"{desktop_path}\"", cfg.bins.umu_run_wrapper);
    let exe_dir = Path::new(new_exe)
        .parent()
        .unwrap_or_else(|| Path::new(""))
        .to_string_lossy()
        .to_string();

    write_desktop_props(
        desktop_path,
        &[
            ("Name", clean_name),
            ("X-UMU-Actual-Exe", new_exe),
            ("Exec", &exec_cmd),
            ("Path", &exe_dir),
        ],
    );

    Command::new(&cfg.bins.notify_send)
        .args([
            "Ярлык обновлен",
            &format!("Новый путь установлен для {clean_name}"),
        ])
        .spawn()
        .ok();
}

fn main() {
    let cfg = RustHelpersConfig::load_or_exit();
    gtk4::init().expect("GTK4 init failed");
    apply_clean_theme();
    let main_loop = glib::MainLoop::new(None, false);

    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        std::process::exit(1);
    }
    let desktop_path = args[1].clone();

    let win = gtk4::Window::builder()
        .title("Исправление пути к файлу - UMU")
        .default_width(520)
        .build();

    let vbox = gtk4::Box::new(gtk4::Orientation::Vertical, 12);
    vbox.set_margin_top(15);
    vbox.set_margin_bottom(15);
    vbox.set_margin_start(15);
    vbox.set_margin_end(15);
    win.set_child(Some(&vbox));

    let current_name = read_desktop_prop(&desktop_path, "Name");
    let clean_name = current_name.replace(" (Inactive)", "").trim().to_string();
    let actual_exe = read_desktop_prop(&desktop_path, "X-UMU-Actual-Exe");

    let lbl_info = gtk4::Label::builder()
        .label(format!(
            "<b>Файл запуска для '{clean_name}' не найден!</b>\n<span foreground='gray'>Текущий путь: {actual_exe}</span>\n\nУкажите новое местоположение исполняемого файла (.exe)"
        ))
        .use_markup(true)
        .xalign(0.0)
        .wrap(true)
        .build();
    vbox.append(&lbl_info);

    let path_hbox = gtk4::Box::new(gtk4::Orientation::Horizontal, 5);
    let ent_path = gtk4::Entry::new();
    ent_path.set_text(&actual_exe);
    ent_path.set_hexpand(true);
    let btn_browse = gtk4::Button::with_label("Обзор...");
    path_hbox.append(&ent_path);
    path_hbox.append(&btn_browse);
    vbox.append(&path_hbox);

    let w_browse = win.clone();
    let ep_browse = ent_path.clone();
    btn_browse.connect_clicked(move |_| {
        let dlg = gtk4::FileChooserNative::builder()
            .title("Выберите исполняемый файл (.exe)")
            .transient_for(&w_browse)
            .action(gtk4::FileChooserAction::Open)
            .build();
        let ec = ep_browse.clone();
        dlg.connect_response(move |d, response| {
            if response == gtk4::ResponseType::Accept
                && let Some(f) = d.file()
                && let Some(p) = f.path()
            {
                ec.set_text(&p.to_string_lossy());
            }
            d.destroy();
        });
        dlg.show();
    });

    let bbox = gtk4::Box::new(gtk4::Orientation::Horizontal, 10);
    bbox.set_halign(gtk4::Align::End);
    let btn_ok = gtk4::Button::with_label("Сохранить и активировать");
    let btn_cancel = gtk4::Button::with_label("Отмена");
    bbox.append(&btn_ok);
    bbox.append(&btn_cancel);
    vbox.append(&bbox);

    let ml_c = main_loop.clone();
    btn_cancel.connect_clicked(move |_| ml_c.quit());

    let w_ok = win.clone();
    let ep_ok = ent_path;
    let ml_ok = main_loop.clone();
    let dp_ok = desktop_path;
    let cn_ok = clean_name;

    btn_ok.connect_clicked(move |_| {
        let new_exe = ep_ok.text().trim().to_string();
        if new_exe.is_empty() || !Path::new(&new_exe).exists() {
            let err_dlg = gtk4::MessageDialog::builder()
                .transient_for(&w_ok)
                .modal(true)
                .message_type(gtk4::MessageType::Error)
                .buttons(gtk4::ButtonsType::Ok)
                .text("Указанный файл не существует! Пожалуйста, выберите действительный файл.")
                .build();
            err_dlg.connect_response(|d, _| d.destroy());
            err_dlg.present();
            return;
        }

        apply_path_update(&cfg, &dp_ok, &cn_ok, &new_exe);
        ml_ok.quit();
    });

    let ml_win = main_loop;
    win.connect_close_request(move |_| {
        ml_win.quit();
        glib::Propagation::Proceed
    });
    win.present();
}
