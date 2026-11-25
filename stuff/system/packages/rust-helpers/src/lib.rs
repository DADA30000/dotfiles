use gdk_pixbuf::Pixbuf;
use gtk4::gdk;
use gtk4::pango;
use gtk4::prelude::*;
use serde_json::Value;
use std::cell::RefCell;
use std::env;
use std::fmt::Write;
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::rc::Rc;
use std::thread;

pub mod config;
pub mod sandbox_ui;
pub mod shortcut_editor;
pub use config::*;
pub use sandbox_ui::*;
pub use shortcut_editor::*;

struct TempDir(PathBuf);

impl TempDir {
    fn new() -> Option<Self> {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_nanos());
        let pid = std::process::id();
        let unique = format!("umu-tmp-{pid}-{nanos}");
        let p = env::temp_dir().join(unique);
        fs::create_dir_all(&p).ok()?;
        Some(Self(p))
    }

    const fn path(&self) -> &PathBuf {
        &self.0
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.0).ok();
    }
}

pub fn apply_clean_theme() {
    let css = "
        listbox, listbox row {
            outline: none;
            box-shadow: none;
        }
        listbox row:focus, listbox row:focus-visible, listbox row:focus-within, listbox row:selected, listbox row:hover {
            outline: none;
            box-shadow: none;
        }
        image {
            -gtk-icon-style: requested;
        }
    ";
    let provider = gtk4::CssProvider::new();
    provider.load_from_data(css);
    if let Some(display) = gtk4::gdk::Display::default() {
        gtk4::style_context_add_provider_for_display(
            &display,
            &provider,
            gtk4::STYLE_PROVIDER_PRIORITY_APPLICATION,
        );
    }
}

#[derive(Clone)]
pub struct FileChooserButton {
    button: gtk4::Button,
    label: gtk4::Label,
    current_path: Rc<RefCell<String>>,
}

impl FileChooserButton {
    pub fn new(title: &str, parent: &gtk4::Window, on_file_set: impl Fn(String) + 'static) -> Self {
        let button = gtk4::Button::new();
        button.set_hexpand(true);

        let box_widget = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
        box_widget.set_margin_start(4);
        box_widget.set_margin_end(4);

        let icon = gtk4::Image::from_icon_name("folder-symbolic");
        icon.set_valign(gtk4::Align::Center);

        let label = gtk4::Label::builder()
            .label("(Нет файла)")
            .xalign(0.0)
            .hexpand(true)
            .ellipsize(pango::EllipsizeMode::Middle)
            .build();

        box_widget.append(&icon);
        box_widget.append(&label);
        button.set_child(Some(&box_widget));

        let current_path = Rc::new(RefCell::new(String::new()));
        let title_str = title.to_string();
        let parent_win = parent.clone();
        let cp_click = Rc::clone(&current_path);
        let lbl_click = label.clone();
        let on_set = Rc::new(on_file_set);

        button.connect_clicked(move |_| {
            let dlg = gtk4::FileChooserNative::builder()
                .title(&title_str)
                .transient_for(&parent_win)
                .action(gtk4::FileChooserAction::Open)
                .build();

            let cp = Rc::clone(&cp_click);
            let lbl = lbl_click.clone();
            let cb = Rc::clone(&on_set);

            dlg.connect_response(move |d, res| {
                if res == gtk4::ResponseType::Accept
                    && let Some(f) = d.file()
                    && let Some(p) = f.path()
                {
                    let path = p.to_string_lossy().to_string();
                    (*cp.borrow_mut()).clone_from(&path);
                    let fname = Path::new(&path)
                        .file_name()
                        .unwrap_or_default()
                        .to_string_lossy()
                        .to_string();
                    lbl.set_text(&fname);
                    cb(path);
                }
                d.destroy();
            });
            dlg.show();
        });

        Self {
            button,
            label,
            current_path,
        }
    }

    #[must_use]
    pub const fn widget(&self) -> &gtk4::Button {
        &self.button
    }

    #[must_use]
    pub fn get_filename(&self) -> String {
        self.current_path.borrow().clone()
    }

    pub fn set_filename(&self, path: &str) {
        *self.current_path.borrow_mut() = path.to_string();
        if path.is_empty() {
            self.label.set_text("(Нет файла)");
        } else {
            let fname = Path::new(path)
                .file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .to_string();
            self.label.set_text(&fname);
        }
    }
}

