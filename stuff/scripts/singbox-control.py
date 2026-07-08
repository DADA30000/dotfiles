import json
import threading
import time
import urllib.request
import urllib.parse
import urllib.error

# Deferred GTK imports to speed up CLI calls if necessary
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, GLib

API_BASE = "http://127.0.0.1:9090"


class ProxyRow(Gtk.ListBoxRow):
    def __init__(self, node_name, is_active):
        super().__init__()
        self.node_name = node_name
        self.is_active = is_active

        self.box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        self.box.set_border_width(8)
        self.add(self.box)

        # 1. Initialize ALL UI widgets first to prevent AttributeErrors
        self.status_icon = Gtk.Image()
        self.box.pack_start(self.status_icon, False, False, 0)

        self.lbl_name = Gtk.Label(xalign=0.0)
        self.box.pack_start(self.lbl_name, True, True, 0)

        self.lbl_delay = Gtk.Label(xalign=1.0)
        self.lbl_delay.get_style_context().add_class("dim-label")
        self.box.pack_end(self.lbl_delay, False, False, 0)

        # 2. Safely apply states now that widgets are allocated
        self.update_active_state(is_active)

    def update_active_state(self, is_active):
        self.is_active = is_active
        if is_active:
            self.status_icon.set_from_icon_name(
                "emblem-ok-symbolic", Gtk.IconSize.MENU
            )
        else:
            self.status_icon.set_from_icon_name(
                "network-vpn-symbolic", Gtk.IconSize.MENU
            )
        self.update_label_markup()

    def update_label_markup(self):
        if self.is_active:
            self.lbl_name.set_markup(f"<b>{self.node_name}</b>")
        else:
            self.lbl_name.set_text(self.node_name)

    def set_delay(self, delay_ms):
        if delay_ms > 0:
            self.lbl_delay.set_markup(
                f"<span color='#2ecc71'><b>{delay_ms} ms</b></span>"
            )
        elif delay_ms == -2:
            self.lbl_delay.set_markup("<span color='#e74c3c'>timeout</span>")
        else:
            self.lbl_delay.set_markup("<span color='gray'>testing...</span>")


class ClashControlWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="Proxy Selector")
        self.set_border_width(15)
        self.set_default_size(420, 560)
        self.set_position(Gtk.WindowPosition.CENTER)

        self.selector_name = "proxy"
        self.nodes = []
        self.active_node = ""
        self.final_now = "direct"
        self.updating_ui = False

        # Inject CSS to stylize the ListBox layout
        style_provider = Gtk.CssProvider()
        style_provider.load_from_data(b"""
            listbox row {
                border-bottom: 1px solid @unfocused_borders;
            }
            listbox row:selected {
                background-color: @theme_selected_bg_color;
                color: @theme_selected_fg_color;
            }
            .dim-label {
                opacity: 0.6;
            }
            frame {
                border: 1px solid @unfocused_borders;
                border-radius: 8px;
            }
        """)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            style_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(vbox)

        # Header Info Row
        header_box = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL, spacing=10
        )
        vbox.pack_start(header_box, False, False, 0)

        icon_img = Gtk.Image.new_from_icon_name(
            "network-workgroup-symbolic", Gtk.IconSize.LARGE_TOOLBAR
        )
        header_box.pack_start(icon_img, False, False, 0)

        self.lbl_active = Gtk.Label(xalign=0.0)
        self.lbl_active.set_markup(
            "<span size='large'>Active proxy: <b>Connecting...</b></span>"
        )
        header_box.pack_start(self.lbl_active, True, True, 0)

        vbox.pack_start(
            Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL),
            False,
            False,
            5,
        )

        # Dynamic Final Fallback Toggle Frame
        frame_final = Gtk.Frame(label="Global Fallback Routing")
        vbox.pack_start(frame_final, False, False, 0)

        hbox_final = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL, spacing=10
        )
        hbox_final.set_border_width(10)
        frame_final.add(hbox_final)

        lbl_final_info = Gtk.Label(xalign=0.0)
        lbl_final_info.set_markup("<b>Route unmatched traffic to:</b>")
        hbox_final.pack_start(lbl_final_info, True, True, 0)

        self.lbl_final_state = Gtk.Label(xalign=1.0)
        self.lbl_final_state.set_markup(
            "<span weight='bold' color='gray'>direct</span>"
        )
        hbox_final.pack_end(self.lbl_final_state, False, False, 5)

        self.switch_final = Gtk.Switch()
        self.switch_final.set_valign(Gtk.Align.CENTER)
        self.switch_final.set_halign(Gtk.Align.END)
        self.switch_final.connect(
            "notify::active", self.on_final_switch_toggled
        )
        hbox_final.pack_end(self.switch_final, False, False, 0)

        vbox.pack_start(
            Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL),
            False,
            False,
            5,
        )

        # Search bar
        self.search_entry = Gtk.SearchEntry()
        self.search_entry.set_placeholder_text("Filter proxies...")
        self.search_entry.connect("search-changed", self.on_search_changed)
        vbox.pack_start(self.search_entry, False, False, 0)

        # Frame for Scrolled Window
        frame = Gtk.Frame()
        vbox.pack_start(frame, True, True, 0)

        # Scrollable Box List container
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        frame.add(scrolled)

        self.listbox = Gtk.ListBox()
        self.listbox.set_filter_func(self.filter_rows, None)
        self.listbox.connect("row-activated", self.on_row_activated)
        scrolled.add(self.listbox)

        # Action Buttons layout
        action_box = Gtk.ButtonBox(orientation=Gtk.Orientation.HORIZONTAL)
        action_box.set_layout(Gtk.ButtonBoxStyle.SPREAD)
        vbox.pack_start(action_box, False, False, 5)

        self.btn_test = Gtk.Button(label="Test All Latencies")
        self.btn_test.connect("clicked", self.on_test_delays_clicked)
        action_box.pack_start(self.btn_test, True, True, 0)

        btn_close = Gtk.Button(label="Close")
        btn_close.connect("clicked", Gtk.main_quit)
        action_box.pack_start(btn_close, True, True, 0)

        self.connect("destroy", Gtk.main_quit)
        self.show_all()

        # Connect Async on launch
        self.trigger_async_load()

    def api_get(self, endpoint):
        req = urllib.request.Request(f"{API_BASE}{endpoint}")
        with urllib.request.urlopen(req, timeout=2) as response:
            return json.loads(response.read().decode("utf-8"))

    def api_put(self, endpoint, payload):
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            f"{API_BASE}{endpoint}", data=data, method="PUT"
        )
        req.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(req, timeout=2) as response:
            return response.status

    def filter_rows(self, row, _user_data):
        search_text = self.search_entry.get_text().lower()
        if not search_text:
            return True
        return search_text in row.node_name.lower()

    def on_search_changed(self, _entry):
        self.listbox.invalidate_filter()

    def trigger_async_load(self):
        threading.Thread(target=self.bg_load_proxies, daemon=True).start()

    def bg_load_proxies(self):
        try:
            # Query all proxies to find the correct selector tag automatically
            data = self.api_get("/proxies")
            proxies = data.get("proxies", {})

            # Look for selector keys (proxy or out)
            for key in ["proxy", "out"]:
                if key in proxies and proxies[key].get("type") == "Selector":
                    self.selector_name = key
                    break

            selector_data = proxies.get(self.selector_name, {})
            self.nodes = selector_data.get("all", [])
            self.active_node = selector_data.get("now", "")

            # Sync final fallback route state
            final_data = proxies.get("final-toggle", {})
            self.final_now = final_data.get("now", "direct")

            GLib.idle_add(self.update_ui_nodes)
        except Exception as e:
            GLib.idle_add(self.show_connection_error, str(e))

    def update_ui_nodes(self):
        self.lbl_active.set_markup(
            f"Active proxy: <span color='#2ecc71'><b>{self.active_node}</b></span>"
        )

        # Lock switch updates to prevent infinite event feedback loop
        self.updating_ui = True
        is_proxy_mode = self.final_now == "proxy"
        self.switch_final.set_active(is_proxy_mode)
        if is_proxy_mode:
            self.lbl_final_state.set_markup(
                "<span weight='bold' color='#3498db'>proxy</span>"
            )
        else:
            self.lbl_final_state.set_markup(
                "<span weight='bold' color='#95a5a6'>direct</span>"
            )
        self.updating_ui = False

        # Clear existing rows
        for child in self.listbox.get_children():
            self.listbox.remove(child)

        for node in self.nodes:
            is_active = node == self.active_node
            row = ProxyRow(node, is_active)
            self.listbox.add(row)

        self.listbox.show_all()

    def show_connection_error(self, error_details):
        self.lbl_active.set_markup(
            "<span color='#e74c3c'><b>Cannot connect to sing-box API!</b></span>"
        )

        # Clear list on fail and show error row
        for child in self.listbox.get_children():
            self.listbox.remove(child)

        row = Gtk.ListBoxRow()
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        box.set_border_width(12)
        lbl = Gtk.Label(xalign=0.0)
        lbl.set_markup(
            f"<span color='gray'>Is sing-box started? (Port 9090)\nDetails: {error_details}</span>"
        )
        box.add(lbl)
        row.add(box)
        self.listbox.add(row)
        self.listbox.show_all()

    def on_row_activated(self, _listbox, row):
        if not hasattr(row, "node_name") or row.is_active:
            return

        self.lbl_active.set_markup(f"Switching to <b>{row.node_name}...</b>")
        threading.Thread(
            target=self.bg_switch_proxy, args=(row.node_name,), daemon=True
        ).start()

    def bg_switch_proxy(self, target_node):
        try:
            self.api_put(
                f"/proxies/{self.selector_name}", {"name": target_node}
            )
            self.bg_load_proxies()
        except Exception as e:
            GLib.idle_add(
                self.show_error_dialog, "Failed to switch proxy", str(e)
            )

    def on_final_switch_toggled(self, switch, _gparamspec):
        if self.updating_ui:
            return

        active = switch.get_active()
        target_mode = "proxy" if active else "direct"

        if active:
            self.lbl_final_state.set_markup(
                "<span weight='bold' color='#3498db'>proxy</span>"
            )
        else:
            self.lbl_final_state.set_markup(
                "<span weight='bold' color='#95a5a6'>direct</span>"
            )

        threading.Thread(
            target=self.bg_switch_final, args=(target_mode,), daemon=True
        ).start()

    def bg_switch_final(self, target_mode):
        try:
            self.api_put("/proxies/final-toggle", {"name": target_mode})
        except Exception as e:
            GLib.idle_add(
                self.show_error_dialog,
                "Failed to set default fallback route",
                str(e),
            )

    def on_test_delays_clicked(self, _button):
        self.btn_test.set_sensitive(False)
        self.btn_test.set_label("Testing all nodes...")
        threading.Thread(target=self.bg_test_all_delays, daemon=True).start()

    def bg_test_all_delays(self):
        target_url = urllib.parse.quote("http://www.gstatic.com/generate_204")

        rows = [
            r for r in self.listbox.get_children() if hasattr(r, "node_name")
        ]
        for r in rows:
            GLib.idle_add(r.set_delay, -1)

        for r in rows:
            node_encoded = urllib.parse.quote(r.node_name)
            endpoint = (
                f"/proxies/{node_encoded}/delay?timeout=3000&url={target_url}"
            )
            try:
                res = self.api_get(endpoint)
                delay = res.get("delay", 0)
                GLib.idle_add(r.set_delay, delay)
            except urllib.error.HTTPError:
                GLib.idle_add(r.set_delay, -2)
            except Exception:
                GLib.idle_add(r.set_delay, -2)

            time.sleep(0.05)

        GLib.idle_add(self.reset_test_button)

    def reset_test_button(self):
        self.btn_test.set_sensitive(True)
        self.btn_test.set_label("Test All Latencies")

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
    ClashControlWindow()
    Gtk.main()
