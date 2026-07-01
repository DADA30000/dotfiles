import sys
import os
import glob
import json
import re
import subprocess
import threading
import time

# Nix/Environment path placeholders
LACT_BIN = "%{{{pkgs.lact}}}/bin/lact"
TLP_CTL = "%{{{pkgs.tlp-pd}}}/bin/tlpctl"
PKILL_BIN = "%{{{pkgs.procps}}}/bin/pkill"
NV_BLINDFOLD_BIN = "/run/wrappers/bin/nv-blindfold"
FAN_CONTROL_BIN = "/run/wrappers/bin/fan-control"
FAN_MODE_PATH = "/sys/devices/platform/aorus_laptop/fan_mode"

# Match pattern: width x height @ refresh_rate
mode_pattern = re.compile(r"(\d+)x(\d+)@([\d.]+)")


def get_current_tlp_profile():
    try:
        res = subprocess.run([TLP_CTL, "get"], capture_output=True, text=True)
        if res.returncode == 0:
            return res.stdout.strip()
    except Exception:
        pass
    return "balanced"


# Status API handling for Waybar - executed immediately to prevent loading GTK
has_getdata = any("getdata" in arg.lower() for arg in sys.argv)
if len(sys.argv) > 1 and has_getdata:
    profile = get_current_tlp_profile()
    if "power-saver" in profile:
        data = {
            "text": "󰌪",
            "class": "powersave",
            "tooltip": "Mode: Power Saver",
        }
    elif "performance" in profile:
        data = {
            "text": "󰓅",
            "class": "performance",
            "tooltip": "Mode: Performance",
        }
    else:
        data = {"text": "󰗑", "class": "default", "tooltip": "Mode: Balanced"}
    print(json.dumps(data))
    sys.exit(0)

# Deferred GTK imports (only imported when running GUI operations)
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk


def is_nv_blocked():
    return len(glob.glob("/dev/nvidia*.bak")) > 0


def get_current_lact_profile():
    try:
        res = subprocess.run(
            [LACT_BIN, "cli", "profile", "get"],
            capture_output=True,
            text=True,
        )
        if res.returncode == 0:
            profile = res.stdout.strip().lower()
            if "powersave" in profile:
                return "Powersave"
            elif "performance" in profile:
                return "Performance"
            elif "balanced" in profile or "default" in profile:
                return "Balanced"
    except Exception:
        pass
    return "Balanced"


def get_fan_mode():
    try:
        if os.path.exists(FAN_MODE_PATH):
            with open(FAN_MODE_PATH, "r") as f:
                mode = f.read().strip()
                if mode == "5":
                    return "max"
    except Exception:
        pass
    return "auto"


def get_hypr_animations_enabled():
    try:
        res = subprocess.run(
            ["hyprctl", "getoption", "animations:enabled", "-j"],
            capture_output=True,
            text=True,
        )
        if res.returncode == 0:
            data = json.loads(res.stdout)
            if "int" in data:
                return data["int"] == 1
            if "bool" in data:
                return bool(data["bool"])
    except Exception:
        pass
    try:
        res = subprocess.run(
            ["hyprctl", "getoption", "animations:enabled"],
            capture_output=True,
            text=True,
        )
        if res.returncode == 0:
            line = res.stdout.splitlines()[0].lower()
            if "int: 0" in line or "false" in line:
                return False
    except Exception:
        pass
    return True


def get_internal_monitor_info():
    try:
        res = subprocess.run(
            ["hyprctl", "monitors", "-j"], capture_output=True, text=True
        )
        if res.returncode == 0:
            monitors = json.loads(res.stdout)
            if isinstance(monitors, list):
                for m in monitors:
                    if isinstance(m, dict):
                        name = m.get("name", "")
                        if name.startswith("eDP-"):
                            return m
    except Exception:
        pass
    return None