#[must_use]
pub fn load_proton_versions(cfg: &RustHelpersConfig) -> Vec<ProtonVersion> {
    if let Ok(val) = env::var("UMU_PROTON_VERSIONS_JSON")
        && !val.is_empty()
        && let Ok(list) = serde_json::from_str::<Vec<ProtonVersion>>(&val)
        && !list.is_empty()
    {
        return list;
    }

    let candidate = cfg.proton_versions_path();
    if candidate.exists()
        && let Ok(content) = fs::read_to_string(candidate)
        && let Ok(list) = serde_json::from_str::<Vec<ProtonVersion>>(&content)
        && !list.is_empty()
    {
        return list;
    }

    cfg.shortcut_defaults.proton_versions.clone()
}

#[must_use]
pub fn get_default_proton_name(cfg: &RustHelpersConfig, versions: &[ProtonVersion]) -> String {
    versions
        .iter()
        .find(|v| v.default)
        .or_else(|| versions.first())
        .map_or_else(
            || cfg.shortcut_defaults.default_proton.clone(),
            |v| v.name.clone(),
        )
}

#[must_use]
pub fn read_desktop_prop(path: &str, key: &str) -> String {
    if let Ok(content) = fs::read_to_string(path) {
        for line in content.lines() {
            if let Some((k, v)) = line.split_once('=')
                && k.trim() == key
            {
                return v.to_string();
            }
        }
    }
    String::new()
}

pub fn write_desktop_props(path: &str, props: &[(&str, &str)]) {
    if let Ok(content) = fs::read_to_string(path) {
        let mut new_lines = Vec::new();
        let mut written_keys = std::collections::HashSet::new();

        for line in content.lines() {
            let mut replaced = false;
            for (k, v) in props {
                if line.starts_with(&format!("{k}=")) {
                    new_lines.push(format!("{k}={v}"));
                    written_keys.insert(*k);
                    replaced = true;
                    break;
                }
            }
            if !replaced {
                new_lines.push(line.to_string());
            }
        }

        for (k, v) in props {
            if !written_keys.contains(k) {
                new_lines.push(format!("{k}={v}"));
            }
        }

        fs::write(path, new_lines.join("\n")).ok();
    }
}

pub fn set_image_from_path_or_theme(img: &gtk4::Image, path: &str, display_size: i32) {
    img.set_pixel_size(display_size);
    img.set_valign(gtk4::Align::Center);
    if !path.is_empty() && Path::new(path).exists() {
        let load_size = display_size * 2;
        if let Ok(pixbuf) = Pixbuf::from_file_at_scale(path, load_size, load_size, true) {
            let texture = gdk::Texture::for_pixbuf(&pixbuf);
            img.set_paintable(Some(&texture));
            return;
        }
    }
    img.set_icon_name(Some("wine"));
}

#[must_use]
pub fn fetch_steam_icon_cached(cfg: &RustHelpersConfig, appid: &str) -> Option<String> {
    let cache_dir = cfg.icon_cache_dir();
    let dest_path = cache_dir.join(format!("steam-{appid}.png"));
    if dest_path.exists() {
        return Some(dest_path.to_string_lossy().to_string());
    }

    let info_url = replace_token(&cfg.steam.info_api_url, "appid", appid);
    let resp: Value = ureq::get(&info_url)
        .timeout(std::time::Duration::from_secs(cfg.steam.info_timeout_secs))
        .call()
        .ok()?
        .into_json()
        .ok()?;

    let client_icon_hash = resp
        .get("data")?
        .get(appid)?
        .get("common")?
        .get("clienticon")?
        .as_str()?;

    let ico_url = replace_token(
        &replace_token(&cfg.steam.icon_cdn_url, "appid", appid),
        "hash",
        client_icon_hash,
    );

    let mut ico_data = Vec::new();
    ureq::get(&ico_url)
        .timeout(std::time::Duration::from_secs(cfg.steam.icon_timeout_secs))
        .call()
        .ok()?
        .into_reader()
        .read_to_end(&mut ico_data)
        .ok()?;

    let tmp_dir = TempDir::new()?;
    let tmp_ico = tmp_dir.path().join("icon.ico");
    let tmp_png = tmp_dir.path().join("icon.png");
    fs::write(&tmp_ico, &ico_data).ok()?;

    Command::new(&cfg.bins.magick)
        .arg(&tmp_ico)
        .arg(&tmp_png)
        .output()
        .ok()?;

    let mut generated_pngs = Vec::new();
    if let Ok(entries) = fs::read_dir(tmp_dir.path()) {
        for entry in entries.flatten() {
            let p = entry.path();
            if p.is_file()
                && p.file_name()
                    .unwrap_or_default()
                    .to_string_lossy()
                    .starts_with("icon")
                && p.extension().is_some_and(|ext| ext == "png")
                && let Ok(meta) = p.metadata()
            {
                generated_pngs.push((meta.len(), p));
            }
        }
    }

    if generated_pngs.is_empty() {
        return None;
    }

    generated_pngs.sort_by_key(|b| std::cmp::Reverse(b.0));
    fs::copy(&generated_pngs[0].1, &dest_path).ok()?;

    Some(dest_path.to_string_lossy().to_string())
}

