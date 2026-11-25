use gtk4::prelude::*;
use std::fs;
use std::rc::Rc;
use system_ui_helpers::{
    RustHelpersConfig, UmuOptionsWidget, apply_clean_theme, load_shortcut_from_desktop,
    read_desktop_prop, save_shortcut_to_desktop, set_image_from_path_or_theme,
};

fn populate_shortcuts(cfg: &RustHelpersConfig, listbox: &gtk4::ListBox) {
    while let Some(child) = listbox.first_child() {
        listbox.remove(&child);
    }
    let desk_dir = cfg.desktop_dir();
    if let Ok(entries) = fs::read_dir(desk_dir) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with("umu-") && name.ends_with(".desktop") {
                let path = entry.path().to_string_lossy().to_string();
                let dname = read_desktop_prop(&path, "Name");
                let icon_path = read_desktop_prop(&path, "Icon");

                let row = gtk4::ListBoxRow::new();
                row.set_widget_name(&format!("{dname}|{path}"));

                let row_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 15);
                row_box.set_margin_top(8);
                row_box.set_margin_bottom(8);
                row_box.set_margin_start(10);
                row_box.set_margin_end(10);

                let img = gtk4::Image::new();
                set_image_from_path_or_theme(&img, &icon_path, 64);

                let lbl = gtk4::Label::builder()
                    .label(&dname)
                    .xalign(0.0)
                    .hexpand(true)
                    .build();

                row_box.append(&img);
                row_box.append(&lbl);
                row.set_child(Some(&row_box));
                listbox.append(&row);
            }
        }
    }
}

fn setup_shortcuts_window() -> (
    gtk4::Window,
    gtk4::SearchEntry,
    gtk4::ListBox,
    gtk4::Button,
    gtk4::Button,
    gtk4::Button,
) {
    let win = gtk4::Window::builder()
        .title("Manage UMU Shortcuts")
        .default_width(750)
        .default_height(480)
        .build();

    let vbox = gtk4::Box::new(gtk4::Orientation::Vertical, 8);
    vbox.set_margin_top(10);
    vbox.set_margin_bottom(10);
    vbox.set_margin_start(10);
    vbox.set_margin_end(10);
    win.set_child(Some(&vbox));

    let search_hbox = gtk4::Box::new(gtk4::Orientation::Horizontal, 5);
    let search_lbl = gtk4::Label::new(Some("Поиск ярлыков"));
    let search_entry = gtk4::SearchEntry::new();
    search_entry.set_hexpand(true);
    search_entry.set_can_focus(true);
    search_hbox.append(&search_lbl);
    search_hbox.append(&search_entry);
    vbox.append(&search_hbox);

    let listbox = gtk4::ListBox::new();
    listbox.set_selection_mode(gtk4::SelectionMode::Single);
    let scroll = gtk4::ScrolledWindow::builder()
        .child(&listbox)
        .vexpand(true)
        .build();
    vbox.append(&scroll);

    let bbox = gtk4::Box::new(gtk4::Orientation::Horizontal, 10);
    bbox.set_halign(gtk4::Align::End);
    let btn_create = gtk4::Button::with_label("Создать ярлык");
    btn_create.add_css_class("suggested-action");
    let btn_delete = gtk4::Button::with_label("Удалить ярлык");
    let btn_close = gtk4::Button::with_label("Закрыть");

    btn_create.set_focusable(false);
    btn_create.set_can_focus(false);
    btn_delete.set_focusable(false);
    btn_delete.set_can_focus(false);
    btn_close.set_focusable(false);
    btn_close.set_can_focus(false);

    bbox.append(&btn_create);
    bbox.append(&btn_delete);
    bbox.append(&btn_close);
    vbox.append(&bbox);

    (
        win,
        search_entry,
        listbox,
        btn_create,
        btn_delete,
        btn_close,
    )
}

fn connect_main_actions(
    cfg: &RustHelpersConfig,
    win: &gtk4::Window,
    listbox: &gtk4::ListBox,
    btn_create: &gtk4::Button,
    btn_delete: &gtk4::Button,
    get_selected: &Rc<dyn Fn() -> Option<(String, String)>>,
) {
    let lb_create = listbox.clone();
    let cfg_create = cfg.clone();
    btn_create.connect_clicked(move |_| {
        let lb = lb_create.clone();
        let cfg_poll = cfg_create.clone();
        let mut child = std::process::Command::new(&cfg_create.bins.run_exe);
        if let Ok(mut c) = child.spawn() {
            glib::timeout_add_local(std::time::Duration::from_millis(500), move || {
                match c.try_wait() {
                    Ok(Some(_)) => {
                        populate_shortcuts(&cfg_poll, &lb);
                        glib::ControlFlow::Break
                    }
                    Ok(None) => glib::ControlFlow::Continue,
                    Err(_) => glib::ControlFlow::Break,
                }
            });
        }
    });

    let w_del = win.clone();
    let gs_del = Rc::clone(get_selected);
    let lb_del = listbox.clone();
    let cfg_del = cfg.clone();
    btn_delete.connect_clicked(move |_| {
        if let Some((name, desk_path)) = gs_del() {
            let dlg = gtk4::MessageDialog::builder()
                .transient_for(&w_del)
                .modal(true)
                .message_type(gtk4::MessageType::Question)
                .buttons(gtk4::ButtonsType::YesNo)
                .text(format!(
                    "Вы уверены, что хотите полностью удалить ярлык '{name}'?"
                ))
                .build();

            let lb_c = lb_del.clone();
            let cfg_c = cfg_del.clone();
            dlg.connect_response(move |d, response| {
                if response == gtk4::ResponseType::Yes {
                    fs::remove_file(&desk_path).ok();
                    populate_shortcuts(&cfg_c, &lb_c);
                }
                d.destroy();
            });
            dlg.present();
        }
    });
}

