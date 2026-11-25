use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProtonVersion {
    pub name: String,
    #[serde(default)]
    pub default: bool,
}

#[derive(Debug, Clone, Deserialize)]
pub struct BridgePreset {
    pub label: String,
    pub rule: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct PathsConfig {
    pub umu_dir_rel: String,
    pub icon_cache_rel: String,
    pub icon_dest_rel: String,
    pub desktop_dir_rel: String,
    pub proton_versions_file: String,
    pub games_appid_file: String,
    pub ignored_prefix_dirs: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct BinsConfig {
    pub umu_run_wrapper: String,
    pub scan_umu_for_lnk: String,
    pub run_exe: String,
    pub sb_run: String,
    pub notify_send: String,
    pub xdg_open: String,
    pub exiftool: String,
    pub wrestool: String,
    pub magick: String,
    pub systemctl: String,
    pub mountpoint: String,
    pub umount: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SteamConfig {
    pub info_api_url: String,
    pub icon_cdn_url: String,
    pub info_timeout_secs: u64,
    pub icon_timeout_secs: u64,
    pub search_max_results: usize,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SystemdConfig {
    pub prefix_scope_template: String,
    pub prefix_mount_rel: String,
    pub stop_timeout_ms: u64,
    pub stop_poll_ms: u64,
}

#[derive(Debug, Clone, Copy, Deserialize)]
pub struct ShortcutPerfDefaults {
    pub gamemode: bool,
    pub mangohud: bool,
}

#[derive(Debug, Clone, Copy, Deserialize)]
pub struct ShortcutSteamDefaults {
    pub steam_integration: bool,
    pub steam_overlay: bool,
}

#[derive(Debug, Clone, Copy, Deserialize)]
pub struct ShortcutIsolationDefaults {
    pub vpn: bool,
    pub sandbox: bool,
    pub gamepad: bool,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ShortcutDefaultsConfig {
    pub prefix: String,
    pub icon: String,
    pub gpu: String,
    pub gpu_options: Vec<String>,
    pub default_proton: String,
    pub proton_versions: Vec<ProtonVersion>,
    pub wayland: bool,
    pub x11: String,
    pub network: String,
    pub categories: String,
    pub args_placeholder: String,
    pub gameid_placeholder: String,
    #[serde(flatten)]
    pub perf: ShortcutPerfDefaults,
    #[serde(flatten)]
    pub steam: ShortcutSteamDefaults,
    #[serde(flatten)]
    pub isolation: ShortcutIsolationDefaults,
}

#[derive(Debug, Clone, Deserialize)]
pub struct UmuSandboxDefaults {
    pub x11: String,
    pub gpu: bool,
    pub landlock: bool,
    pub tmpfs: bool,
    pub seccomp_allow: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SandboxUiConfig {
    pub tmp_id_prefix: String,
    pub sb_gui_width: i32,
    pub sb_gui_height: i32,
    pub seccomp_dialog_width: i32,
    pub seccomp_dialog_height: i32,
    pub umu_width_collapsed: i32,
    pub umu_width_expanded: i32,
    pub bridge_default_address: String,
    pub bridge_ports_placeholder: String,
    pub bridge_presets: Vec<BridgePreset>,
    pub umu_defaults: UmuSandboxDefaults,
}

#[derive(Debug, Clone, Deserialize)]
pub struct RustHelpersConfig {
    pub paths: PathsConfig,
    pub bins: BinsConfig,
    pub steam: SteamConfig,
    pub systemd: SystemdConfig,
    pub shortcut_defaults: ShortcutDefaultsConfig,
    pub sandbox_ui: SandboxUiConfig,
}

#[must_use]
pub fn home_dir() -> PathBuf {
    PathBuf::from(env::var("HOME").unwrap_or_else(|_| ".".to_string()))
}

#[must_use]
pub fn get_xdg_data_home() -> PathBuf {
    if let Ok(val) = env::var("XDG_DATA_HOME")
        && !val.is_empty()
    {
        return PathBuf::from(val);
    }
    home_dir().join(".local/share")
}

#[must_use]
pub fn get_xdg_config_home() -> PathBuf {
    if let Ok(val) = env::var("XDG_CONFIG_HOME")
        && !val.is_empty()
    {
        return PathBuf::from(val);
    }
    home_dir().join(".config")
}

pub(crate) fn replace_token(template: &str, token: &str, value: &str) -> String {
    let needle = format!("{{{token}}}");
    template.replace(&needle, value)
}

#[must_use]
pub fn expand_path_vars(raw: &str) -> PathBuf {
    let home = home_dir().to_string_lossy().to_string();
    let data_home = get_xdg_data_home().to_string_lossy().to_string();
    let config_home = get_xdg_config_home().to_string_lossy().to_string();
    let mut expanded = raw
        .strip_prefix("~/")
        .map_or_else(|| raw.to_string(), |rest| format!("{home}/{rest}"));
    for (name, val) in [
        ("HOME", &home),
        ("XDG_DATA_HOME", &data_home),
        ("XDG_CONFIG_HOME", &config_home),
    ] {
        expanded = expanded
            .replace(&format!("${name}"), val)
            .replace(&format!("${{{name}}}"), val);
    }
    if let Ok(runtime) = env::var("XDG_RUNTIME_DIR")
        && !runtime.is_empty()
    {
        expanded = expanded
            .replace("$XDG_RUNTIME_DIR", &runtime)
            .replace("${XDG_RUNTIME_DIR}", &runtime);
    }
    PathBuf::from(expanded)
}

pub(crate) fn read_json_value(path: &Path) -> Result<Value, String> {
    let raw = fs::read_to_string(path)
        .map_err(|e| format!("failed to read '{}': {e}", path.display()))?;
    serde_json::from_str(&raw).map_err(|e| format!("invalid JSON in '{}': {e}", path.display()))
}

pub(crate) fn xdg_subpath(env_key: &str, fallback_rel: &str, rel_target: &str) -> Option<PathBuf> {
    env::var(env_key)
        .ok()
        .filter(|s| !s.is_empty())
        .map_or_else(
            || {
                env::var("HOME")
                    .ok()
                    .filter(|h| !h.is_empty())
                    .map(|h| PathBuf::from(h).join(fallback_rel))
            },
            |d| Some(PathBuf::from(d).join(rel_target)),
        )
}

fn load_config_value() -> Result<Value, String> {
    if let Ok(explicit) = env::var("RUST_HELPERS_CONFIG")
        && !explicit.is_empty()
    {
        if explicit == "none" {
            return Err("RUST_HELPERS_CONFIG=none is not supported".into());
        }
        let ep = PathBuf::from(&explicit);
        if !ep.is_file() {
            return Err(format!(
                "RUST_HELPERS_CONFIG '{}' does not exist",
                ep.display()
            ));
        }
        return read_json_value(&ep);
    }

    let candidates = [
        xdg_subpath(
            "XDG_CONFIG_HOME",
            ".config/rust-helpers/config.json",
            "rust-helpers/config.json",
        ),
        xdg_subpath(
            "XDG_DATA_HOME",
            ".local/share/rust-helpers/config.json",
            "rust-helpers/config.json",
        ),
    ];

    for path in candidates.into_iter().flatten() {
        if path.is_file() {
            return read_json_value(&path);
        }
    }
    Err("missing rust-helpers config.json in XDG config/data home".into())
}

impl RustHelpersConfig {
    /// Loads the declarative `rust-helpers` runtime configuration.
    ///
    /// # Errors
    ///
    /// Returns a descriptive error string if `config.json` is missing or invalid.
    pub fn load() -> Result<Self, String> {
        let val = load_config_value()?;
        serde_json::from_value(val).map_err(|e| format!("invalid rust-helpers config schema: {e}"))
    }

    #[must_use]
    pub fn load_or_exit() -> Self {
        match Self::load() {
            Ok(cfg) => cfg,
            Err(err) => {
                eprintln!("[rust-helpers] Error: {err}");
                std::process::exit(1);
            }
        }
    }

    #[must_use]
    pub fn umu_dir(&self) -> PathBuf {
        home_dir().join(&self.paths.umu_dir_rel)
    }

    #[must_use]
    pub fn icon_cache_dir(&self) -> PathBuf {
        let dir = home_dir().join(&self.paths.icon_cache_rel);
        fs::create_dir_all(&dir).ok();
        dir
    }

    #[must_use]
    pub fn icon_dest_dir(&self) -> PathBuf {
        get_xdg_data_home().join(&self.paths.icon_dest_rel)
    }

    #[must_use]
    pub fn desktop_dir(&self) -> PathBuf {
        get_xdg_data_home().join(&self.paths.desktop_dir_rel)
    }

    #[must_use]
    pub fn proton_versions_path(&self) -> PathBuf {
        if let Ok(val) = env::var("UMU_PROTON_VERSIONS_JSON")
            && !val.is_empty()
        {
            return PathBuf::from(val);
        }
        expand_path_vars(&self.paths.proton_versions_file)
    }

    #[must_use]
    pub fn games_appid_path(&self) -> PathBuf {
        if let Ok(val) = env::var("STEAM_APP_ID_LIST_PATH")
            && !val.is_empty()
        {
            let p = PathBuf::from(val);
            if p.exists() {
                return p;
            }
        }
        expand_path_vars(&self.paths.games_appid_file)
    }

    #[must_use]
    pub fn scope_unit_name(&self, prefix: &str) -> String {
        replace_token(&self.systemd.prefix_scope_template, "prefix", prefix)
    }

    #[must_use]
    pub fn prefix_mount_path(&self, runtime_dir: &str, prefix: &str) -> PathBuf {
        PathBuf::from(runtime_dir).join(replace_token(
            &self.systemd.prefix_mount_rel,
            "prefix",
            prefix,
        ))
    }
}