def find_powersave_mode(monitor_info):
    if not monitor_info:
        return "eDP-1", "2560x1600@60"

    name = monitor_info.get("name", "eDP-1")
    curr_width = monitor_info.get("width", 2560)
    curr_height = monitor_info.get("height", 1600)
    modes = monitor_info.get("availableModes", [])

    matching_modes = []

    for mode in modes:
        match = mode_pattern.match(mode)
        if match:
            w = int(match.group(1))
            h = int(match.group(2))
            hz = float(match.group(3))
            if w == curr_width and h == curr_height:
                matching_modes.append((hz, f"{w}x{h}@{hz}"))

    if not matching_modes:
        return name, f"{curr_width}x{curr_height}@60"

    # Search for exactly 60Hz mode
    for hz, _ in matching_modes:
        if 59.0 <= hz <= 61.0:
            return name, f"{curr_width}x{curr_height}@60"

    # Else find lowest hz mode
    matching_modes.sort(key=lambda x: x[0])
    lowest_hz = matching_modes[0][0]

    if lowest_hz.is_integer():
        lowest_hz_str = str(int(lowest_hz))
    else:
        lowest_hz_str = f"{lowest_hz:.2f}"

    return name, f"{curr_width}x{curr_height}@{lowest_hz_str}"


def is_edp_60hz():
    try:
        res = subprocess.run(
            ["hyprctl", "monitors", "-j"], capture_output=True, text=True
        )
        if res.returncode == 0:
            monitors = json.loads(res.stdout)
            if isinstance(monitors, list):
                for m in monitors:
                    if isinstance(m, dict):
                        name = m.get("name", "")
                        if name.startswith("eDP-"):
                            rate = m.get("refreshRate", 0)
                            if (
                                isinstance(rate, (int, float))
                                and 58.0 < rate < 61.0
                            ):
                                return True
            return False
    except Exception:
        pass
    return False


def is_replays_running():
    try:
        res = subprocess.run(
            ["systemctl", "--user", "is-active", "replays"],
            capture_output=True,
            text=True,
        )
        return res.returncode == 0
    except Exception:
        pass
    return False


class ControlPanelWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="Power menu")
        self.set_border_width(15)
        self.set_default_size(480, -1)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_resizable(False)
        self.set_type_hint(Gdk.WindowTypeHint.DIALOG)

        self.updating_ui = True

        # Inject CSS for a cohesive UI layout
        style_provider = Gtk.CssProvider()
        style_provider.load_from_data(b"""
            window {
                background-color: @theme_bg_color;
            }
            .linked button {
                padding: 6px 12px;
            }
            .linked button:checked {
                background-image: none;
                background-color: @theme_selected_bg_color;
                color: @theme_selected_fg_color;
            }
            frame {
                border: 1px solid @unfocused_borders;
                border-radius: 8px;
                padding: 10px;
                margin-bottom: 15px;
            }
            frame > label {
                font-weight: bold;
                margin-bottom: 5px;
            }
        """)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            style_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(vbox)

        # Header bar
        title_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        vbox.pack_start(title_box, False, False, 0)

        icon_img = Gtk.Image.new_from_icon_name(
            "battery-full-symbolic", Gtk.IconSize.LARGE_TOOLBAR
        )
        title_box.pack_start(icon_img, False, False, 0)

        lbl_title = Gtk.Label()
        lbl_title.set_markup(
            "<span size='large' weight='bold'>Power menu</span>"
        )
        title_box.pack_start(lbl_title, False, False, 0)

        vbox.pack_start(
            Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL),
            False,
            False,
            5,
        )

        # ==================== FRAME 1: HARDWARE CONTROLS ====================
        frame_hw = Gtk.Frame(label="Hardware Power Settings")
        vbox.pack_start(frame_hw, True, True, 0)

        grid_hw = Gtk.Grid(column_spacing=20, row_spacing=15)
        grid_hw.set_border_width(8)
        frame_hw.add(grid_hw)

        # Hardware Row 0: NVIDIA Block Switch
        lbl_nv = Gtk.Label()
        lbl_nv.set_markup(
            "<b>Block NVIDIA GPU:</b>\n"
            "<span size='small' color='gray'>nv-blindfold wrapper</span>"
        )
        lbl_nv.set_xalign(0.0)
        lbl_nv.set_yalign(0.5)
        grid_hw.attach(lbl_nv, 0, 0, 1, 1)

        self.switch_nv = Gtk.Switch()
        self.switch_nv.set_valign(Gtk.Align.CENTER)
        self.switch_nv.set_halign(Gtk.Align.END)
        self.switch_nv.connect("notify::active", self.on_nv_toggled)
        grid_hw.attach(self.switch_nv, 1, 0, 1, 1)

        # Hardware Row 1: TLP Power Profile (Saver / Balanced / Performance)
        lbl_tlp = Gtk.Label()
        lbl_tlp.set_markup(
            "<b>TLP Power Profile:</b>\n"
            "<span size='small' color='gray'>System CPU power scaling</span>"
        )
        lbl_tlp.set_xalign(0.0)
        lbl_tlp.set_yalign(0.5)
        grid_hw.attach(lbl_tlp, 0, 1, 1, 1)

        tlp_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        tlp_box.get_style_context().add_class("linked")
        tlp_box.set_valign(Gtk.Align.CENTER)
        tlp_box.set_halign(Gtk.Align.END)

        self.btn_tlp_saver = Gtk.RadioButton.new_with_label(None, "Saver")
        self.btn_tlp_saver.set_mode(False)
        self.btn_tlp_saver.set_hexpand(True)
        self.btn_tlp_saver.connect(
            "toggled", self.on_tlp_toggled, "power-saver"
        )

        self.btn_tlp_bal = Gtk.RadioButton.new_with_label_from_widget(
            self.btn_tlp_saver, "Balanced"
        )
        self.btn_tlp_bal.set_mode(False)
        self.btn_tlp_bal.set_hexpand(True)
        self.btn_tlp_bal.connect("toggled", self.on_tlp_toggled, "balanced")

        self.btn_tlp_perf = Gtk.RadioButton.new_with_label_from_widget(
            self.btn_tlp_saver, "Performance"
        )
        self.btn_tlp_perf.set_mode(False)
        self.btn_tlp_perf.set_hexpand(True)
        self.btn_tlp_perf.connect(
            "toggled", self.on_tlp_toggled, "performance"
        )

        tlp_box.pack_start(self.btn_tlp_saver, True, True, 0)
        tlp_box.pack_start(self.btn_tlp_bal, True, True, 0)
        tlp_box.pack_start(self.btn_tlp_perf, True, True, 0)
        grid_hw.attach(tlp_box, 1, 1, 1, 1)

        # Hardware Row 2: LACT GPU Profile (Saver / Balanced / Performance)
        lbl_lact = Gtk.Label()
        lbl_lact.set_markup(
            "<b>LACT GPU Profile:</b>\n"
            "<span size='small' color='gray'>Radeon power profiles</span>"
        )
        lbl_lact.set_xalign(0.0)
        lbl_lact.set_yalign(0.5)
        grid_hw.attach(lbl_lact, 0, 2, 1, 1)

        lact_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        lact_box.get_style_context().add_class("linked")
        lact_box.set_valign(Gtk.Align.CENTER)
        lact_box.set_halign(Gtk.Align.END)

        self.btn_lact_saver = Gtk.RadioButton.new_with_label(None, "Saver")
        self.btn_lact_saver.set_mode(False)
        self.btn_lact_saver.set_hexpand(True)
        self.btn_lact_saver.connect(
            "toggled", self.on_lact_toggled, "Powersave"
        )

        self.btn_lact_bal = Gtk.RadioButton.new_with_label_from_widget(
            self.btn_lact_saver, "Balanced"
        )
        self.btn_lact_bal.set_mode(False)
        self.btn_lact_bal.set_hexpand(True)
        self.btn_lact_bal.connect("toggled", self.on_lact_toggled, "Balanced")

        self.btn_lact_perf = Gtk.RadioButton.new_with_label_from_widget(
            self.btn_lact_saver, "Performance"
        )
        self.btn_lact_perf.set_mode(False)
        self.btn_lact_perf.set_hexpand(True)
        self.btn_lact_perf.connect(
            "toggled", self.on_lact_toggled, "Performance"
        )

        lact_box.pack_start(self.btn_lact_saver, True, True, 0)
        lact_box.pack_start(self.btn_lact_bal, True, True, 0)
        lact_box.pack_start(self.btn_lact_perf, True, True, 0)
        grid_hw.attach(lact_box, 1, 2, 1, 1)

        # Hardware Row 3: Fan Mode Selection (Auto / Max)
        lbl_fan = Gtk.Label()
        lbl_fan.set_markup(
            "<b>Fan Control:</b>\n"
            "<span size='small' color='gray'>Aorus laptop fan speed</span>"
        )
        lbl_fan.set_xalign(0.0)
        lbl_fan.set_yalign(0.5)
        grid_hw.attach(lbl_fan, 0, 3, 1, 1)

        fan_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        fan_box.get_style_context().add_class("linked")
        fan_box.set_valign(Gtk.Align.CENTER)
        fan_box.set_halign(Gtk.Align.END)

        self.btn_fan_auto = Gtk.RadioButton.new_with_label(None, "Auto")
        self.btn_fan_auto.set_mode(False)
        self.btn_fan_auto.set_hexpand(True)
        self.btn_fan_auto.connect("toggled", self.on_fan_toggled, "auto")

        self.btn_fan_max = Gtk.RadioButton.new_with_label_from_widget(
            self.btn_fan_auto, "Max"
        )
        self.btn_fan_max.set_mode(False)
        self.btn_fan_max.set_hexpand(True)
        self.btn_fan_max.connect("toggled", self.on_fan_toggled, "max")

        fan_box.pack_start(self.btn_fan_auto, True, True, 0)
        fan_box.pack_start(self.btn_fan_max, True, True, 0)
        grid_hw.attach(fan_box, 1, 3, 1, 1)

        frame_sw = Gtk.Frame(label="UI & Desktop Powersave")
        vbox.pack_start(frame_sw, True, True, 0)

        grid_sw = Gtk.Grid(column_spacing=20, row_spacing=15)
        grid_sw.set_border_width(8)
        frame_sw.add(grid_sw)

        # Software Row 0: Master Eco Mode Switch
        lbl_eco = Gtk.Label()
        lbl_eco.set_markup(
            "<span weight='bold'>Batch Software Powersaving:</span>\n"
            "<span size='small' color='gray'>"
            "Toggles animations, 60Hz rate, &amp; replays"
            "</span>"
        )
        lbl_eco.set_xalign(0.0)
        lbl_eco.set_yalign(0.5)
        grid_sw.attach(lbl_eco, 0, 0, 1, 1)

        self.switch_eco = Gtk.Switch()
        self.switch_eco.set_valign(Gtk.Align.CENTER)
        self.switch_eco.set_halign(Gtk.Align.END)
        self.switch_eco.connect("notify::active", self.on_eco_toggled)
        grid_sw.attach(self.switch_eco, 1, 0, 1, 1)

        # Clean separator for clarity
        sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        sep.set_margin_top(5)
        sep.set_margin_bottom(5)
        grid_sw.attach(sep, 0, 1, 2, 1)

        # Software Row 2: Hyprland Animations
        lbl_anim = Gtk.Label()
        lbl_anim.set_markup(
            "<b>Hyprland Animations:</b>\n"
            "<span size='small' color='gray'>"
            "Rendering animations &amp; borders"
            "</span>"
        )
        lbl_anim.set_xalign(0.0)
        lbl_anim.set_yalign(0.5)
        grid_sw.attach(lbl_anim, 0, 2, 1, 1)

        self.switch_anim = Gtk.Switch()
        self.switch_anim.set_valign(Gtk.Align.CENTER)
        self.switch_anim.set_halign(Gtk.Align.END)
        self.switch_anim.connect(
            "notify::active", self.on_software_switch_toggled
        )
        grid_sw.attach(self.switch_anim, 1, 2, 1, 1)

        # Software Row 3: eDP-1 60Hz Limit
        lbl_fps = Gtk.Label()
        lbl_fps.set_markup(
            "<b>Limit Screen to 60Hz:</b>\n"
            "<span size='small' color='gray'>"
            "eDP-1 display resolution refresh rate"
            "</span>"
        )
        lbl_fps.set_xalign(0.0)
        lbl_fps.set_yalign(0.5)
        grid_sw.attach(lbl_fps, 0, 3, 1, 1)

        self.switch_fps = Gtk.Switch()
        self.switch_fps.set_valign(Gtk.Align.CENTER)
        self.switch_fps.set_halign(Gtk.Align.END)
        self.switch_fps.connect(
            "notify::active", self.on_software_switch_toggled
        )
        grid_sw.attach(self.switch_fps, 1, 3, 1, 1)

        # Software Row 4: Replays Systemd Status
        lbl_replays = Gtk.Label()
        lbl_replays.set_markup(
            "<b>Enable Replays Service:</b>\n"
            "<span size='small' color='gray'>"
            "systemctl --user service status"
            "</span>"
        )
        lbl_replays.set_xalign(0.0)
        lbl_replays.set_yalign(0.5)
        grid_sw.attach(lbl_replays, 0, 4, 1, 1)

        self.switch_replays = Gtk.Switch()
        self.switch_replays.set_valign(Gtk.Align.CENTER)
        self.switch_replays.set_halign(Gtk.Align.END)
        self.switch_replays.connect(
            "notify::active", self.on_software_switch_toggled
        )
        grid_sw.attach(self.switch_replays, 1, 4, 1, 1)

        # Synchronize states on launch
        self.load_states()

        # Footer control actions
        footer_box = Gtk.ButtonBox(orientation=Gtk.Orientation.HORIZONTAL)
        footer_box.set_layout(Gtk.ButtonBoxStyle.END)
        vbox.pack_start(footer_box, False, False, 5)

        btn_close = Gtk.Button(label="Close")
        btn_close.connect("clicked", Gtk.main_quit)
        footer_box.pack_start(btn_close, True, True, 0)

        self.connect("destroy", Gtk.main_quit)
        self.show_all()

    def load_states(self):
        self.updating_ui = True

        # HW State Loader
        nv_blocked = is_nv_blocked()
        self.switch_nv.set_active(nv_blocked)

        tlp_profile = get_current_tlp_profile()
        if tlp_profile == "power-saver":
            self.btn_tlp_saver.set_active(True)
        elif tlp_profile == "performance":
            self.btn_tlp_perf.set_active(True)
        else:
            self.btn_tlp_bal.set_active(True)

        lact_profile = get_current_lact_profile()
        if lact_profile == "Powersave":
            self.btn_lact_saver.set_active(True)
        elif lact_profile == "Performance":
            self.btn_lact_perf.set_active(True)
        else:
            self.btn_lact_bal.set_active(True)

        fan_mode = get_fan_mode()
        if fan_mode == "max":
            self.btn_fan_max.set_active(True)
        else:
            self.btn_fan_auto.set_active(True)

        # SW Powersave State Loader
        animations_on = get_hypr_animations_enabled()
        self.switch_anim.set_active(animations_on)

        limit_60hz = is_edp_60hz()
        self.switch_fps.set_active(limit_60hz)

        replays_on = is_replays_running()
        self.switch_replays.set_active(replays_on)

        self.updating_ui = False
        self.update_master_switch()

    def notify_waybar(self):
        def bg_notify():
            time.sleep(0.15)
            try:
                subprocess.run(
                    [PKILL_BIN, "-RTMIN+5", "waybar"],
                    stderr=subprocess.DEVNULL,
                )
            except Exception:
                pass

        threading.Thread(target=bg_notify, daemon=True).start()

    def update_master_switch(self):
        self.updating_ui = True
        anim = self.switch_anim.get_active()
        low_fps = self.switch_fps.get_active()
        replays = self.switch_replays.get_active()

        # UI Powersave is active when: animations are off,
        # refresh limit is on, and replays are off
        if (not anim) and low_fps and (not replays):
            self.switch_eco.set_active(True)
        elif anim and (not low_fps) and replays:
            self.switch_eco.set_active(False)
        else:
            self.switch_eco.set_active(False)
        self.updating_ui = False

    def on_nv_toggled(self, switch, _gparamspec):
        if self.updating_ui:
            return
        active = switch.get_active()
        action = "block" if active else "unblock"
        try:
            subprocess.run([NV_BLINDFOLD_BIN, action], check=True)
            self.notify_waybar()
        except Exception as e:
            self.show_error_dialog(
                f"Failed to execute nv-blindfold {action}", str(e)
            )
            self.updating_ui = True
            switch.set_active(not active)
            self.updating_ui = False

    def on_tlp_toggled(self, button, profile_name):
        if self.updating_ui:
            return
        if button.get_active():
            try:
                subprocess.run([TLP_CTL, "set", profile_name], check=True)
                self.notify_waybar()
            except Exception as e:
                self.show_error_dialog(
                    f"Failed to set TLP profile to {profile_name}", str(e)
                )
                self.load_states()

    def on_lact_toggled(self, button, profile_name):
        if self.updating_ui:
            return
        if button.get_active():
            try:
                subprocess.run(
                    [LACT_BIN, "cli", "profile", "set", profile_name],
                    check=True,
                )
                self.notify_waybar()
            except Exception as e:
                self.show_error_dialog(
                    f"Failed to set LACT profile to {profile_name}", str(e)
                )
                self.load_states()

    def on_fan_toggled(self, button, fan_mode):
        if self.updating_ui:
            return
        if button.get_active():
            try:
                subprocess.run([FAN_CONTROL_BIN, fan_mode], check=True)
            except Exception as e:
                self.show_error_dialog(
                    f"Failed to set fan mode to {fan_mode}", str(e)
                )
                self.load_states()

    # Master Batch Toggle Handler
    def on_eco_toggled(self, switch, _gparamspec):
        if self.updating_ui:
            return
        active = switch.get_active()

        self.updating_ui = True
        if active:
            self.switch_anim.set_active(False)  # animations disabled
            self.switch_fps.set_active(True)  # 60Hz limit enabled
            self.switch_replays.set_active(False)  # replays stopped
        else:
            self.switch_anim.set_active(True)  # animations enabled
            self.switch_fps.set_active(False)  # 60Hz limit disabled
            self.switch_replays.set_active(True)  # replays running
        self.updating_ui = False

        self.apply_hypr_and_replays()

    # Individual Software Toggle Handler
    def on_software_switch_toggled(self, _switch, _gparamspec):
        if self.updating_ui:
            return
        self.apply_hypr_and_replays()
        self.update_master_switch()

    def apply_hypr_and_replays(self):
        anim = self.switch_anim.get_active()
        low_fps = self.switch_fps.get_active()
        replays = self.switch_replays.get_active()

        try:
            # If animations or high refresh rate are requested,
            # trigger a clean reload
            if anim or not low_fps:
                subprocess.run(["hyprctl", "reload"], check=True)

            # Override animations if disabled
            if not anim:
                subprocess.run(
                    [
                        "hyprctl",
                        "eval",
                        "hl.config { "
                        "animations = { enabled = 0 }, "
                        "general = { border_size = 0 } "
                        "}",
                    ],
                    check=True,
                )

            # Override monitor modes if 60Hz restriction is active
            if low_fps:
                m_info = get_internal_monitor_info()
                name, mode = find_powersave_mode(m_info)
                subprocess.run(
                    [
                        "hyprctl",
                        "eval",
                        f'hl.monitor({{ output = "{name}", '
                        f'mode = "{mode}", '
                        f'position = "auto", '
                        f'scale = "auto", '
                        f"bitdepth = 10 }})",
                    ],
                    check=True,
                )

            # Manage replays background daemon
            service_action = "start" if replays else "stop"
            subprocess.run(
                ["systemctl", "--user", service_action, "replays"], check=True
            )

            self.notify_waybar()
        except Exception as e:
            self.show_error_dialog("Failed to apply screen/WM state", str(e))

    def show_error_dialog(self, message, details):
        dialog = Gtk.MessageDialog(
            transient_for=self,
            flags=0,
            type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK,
            message_format=message,
        )
        dialog.format_secondary_text(details)
        dialog.run()
        dialog.destroy()


if __name__ == "__main__":
    ControlPanelWindow()
    Gtk.main()