fn spawn_db_loader(db_path: PathBuf, db_tx: std::sync::mpsc::Sender<Vec<(String, String)>>) {
    thread::spawn(move || {
        let mut apps = Vec::new();
        if let Ok(content) = fs::read_to_string(db_path)
            && let Ok(data) = serde_json::from_str::<Value>(&content)
        {
            if let Some(arr) = data.as_array() {
                for item in arr {
                    let name = item
                        .get("name")
                        .and_then(|n| n.as_str())
                        .unwrap_or("")
                        .to_string();
                    let appid = item
                        .get("appid")
                        .map_or_else(String::new, |a| a.to_string().replace('"', ""));
                    if !name.is_empty() && !appid.is_empty() {
                        apps.push((name, appid));
                    }
                }
            } else if let Some(obj) = data.as_object() {
                for (k, v) in obj {
                    let name = v.get("name").and_then(|n| n.as_str()).map_or_else(
                        || v.as_str().unwrap_or_default().to_string(),
                        ToString::to_string,
                    );
                    if !name.is_empty() {
                        apps.push((name, k.clone()));
                    }
                }
            }
        }
        let _ = db_tx.send(apps);
    });
}

fn create_search_row(
    cfg: &RustHelpersConfig,
    name: &str,
    appid: &str,
    icon_tx: &std::sync::mpsc::Sender<(String, String)>,
) -> gtk4::ListBoxRow {
    let row = gtk4::ListBoxRow::new();
    row.set_selectable(false);
    row.set_focusable(false);
    row.set_activatable(true);
    row.set_widget_name(&format!("{name}|{appid}"));

    let row_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 12);
    row_box.set_margin_top(6);
    row_box.set_margin_bottom(6);
    row_box.set_margin_start(8);
    row_box.set_margin_end(8);

    let img = gtk4::Image::new();
    let cache_file = cfg.icon_cache_dir().join(format!("steam-{appid}.png"));
    if cache_file.exists() {
        set_image_from_path_or_theme(&img, cache_file.to_string_lossy().as_ref(), 64);
    } else {
        set_image_from_path_or_theme(&img, &cfg.shortcut_defaults.icon, 64);
        let a_clone = appid.to_string();
        let itx = icon_tx.clone();
        let cfg_clone = cfg.clone();
        thread::spawn(move || {
            if let Some(path) = fetch_steam_icon_cached(&cfg_clone, &a_clone) {
                let _ = itx.send((a_clone, path));
            }
        });
    }

    let lbl = gtk4::Label::builder()
        .label(format!("{name} ({appid})"))
        .xalign(0.0)
        .hexpand(true)
        .build();

    row_box.append(&img);
    row_box.append(&lbl);
    row.set_child(Some(&row_box));
    row
}

fn build_steam_search_window(
    parent: &gtk4::Window,
) -> (
    gtk4::Window,
    gtk4::SearchEntry,
    gtk4::ListBox,
    gtk4::Label,
    gtk4::Spinner,
) {
    let win = gtk4::Window::builder()
        .title("Поиск в Steam")
        .default_width(550)
        .default_height(500)
        .transient_for(parent)
        .modal(true)
        .build();

    let vbox = gtk4::Box::new(gtk4::Orientation::Vertical, 10);
    vbox.set_margin_top(10);
    vbox.set_margin_bottom(10);
    vbox.set_margin_start(10);
    vbox.set_margin_end(10);
    win.set_child(Some(&vbox));

    let search_entry = gtk4::SearchEntry::builder()
        .placeholder_text("Введите название игры или AppID...")
        .build();
    vbox.append(&search_entry);

    let listbox = gtk4::ListBox::new();
    listbox.set_selection_mode(gtk4::SelectionMode::None);
    listbox.set_focusable(false);
    let scroll = gtk4::ScrolledWindow::builder()
        .child(&listbox)
        .vexpand(true)
        .build();
    vbox.append(&scroll);

    let status_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 10);
    let lbl_status = gtk4::Label::new(Some("Загрузка базы данных..."));
    lbl_status.set_xalign(0.0);
    lbl_status.set_hexpand(true);
    let spinner = gtk4::Spinner::new();
    status_box.append(&lbl_status);
    status_box.append(&spinner);
    vbox.append(&status_box);

    (win, search_entry, listbox, lbl_status, spinner)
}

