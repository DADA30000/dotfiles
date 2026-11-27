use gtk4::prelude::*;
use serde::Deserialize;
use serde_json::Value;
use std::cell::RefCell;
use std::collections::{BTreeMap, BTreeSet, HashSet};
use std::env;
use std::fmt::Write as _;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::rc::Rc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::thread;

use crate::{
    BindMode, PathsListWidget, RustHelpersConfig, expand_path_vars, read_json_value, xdg_subpath,
};

static EDIT_SEQ: AtomicU64 = AtomicU64::new(1);

#[derive(Clone, Debug, Deserialize)]
struct SbDbusSection {
    mode: String,
}

#[derive(Clone, Debug, Deserialize)]
struct SbSeccompSection {
    enable: bool,
    action: String,
    notify: String,
    allow: Vec<String>,
    deny: BTreeMap<String, BTreeMap<String, Vec<String>>>,
}

#[derive(Clone, Debug, Deserialize)]
struct SbConfigFile {
    network: String,
    wayland: String,
    x11: String,
    pulse: String,
    pipewire: String,
    microphone: String,
    webcam: Value,
    shm: String,
    tmp: String,
    dbus: SbDbusSection,
    seccomp: SbSeccompSection,
    bins: BTreeMap<String, String>,
    singbox_config: String,
    syscalls_file: String,
    #[serde(flatten)]
    flags: BTreeMap<String, Value>,
}

pub type SeccompDenyMap = BTreeMap<(String, String), Vec<String>>;
type SharedSeccompDenyMap = Rc<RefCell<SeccompDenyMap>>;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SbSeccompConfig {
    pub enable: bool,
    pub action: String,
    pub notify: String,
    pub allow: Vec<String>,
    pub deny: SeccompDenyMap,
}

#[derive(Clone, Debug)]
pub struct SbRunConfig {
    pub network: String,
    pub wayland: String,
    pub x11: String,
    pub pulse: String,
    pub pipewire: String,
    pub microphone: String,
    pub webcam: String,
    pub dbus: String,
    pub shm: String,
    pub tmp: String,
    pub hw: SandboxHwFlags,
    pub sec: SandboxSecurityFlags,
    pub runtime: SandboxRuntimeFlags,
    pub flatpak_portal: bool,
    pub seccomp: SbSeccompConfig,
    pub singbox_config: String,
    pub neovide_bin: String,
    pub syscalls: BTreeSet<String>,
}

fn load_single_source_config_value() -> Result<Value, String> {
    if let Ok(explicit) = env::var("SB_RUN_CONFIG")
        && !explicit.is_empty()
    {
        if explicit == "none" {
            return Err("SB_RUN_CONFIG=none is not supported in GUI (no config file)".into());
        }
        let ep = PathBuf::from(&explicit);
        if !ep.is_file() {
            return Err(format!("SB_RUN_CONFIG '{}' does not exist", ep.display()));
        }
        return read_json_value(&ep);
    }

    let candidates = [
        xdg_subpath(
            "XDG_CONFIG_HOME",
            ".config/sb-run/config.json",
            "sb-run/config.json",
        ),
        xdg_subpath(
            "XDG_DATA_HOME",
            ".local/share/sb-run/config.json",
            "sb-run/config.json",
        ),
    ];

    for path in candidates.into_iter().flatten() {
        if path.is_file() {
            return read_json_value(&path);
        }
    }
    Err("missing sb-run declarative config.json in XDG config/data home".into())
}

fn valid_seccomp_cond(cond_raw: &str) -> bool {
    let cond = cond_raw.trim();
    let Some(rest) = cond.strip_prefix("arg") else {
        return false;
    };
    let mut chars = rest.chars();
    let Some(arg_ch) = chars.next() else {
        return false;
    };
    if !matches!(arg_ch, '0'..='5') {
        return false;
    }
    let (u32_only, after_idx) = chars.as_str().strip_prefix("_u32").map_or_else(
        || (false, chars.as_str().trim_start()),
        |rem| (true, rem.trim_start()),
    );
    let ops = ["==", "!=", "!&", "<=", ">=", "&", "<", ">"];
    let Some(val_str) = ops
        .iter()
        .find_map(|op| after_idx.strip_prefix(op).map(str::trim))
    else {
        return false;
    };
    if val_str.is_empty() {
        return false;
    }
    let parsed = val_str
        .strip_prefix("0x")
        .or_else(|| val_str.strip_prefix("0X"))
        .map_or_else(
            || val_str.parse::<u64>(),
            |hex| u64::from_str_radix(hex, 16),
        );
    parsed.is_ok_and(|val| !u32_only || u32::try_from(val).is_ok())
}

#[must_use]
pub fn rule_syscall_name(raw: &str) -> &str {
    let after_prio = raw
        .trim()
        .strip_prefix('@')
        .and_then(|s| s.split_once(':'))
        .map_or_else(|| raw.trim(), |(_, rest)| rest.trim());
    after_prio
        .split_once(':')
        .map_or(after_prio, |(name, _)| name.trim())
}

impl SbRunConfig {
    /// Loads the declarative `sb-run` configuration and syscall table.
    ///
    /// # Errors
    ///
    /// Returns a descriptive error string if the config, syscall table, or required fields are missing.
    pub fn load() -> Result<Self, String> {
        let root_val = load_single_source_config_value()?;
        let parsed: SbConfigFile = serde_json::from_value(root_val)
            .map_err(|e| format!("invalid sb-run config schema: {e}"))?;

        let neovide_bin = parsed
            .bins
            .get("neovide")
            .filter(|s| !s.is_empty())
            .ok_or_else(|| "missing 'bins.neovide' in sb-run config".to_string())?
            .clone();

        let singbox_config_path = expand_path_vars(&parsed.singbox_config);
        if !singbox_config_path.is_file() {
            return Err(format!(
                "missing default singbox_config '{}'",
                singbox_config_path.display()
            ));
        }
        let syscalls_path = expand_path_vars(&parsed.syscalls_file);
        let sys_raw = fs::read_to_string(&syscalls_path)
            .map_err(|e| format!("missing syscalls_file '{}': {e}", syscalls_path.display()))?;
        let sys_val: Value = serde_json::from_str(&sys_raw)
            .map_err(|e| format!("invalid syscalls JSON '{}': {e}", syscalls_path.display()))?;

        let mut syscalls = BTreeSet::new();
        for arch in ["x86_64", "i386"] {
            if let Some(obj) = sys_val.get(arch).and_then(Value::as_object) {
                for key in obj.keys() {
                    syscalls.insert(key.clone());
                }
            }
        }
        if syscalls.is_empty() {
            return Err(format!(
                "syscalls_file '{}' contains no syscalls",
                syscalls_path.display()
            ));
        }

        let bool_flag = |key: &str| -> Result<bool, String> {
            parsed
                .flags
                .get(key)
                .and_then(Value::as_bool)
                .ok_or_else(|| format!("missing bool '{key}' in sb-run config"))
        };

        let mut deny = BTreeMap::new();
        for (notify, actions) in parsed.seccomp.deny {
            for (action, rules) in actions {
                if !rules.is_empty() {
                    deny.insert((notify.clone(), action), rules);
                }
            }
        }

        Ok(Self {
            network: parsed.network,
            wayland: parsed.wayland,
            x11: parsed.x11,
            pulse: parsed.pulse,
            pipewire: parsed.pipewire,
            microphone: parsed.microphone,
            webcam: match parsed.webcam {
                Value::String(s) => s,
                Value::Number(n) => n.to_string(),
                _ => "off".into(),
            },
            dbus: parsed.dbus.mode,
            shm: parsed.shm,
            tmp: parsed.tmp,
            hw: SandboxHwFlags {
                gpu: bool_flag("gpu")?,
                gamepad: bool_flag("gamepad")?,
            },
            sec: SandboxSecurityFlags {
                landlock: bool_flag("landlock")?,
                seccomp: parsed.seccomp.enable,
                portals: bool_flag("portals")?,
            },
            runtime: SandboxRuntimeFlags {
                tmpfs: bool_flag("tmpfs")?,
                share_pid: bool_flag("share_pid")?,
                vpnify: bool_flag("vpnify")?,
            },
            flatpak_portal: bool_flag("flatpak_portal")?,
            seccomp: SbSeccompConfig {
                enable: parsed.seccomp.enable,
                action: parsed.seccomp.action,
                notify: parsed.seccomp.notify,
                allow: parsed.seccomp.allow,
                deny,
            },
            singbox_config: singbox_config_path.to_string_lossy().to_string(),
            neovide_bin,
            syscalls,
        })
    }

    #[must_use]
    pub fn load_or_exit() -> Self {
        match Self::load() {
            Ok(cfg) => cfg,
            Err(err) => {
                eprintln!("[sb-gui] Error: {err}");
                std::process::exit(1);
            }
        }
    }