fn open_edit_dialog(
    parent: &gtk4::Window,
    cfg: &RustHelpersConfig,
    desktop_path: &str,
    on_saved: impl Fn() + 'static,
) {
    let data = load_shortcut_from_desktop(desktop_path, cfg);
    let initial_width = if data.isolation.sandbox {
        cfg.sandbox_ui.umu_width_expanded
    } else {
        cfg.sandbox_ui.umu_width_collapsed
    };

    let dlg = gtk4::Window::builder()
        .title("Редактирование ярлыка")
        .default_width(initial_width)
        .transient_for(parent)
        .modal(true)
        .resizable(false)
        .build();

    let vbox = gtk4::Box::new(gtk4::Orientation::Vertical, 12);
    vbox.set_margin_top(15);
    vbox.set_margin_bottom(15);
    vbox.set_margin_start(15);
    vbox.set_margin_end(15);
    dlg.set_child(Some(&vbox));

    let title_hbox = gtk4::Box::new(gtk4::Orientation::Horizontal, 5);
    let lbl_p = gtk4::Label::builder()
        .label("<b>Редактирование:</b>")
        .use_markup(true)
        .build();
    let lbl_f = gtk4::Label::builder()
        .label(format!("<b>{}</b>", data.name))
        .use_markup(true)
        .build();
    title_hbox.append(&lbl_p);
    title_hbox.append(&lbl_f);
    vbox.append(&title_hbox);

    let options_widget = UmuOptionsWidget::new(&dlg, cfg, Some(&data));
    vbox.append(options_widget.widget());

    let bbox = gtk4::Box::new(gtk4::Orientation::Horizontal, 10);
    bbox.set_halign(gtk4::Align::End);
    let btn_save = gtk4::Button::with_label("Сохранить изменения");
    btn_save.add_css_class("suggested-action");
    let btn_cancel = gtk4::Button::with_label("Отмена");

    bbox.append(&btn_save);
    bbox.append(&btn_cancel);
    vbox.append(&bbox);

    let w_c = dlg.clone();
    btn_cancel.connect_clicked(move |_| w_c.close());

    let d_path = desktop_path.to_string();
    let w_save = dlg.clone();
    let on_s = Rc::new(on_saved);
    let cfg_save = cfg.clone();

    btn_save.connect_clicked(move |_| {
        let updated = options_widget.get_data();
        let _ = save_shortcut_to_desktop(&cfg_save, &updated, Some(&d_path));
        on_s();
        w_save.close();
    });

    dlg.present();
}

fn main() {
    let cfg = RustHelpersConfig::load_or_exit();
    gtk4::init().expect("GTK4 init failed");
    apply_clean_theme();
    let main_loop = glib::MainLoop::new(None, false);

    let (win, search_entry, listbox, btn_create, btn_delete, btn_close) = setup_shortcuts_window();

    populate_shortcuts(&cfg, &listbox);

    let s_clone = search_entry.clone();
    listbox.set_filter_func(move |row| {
        let query = s_clone.text().trim().to_lowercase();
        if query.is_empty() {
            return true;
        }
        let data = row.widget_name().to_lowercase();
        let (name, _) = data.split_once('|').unwrap_or((&data, ""));
        name.contains(&query)
    });

    let lb_filter = listbox.clone();
    search_entry.connect_search_changed(move |_| {
        lb_filter.invalidate_filter();
    });

    let w_close = win.clone();
    btn_close.connect_clicked(move |_| w_close.close());

    let get_selected: Rc<dyn Fn() -> Option<(String, String)>> = {
        let lb = listbox.clone();
        Rc::new(move || -> Option<(String, String)> {
            if let Some(row) = lb.selected_row() {
                let data = row.widget_name().to_string();
                if let Some((name, path)) = data.split_once('|') {
                    return Some((name.to_string(), path.to_string()));
                }
            }
            None
        })
    };

    let w_edit = win.clone();
    let gs_edit = Rc::clone(&get_selected);
    let lb_edit = listbox.clone();
    let cfg_edit = cfg.clone();
    listbox.connect_row_activated(move |_, _| {
        if let Some((_, desk_path)) = gs_edit() {
            let lb = lb_edit.clone();
            let cfg_pop = cfg_edit.clone();
            open_edit_dialog(&w_edit, &cfg_edit, &desk_path, move || {
                populate_shortcuts(&cfg_pop, &lb);
            });
        }
    });

    connect_main_actions(
        &cfg,
        &win,
        &listbox,
        &btn_create,
        &btn_delete,
        &get_selected,
    );

    let ml_win = main_loop.clone();
    win.connect_close_request(move |_| {
        ml_win.quit();
        glib::Propagation::Proceed
    });

    search_entry.grab_focus();
    win.present();
    main_loop.run();
}