pub fn open_steam_search_dialog(
    parent: &gtk4::Window,
    cfg: &RustHelpersConfig,
    on_selected: impl Fn(String, String, Option<String>) + 'static,
) {
    let (win, search_entry, listbox, lbl_status, spinner) = build_steam_search_window(parent);

    let (db_tx, db_rx) = std::sync::mpsc::channel::<Vec<(String, String)>>();
    spawn_db_loader(cfg.games_appid_path(), db_tx);

    let apps_cache = Rc::new(RefCell::new(Vec::new()));
    let ac_load = Rc::clone(&apps_cache);
    let lbl_load = lbl_status.clone();

    glib::timeout_add_local(std::time::Duration::from_millis(80), move || {
        if let Ok(apps) = db_rx.try_recv() {
            if apps.is_empty() {
                lbl_load.set_markup("<span foreground='red'>БД Steam не найдена!</span>");
            } else {
                lbl_load.set_markup("<span foreground='green'>БД Steam загружена</span>");
                *ac_load.borrow_mut() = apps;
            }
            return glib::ControlFlow::Break;
        }
        glib::ControlFlow::Continue
    });

    let (icon_tx, icon_rx) = std::sync::mpsc::channel::<(String, String)>();
    let lb_icons = listbox.clone();

    glib::timeout_add_local(std::time::Duration::from_millis(80), move || {
        while let Ok((appid, icon_path)) = icon_rx.try_recv() {
            let mut child = lb_icons.first_child();
            while let Some(row_widget) = child {
                if let Some(row) = row_widget.downcast_ref::<gtk4::ListBoxRow>()
                    && row.widget_name().ends_with(&format!("|{appid}"))
                    && let Some(bx) = row.child().and_then(|c| c.downcast::<gtk4::Box>().ok())
                    && let Some(img_w) = bx.first_child()
                    && let Some(img) = img_w.downcast_ref::<gtk4::Image>()
                {
                    set_image_from_path_or_theme(img, &icon_path, 64);
                }
                child = row_widget.next_sibling();
            }
        }
        glib::ControlFlow::Continue
    });

    let ac_filter = Rc::clone(&apps_cache);
    let lb_filter = listbox.clone();
    let cfg_search = cfg.clone();

    search_entry.connect_search_changed(move |entry| {
        let query = entry.text().trim().to_lowercase();
        while let Some(child) = lb_filter.first_child() {
            lb_filter.remove(&child);
        }

        if query.is_empty() {
            lbl_status.set_markup("<span foreground='gray'>Ожидание поиска</span>");
            spinner.stop();
            return;
        }

        let apps = ac_filter.borrow();
        let mut results = Vec::new();
        for (name, appid) in apps.iter() {
            if name.to_lowercase().contains(&query) || appid == &query {
                results.push((name.clone(), appid.clone()));
                if results.len() >= cfg_search.steam.search_max_results {
                    break;
                }
            }
        }

        lbl_status.set_text(&format!("Найдено игр: {}", results.len()));

        for (name, appid) in &results {
            let row = create_search_row(&cfg_search, name, appid, &icon_tx);
            lb_filter.append(&row);
        }
    });

    let on_sel = Rc::new(on_selected);
    let w_close = win.clone();
    let cfg_sel = cfg.clone();
    listbox.connect_row_activated(move |_, row| {
        let name_id = row.widget_name().to_string();
        if let Some((name, appid)) = name_id.split_once('|') {
            let cache_file = cfg_sel.icon_cache_dir().join(format!("steam-{appid}.png"));
            let icon_str = if cache_file.exists() {
                Some(cache_file.to_string_lossy().to_string())
            } else {
                None
            };
            on_sel(name.to_string(), appid.to_string(), icon_str);
            w_close.close();
        }
    });

    win.present();
}

