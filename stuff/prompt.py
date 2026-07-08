import sys
import os
import json
import subprocess
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, GLib

SERVICES_JSON = "%{{{servicesJson}}}"
INSTALL_CMD = "%{{{installScript}}}"


def get_service_description(name, is_user):
    cmd = (
        ["systemctl", "--user", "show", name, "-p", "Description", "--value"]
        if is_user
        else ["systemctl", "show", name, "-p", "Description", "--value"]
    )
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
        desc = res.stdout.strip()
        return desc if desc else f"No description found for {name}.service"
    except Exception:
        return f"Failed to retrieve description for {name}.service"


def is_service_active(name, is_user):
    cmd = (
        ["systemctl", "--user", "is-active", name]
        if is_user
        else ["systemctl", "is-active", name]
    )
    res = subprocess.run(cmd, capture_output=True, text=True)
    return res.returncode == 0


def toggle_service(name, is_user, enable):
    action = "start" if enable else "stop"
    if is_user:
        cmd = ["systemctl", "--user", action, name]
    else:
        cmd = ["/run/wrappers/bin/pkexec", "systemctl", action, name]
    try:
        subprocess.run(cmd, check=True)
        return True
    except subprocess.CalledProcessError:
        return False


class ServiceRow(Gtk.ListBoxRow):
    def __init__(self, service_str):
        super().__init__()
        parts = service_str.split("/")
        self.service_type = parts[0]  # "user" or "system"
        self.service_name = parts[1]
        self.is_user = self.service_type == "user"

        # Fetch description dynamically at runtime
        self.service_desc = get_service_description(
            self.service_name, self.is_user
        )

        row_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        row_box.set_border_width(8)
        self.add(row_box)

        text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        row_box.pack_start(text_box, True, True, 0)

        lbl_name = Gtk.Label()
        lbl_name.set_markup(
            f"<b>{self.service_name}</b> <span size='small' color='gray'>({self.service_type})</span>"
        )
        lbl_name.set_xalign(0.0)
        text_box.pack_start(lbl_name, False, False, 0)

        lbl_desc = Gtk.Label()
        lbl_desc.set_text(self.service_desc)
        lbl_desc.set_line_wrap(True)
        lbl_desc.set_max_width_chars(50)
        lbl_desc.set_xalign(0.0)
        text_box.pack_start(lbl_desc, False, False, 0)

        self.switch = Gtk.Switch()
        self.switch.set_active(
            is_service_active(self.service_name, self.is_user)
        )
        self.switch.set_valign(Gtk.Align.CENTER)
        self.switch.connect("state-set", self.on_switch_state_set)
        row_box.pack_end(self.switch, False, False, 0)

    def on_switch_state_set(self, switch, state):
        success = toggle_service(self.service_name, self.is_user, state)
        if not success:
            GLib.idle_add(lambda: switch.set_active(not state))
        return False


class ServicePrompterWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="Управление службами")
        self.set_border_width(15)
        self.set_default_size(500, 400)
        self.set_position(Gtk.WindowPosition.CENTER)

        style_provider = Gtk.CssProvider()
        style_provider.load_from_data(b"""
            .suggested-action {
                background-image: none;
                background-color: @theme_selected_bg_color;
                color: @theme_selected_fg_color;
            }
            listrow {
                border-bottom: 1px solid @unfocused_borders;
            }
        """)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            style_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(vbox)

        search_entry = Gtk.SearchEntry()
        search_entry.set_placeholder_text("Поиск служб...")
        search_entry.connect("search-changed", self.on_search_changed)
        vbox.pack_start(search_entry, False, False, 0)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scrolled.set_min_content_height(220)
        vbox.pack_start(scrolled, True, True, 0)

        self.listbox = Gtk.ListBox()
        self.listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        scrolled.add(self.listbox)

        def filter_func(row):
            text = search_entry.get_text().lower()
            if not text:
                return True
            return (
                text in row.service_name.lower()
                or text in row.service_desc.lower()
            )

        self.listbox.set_filter_func(filter_func)

        try:
            with open(SERVICES_JSON, "r") as f:
                services_list = json.load(f)
                for srv_str in services_list:
                    self.listbox.add(ServiceRow(srv_str))
        except Exception as e:
            print(f"Failed to load services: {e}")

        vbox.pack_start(
            Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL),
            False,
            False,
            5,
        )

        bbox = Gtk.ButtonBox(orientation=Gtk.Orientation.HORIZONTAL)
        bbox.set_layout(Gtk.ButtonBoxStyle.SPREAD)
        vbox.pack_start(bbox, False, False, 0)

        btn_install = Gtk.Button(label="Запустить установку")
        btn_install.get_style_context().add_class("suggested-action")
        btn_install.connect("clicked", self.on_install_clicked)
        bbox.pack_start(btn_install, True, True, 0)

        btn_close = Gtk.Button(label="Закрыть")
        btn_close.connect("clicked", Gtk.main_quit)
        bbox.pack_start(btn_close, True, True, 0)

        self.connect("destroy", Gtk.main_quit)
        self.show_all()

    def on_search_changed(self, entry):
        self.listbox.invalidate_filter()

    def on_install_clicked(self, button):
        try:
            subprocess.Popen([INSTALL_CMD])
        except Exception as e:
            print(f"Failed to run installer: {e}")


if __name__ == "__main__":
    ServicePrompterWindow()
    Gtk.main()