    #[must_use]
    pub fn is_valid_seccomp_rule(&self, raw: &str) -> bool {
        let s = raw.trim();
        if s.is_empty() {
            return false;
        }
        let rem = if let Some(after_at) = s.strip_prefix('@') {
            let Some((prio_str, rest)) = after_at.split_once(':') else {
                return false;
            };
            if prio_str.trim().parse::<i32>().is_err() {
                return false;
            }
            rest.trim()
        } else {
            s
        };

        let (syscall, conds_opt) = match rem.split_once(':') {
            Some((name, cond_part)) => (name.trim(), Some(cond_part.trim())),
            None => (rem, None),
        };
        if syscall.is_empty() || !self.syscalls.contains(syscall) {
            return false;
        }
        if let Some(cond_part) = conds_opt {
            if cond_part.is_empty() {
                return false;
            }
            if !cond_part.split("&&").all(valid_seccomp_cond) {
                return false;
            }
        }
        true
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SandboxHwFlags {
    pub gpu: bool,
    pub gamepad: bool,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SandboxSecurityFlags {
    pub landlock: bool,
    pub seccomp: bool,
    pub portals: bool,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SandboxRuntimeFlags {
    pub tmpfs: bool,
    pub share_pid: bool,
    pub vpnify: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SeccompDiff {
    pub clear: bool,
    pub allow: Vec<String>,
    pub block: Vec<String>,
    pub deny: BTreeMap<(String, String), Vec<String>>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SandboxFormData {
    pub network: String,
    pub singbox_config: String,
    pub wayland: String,
    pub x11: String,
    pub pulse: String,
    pub pipewire: String,
    pub microphone: String,
    pub webcam: String,
    pub dbus: String,
    pub dbus_args: String,
    pub shm: String,
    pub tmp: String,
    pub hw: SandboxHwFlags,
    pub sec: SandboxSecurityFlags,
    pub runtime: SandboxRuntimeFlags,
    pub flatpak_portal: bool,
    pub seccomp_action: String,
    pub seccomp_notify: String,
    pub seccomp_allowed: Vec<String>,
    pub seccomp_deny: BTreeMap<(String, String), Vec<String>>,
    pub bridges: Vec<String>,
    pub bwrap_args: String,
    pub extra_env: String,
    pub extra_paths: String,
}

impl SandboxFormData {
    #[must_use]
    pub fn from_decl(decl: &SbRunConfig) -> Self {
        Self {
            network: decl.network.clone(),
            singbox_config: String::new(),
            wayland: decl.wayland.clone(),
            x11: decl.x11.clone(),
            pulse: decl.pulse.clone(),
            pipewire: decl.pipewire.clone(),
            microphone: decl.microphone.clone(),
            webcam: decl.webcam.clone(),
            dbus: decl.dbus.clone(),
            dbus_args: String::new(),
            shm: decl.shm.clone(),
            tmp: decl.tmp.clone(),
            hw: decl.hw,
            sec: decl.sec,
            runtime: decl.runtime,
            flatpak_portal: decl.flatpak_portal,
            seccomp_action: decl.seccomp.action.clone(),
            seccomp_notify: decl.seccomp.notify.clone(),
            seccomp_allowed: decl.seccomp.allow.clone(),
            seccomp_deny: decl.seccomp.deny.clone(),
            bridges: Vec::new(),
            bwrap_args: String::new(),
            extra_env: String::new(),
            extra_paths: String::new(),
        }
    }

    #[must_use]
    pub fn umu_defaults(decl: &SbRunConfig, ui_cfg: &RustHelpersConfig) -> Self {
        let umu_def = &ui_cfg.sandbox_ui.umu_defaults;
        let mut data = Self::from_decl(decl);
        data.x11.clone_from(&umu_def.x11);
        data.hw.gpu = umu_def.gpu;
        data.sec.landlock = umu_def.landlock;
        data.flatpak_portal = umu_def.portal.flatpak_portal;
        data.runtime.tmpfs = umu_def.tmpfs;
        for s in &umu_def.seccomp_allow {
            if !data.seccomp_allowed.iter().any(|x| x == s) {
                data.seccomp_allowed.push(s.clone());
            }
        }
        data
    }

    #[must_use]
    pub fn seccomp_diff(&self, decl: &SbRunConfig) -> SeccompDiff {
        let def_set: HashSet<&str> = decl.seccomp.allow.iter().map(String::as_str).collect();
        let cur_set: HashSet<&str> = self.seccomp_allowed.iter().map(String::as_str).collect();

        let removed: Vec<&String> = decl
            .seccomp
            .allow
            .iter()
            .filter(|s| !cur_set.contains(s.as_str()))
            .collect();
        let cur_syscalls: HashSet<&str> = self
            .seccomp_allowed
            .iter()
            .map(|s| rule_syscall_name(s))
            .collect();

        let needs_clear = (self.seccomp_allowed.is_empty() && !decl.seccomp.allow.is_empty())
            || removed.iter().any(|r| {
                r.starts_with('@') || r.contains(':') || cur_syscalls.contains(rule_syscall_name(r))
            });

        let (allow, block) = if needs_clear {
            (self.seccomp_allowed.clone(), Vec::new())
        } else {
            let add: Vec<String> = self
                .seccomp_allowed
                .iter()
                .filter(|s| !def_set.contains(s.as_str()))
                .cloned()
                .collect();
            let blk: Vec<String> = removed.into_iter().cloned().collect();
            (add, blk)
        };

        let mut deny = BTreeMap::new();
        for (bucket, rules) in &self.seccomp_deny {
            let def_rules: HashSet<&str> = decl
                .seccomp
                .deny
                .get(bucket)
                .map(|v| v.iter().map(String::as_str).collect())
                .unwrap_or_default();
            let added: Vec<String> = rules
                .iter()
                .filter(|r| !def_rules.contains(r.as_str()))
                .cloned()
                .collect();
            if !added.is_empty() {
                deny.insert(bucket.clone(), added);
            }
        }

        SeccompDiff {
            clear: needs_clear,
            allow,
            block,
            deny,
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum SandboxUiMode {
    Standalone,
    Umu,
}

#[derive(Clone)]
pub struct BridgesListWidget {
    container: gtk4::Box,
    list_box: gtk4::ListBox,
    rules: Rc<RefCell<Vec<String>>>,
}

fn create_bridge_row(
    rule: &str,
    rules: &Rc<RefCell<Vec<String>>>,
    list_box: &gtk4::ListBox,
) -> gtk4::ListBoxRow {
    let mut parts = rule.splitn(3, ':');
    let dir = parts.next().unwrap_or("from");
    let addr = parts.next().unwrap_or("127.0.0.1");
    let port_list = parts.next().unwrap_or("");

    let row_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
    let dir_lbl = if dir == "from" {
        "[Из песочницы -> Хост]"
    } else {
        "[Хост -> Песочница]"
    };
    let label = gtk4::Label::builder()
        .label(format!("{dir_lbl} {addr}:[{port_list}]"))
        .xalign(0.0)
        .hexpand(true)
        .build();
    let btn_del = gtk4::Button::with_label("✕");

    row_box.append(&label);
    row_box.append(&btn_del);

    let row = gtk4::ListBoxRow::new();
    row.set_child(Some(&row_box));

    let rc_del = Rc::clone(rules);
    let lc_del = list_box.clone();
    let row_del = row.clone();
    btn_del.connect_clicked(move |_| {
        let idx = row_del.index();
        if let Ok(pos) = usize::try_from(idx)
            && pos < rc_del.borrow().len()
        {
            rc_del.borrow_mut().remove(pos);
        }
        lc_del.remove(&row_del);
    });

    row
}

impl BridgesListWidget {
    #[must_use]
    pub fn new(ui_cfg: &RustHelpersConfig) -> Self {
        let container = gtk4::Box::new(gtk4::Orientation::Vertical, 6);
        let rules = Rc::new(RefCell::new(Vec::new()));

        let title = gtk4::Label::builder()
            .label("Сетевые мосты TCP (rust-bridge):")
            .xalign(0.0)
            .margin_top(4)
            .build();
        container.append(&title);

        let input_row = gtk4::Box::new(gtk4::Orientation::Horizontal, 6);

        let cmb_dir = gtk4::ComboBoxText::new();
        cmb_dir.append(Some("from"), "Из песочницы");
        cmb_dir.append(Some("to"), "В песочницу");
        cmb_dir.set_active_id(Some("from"));
        input_row.append(&cmb_dir);

        let ent_addr = gtk4::Entry::new();
        ent_addr.set_text(&ui_cfg.sandbox_ui.bridge_default_address);
        ent_addr.set_width_chars(11);
        input_row.append(&ent_addr);

        let ent_ports = gtk4::Entry::new();
        ent_ports.set_placeholder_text(Some(&ui_cfg.sandbox_ui.bridge_ports_placeholder));
        ent_ports.set_hexpand(true);
        input_row.append(&ent_ports);

        let btn_add = gtk4::Button::with_label("+ Добавить");
        input_row.append(&btn_add);

        let list_box = gtk4::ListBox::new();
        list_box.add_css_class("boxed-list");

        let w = Self {
            container,
            list_box,
            rules,
        };

        for preset in &ui_cfg.sandbox_ui.bridge_presets {
            let btn_preset = gtk4::Button::with_label(&preset.label);
            let w_preset = w.clone();
            let rule = preset.rule.clone();
            btn_preset.connect_clicked(move |_| {
                w_preset.add_rule(&rule);
            });
            input_row.append(&btn_preset);
        }

        w.container.append(&input_row);
        w.container.append(&w.list_box);

        let w_add = w.clone();
        btn_add.connect_clicked(move |_| {
            let dir = cmb_dir.active_id().unwrap_or_else(|| "from".into());
            let addr = ent_addr.text().to_string();
            let ports = ent_ports.text().to_string();
            if !ports.trim().is_empty() {
                w_add.add_rule(&format!("{dir}:{addr}:{ports}"));
                ent_ports.set_text("");
            }
        });

        w
    }

    pub fn add_rule(&self, rule_str: &str) {
        let trimmed = rule_str.trim();
        if trimmed.is_empty() {
            return;
        }
        self.rules.borrow_mut().push(trimmed.to_string());
        let row = create_bridge_row(trimmed, &self.rules, &self.list_box);
        self.list_box.append(&row);
    }

    pub fn load_rules(&self, items: &[String]) {
        self.rules.borrow_mut().clear();
        while let Some(child) = self.list_box.first_child() {
            self.list_box.remove(&child);
        }
        for item in items {
            self.add_rule(item);
        }
    }

    #[must_use]
    pub const fn widget(&self) -> &gtk4::Box {
        &self.container
    }

    #[must_use]
    pub fn get_rules(&self) -> Vec<String> {
        self.rules.borrow().clone()
    }
}

fn show_error_dialog(parent: &gtk4::Window, title: &str, body: &str) {
    let dlg = gtk4::MessageDialog::builder()
        .transient_for(parent)
        .modal(true)
        .message_type(gtk4::MessageType::Error)
        .buttons(gtk4::ButtonsType::Ok)
        .text(title)
        .secondary_text(body)
        .build();
    dlg.connect_response(|d, _| d.destroy());
    dlg.present();
}

fn create_temp_edit_file(prefix: &str, content: &str) -> Result<PathBuf, String> {
    let runtime = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into());
    let seq = EDIT_SEQ.fetch_add(1, Ordering::Relaxed);
    let pid = std::process::id();
    let path = PathBuf::from(runtime).join(format!("{prefix}-{pid}-{seq}.json"));
    fs::write(&path, content).map_err(|e| format!("failed to write '{}': {e}", path.display()))?;
    Ok(path)
}

fn spawn_neovide_json_editor<F>(
    parent: &gtk4::Window,
    neovide_bin: &str,
    prefix: &str,
    initial_json: &str,
    on_saved: F,
) where
    F: Fn(String) + 'static,
{
    let tmp_path = match create_temp_edit_file(prefix, initial_json) {
        Ok(p) => p,
        Err(e) => {
            show_error_dialog(parent, "Ошибка создания временного файла", &e);
            return;
        }
    };

    let (tx, rx) = std::sync::mpsc::channel::<Result<String, String>>();
    let bin = neovide_bin.to_string();
    let path_thread = tmp_path;

    thread::spawn(move || {
        let status = Command::new(&bin).arg(&path_thread).status();
        let res = match status {
            Ok(s) if s.success() => fs::read_to_string(&path_thread)
                .map_err(|e| format!("Не удалось прочитать файл: {e}")),
            Ok(s) => Err(format!("Neovide завершился с кодом {:?}", s.code())),
            Err(e) => Err(format!("Не удалось запустить '{bin}': {e}")),
        };
        let _ = fs::remove_file(&path_thread);
        let _ = tx.send(res);
    });

    let p_win = parent.clone();
    glib::timeout_add_local(std::time::Duration::from_millis(120), move || {
        match rx.try_recv() {
            Ok(Ok(edited)) => {
                on_saved(edited);
                glib::ControlFlow::Break
            }
            Ok(Err(err)) => {
                show_error_dialog(&p_win, "Ошибка редактора Neovide", &err);
                glib::ControlFlow::Break
            }
            Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
            Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
        }
    });
}

fn read_singbox_source_pretty(decl: &SbRunConfig, current: &str) -> Result<String, String> {
    let trimmed = current.trim();
    let raw = if trimmed.is_empty() {
        fs::read_to_string(&decl.singbox_config)
            .map_err(|e| format!("Не удалось прочитать '{}': {e}", decl.singbox_config))?
    } else if trimmed.starts_with('{') {
        trimmed.to_string()
    } else {
        fs::read_to_string(trimmed).map_err(|e| format!("Не удалось прочитать '{trimmed}': {e}"))?
    };

    let val: Value =
        serde_json::from_str(&raw).map_err(|e| format!("Некорректный JSON sing-box: {e}"))?;
    serde_json::to_string_pretty(&val).map_err(|e| format!("Ошибка сериализации JSON: {e}"))
}

fn open_singbox_neovide_editor(parent: &gtk4::Window, decl: &SbRunConfig, entry: &gtk4::Entry) {
    let current = entry.text().to_string();
    let pretty = match read_singbox_source_pretty(decl, &current) {
        Ok(s) => s,
        Err(e) => {
            show_error_dialog(parent, "Ошибка конфигурации sing-box", &e);
            return;
        }
    };

    let default_compact = fs::read_to_string(&decl.singbox_config)
        .ok()
        .and_then(|s| serde_json::from_str::<Value>(&s).ok())
        .and_then(|v| serde_json::to_string(&v).ok())
        .unwrap_or_default();

    let p_win = parent.clone();
    let ent = entry.clone();
    spawn_neovide_json_editor(
        parent,
        &decl.neovide_bin,
        "sb-singbox-edit",
        &pretty,
        move |edited| match serde_json::from_str::<Value>(&edited) {
            Ok(val) => {
                if let Ok(compact) = serde_json::to_string(&val) {
                    if compact == default_compact {
                        ent.set_text("");
                    } else {
                        ent.set_text(&compact);
                    }
                }
            }
            Err(e) => {
                show_error_dialog(
                    &p_win,
                    "Некорректный JSON sing-box",
                    &format!("Изменения отклонены: {e}"),
                );
            }
        },
    );
}

fn update_seccomp_summary_label(
    btn: &gtk4::Button,
    allowed: &Rc<RefCell<Vec<String>>>,
    deny: &SharedSeccompDenyMap,
) {
    let allow_len = allowed.borrow().len();
    let deny_len: usize = deny.borrow().values().map(Vec::len).sum();
    btn.set_label(&format!(
        "Syscalls (allow: {allow_len}, deny: {deny_len})..."
    ));
}

fn build_syscall_list_rows(
    list_box: &gtk4::ListBox,
    allowed: &Rc<RefCell<Vec<String>>>,
    deny: &SharedSeccompDenyMap,
    query: &str,
    btn_label: &gtk4::Button,
) {
    while let Some(child) = list_box.first_child() {
        list_box.remove(&child);
    }
    let q = query.trim().to_lowercase();
    update_seccomp_summary_label(btn_label, allowed, deny);

    let items = allowed.borrow().clone();
    for name in items {
        if !q.is_empty() && !name.to_lowercase().contains(&q) {
            continue;
        }
        let row_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
        row_box.set_margin_start(8);
        row_box.set_margin_end(8);
        row_box.set_margin_top(4);
        row_box.set_margin_bottom(4);

        let lbl = gtk4::Label::builder()
            .label(&name)
            .xalign(0.0)
            .hexpand(true)
            .build();
        let btn_del = gtk4::Button::with_label("✕");
        row_box.append(&lbl);
        row_box.append(&btn_del);

        let row = gtk4::ListBoxRow::new();
        row.set_child(Some(&row_box));
        list_box.append(&row);

        let a_rc = Rc::clone(allowed);
        let d_rc = Rc::clone(deny);
        let lb_c = list_box.clone();
        let btn_c = btn_label.clone();
        let name_del = name.clone();
        let q_del = q.clone();
        btn_del.connect_clicked(move |_| {
            a_rc.borrow_mut().retain(|s| s != &name_del);
            build_syscall_list_rows(&lb_c, &a_rc, &d_rc, &q_del, &btn_c);
        });
    }
}

fn build_deny_list_rows(
    list_box: &gtk4::ListBox,
    allowed: &Rc<RefCell<Vec<String>>>,
    deny: &SharedSeccompDenyMap,
    query: &str,
    btn_label: &gtk4::Button,
) {
    while let Some(child) = list_box.first_child() {
        list_box.remove(&child);
    }
    let q = query.trim().to_lowercase();
    update_seccomp_summary_label(btn_label, allowed, deny);

    let entries: Vec<((String, String), String)> = deny
        .borrow()
        .iter()
        .flat_map(|(k, rules)| rules.iter().map(move |r| (k.clone(), r.clone())))
        .collect();

    for ((notify, action), rule) in entries {
        let display = format!("[{notify}:{action}] {rule}");
        if !q.is_empty() && !display.to_lowercase().contains(&q) {
            continue;
        }
        let row_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
        row_box.set_margin_start(8);
        row_box.set_margin_end(8);
        row_box.set_margin_top(4);
        row_box.set_margin_bottom(4);

        let lbl = gtk4::Label::builder()
            .label(&display)
            .xalign(0.0)
            .hexpand(true)
            .build();
        let btn_del = gtk4::Button::with_label("✕");
        row_box.append(&lbl);
        row_box.append(&btn_del);

        let row = gtk4::ListBoxRow::new();
        row.set_child(Some(&row_box));
        list_box.append(&row);

        let a_rc = Rc::clone(allowed);
        let d_rc = Rc::clone(deny);
        let lb_c = list_box.clone();
        let btn_c = btn_label.clone();
        let key_del = (notify, action);
        let rule_del = rule;
        let q_del = q.clone();
        btn_del.connect_clicked(move |_| {
            let mut map = d_rc.borrow_mut();
            if let Some(vec) = map.get_mut(&key_del) {
                vec.retain(|s| s != &rule_del);
                if vec.is_empty() {
                    map.remove(&key_del);
                }
            }
            drop(map);
            build_deny_list_rows(&lb_c, &a_rc, &d_rc, &q_del, &btn_c);
        });
    }
}

fn attach_syscall_completion(entry: &gtk4::Entry, syscalls: &BTreeSet<String>) {
    let store = gtk4::ListStore::new(&[glib::Type::STRING]);
    for name in syscalls {
        store.insert_with_values(None, &[(0, name)]);
    }
    let completion = gtk4::EntryCompletion::new();
    completion.set_model(Some(&store));
    completion.set_text_column(0);
    completion.set_minimum_key_length(1);
    #[allow(deprecated)]
    entry.set_completion(Some(&completion));
}

fn build_seccomp_add_row(
    decl: &SbRunConfig,
    allowed: &Rc<RefCell<Vec<String>>>,
    deny: &SharedSeccompDenyMap,
    list_box: &gtk4::ListBox,
    search: &gtk4::SearchEntry,
    btn_summary: &gtk4::Button,
    lbl_err: &gtk4::Label,
) -> gtk4::Box {
    let add_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 6);
    let ent_sys = gtk4::Entry::builder()
        .placeholder_text("Правило (напр. ptrace, @10:clone:arg0!&0x7e020080)...")
        .hexpand(true)
        .build();
    attach_syscall_completion(&ent_sys, &decl.syscalls);

    let btn_add = gtk4::Button::with_label("+ Разрешить");
    add_box.append(&ent_sys);
    add_box.append(&btn_add);

    let a_add = Rc::clone(allowed);
    let d_add = Rc::clone(deny);
    let lb_add = list_box.clone();
    let summary_add = btn_summary.clone();
    let s_add = search.clone();
    let decl_add = decl.clone();
    let err_lbl = lbl_err.clone();
    btn_add.connect_clicked(move |_| {
        let name = ent_sys.text().trim().to_string();
        if name.is_empty() {
            return;
        }
        if !decl_add.is_valid_seccomp_rule(&name) {
            err_lbl.set_markup(&format!(
                "<span foreground='red'>Некорректное правило или неизвестный syscall: {name}</span>"
            ));
            return;
        }
        let mut list = a_add.borrow_mut();
        if !list.contains(&name) {
            list.push(name);
        }
        drop(list);
        err_lbl.set_text("");
        ent_sys.set_text("");
        build_syscall_list_rows(&lb_add, &a_add, &d_add, &s_add.text(), &summary_add);
    });

    add_box
}

struct SeccompDenyTab {
    container: gtk4::Box,
    list_box: gtk4::ListBox,
    search: gtk4::SearchEntry,
}

fn build_seccomp_deny_tab(
    decl: &SbRunConfig,
    allowed: &Rc<RefCell<Vec<String>>>,
    deny: &SharedSeccompDenyMap,
    btn_summary: &gtk4::Button,
) -> SeccompDenyTab {
    let vbox = gtk4::Box::new(gtk4::Orientation::Vertical, 6);
    let search = gtk4::SearchEntry::builder()
        .placeholder_text("Поиск среди запрещенных...")
        .build();
    vbox.append(&search);

    let add_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 6);
    let cmb_notify = gtk4::ComboBoxText::new();
    for (id, name) in [("none", "none"), ("log", "log"), ("notify", "notify")] {
        cmb_notify.append(Some(id), name);
    }
    cmb_notify.set_active_id(Some("none"));

    let cmb_action = gtk4::ComboBoxText::new();
    for a in [
        "eperm", "enosys", "eacces", "einval", "enotsup", "kill", "trap",
    ] {
        cmb_action.append(Some(a), a);
    }
    cmb_action.set_active_id(Some("eperm"));

    let ent_rule = gtk4::Entry::builder()
        .placeholder_text("Правило (напр. @10:ioctl:arg1==0x5412)...")
        .hexpand(true)
        .build();
    attach_syscall_completion(&ent_rule, &decl.syscalls);

    let btn_add = gtk4::Button::with_label("+ Запретить");
    add_box.append(&cmb_notify);
    add_box.append(&cmb_action);
    add_box.append(&ent_rule);
    add_box.append(&btn_add);
    vbox.append(&add_box);

    let lbl_err = gtk4::Label::builder().xalign(0.0).build();
    vbox.append(&lbl_err);

    let list_box = gtk4::ListBox::new();
    list_box.set_selection_mode(gtk4::SelectionMode::None);
    list_box.add_css_class("boxed-list");
    let scroll = gtk4::ScrolledWindow::builder()
        .vexpand(true)
        .child(&list_box)
        .build();
    vbox.append(&scroll);

    build_deny_list_rows(&list_box, allowed, deny, "", btn_summary);

    let lb_s = list_box.clone();
    let a_s = Rc::clone(allowed);
    let d_s = Rc::clone(deny);
    let sum_s = btn_summary.clone();
    search.connect_search_changed(move |s| {
        build_deny_list_rows(&lb_s, &a_s, &d_s, &s.text(), &sum_s);
    });

    let a_add = Rc::clone(allowed);
    let d_add = Rc::clone(deny);
    let lb_add = list_box.clone();
    let s_add = search.clone();
    let sum_add = btn_summary.clone();
    let decl_add = decl.clone();
    btn_add.connect_clicked(move |_| {
        let rule = ent_rule.text().trim().to_string();
        if rule.is_empty() {
            return;
        }
        if !decl_add.is_valid_seccomp_rule(&rule) {
            lbl_err.set_markup(&format!(
                "<span foreground='red'>Некорректное правило или неизвестный syscall: {rule}</span>"
            ));
            return;
        }
        let notify = cmb_notify
            .active_id()
            .map_or_else(|| "none".into(), |s| s.to_string());
        let action = cmb_action
            .active_id()
            .map_or_else(|| "eperm".into(), |s| s.to_string());
        let mut map = d_add.borrow_mut();
        let list = map.entry((notify, action)).or_default();
        if !list.contains(&rule) {
            list.push(rule);
        }
        drop(map);
        lbl_err.set_text("");
        ent_rule.set_text("");
        build_deny_list_rows(&lb_add, &a_add, &d_add, &s_add.text(), &sum_add);
    });

    SeccompDenyTab {
        container: vbox,
        list_box,
        search,
    }
}

#[derive(Clone)]
struct SeccompEditorState {
    action: Rc<RefCell<String>>,
    notify: Rc<RefCell<String>>,
    allowed: Rc<RefCell<Vec<String>>>,
    deny: SharedSeccompDenyMap,
}

struct SeccompAllowTab {
    container: gtk4::Box,
    list_box: gtk4::ListBox,
    search: gtk4::SearchEntry,
}

fn build_seccomp_policy_row(
    state: &SeccompEditorState,
) -> (gtk4::Box, gtk4::ComboBoxText, gtk4::ComboBoxText) {
    let policy_row = gtk4::Box::new(gtk4::Orientation::Horizontal, 10);
    let (act_box, cmb_act) = create_labelled_combo(
        "Действие:",
        &[
            ("eperm", "EPERM (1)"),
            ("enosys", "ENOSYS (38)"),
            ("eacces", "EACCES (13)"),
            ("einval", "EINVAL (22)"),
            ("enotsup", "ENOTSUP (95)"),
            ("kill", "KILL (SIGKILL)"),
            ("trap", "TRAP (SIGSYS)"),
        ],
        &state.action.borrow(),
    );
    let (not_box, cmb_not) = create_labelled_combo(
        "Уведомление:",
        &[
            ("notify", "Уведомление (notify-send)"),
            ("log", "Журнал (logs/seccomp.log)"),
            ("none", "Тихо (none)"),
        ],
        &state.notify.borrow(),
    );
    policy_row.append(&act_box);
    policy_row.append(&not_box);

    let act_rc = Rc::clone(&state.action);
    cmb_act.connect_changed(move |c| {
        if let Some(id) = c.active_id() {
            *act_rc.borrow_mut() = id.to_string();
        }
    });
    let not_rc = Rc::clone(&state.notify);
    cmb_not.connect_changed(move |c| {
        if let Some(id) = c.active_id() {
            *not_rc.borrow_mut() = id.to_string();
        }
    });

    (policy_row, cmb_act, cmb_not)
}

fn build_seccomp_allow_tab(
    decl: &SbRunConfig,
    state: &SeccompEditorState,
    btn_summary: &gtk4::Button,
) -> SeccompAllowTab {
    let allow_vbox = gtk4::Box::new(gtk4::Orientation::Vertical, 6);
    let search = gtk4::SearchEntry::builder()
        .placeholder_text("Поиск среди разрешенных...")
        .build();
    allow_vbox.append(&search);

    let lbl_status = gtk4::Label::builder().xalign(0.0).build();
    let list_box = gtk4::ListBox::new();
    list_box.set_selection_mode(gtk4::SelectionMode::None);
    list_box.add_css_class("boxed-list");

    allow_vbox.append(&build_seccomp_add_row(
        decl,
        &state.allowed,
        &state.deny,
        &list_box,
        &search,
        btn_summary,
        &lbl_status,
    ));
    allow_vbox.append(&lbl_status);

    let scroll = gtk4::ScrolledWindow::builder()
        .vexpand(true)
        .child(&list_box)
        .build();
    allow_vbox.append(&scroll);
    build_syscall_list_rows(&list_box, &state.allowed, &state.deny, "", btn_summary);

    let lb_search = list_box.clone();
    let a_search = Rc::clone(&state.allowed);
    let d_search = Rc::clone(&state.deny);
    let summary_search = btn_summary.clone();
    search.connect_search_changed(move |s| {
        build_syscall_list_rows(&lb_search, &a_search, &d_search, &s.text(), &summary_search);
    });

    SeccompAllowTab {
        container: allow_vbox,
        list_box,
        search,
    }
}

fn open_seccomp_editor_dialog(
    parent: &gtk4::Window,
    decl: &SbRunConfig,
    ui_cfg: &RustHelpersConfig,
    state: &SeccompEditorState,
    btn_summary: &gtk4::Button,
    default_preset: &SandboxFormData,
) {
    let dlg = gtk4::Window::builder()
        .title("Настройка Seccomp")
        .default_width(ui_cfg.sandbox_ui.seccomp_dialog_width)
        .default_height(ui_cfg.sandbox_ui.seccomp_dialog_height)
        .transient_for(parent)
        .modal(true)
        .build();

    let vbox = gtk4::Box::new(gtk4::Orientation::Vertical, 8);
    vbox.set_margin_top(12);
    vbox.set_margin_bottom(12);
    vbox.set_margin_start(12);
    vbox.set_margin_end(12);
    dlg.set_child(Some(&vbox));

    let (policy_row, cmb_act, cmb_not) = build_seccomp_policy_row(state);
    vbox.append(&policy_row);

    let stack = gtk4::Stack::builder().vexpand(true).build();
    let switcher = gtk4::StackSwitcher::builder().stack(&stack).build();
    vbox.append(&switcher);
    vbox.append(&stack);

    let allow_tab = build_seccomp_allow_tab(decl, state, btn_summary);
    let deny_tab = build_seccomp_deny_tab(decl, &state.allowed, &state.deny, btn_summary);
    stack.add_titled(&allow_tab.container, Some("allow"), "Разрешенные (Allow)");
    stack.add_titled(&deny_tab.container, Some("deny"), "Запрещенные (Deny)");

    let bbox = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
    bbox.set_halign(gtk4::Align::End);
    let btn_nvim = gtk4::Button::with_label("Neovide (JSON)");
    let btn_reset = gtk4::Button::with_label("По умолчанию");
    let btn_done = gtk4::Button::with_label("Готово");
    btn_done.add_css_class("suggested-action");
    bbox.append(&btn_nvim);
    bbox.append(&btn_reset);
    bbox.append(&btn_done);
    vbox.append(&bbox);

    connect_seccomp_neovide_btn(
        &btn_nvim,
        &SeccompNeovideCtx {
            dlg: &dlg,
            decl,
            stack: &stack,
            state,
            allow_lb: &allow_tab.list_box,
            deny_lb: &deny_tab.list_box,
            btn_summary,
            allow_search: &allow_tab.search,
            deny_search: &deny_tab.search,
        },
    );

    let rst_state = state.clone();
    let lb_rst = allow_tab.list_box;
    let d_lb_rst = deny_tab.list_box;
    let summary_reset = btn_summary.clone();
    let preset_allow = default_preset.seccomp_allowed.clone();
    let preset_deny = default_preset.seccomp_deny.clone();
    let preset_act = default_preset.seccomp_action.clone();
    let preset_not = default_preset.seccomp_notify.clone();
    let allow_search = allow_tab.search;
    let deny_search = deny_tab.search;
    btn_reset.connect_clicked(move |_| {
        (*rst_state.allowed.borrow_mut()).clone_from(&preset_allow);
        (*rst_state.deny.borrow_mut()).clone_from(&preset_deny);
        (*rst_state.action.borrow_mut()).clone_from(&preset_act);
        (*rst_state.notify.borrow_mut()).clone_from(&preset_not);
        cmb_act.set_active_id(Some(&preset_act));
        cmb_not.set_active_id(Some(&preset_not));
        build_syscall_list_rows(
            &lb_rst,
            &rst_state.allowed,
            &rst_state.deny,
            &allow_search.text(),
            &summary_reset,
        );
        build_deny_list_rows(
            &d_lb_rst,
            &rst_state.allowed,
            &rst_state.deny,
            &deny_search.text(),
            &summary_reset,
        );
    });

    let dlg_c = dlg.clone();
    btn_done.connect_clicked(move |_| dlg_c.close());
    dlg.present();
}

struct SeccompNeovideCtx<'a> {
    dlg: &'a gtk4::Window,
    decl: &'a SbRunConfig,
    stack: &'a gtk4::Stack,
    state: &'a SeccompEditorState,
    allow_lb: &'a gtk4::ListBox,
    deny_lb: &'a gtk4::ListBox,
    btn_summary: &'a gtk4::Button,
    allow_search: &'a gtk4::SearchEntry,
    deny_search: &'a gtk4::SearchEntry,
}

fn parse_deny_json_map(
    raw: &str,
    decl: &SbRunConfig,
) -> Result<SeccompDenyMap, (&'static str, String)> {
    let parsed: BTreeMap<String, BTreeMap<String, Vec<String>>> =
        serde_json::from_str(raw).map_err(|e| ("Некорректный JSON", e.to_string()))?;
    let mut flat = BTreeMap::new();
    for (notify, actions) in parsed {
        if !matches!(notify.as_str(), "none" | "log" | "notify") {
            return Err((
                "Некорректный notify",
                format!("Неизвестный режим notify '{notify}'"),
            ));
        }
        for (action, rules) in actions {
            if !matches!(
                action.as_str(),
                "eperm" | "enosys" | "eacces" | "einval" | "enotsup" | "kill" | "trap"
            ) {
                return Err((
                    "Некорректный action",
                    format!("Неизвестное действие '{action}'"),
                ));
            }
            for rule in &rules {
                if !decl.is_valid_seccomp_rule(rule) {
                    return Err((
                        "Некорректное правило",
                        format!("Некорректное правило '{rule}'"),
                    ));
                }
            }
            if !rules.is_empty() {
                flat.insert((notify.clone(), action), rules);
            }
        }
    }
    Ok(flat)
}

fn launch_deny_neovide_editor(
    dlg_win: &gtk4::Window,
    decl: &SbRunConfig,
    state: &SeccompEditorState,
    allow_lb: &gtk4::ListBox,
    deny_lb: &gtk4::ListBox,
    btn_summary: &gtk4::Button,
    deny_search: &gtk4::SearchEntry,
) {
    let mut nested: BTreeMap<String, BTreeMap<String, Vec<String>>> = BTreeMap::new();
    for ((n, a), rules) in &*state.deny.borrow() {
        nested
            .entry(n.clone())
            .or_default()
            .insert(a.clone(), rules.clone());
    }
    let Ok(pretty) = serde_json::to_string_pretty(&nested) else {
        return;
    };
    let state_cb = state.clone();
    let allow_lb_cb = allow_lb.clone();
    let deny_lb_cb = deny_lb.clone();
    let btn_cb = btn_summary.clone();
    let filter_cb = deny_search.clone();
    let win_cb = dlg_win.clone();
    let cfg_cb = decl.clone();
    spawn_neovide_json_editor(
        dlg_win,
        &decl.neovide_bin,
        "sb-seccomp-deny-edit",
        &pretty,
        move |edited| match parse_deny_json_map(&edited, &cfg_cb) {
            Ok(flat) => {
                *state_cb.deny.borrow_mut() = flat;
                build_deny_list_rows(
                    &deny_lb_cb,
                    &state_cb.allowed,
                    &state_cb.deny,
                    &filter_cb.text(),
                    &btn_cb,
                );
                build_syscall_list_rows(
                    &allow_lb_cb,
                    &state_cb.allowed,
                    &state_cb.deny,
                    "",
                    &btn_cb,
                );
            }
            Err((title, msg)) => show_error_dialog(&win_cb, title, &msg),
        },
    );
}

fn launch_allow_neovide_editor(
    dlg_win: &gtk4::Window,
    decl: &SbRunConfig,
    state: &SeccompEditorState,
    allow_lb: &gtk4::ListBox,
    btn_summary: &gtk4::Button,
    allow_search: &gtk4::SearchEntry,
) {
    let Ok(pretty) = serde_json::to_string_pretty(&*state.allowed.borrow()) else {
        return;
    };
    let state_cb = state.clone();
    let lb_cb = allow_lb.clone();
    let btn_cb = btn_summary.clone();
    let filter_cb = allow_search.clone();
    let win_cb = dlg_win.clone();
    let cfg_cb = decl.clone();
    spawn_neovide_json_editor(
        dlg_win,
        &decl.neovide_bin,
        "sb-seccomp-edit",
        &pretty,
        move |edited| match serde_json::from_str::<Vec<String>>(&edited) {
            Ok(new_list) => {
                for name in &new_list {
                    if !cfg_cb.is_valid_seccomp_rule(name) {
                        show_error_dialog(
                            &win_cb,
                            "Некорректное правило",
                            &format!("Правило '{name}' некорректно или неизвестный syscall."),
                        );
                        return;
                    }
                }
                *state_cb.allowed.borrow_mut() = new_list;
                build_syscall_list_rows(
                    &lb_cb,
                    &state_cb.allowed,
                    &state_cb.deny,
                    &filter_cb.text(),
                    &btn_cb,
                );
            }
            Err(e) => show_error_dialog(&win_cb, "Некорректный JSON", &e.to_string()),
        },
    );
}

fn connect_seccomp_neovide_btn(btn_nvim: &gtk4::Button, ctx: &SeccompNeovideCtx<'_>) {
    let state = ctx.state.clone();
    let allow_lb = ctx.allow_lb.clone();
    let deny_lb = ctx.deny_lb.clone();
    let sum_btn = ctx.btn_summary.clone();
    let allow_search = ctx.allow_search.clone();
    let deny_search = ctx.deny_search.clone();
    let dlg_win = ctx.dlg.clone();
    let decl_cfg = ctx.decl.clone();
    let stack = ctx.stack.clone();
    btn_nvim.connect_clicked(move |_| {
        if stack.visible_child_name().as_deref() == Some("deny") {
            launch_deny_neovide_editor(
                &dlg_win,
                &decl_cfg,
                &state,
                &allow_lb,
                &deny_lb,
                &sum_btn,
                &deny_search,
            );
        } else {
            launch_allow_neovide_editor(
                &dlg_win,
                &decl_cfg,
                &state,
                &allow_lb,
                &sum_btn,
                &allow_search,
            );
        }
    });
}

#[must_use]
pub fn create_labelled_combo(
    label_text: &str,
    options: &[(&str, &str)],
    default_id: &str,
) -> (gtk4::Box, gtk4::ComboBoxText) {
    let hbox = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
    let lbl = gtk4::Label::builder().label(label_text).xalign(0.0).build();
    hbox.append(&lbl);

    let cmb = gtk4::ComboBoxText::new();
    for (id, name) in options {
        cmb.append(Some(id), name);
    }
    if !cmb.set_active_id(Some(default_id)) {
        cmb.set_active(Some(0));
    }
    cmb.set_hexpand(true);
    hbox.append(&cmb);

    (hbox, cmb)
}

#[must_use]
pub fn detect_video_nodes() -> Vec<(u32, String)> {
    let mut nodes = Vec::new();
    let sys_dir = Path::new("/sys/class/video4linux");
    if let Ok(entries) = fs::read_dir(sys_dir) {
        for entry in entries.flatten() {
            let file_name = entry.file_name();
            let name_str = file_name.to_string_lossy();
            if let Some(idx_str) = name_str.strip_prefix("video")
                && let Ok(idx) = idx_str.parse::<u32>()
            {
                let desc = fs::read_to_string(entry.path().join("name"))
                    .map_or_else(|_| format!("Video {idx}"), |s| s.trim().to_string());
                nodes.push((idx, desc));
            }
        }
    }
    nodes.sort_by_key(|&(idx, _)| idx);
    nodes
}

#[derive(Clone)]
pub struct SandboxOptionsWidget {
    container: gtk4::Box,
    decl: SbRunConfig,
    mode: SandboxUiMode,
    pub combo_net: gtk4::ComboBoxText,
    pub entry_singbox: gtk4::Entry,
    pub combo_wayland: Option<gtk4::ComboBoxText>,
    pub combo_x11: gtk4::ComboBoxText,
    pub combo_pulse: gtk4::ComboBoxText,
    pub combo_pipewire: gtk4::ComboBoxText,
    pub combo_microphone: gtk4::ComboBoxText,
    pub toggle_gpu: gtk4::CheckButton,
    pub toggle_gamepad: gtk4::CheckButton,
    pub combo_webcam_mode: gtk4::ComboBoxText,
    pub webcam_nodes_box: gtk4::Box,
    pub webcam_node_toggles: Vec<(u32, gtk4::CheckButton)>,
    pub paths_widget: PathsListWidget,
    pub combo_dbus: gtk4::ComboBoxText,
    pub toggle_portals: gtk4::CheckButton,
    pub toggle_flatpak_portal: gtk4::CheckButton,
    pub toggle_landlock: gtk4::CheckButton,
    pub toggle_seccomp: gtk4::CheckButton,
    pub btn_seccomp_edit: gtk4::Button,
    pub seccomp_action: Rc<RefCell<String>>,
    pub seccomp_notify: Rc<RefCell<String>>,
    pub seccomp_allowed: Rc<RefCell<Vec<String>>>,
    pub seccomp_deny: SharedSeccompDenyMap,
    pub toggle_tmpfs: gtk4::CheckButton,
    pub toggle_share_pid: gtk4::CheckButton,
    pub toggle_vpnify: gtk4::CheckButton,
    pub combo_shm: gtk4::ComboBoxText,
    pub combo_tmp: gtk4::ComboBoxText,
    pub bridges_widget: BridgesListWidget,
    pub entry_dbus: gtk4::Entry,
    pub entry_bwrap: gtk4::Entry,
    pub entry_env: gtk4::Entry,
}

struct SingboxRowControls {
    row: gtk4::Box,
    entry: gtk4::Entry,
}

fn build_singbox_row(
    parent: &gtk4::Window,
    decl: &SbRunConfig,
    initial_val: &str,
) -> SingboxRowControls {
    let row = gtk4::Box::new(gtk4::Orientation::Horizontal, 6);
    let lbl = gtk4::Label::builder()
        .label("Конфиг Sing-Box:")
        .xalign(0.0)
        .build();
    let entry = gtk4::Entry::builder()
        .placeholder_text("По умолчанию, путь к JSON или строка {...}")
        .hexpand(true)
        .build();
    entry.set_text(initial_val);

    let btn_file = gtk4::Button::with_label("Файл...");
    let btn_nvim = gtk4::Button::with_label("Neovide");
    let btn_reset = gtk4::Button::with_label("✕");
    btn_reset.set_tooltip_text(Some("Сбросить к конфигу по умолчанию"));

    row.append(&lbl);
    row.append(&entry);
    row.append(&btn_file);
    row.append(&btn_nvim);
    row.append(&btn_reset);

    let w_file = parent.clone();
    let e_file = entry.clone();
    btn_file.connect_clicked(move |_| {
        let filter = gtk4::FileFilter::new();
        filter.set_name(Some("JSON (*.json)"));
        filter.add_pattern("*.json");
        let dlg = gtk4::FileChooserNative::builder()
            .title("Выберите JSON-конфиг sing-box")
            .transient_for(&w_file)
            .action(gtk4::FileChooserAction::Open)
            .build();
        dlg.add_filter(&filter);
        let ee = e_file.clone();
        dlg.connect_response(move |d, resp| {
            if resp == gtk4::ResponseType::Accept
                && let Some(f) = d.file()
                && let Some(p) = f.path()
            {
                ee.set_text(&p.to_string_lossy());
            }
            d.destroy();
        });
        dlg.show();
    });

    let w_nv = parent.clone();
    let d_nv = decl.clone();
    let e_nv = entry.clone();
    btn_nvim.connect_clicked(move |_| {
        open_singbox_neovide_editor(&w_nv, &d_nv, &e_nv);
    });

    let e_rst = entry.clone();
    btn_reset.connect_clicked(move |_| {
        e_rst.set_text("");
    });

    SingboxRowControls { row, entry }
}

struct SubsysGridWidgets {
    grid: gtk4::Grid,
    combo_wayland: Option<gtk4::ComboBoxText>,
    combo_x11: gtk4::ComboBoxText,
    combo_pulse: gtk4::ComboBoxText,
    combo_pipewire: gtk4::ComboBoxText,
    combo_microphone: gtk4::ComboBoxText,
    toggle_gpu: gtk4::CheckButton,
    toggle_gamepad: gtk4::CheckButton,
    combo_webcam_mode: gtk4::ComboBoxText,
    webcam_nodes_box: gtk4::Box,
    webcam_node_toggles: Vec<(u32, gtk4::CheckButton)>,
}

fn attach_display_and_audio_combos(
    grid: &gtk4::Grid,
    mode: SandboxUiMode,
    init: &SandboxFormData,
) -> (
    Option<gtk4::ComboBoxText>,
    gtk4::ComboBoxText,
    gtk4::ComboBoxText,
    gtk4::ComboBoxText,
    i32,
) {
    let mut row = 0;
    let (cmb_wl, cmb_x11) = if mode == SandboxUiMode::Standalone {
        let (wl_box, wl) = create_labelled_combo(
            "Wayland:",
            &[
                ("sandboxed", "Изолированный (way-secure)"),
                ("passthrough", "Прямой (хост)"),
                ("off", "Отключен"),
            ],
            &init.wayland,
        );
        let (x11_box, x11) = create_labelled_combo(
            "X11:",
            &[
                ("off", "Отключен"),
                ("passthrough", "Прямой (/tmp/.X11-unix)"),
                ("sandboxed", "Изолированный (xwayland-satellite)"),
            ],
            &init.x11,
        );
        grid.attach(&wl_box, 0, row, 1, 1);
        grid.attach(&x11_box, 1, row, 1, 1);
        row += 1;
        (Some(wl), x11)
    } else {
        let (x11_box, x11) = create_labelled_combo(
            "XWayland (X11):",
            &[
                ("passthrough", "Прямой доступ (Хост X11)"),
                ("sandboxed", "Изолированный (xwayland-satellite)"),
                ("off", "Отключен"),
            ],
            &init.x11,
        );
        grid.attach(&x11_box, 0, row, 2, 1);
        row += 1;
        (None, x11)
    };

    let (pw_box, cmb_pw) = create_labelled_combo(
        "PipeWire:",
        &[
            ("sandboxed", "Изолированный"),
            ("passthrough", "Прямой (хост)"),
            ("off", "Отключен"),
        ],
        &init.pipewire,
    );
    let (pulse_box, cmb_pulse) = create_labelled_combo(
        "PulseAudio:",
        &[
            ("sandboxed", "Изолированный"),
            ("passthrough", "Прямой (хост)"),
            ("off", "Отключен"),
        ],
        &init.pulse,
    );
    grid.attach(&pw_box, 0, row, 1, 1);
    grid.attach(&pulse_box, 1, row, 1, 1);
    row += 1;
    (cmb_wl, cmb_x11, cmb_pw, cmb_pulse, row)
}

fn build_subsys_grid(mode: SandboxUiMode, init: &SandboxFormData) -> SubsysGridWidgets {
    let grid = gtk4::Grid::new();
    grid.set_column_spacing(12);
    grid.set_row_spacing(8);

    let combo_wayland = attach_display_and_audio_combos(&grid, mode, init);
    let mut row = combo_wayland.4;

    let (mic_box, cmb_mic) = create_labelled_combo(
        "Микрофон:",
        &[
            ("off", "Отключен"),
            ("portal", "Портал (AccessDialog)"),
            ("allow", "Разрешен"),
        ],
        &init.microphone,
    );
    grid.attach(&mic_box, 0, row, 2, 1);
    row += 1;

    let chk_gpu = gtk4::CheckButton::with_label("GPU / 3D Ускорение");
    chk_gpu.set_active(init.hw.gpu);
    let chk_gamepad = gtk4::CheckButton::with_label("Геймпад (/dev/input)");
    chk_gamepad.set_active(init.hw.gamepad);
    grid.attach(&chk_gpu, 0, row, 1, 1);
    grid.attach(&chk_gamepad, 1, row, 1, 1);
    row += 1;

    let init_webcam_mode = if init.webcam == "portal" {
        "portal"
    } else if init.webcam == "off" || init.webcam.is_empty() {
        "off"
    } else {
        "nodes"
    };

    let (cam_box, cmb_cam) = create_labelled_combo(
        "Веб-камера:",
        &[
            ("off", "Отключена"),
            ("portal", "Портал (pw-v4l2)"),
            ("nodes", "Устройства (/dev/video*)"),
        ],
        init_webcam_mode,
    );
    grid.attach(&cam_box, 0, row, 2, 1);
    row += 1;

    let detected_nodes = detect_video_nodes();
    let nodes_box = gtk4::Box::new(gtk4::Orientation::Vertical, 4);
    nodes_box.set_margin_start(16);
    nodes_box.set_margin_bottom(6);

    let mut node_toggles = Vec::new();
    if detected_nodes.is_empty() {
        let lbl = gtk4::Label::builder()
            .label("Устройства /dev/video не обнаружены")
            .xalign(0.0)
            .css_classes(["dim-label"])
            .build();
        nodes_box.append(&lbl);
    } else {
        let active_set: HashSet<u32> =
            if init.webcam == "portal" || init.webcam == "off" || init.webcam.is_empty() {
                HashSet::new()
            } else {
                init.webcam
                    .split(',')
                    .filter_map(|s| s.trim().parse::<u32>().ok())
                    .collect()
            };

        for (idx, desc) in detected_nodes {
            let chk = gtk4::CheckButton::builder()
                .label(format!("/dev/video{idx}: {desc}"))
                .active(active_set.contains(&idx))
                .build();
            nodes_box.append(&chk);
            node_toggles.push((idx, chk));
        }
    }

    let is_nodes = cmb_cam.active_id().as_deref() == Some("nodes");
    nodes_box.set_visible(is_nodes);

    let nodes_box_clone = nodes_box.clone();
    cmb_cam.connect_changed(move |c| {
        let is_nodes_selected = c.active_id().as_deref() == Some("nodes");
        nodes_box_clone.set_visible(is_nodes_selected);
    });

    grid.attach(&nodes_box, 0, row, 2, 1);

    SubsysGridWidgets {
        grid,
        combo_wayland: combo_wayland.0,
        combo_x11: combo_wayland.1,
        combo_pipewire: combo_wayland.2,
        combo_pulse: combo_wayland.3,
        combo_microphone: cmb_mic,
        toggle_gpu: chk_gpu,
        toggle_gamepad: chk_gamepad,
        combo_webcam_mode: cmb_cam,
        webcam_nodes_box: nodes_box,
        webcam_node_toggles: node_toggles,
    }
}

struct AdvWidgets {
    expander: gtk4::Expander,
    combo_dbus: gtk4::ComboBoxText,
    toggle_portals: gtk4::CheckButton,
    toggle_flatpak_portal: gtk4::CheckButton,
    toggle_landlock: gtk4::CheckButton,
    toggle_seccomp: gtk4::CheckButton,
    btn_seccomp_edit: gtk4::Button,
    seccomp_state: SeccompEditorState,
    toggle_tmpfs: gtk4::CheckButton,
    toggle_share_pid: gtk4::CheckButton,
    toggle_vpnify: gtk4::CheckButton,
    combo_shm: gtk4::ComboBoxText,
    combo_tmp: gtk4::ComboBoxText,
    bridges_widget: BridgesListWidget,
    entry_dbus: gtk4::Entry,
    entry_bwrap: gtk4::Entry,
    entry_env: gtk4::Entry,
}

fn append_labeled_entry(
    parent: &gtk4::Box,
    label: &str,
    placeholder: &str,
    initial: &str,
) -> gtk4::Entry {
    let entry = gtk4::Entry::new();
    entry.set_placeholder_text(Some(placeholder));
    entry.set_text(initial);
    parent.append(
        &gtk4::Label::builder()
            .label(label)
            .xalign(0.0)
            .margin_top(4)
            .build(),
    );
    parent.append(&entry);
    entry
}

fn build_seccomp_controls(
    parent: &gtk4::Window,
    decl: &SbRunConfig,
    ui_cfg: &RustHelpersConfig,
    mode: SandboxUiMode,
    init: &SandboxFormData,
) -> (
    gtk4::Box,
    gtk4::CheckButton,
    gtk4::Button,
    SeccompEditorState,
) {
    let seccomp_box = gtk4::Box::new(gtk4::Orientation::Horizontal, 8);
    let chk_seccomp = gtk4::CheckButton::with_label("Seccomp фильтр");
    chk_seccomp.set_active(init.sec.seccomp);
    let seccomp_state = SeccompEditorState {
        action: Rc::new(RefCell::new(init.seccomp_action.clone())),
        notify: Rc::new(RefCell::new(init.seccomp_notify.clone())),
        allowed: Rc::new(RefCell::new(init.seccomp_allowed.clone())),
        deny: Rc::new(RefCell::new(init.seccomp_deny.clone())),
    };
    let btn_seccomp_edit = gtk4::Button::new();
    update_seccomp_summary_label(
        &btn_seccomp_edit,
        &seccomp_state.allowed,
        &seccomp_state.deny,
    );
    btn_seccomp_edit.set_sensitive(init.sec.seccomp);
    seccomp_box.append(&chk_seccomp);
    seccomp_box.append(&btn_seccomp_edit);

    let b_btn = btn_seccomp_edit.clone();
    chk_seccomp.connect_toggled(move |c| b_btn.set_sensitive(c.is_active()));

    let preset_defaults = if mode == SandboxUiMode::Umu {
        SandboxFormData::umu_defaults(decl, ui_cfg)
    } else {
        SandboxFormData::from_decl(decl)
    };
    let w_sec = parent.clone();
    let d_sec = decl.clone();
    let u_sec = ui_cfg.clone();
    let st_sec = seccomp_state.clone();
    let b_sec_lbl = btn_seccomp_edit.clone();
    btn_seccomp_edit.connect_clicked(move |_| {
        open_seccomp_editor_dialog(
            &w_sec,
            &d_sec,
            &u_sec,
            &st_sec,
            &b_sec_lbl,
            &preset_defaults,
        );
    });

    (seccomp_box, chk_seccomp, btn_seccomp_edit, seccomp_state)
}

struct AdvGridControls {
    grid: gtk4::Grid,
    combo_dbus: gtk4::ComboBoxText,
    toggle_portals: gtk4::CheckButton,
    toggle_flatpak_portal: gtk4::CheckButton,
    toggle_landlock: gtk4::CheckButton,
    toggle_tmpfs: gtk4::CheckButton,
    toggle_share_pid: gtk4::CheckButton,
    toggle_vpnify: gtk4::CheckButton,
    combo_shm: gtk4::ComboBoxText,
    combo_tmp: gtk4::ComboBoxText,
}

fn build_adv_toggles_grid(mode: SandboxUiMode, init: &SandboxFormData) -> AdvGridControls {
    let grid = gtk4::Grid::new();
    grid.set_column_spacing(14);
    grid.set_row_spacing(8);

    let (dbus_box, combo_dbus) = create_labelled_combo(
        "D-Bus:",
        &[
            ("sandboxed", "Изолированный (Прокси)"),
            ("passthrough", "Прямой (хост)"),
            ("off", "Отключен"),
        ],
        &init.dbus,
    );
    grid.attach(&dbus_box, 0, 0, 1, 1);

    let toggle_portals = gtk4::CheckButton::with_label("Порталы XDG (MIME)");
    toggle_portals.set_active(init.sec.portals);
    grid.attach(&toggle_portals, 1, 0, 1, 1);

    let toggle_landlock = gtk4::CheckButton::with_label("Landlock (сигналы)");
    toggle_landlock.set_active(init.sec.landlock);
    grid.attach(&toggle_landlock, 0, 1, 1, 1);

    let tmpfs_label = if mode == SandboxUiMode::Umu {
        "Одноразовый дом (Tmpfs)"
    } else {
        "Одноразовая среда (Tmpfs)"
    };
    let toggle_tmpfs = gtk4::CheckButton::with_label(tmpfs_label);
    toggle_tmpfs.set_active(init.runtime.tmpfs);
    grid.attach(&toggle_tmpfs, 1, 1, 1, 1);

    let toggle_share_pid = gtk4::CheckButton::with_label("Разделять PID (Share PID)");
    toggle_share_pid.set_active(init.runtime.share_pid);
    grid.attach(&toggle_share_pid, 0, 2, 1, 1);

    let toggle_vpnify = gtk4::CheckButton::with_label("VPN (vpnify)");
    toggle_vpnify.set_active(init.runtime.vpnify);
    grid.attach(&toggle_vpnify, 1, 2, 1, 1);

    let (shm_box, combo_shm) = create_labelled_combo(
        "/dev/shm:",
        &[
            ("sandboxed", "Изолированный"),
            ("passthrough", "Прямой (хост)"),
        ],
        &init.shm,
    );
    grid.attach(&shm_box, 0, 3, 1, 1);

    let (tmp_box, combo_tmp) = create_labelled_combo(
        "/tmp:",
        &[
            ("sandboxed", "Изолированный"),
            ("passthrough", "Прямой (хост)"),
        ],
        &init.tmp,
    );
    grid.attach(&tmp_box, 1, 3, 1, 1);

    let toggle_flatpak_portal = gtk4::CheckButton::with_label("Flatpak Portal (Zypak/PV)");
    toggle_flatpak_portal.set_active(init.flatpak_portal);
    grid.attach(&toggle_flatpak_portal, 0, 4, 2, 1);

    AdvGridControls {
        grid,
        combo_dbus,
        toggle_portals,
        toggle_flatpak_portal,
        toggle_landlock,
        toggle_tmpfs,
        toggle_share_pid,
        toggle_vpnify,
        combo_shm,
        combo_tmp,
    }
}

fn build_adv_section(
    parent: &gtk4::Window,
    decl: &SbRunConfig,
    ui_cfg: &RustHelpersConfig,
    mode: SandboxUiMode,
    init: &SandboxFormData,
) -> AdvWidgets {
    let adv_box = gtk4::Box::new(gtk4::Orientation::Vertical, 8);
    adv_box.set_margin_top(6);
    adv_box.set_margin_bottom(6);
    adv_box.set_margin_start(4);
    adv_box.set_margin_end(4);

    let g = build_adv_toggles_grid(mode, init);
    let adv_grid = g.grid;

    let (seccomp_box, chk_seccomp, btn_seccomp_edit, seccomp_state) =
        build_seccomp_controls(parent, decl, ui_cfg, mode, init);
    adv_grid.attach(&seccomp_box, 0, 4, 2, 1);

    adv_box.append(&adv_grid);
    let bridges_widget = BridgesListWidget::new(ui_cfg);
    bridges_widget.load_rules(&init.bridges);
    adv_box.append(bridges_widget.widget());

    let dbus_entry = append_labeled_entry(
        &adv_box,
        "Дополнительные аргументы D-Bus:",
        "--dbus-talk=org.freedesktop.Notifications --dbus-own=org.example.App",
        &init.dbus_args,
    );
    let bwrap_entry = append_labeled_entry(
        &adv_box,
        "Дополнительные аргументы Bubblewrap:",
        "Например: --cap-add CAP_SYS_PTRACE",
        &init.bwrap_args,
    );
    let env_entry = append_labeled_entry(
        &adv_box,
        "Переменные среды (--env):",
        "KEY=VAL KEY2=VAL2",
        &init.extra_env,
    );

    let expander = gtk4::Expander::builder()
        .label("Дополнительные настройки")
        .child(&adv_box)
        .build();

    AdvWidgets {
        expander,
        combo_dbus: g.combo_dbus,
        toggle_portals: g.toggle_portals,
        toggle_flatpak_portal: g.toggle_flatpak_portal,
        toggle_landlock: g.toggle_landlock,
        toggle_seccomp: chk_seccomp,
        btn_seccomp_edit,
        seccomp_state,
        toggle_tmpfs: g.toggle_tmpfs,
        toggle_share_pid: g.toggle_share_pid,
        toggle_vpnify: g.toggle_vpnify,
        combo_shm: g.combo_shm,
        combo_tmp: g.combo_tmp,
        bridges_widget,
        entry_dbus: dbus_entry,
        entry_bwrap: bwrap_entry,
        entry_env: env_entry,
    }
}

fn push_webcam_args(args: &mut Vec<String>, webcam: &str) {
    args.push("--webcam".into());
    if webcam == "portal" {
        args.push("portal".into());
    } else if webcam == "auto" {
        args.push("auto".into());
    } else if webcam != "off" && !webcam.is_empty() {
        args.push("off".into());
        for node in webcam.split(',') {
            let node = node.trim();
            if !node.is_empty() {
                args.push("--dev".into());
                args.push(format!("/dev/video{node}"));
            }
        }
    } else {
        args.push("off".into());
    }
}

fn push_seccomp_args(args: &mut Vec<String>, d: &SandboxFormData, decl: &SbRunConfig) {
    if !d.sec.seccomp {
        args.push("--no-seccomp".into());
        return;
    }
    args.push("--seccomp".into());
    if d.seccomp_action != decl.seccomp.action {
        args.push("--seccomp-action".into());
        args.push(d.seccomp_action.clone());
    }
    if d.seccomp_notify != decl.seccomp.notify {
        args.push("--seccomp-notify".into());
        args.push(d.seccomp_notify.clone());
    }
    let diff = d.seccomp_diff(decl);
    if diff.clear {
        args.push("--seccomp-clear".into());
    }
    if !diff.allow.is_empty() {
        args.push("--seccomp-allow".into());
        args.push(diff.allow.join(","));
    }
    if !diff.block.is_empty() {
        args.push("--seccomp-block".into());
        args.push(diff.block.join(","));
    }
    for ((notify, action), rules) in diff.deny {
        args.push("--seccomp-deny".into());
        args.push(format!("{notify}:{action}:{}", rules.join(",")));
    }
}

impl SandboxOptionsWidget {
    #[must_use]
    pub fn new(
        parent: &gtk4::Window,
        decl: &SbRunConfig,
        ui_cfg: &RustHelpersConfig,
        mode: SandboxUiMode,
        initial: Option<&SandboxFormData>,
    ) -> Self {
        let defaults = if mode == SandboxUiMode::Umu {
            SandboxFormData::umu_defaults(decl, ui_cfg)
        } else {
            SandboxFormData::from_decl(decl)
        };
        let init = initial.unwrap_or(&defaults);

        let container = gtk4::Box::new(gtk4::Orientation::Vertical, 10);

        let (net_box, cmb_net) = create_labelled_combo(
            "Сеть:",
            &[
                ("sandboxed", "Изолированная (Pasta)"),
                ("singbox", "VPN Туннель (Sing-Box)"),
                ("passthrough", "Прямая (Хост)"),
                ("off", "Отключена"),
            ],
            &init.network,
        );
        container.append(&net_box);

        let sb_controls = build_singbox_row(parent, decl, &init.singbox_config);
        sb_controls.row.set_visible(init.network == "singbox");
        container.append(&sb_controls.row);

        let sb_row_vis = sb_controls.row;
        cmb_net.connect_changed(move |c| {
            sb_row_vis.set_visible(c.active_id().as_deref() == Some("singbox"));
        });

        let sub = build_subsys_grid(mode, init);
        container.append(&sub.grid);

        let paths_widget = PathsListWidget::new(parent);
        if !init.extra_paths.trim().is_empty() {
            paths_widget.load_from_string_args(&init.extra_paths);
        }
        container.append(paths_widget.widget());

        let adv = build_adv_section(parent, decl, ui_cfg, mode, init);
        container.append(&adv.expander);

        Self {
            container,
            decl: decl.clone(),
            mode,
            combo_net: cmb_net,
            entry_singbox: sb_controls.entry,
            combo_wayland: sub.combo_wayland,
            combo_x11: sub.combo_x11,
            combo_pulse: sub.combo_pulse,
            combo_pipewire: sub.combo_pipewire,
            combo_microphone: sub.combo_microphone,
            toggle_gpu: sub.toggle_gpu,
            toggle_gamepad: sub.toggle_gamepad,
            combo_webcam_mode: sub.combo_webcam_mode,
            webcam_nodes_box: sub.webcam_nodes_box,
            webcam_node_toggles: sub.webcam_node_toggles,
            paths_widget,
            combo_dbus: adv.combo_dbus,
            toggle_portals: adv.toggle_portals,
            toggle_flatpak_portal: adv.toggle_flatpak_portal,
            toggle_landlock: adv.toggle_landlock,
            toggle_seccomp: adv.toggle_seccomp,
            btn_seccomp_edit: adv.btn_seccomp_edit,
            seccomp_action: adv.seccomp_state.action,
            seccomp_notify: adv.seccomp_state.notify,
            seccomp_allowed: adv.seccomp_state.allowed,
            seccomp_deny: adv.seccomp_state.deny,
            toggle_tmpfs: adv.toggle_tmpfs,
            toggle_share_pid: adv.toggle_share_pid,
            toggle_vpnify: adv.toggle_vpnify,
            combo_shm: adv.combo_shm,
            combo_tmp: adv.combo_tmp,
            bridges_widget: adv.bridges_widget,
            entry_dbus: adv.entry_dbus,
            entry_bwrap: adv.entry_bwrap,
            entry_env: adv.entry_env,
        }
    }

    #[must_use]
    pub const fn widget(&self) -> &gtk4::Box {
        &self.container
    }

    #[must_use]
    pub const fn decl(&self) -> &SbRunConfig {
        &self.decl
    }

    #[must_use]
    pub fn get_data(&self) -> SandboxFormData {
        let combo_val = |c: &gtk4::ComboBoxText, fallback: &str| -> String {
            c.active_id()
                .map_or_else(|| fallback.to_string(), |s| s.to_string())
        };
        SandboxFormData {
            network: combo_val(&self.combo_net, &self.decl.network),
            singbox_config: self.entry_singbox.text().trim().to_string(),
            wayland: self.combo_wayland.as_ref().map_or_else(
                || self.decl.wayland.clone(),
                |c| combo_val(c, &self.decl.wayland),
            ),
            x11: combo_val(&self.combo_x11, &self.decl.x11),
            pulse: combo_val(&self.combo_pulse, &self.decl.pulse),
            pipewire: combo_val(&self.combo_pipewire, &self.decl.pipewire),
            microphone: combo_val(&self.combo_microphone, &self.decl.microphone),
            webcam: match self.combo_webcam_mode.active_id().as_deref() {
                Some("portal") => "portal".to_string(),
                Some("nodes") => {
                    let active: Vec<String> = self
                        .webcam_node_toggles
                        .iter()
                        .filter(|(_, btn)| btn.is_active())
                        .map(|(idx, _)| idx.to_string())
                        .collect();
                    if active.is_empty() {
                        "off".to_string()
                    } else {
                        active.join(",")
                    }
                }
                _ => "off".to_string(),
            },
            dbus: combo_val(&self.combo_dbus, &self.decl.dbus),
            dbus_args: self.entry_dbus.text().to_string(),
            shm: combo_val(&self.combo_shm, &self.decl.shm),
            tmp: combo_val(&self.combo_tmp, &self.decl.tmp),
            hw: SandboxHwFlags {
                gpu: self.toggle_gpu.is_active(),
                gamepad: self.toggle_gamepad.is_active(),
            },
            sec: SandboxSecurityFlags {
                landlock: self.toggle_landlock.is_active(),
                seccomp: self.toggle_seccomp.is_active(),
                portals: self.toggle_portals.is_active(),
            },
            runtime: SandboxRuntimeFlags {
                tmpfs: self.toggle_tmpfs.is_active(),
                share_pid: self.toggle_share_pid.is_active(),
                vpnify: self.toggle_vpnify.is_active(),
            },
            flatpak_portal: self.toggle_flatpak_portal.is_active(),
            seccomp_action: self.seccomp_action.borrow().clone(),
            seccomp_notify: self.seccomp_notify.borrow().clone(),
            seccomp_allowed: self.seccomp_allowed.borrow().clone(),
            seccomp_deny: self.seccomp_deny.borrow().clone(),
            bridges: self.bridges_widget.get_rules(),
            bwrap_args: self.entry_bwrap.text().to_string(),
            extra_env: self.entry_env.text().to_string(),
            extra_paths: self.paths_widget.to_string_args(),
        }
    }

    pub fn load_data(&self, data: &SandboxFormData) {
        self.combo_net.set_active_id(Some(&data.network));
        self.entry_singbox.set_text(&data.singbox_config);
        if let Some(ref c) = self.combo_wayland {
            c.set_active_id(Some(&data.wayland));
        }
        self.combo_x11.set_active_id(Some(&data.x11));
        self.combo_pulse.set_active_id(Some(&data.pulse));
        self.combo_pipewire.set_active_id(Some(&data.pipewire));
        self.combo_microphone.set_active_id(Some(&data.microphone));
        self.toggle_gpu.set_active(data.hw.gpu);
        self.toggle_gamepad.set_active(data.hw.gamepad);
        if data.webcam == "portal" {
            self.combo_webcam_mode.set_active_id(Some("portal"));
            self.webcam_nodes_box.set_visible(false);
            for (_, btn) in &self.webcam_node_toggles {
                btn.set_active(false);
            }
        } else if data.webcam == "off" || data.webcam.is_empty() {
            self.combo_webcam_mode.set_active_id(Some("off"));
            self.webcam_nodes_box.set_visible(false);
            for (_, btn) in &self.webcam_node_toggles {
                btn.set_active(false);
            }
        } else {
            self.combo_webcam_mode.set_active_id(Some("nodes"));
            self.webcam_nodes_box.set_visible(true);
            let active_set: HashSet<u32> = data
                .webcam
                .split(',')
                .filter_map(|s| s.trim().parse::<u32>().ok())
                .collect();
            for (idx, btn) in &self.webcam_node_toggles {
                btn.set_active(active_set.contains(idx));
            }
        }
        self.combo_dbus.set_active_id(Some(&data.dbus));
        self.toggle_portals.set_active(data.sec.portals);
        self.toggle_flatpak_portal.set_active(data.flatpak_portal);
        self.toggle_landlock.set_active(data.sec.landlock);
        self.toggle_seccomp.set_active(data.sec.seccomp);
        (*self.seccomp_action.borrow_mut()).clone_from(&data.seccomp_action);
        (*self.seccomp_notify.borrow_mut()).clone_from(&data.seccomp_notify);
        (*self.seccomp_allowed.borrow_mut()).clone_from(&data.seccomp_allowed);
        (*self.seccomp_deny.borrow_mut()).clone_from(&data.seccomp_deny);
        update_seccomp_summary_label(
            &self.btn_seccomp_edit,
            &self.seccomp_allowed,
            &self.seccomp_deny,
        );
        self.toggle_tmpfs.set_active(data.runtime.tmpfs);
        self.toggle_share_pid.set_active(data.runtime.share_pid);
        self.toggle_vpnify.set_active(data.runtime.vpnify);
        self.combo_shm.set_active_id(Some(&data.shm));
        self.combo_tmp.set_active_id(Some(&data.tmp));
        self.bridges_widget.load_rules(&data.bridges);
        self.entry_dbus.set_text(&data.dbus_args);
        self.entry_bwrap.set_text(&data.bwrap_args);
        self.entry_env.set_text(&data.extra_env);
        if !data.extra_paths.trim().is_empty() {
            self.paths_widget.load_from_string_args(&data.extra_paths);
        }
    }

    #[must_use]
    pub fn build_sb_run_args(&self) -> Vec<String> {
        let d = self.get_data();
        let mut args = vec![
            "--net".into(),
            d.network.clone(),
            "--pulse".into(),
            d.pulse.clone(),
            "--pipewire".into(),
            d.pipewire.clone(),
            "--microphone".into(),
            d.microphone.clone(),
            "--x11".into(),
            d.x11.clone(),
            "--dbus".into(),
            d.dbus.clone(),
            "--shm".into(),
            d.shm.clone(),
            "--tmp".into(),
            d.tmp.clone(),
        ];
        if self.mode == SandboxUiMode::Standalone {
            args.push("--wayland".into());
            args.push(d.wayland.clone());
        }
        if !d.singbox_config.is_empty() {
            if d.singbox_config.starts_with('{') {
                args.push("--singbox-json".into());
            } else {
                args.push("--singbox-config".into());
            }
            args.push(d.singbox_config.clone());
        }
        args.push(if d.hw.gpu { "--gpu" } else { "--no-gpu" }.into());
        if d.hw.gamepad {
            args.push("--gamepad".into());
        }
        push_webcam_args(&mut args, &d.webcam);
        args.push(
            if d.sec.landlock {
                "--landlock"
            } else {
                "--no-landlock"
            }
            .into(),
        );
        if !d.sec.portals {
            args.push("--no-portals".into());
        }
        if d.flatpak_portal {
            args.push("--flatpak-portal".into());
        } else {
            args.push("--no-flatpak-portal".into());
        }
        if d.runtime.tmpfs {
            args.push("--tmpfs".into());
        }
        if d.runtime.share_pid {
            args.push("--share-pid".into());
        }
        if d.runtime.vpnify {
            args.push("--vpnify".into());
        }
        push_seccomp_args(&mut args, &d, &self.decl);
        for b in &d.bridges {
            args.push("--bridge".into());
            args.push(b.clone());
        }
        for piece in d.bwrap_args.split_whitespace() {
            args.push("--bwrap-arg".into());
            args.push(piece.to_string());
        }
        for piece in d.dbus_args.split_whitespace() {
            args.push("--dbus-arg".into());
            args.push(piece.to_string());
        }
        for piece in d.extra_env.split_whitespace() {
            args.push("--env".into());
            args.push(piece.to_string());
        }
        args.extend(self.paths_widget.get_flags());
        args
    }

    pub fn add_path(&self, path: &str, mode: BindMode) {
        self.paths_widget.add_path(path, mode);
    }
}

#[must_use]
pub fn format_seccomp_summary(allowed: &[String], decl: &SbRunConfig) -> String {
    let mut s = String::new();
    let def_set: HashSet<&str> = decl.seccomp.allow.iter().map(String::as_str).collect();
    let cur_set: HashSet<&str> = allowed.iter().map(String::as_str).collect();
    let allow: Vec<&str> = allowed
        .iter()
        .filter(|x| !def_set.contains(x.as_str()))
        .map(String::as_str)
        .collect();
    let block: Vec<&str> = decl
        .seccomp
        .allow
        .iter()
        .filter(|x| !cur_set.contains(x.as_str()))
        .map(String::as_str)
        .collect();
    let _ = write!(s, "allow={} block={}", allow.join(","), block.join(","));
    s
}