#[must_use]
pub fn persist_icon_as(
    cfg: &RustHelpersConfig,
    icon_path: &str,
    custom_dest_filename: Option<&str>,
) -> String {
    if icon_path.is_empty() || icon_path == cfg.shortcut_defaults.icon {
        return icon_path.to_string();
    }
    let path = Path::new(icon_path);
    if !path.exists() {
        return icon_path.to_string();
    }

    let dest_dir = cfg.icon_dest_dir();
    fs::create_dir_all(&dest_dir).ok();

    let dest_path = custom_dest_filename.map_or_else(
        || dest_dir.join(path.file_name().unwrap_or_default()),
        |name| dest_dir.join(name),
    );

    if path.canonicalize().unwrap_or_default() != dest_path.canonicalize().unwrap_or_default() {
        fs::copy(path, &dest_path).ok();
    }

    dest_path.to_string_lossy().to_string()
}

#[must_use]
pub fn persist_icon(cfg: &RustHelpersConfig, icon_path: &str) -> String {
    persist_icon_as(cfg, icon_path, None)
}

pub fn open_zoom_preview(parent: &gtk4::Window, icon_path: &str) {
    if icon_path.is_empty() || !Path::new(icon_path).exists() {
        return;
    }
    let zoom_win = gtk4::Window::builder()
        .title("Предпросмотр")
        .transient_for(parent)
        .modal(true)
        .default_width(300)
        .default_height(300)
        .build();

    let key_controller = gtk4::EventControllerKey::new();
    let zw = zoom_win.clone();
    key_controller.connect_key_pressed(move |_, keyval, _, _| {
        if keyval == gtk4::gdk::Key::Escape {
            zw.close();
            glib::Propagation::Stop
        } else {
            glib::Propagation::Proceed
        }
    });
    zoom_win.add_controller(key_controller);

    let img = gtk4::Image::new();
    set_image_from_path_or_theme(&img, icon_path, 256);
    img.set_margin_top(15);
    img.set_margin_bottom(15);
    img.set_margin_start(15);
    img.set_margin_end(15);
    zoom_win.set_child(Some(&img));
    zoom_win.present();
}

fn resolve_lnk_target(cfg: &RustHelpersConfig, filepath: &str, prefix_name: &str) -> String {
    if filepath.to_lowercase().ends_with(".lnk")
        && let Ok(out) = Command::new(&cfg.bins.exiftool)
            .args(["-s3", "-LocalBasePath", filepath])
            .output()
    {
        let win_path = String::from_utf8_lossy(&out.stdout).trim().to_string();
        if !win_path.is_empty() && win_path != "-" {
            let rel_path = regex_lite_sub_drive(&win_path);
            let p = cfg
                .umu_dir()
                .join(prefix_name)
                .join("upper/drive_c")
                .join(rel_path.trim_start_matches('/'));
            if p.exists() {
                return p.to_string_lossy().to_string();
            }
        }
    }
    filepath.to_string()
}

#[must_use]
pub fn extract_default_icon_for_exe(
    cfg: &RustHelpersConfig,
    filepath: &str,
    prefix_name: &str,
) -> Option<String> {
    let exe_target = resolve_lnk_target(cfg, filepath, prefix_name);

    let digest = md5::compute(filepath.as_bytes());
    let mut hash = String::with_capacity(32);
    for byte in digest {
        let _ = write!(hash, "{byte:02x}");
    }
    let out_icon = cfg.icon_cache_dir().join(format!("umu-{}.png", &hash[..8]));
    if out_icon.exists() {
        return Some(out_icon.to_string_lossy().to_string());
    }

    let tmp_dir = TempDir::new()?;
    let tmp_ico = tmp_dir.path().join("icon.ico");
    let tmp_png = tmp_dir.path().join("icon.png");

    let mut has_ico = false;
    if exe_target.to_lowercase().ends_with(".ico") {
        if fs::copy(&exe_target, &tmp_ico).is_ok() {
            has_ico = true;
        }
    } else {
        if let Ok(res) = Command::new(&cfg.bins.wrestool)
            .args(["-x", "-t", "14", &exe_target])
            .output()
            && !res.stdout.is_empty()
            && fs::write(&tmp_ico, res.stdout).is_ok()
        {
            has_ico = true;
        }
        if !has_ico && let Some(parent) = Path::new(&exe_target).parent() {
            let stem = Path::new(&exe_target)
                .file_stem()
                .unwrap_or_default()
                .to_string_lossy();
            let stem_ico = parent.join(format!("{stem}.ico"));
            let stem_ico_lower = parent.join(format!("{}.ico", stem.to_lowercase()));
            if stem_ico.is_file() {
                has_ico = fs::copy(&stem_ico, &tmp_ico).is_ok();
            } else if stem_ico_lower.is_file() {
                has_ico = fs::copy(&stem_ico_lower, &tmp_ico).is_ok();
            } else if let Ok(entries) = fs::read_dir(parent) {
                for entry in entries.flatten() {
                    let p = entry.path();
                    if p.is_file()
                        && p.extension().is_some_and(|e| e.eq_ignore_ascii_case("ico"))
                        && fs::copy(&p, &tmp_ico).is_ok()
                    {
                        has_ico = true;
                        break;
                    }
                }
            }
        }
    }

    if has_ico {
        Command::new(&cfg.bins.magick)
            .arg(&tmp_ico)
            .arg(&tmp_png)
            .output()
            .ok();

        let mut generated = Vec::new();
        if let Ok(entries) = fs::read_dir(tmp_dir.path()) {
            for entry in entries.flatten() {
                let p = entry.path();
                if p.is_file()
                    && p.file_name()
                        .unwrap_or_default()
                        .to_string_lossy()
                        .starts_with("icon")
                    && p.extension().is_some_and(|ext| ext == "png")
                    && let Ok(m) = p.metadata()
                {
                    generated.push((m.len(), p));
                }
            }
        }
        if !generated.is_empty() {
            generated.sort_by_key(|b| std::cmp::Reverse(b.0));
            fs::copy(&generated[0].1, &out_icon).ok();
            return Some(out_icon.to_string_lossy().to_string());
        }
    }
    None
}

fn regex_lite_sub_drive(path: &str) -> String {
    let s = path.replace('\\', "/");
    if s.len() >= 2 && s.chars().nth(1) == Some(':') {
        s[2..].to_string()
    } else {
        s
    }
}

mod md5 {
    const SHIFTS: [u32; 64] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9, 14, 20, 5,
        9, 14, 20, 5, 9, 14, 20, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 6, 10,
        15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    ];

    const TABLE_K: [u32; 64] = [
        0xd76a_a478,
        0xe8c7_b756,
        0x2420_70db,
        0xc1bd_ceee,
        0xf57c_0faf,
        0x4787_c62a,
        0xa830_4613,
        0xfd46_9501,
        0x6980_98d8,
        0x8b44_f7af,
        0xffff_5bb1,
        0x895c_d7be,
        0x6b90_1122,
        0xfd98_7193,
        0xa679_438e,
        0x49b4_0821,
        0xf61e_2562,
        0xc040_b340,
        0x265e_5a51,
        0xe9b6_c7aa,
        0xd62f_105d,
        0x0244_1453,
        0xd8a1_e681,
        0xe7d3_fbc8,
        0x21e1_cde6,
        0xc337_07d6,
        0xf4d5_0d87,
        0x455a_14ed,
        0xa9e3_e905,
        0xfcef_a3f8,
        0x676f_02d9,
        0x8d2a_4c8a,
        0xfffa_3942,
        0x8771_f681,
        0x6d9d_6122,
        0xfde5_380c,
        0xa4be_ea44,
        0x4bde_cfa9,
        0xf6bb_4b60,
        0xbebf_bc70,
        0x289b_7ec6,
        0xeaa1_27fa,
        0xd4ef_3085,
        0x0488_1d05,
        0xd9d4_d039,
        0xe6db_99e5,
        0x1fa2_7cf8,
        0xc4ac_5665,
        0xf429_2244,
        0x432a_ff97,
        0xab94_23a7,
        0xfc93_a039,
        0x655b_59c3,
        0x8f0c_cc92,
        0xffef_f47d,
        0x8584_5dd1,
        0x6fa8_7e4f,
        0xfe2c_e6e0,
        0xa301_4314,
        0x4e08_11a1,
        0xf753_7e82,
        0xbd3a_f235,
        0x2ad7_d2bb,
        0xeb86_d391,
    ];

    pub fn compute(input: &[u8]) -> [u8; 16] {
        let mut state_d = 0x1032_5476_u32;
        let mut state_c = 0x98ba_dcfe_u32;
        let mut state_b = 0xefcd_ab89_u32;
        let mut state_a = 0x6745_2301_u32;
        let mut msg = input.to_vec();
        let orig_bit_len = u64::try_from(input.len()).unwrap_or(0).wrapping_mul(8);
        msg.push(0x80);
        while (msg.len() % 64) != 56 {
            msg.push(0);
        }
        msg.extend_from_slice(&orig_bit_len.to_le_bytes());

        let (chunks, _) = msg.as_chunks::<64>();
        for chunk in chunks {
            let mut words = [0u32; 16];
            let (slices, _) = chunk.as_chunks::<4>();
            for (idx, slice) in slices.iter().enumerate() {
                words[idx] = u32::from_le_bytes(*slice);
            }
            let (mut acc_a, mut acc_b, mut acc_c, mut acc_d) = (state_a, state_b, state_c, state_d);

            for step in 0..64 {
                let (calc_f, word_idx) = match step {
                    0..=15 => ((acc_b & acc_c) | (!acc_b & acc_d), step),
                    16..=31 => ((acc_d & acc_b) | (!acc_d & acc_c), (5 * step + 1) % 16),
                    32..=47 => (acc_b ^ acc_c ^ acc_d, (3 * step + 5) % 16),
                    _ => (acc_c ^ (acc_b | !acc_d), (7 * step) % 16),
                };
                let prev_d = acc_d;
                acc_d = acc_c;
                acc_c = acc_b;
                acc_b = acc_b.wrapping_add(
                    (acc_a
                        .wrapping_add(calc_f)
                        .wrapping_add(TABLE_K[step])
                        .wrapping_add(words[word_idx]))
                    .rotate_left(SHIFTS[step]),
                );
                acc_a = prev_d;
            }
            state_a = state_a.wrapping_add(acc_a);
            state_b = state_b.wrapping_add(acc_b);
            state_c = state_c.wrapping_add(acc_c);
            state_d = state_d.wrapping_add(acc_d);
        }

        let mut out_bytes = [0u8; 16];
        out_bytes[0..4].copy_from_slice(&state_a.to_le_bytes());
        out_bytes[4..8].copy_from_slice(&state_b.to_le_bytes());
        out_bytes[8..12].copy_from_slice(&state_c.to_le_bytes());
        out_bytes[12..16].copy_from_slice(&state_d.to_le_bytes());
        out_bytes
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BindMode {
    Rw,
    Ro,
}

#[derive(Clone, Debug)]
pub struct BoundPath {
    pub host_path: String,
    pub mode: BindMode,
}

#[derive(Clone)]
pub struct PathsListWidget {
    container: gtk4::Box,
    list_box: gtk4::ListBox,
    items: Rc<RefCell<Vec<BoundPath>>>,
}

impl PathsListWidget {
    #[must_use]
    pub fn new(parent_window: &gtk4::Window) -> Self {
        let container = gtk4::Box::new(gtk4::Orientation::Vertical, 6);
        let header_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);

        let title_label = gtk4::Label::builder()
            .label("Каталоги:")
            .xalign(0.0)
            .hexpand(true)
            .build();
        header_box.append(&title_label);

        let btn_manual = gtk4::Button::with_label("+ Путь");
        header_box.append(&btn_manual);

        let btn_add = gtk4::Button::with_label("+ Обзор...");
        header_box.append(&btn_add);

        container.append(&header_box);

        let list_box = gtk4::ListBox::new();
        list_box.set_selection_mode(gtk4::SelectionMode::None);
        list_box.add_css_class("boxed-list");

        let scroll = gtk4::ScrolledWindow::builder()
            .min_content_height(100)
            .vexpand(true)
            .child(&list_box)
            .build();
        container.set_vexpand(true);
        container.append(&scroll);

        let items = Rc::new(RefCell::new(Vec::new()));

        let widget = Self {
            container,
            list_box,
            items,
        };

        // Connect Manual Path button
        let w_manual = widget.clone();
        btn_manual.connect_clicked(move |_| {
            w_manual.add_path("", BindMode::Rw);
        });

        // Connect Add Directory button
        let w_add = widget.clone();
        let win_add = parent_window.clone();
        btn_add.connect_clicked(move |_| {
            let dlg = gtk4::FileChooserNative::builder()
                .title("Выберите каталог для монтирования")
                .transient_for(&win_add)
                .action(gtk4::FileChooserAction::SelectFolder)
                .build();
            let w_folder = w_add.clone();
            dlg.connect_response(move |d, response| {
                if response == gtk4::ResponseType::Accept
                    && let Some(f) = d.file()
                    && let Some(path) = f.path()
                {
                    w_folder.add_path(&path.to_string_lossy(), BindMode::Rw);
                }
                d.destroy();
            });
            dlg.show();
        });

        widget
    }

    #[must_use]
    pub const fn widget(&self) -> &gtk4::Box {
        &self.container
    }

    pub fn add_path(&self, host_path: &str, mode: BindMode) {
        let trimmed = host_path.trim();
        let mut list = self.items.borrow_mut();
        if !trimmed.is_empty() && list.iter().any(|item| item.host_path == trimmed) {
            return; // Already in list
        }
        list.push(BoundPath {
            host_path: trimmed.to_string(),
            mode,
        });
        drop(list);

        self.rebuild_rows();
    }

    fn rebuild_rows(&self) {
        // Clear list_box
        while let Some(child) = self.list_box.first_child() {
            self.list_box.remove(&child);
        }

        let items_len = self.items.borrow().len();
        for idx in 0..items_len {
            let item = self.items.borrow()[idx].clone();
            let row_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
            row_box.set_margin_start(6);
            row_box.set_margin_end(6);
            row_box.set_margin_top(4);
            row_box.set_margin_bottom(4);

            let btn_mode = gtk4::Button::with_label(if item.mode == BindMode::Rw {
                "RW"
            } else {
                "RO"
            });
            btn_mode.set_tooltip_text(Some(
                "Переключить режим Чтение/Запись (RW) или Только Чтение (RO)",
            ));

            let w_mode = self.clone();
            btn_mode.connect_clicked(move |_| {
                let mut list = w_mode.items.borrow_mut();
                if idx < list.len() {
                    list[idx].mode = if list[idx].mode == BindMode::Rw {
                        BindMode::Ro
                    } else {
                        BindMode::Rw
                    };
                }
                drop(list);
                w_mode.rebuild_rows();
            });
            row_box.append(&btn_mode);

            let path_entry = gtk4::Entry::new();
            path_entry.set_text(&item.host_path);
            path_entry.set_placeholder_text(Some("/путь/к/каталогу"));
            path_entry.set_hexpand(true);

            let w_entry = self.clone();
            path_entry.connect_changed(move |e| {
                let mut list = w_entry.items.borrow_mut();
                if idx < list.len() {
                    list[idx].host_path = e.text().to_string();
                }
            });
            row_box.append(&path_entry);

            let btn_del = gtk4::Button::from_icon_name("user-trash-symbolic");
            btn_del.set_tooltip_text(Some("Удалить путь"));
            let w_del = self.clone();
            btn_del.connect_clicked(move |_| {
                let mut list = w_del.items.borrow_mut();
                if idx < list.len() {
                    list.remove(idx);
                }
                drop(list);
                w_del.rebuild_rows();
            });
            row_box.append(&btn_del);

            self.list_box.append(&row_box);
        }
    }

    #[must_use]
    pub fn get_flags(&self) -> Vec<String> {
        let mut flags = Vec::new();
        for item in self.items.borrow().iter() {
            let flag = if item.mode == BindMode::Rw {
                "--rw"
            } else {
                "--ro"
            };
            flags.push(flag.to_string());
            flags.push(item.host_path.clone());
        }
        flags
    }

    #[must_use]
    pub fn to_string_args(&self) -> String {
        let mut out = String::new();
        for item in self.items.borrow().iter() {
            let flag = if item.mode == BindMode::Rw {
                "--rw"
            } else {
                "--ro"
            };
            let escaped = item.host_path.replace('"', "\\\"");
            let _ = write!(out, "{flag} \"{escaped}\" ");
        }
        out.trim().to_string()
    }

    pub fn load_from_string_args(&self, raw: &str) {
        let mut list = self.items.borrow_mut();
        list.clear();
        let tokens = parse_cli_tokens(raw);
        let mut i = 0;
        while i < tokens.len() {
            if (tokens[i] == "--rw" || tokens[i] == "--ro") && i + 1 < tokens.len() {
                let mode = if tokens[i] == "--rw" {
                    BindMode::Rw
                } else {
                    BindMode::Ro
                };
                list.push(BoundPath {
                    host_path: tokens[i + 1].clone(),
                    mode,
                });
                i += 2;
            } else {
                i += 1;
            }
        }
        drop(list);
        self.rebuild_rows();
    }
}

fn parse_cli_tokens(input_str: &str) -> Vec<String> {
    let mut tokens = Vec::new();
    let mut cur = String::new();
    let mut in_quote = None;
    let mut escaped = false;
    for ch in input_str.chars() {
        if escaped {
            cur.push(ch);
            escaped = false;
            continue;
        }
        if ch == '\\' {
            escaped = true;
            continue;
        }
        match in_quote {
            Some(quote_ch) if ch == quote_ch => in_quote = None,
            None if ch == '"' || ch == '\'' => in_quote = Some(ch),
            None if ch.is_whitespace() => {
                if !cur.is_empty() {
                    tokens.push(std::mem::take(&mut cur));
                }
            }
            Some(_) | None => cur.push(ch),
        }
    }
    if !cur.is_empty() {
        tokens.push(cur);
    }
    tokens
}
