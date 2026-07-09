import sys
import os
import re
import subprocess
import configparser
import json
import threading
import queue
import urllib.request
import tempfile
import shutil
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, GdkPixbuf, GLib

proton_versions_json = os.environ.get("UMU_PROTON_VERSIONS_JSON")
if not proton_versions_json:
    print(
        "Error: UMU_PROTON_VERSIONS_JSON environment variable is not set.",
        file=sys.stderr,
    )
    sys.exit(1)

try:
    proton_versions = json.loads(proton_versions_json)
except Exception as e:
    print(
        f"Error: Failed to parse UMU_PROTON_VERSIONS_JSON: {e}",
        file=sys.stderr,
    )
    sys.exit(1)

default_proton_name = next(
    (v["name"] for v in proton_versions if v.get("default")),
    proton_versions[0]["name"],
)


def scan_gpus():
    amd, nvidia, intel = "", "", ""
    try:
        res = subprocess.run(["lspci", "-nn"], capture_output=True, text=True)
        for line in res.stdout.splitlines():
            if any(
                x in line
                for x in [
                    "VGA compatible controller",
                    "3D controller",
                    "Display controller",
                ]
            ):
                match = re.search(r"\[([0-9a-fA-F]{4}:[0-9a-fA-F]{4})\]", line)
                if match:
                    pci_id = match.group(1)
                    l = line.lower()
                    if "nvidia" in l:
                        nvidia_id = pci_id
                    elif any(
                        x in l
                        for x in ["amd", "advanced micro devices", "ati"]
                    ):
                        amd = pci_id
                    elif "intel" in l:
                        intel = pci_id
    except Exception:
        pass
    return amd, nvidia, intel


class SteamSearchDialog(Gtk.Dialog):
    def __init__(self, parent):
        super().__init__(
            title="Поиск в Steam",
            transient_for=parent,
            modal=True,
            destroy_with_parent=True,
        )
        self.set_default_size(550, 500)
        self.set_border_width(10)
        self.set_position(Gtk.WindowPosition.CENTER_ON_PARENT)
        self.set_resizable(True)

        self.selected_game = None
        self.search_id = 0

        vbox = self.get_content_area()
        vbox.set_spacing(10)

        search_hbox = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL, spacing=5
        )
        vbox.pack_start(search_hbox, False, False, 0)

        self.search_entry = Gtk.Entry()
        self.search_entry.set_placeholder_text(
            "Введите название игры или AppID..."
        )
        self.search_entry.connect("activate", self.on_search_activated)
        search_hbox.pack_start(self.search_entry, True, True, 0)

        btn_search = Gtk.Button(label="Поиск")
        btn_search.connect("clicked", self.on_search_activated)
        search_hbox.pack_start(btn_search, False, False, 0)

        self.store = Gtk.ListStore(GdkPixbuf.Pixbuf, str, str)
        self.treeview = Gtk.TreeView(model=self.store)
        self.treeview.connect("row-activated", self.on_row_activated)
        self.treeview.get_selection().connect(
            "changed", self.on_selection_changed
        )

        renderer_px = Gtk.CellRendererPixbuf()
        renderer_px.set_property("ypad", 6)
        renderer_px.set_property("xpad", 6)
        col_px = Gtk.TreeViewColumn("", renderer_px)
        col_px.set_cell_data_func(renderer_px, self.set_icon_cell)
        self.treeview.append_column(col_px)

        renderer_txt = Gtk.CellRendererText()
        renderer_txt.set_property("ypad", 6)
        renderer_txt.set_property("xpad", 6)
        col_txt = Gtk.TreeViewColumn("Результаты поиска", renderer_txt, text=1)
        col_txt.set_expand(True)
        self.treeview.append_column(col_txt)

        scroll = Gtk.ScrolledWindow()
        scroll.add(self.treeview)
        vbox.pack_start(scroll, True, True, 0)

        status_hbox = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL, spacing=10
        )
        vbox.pack_start(status_hbox, False, False, 0)

        self.lbl_status = Gtk.Label()
        self.lbl_status.set_markup(
            "<span foreground='gray'>Ожидание поиска</span>"
        )
        status_hbox.pack_start(self.lbl_status, True, True, 0)

        self.spinner = Gtk.Spinner()
        status_hbox.pack_start(self.spinner, False, False, 0)

        self.add_button("Отмена", Gtk.ResponseType.CANCEL)
        self.btn_ok = self.add_button("Выбрать", Gtk.ResponseType.OK)
        self.btn_ok.set_sensitive(False)

        self.placeholder_pixbuf = None
        try:
            scale = self.get_scale_factor()
            theme = Gtk.IconTheme.get_default()
            self.placeholder_pixbuf = theme.load_icon("wine", 64 * scale, 0)
        except Exception:
            pass

        self.apps = []
        threading.Thread(target=self.load_database, daemon=True).start()

        self.fetch_queue = queue.Queue()

        for _ in range(32):
            threading.Thread(target=self.fetch_worker, daemon=True).start()

        self.show_all()
        self.spinner.hide()

    def set_icon_cell(self, tree_column, cell, model, iter, data):
        pixbuf = model.get_value(iter, 0)
        if pixbuf:
            scale = self.get_scale_factor()
            if scale > 1:
                try:
                    surface = Gdk.cairo_surface_create_from_pixbuf(
                        pixbuf, scale, None
                    )
                    cell.set_property("surface", surface)
                    return
                except Exception:
                    pass
            cell.set_property("pixbuf", pixbuf)
        else:
            cell.set_property("pixbuf", None)

    def load_database(self):
        db_path = os.environ.get("STEAM_APP_ID_LIST_PATH")
        if not db_path or not os.path.exists(db_path):
            GLib.idle_add(
                self.lbl_status.set_markup,
                "<span foreground='red'>БД Steam не найдена!</span>",
            )
            return

        try:
            with open(db_path, "r", encoding="utf-8") as f:
                data = json.load(f)

            loaded_apps = []
            if isinstance(data, list):
                for item in data:
                    if isinstance(item, dict):
                        name = item.get("name", "")
                        appid = str(item.get("appid", ""))
                        if name and appid:
                            loaded_apps.append({"name": name, "appid": appid})
            elif isinstance(data, dict):
                for k, v in data.items():
                    if isinstance(v, dict):
                        loaded_apps.append(
                            {"name": v.get("name", ""), "appid": str(k)}
                        )
                    else:
                        loaded_apps.append({"name": str(v), "appid": str(k)})

            self.apps = loaded_apps
            GLib.idle_add(
                self.lbl_status.set_markup,
                "<span foreground='green'>БД Steam загружена</span>",
            )
        except Exception as e:
            GLib.idle_add(
                self.lbl_status.set_markup,
                f"<span foreground='red'>Ошибка БД: {e}</span>",
            )

    def on_search_activated(self, widget):
        query = self.search_entry.get_text().strip().lower()
        if not query:
            return

        self.search_id += 1
        self.store.clear()

        while not self.fetch_queue.empty():
            try:
                self.fetch_queue.get_nowait()
            except queue.Empty:
                break

        results = []
        for app in self.apps:
            if query in app["name"].lower() or query == app["appid"]:
                results.append(app)
                if len(results) >= 80:
                    break

        for res in results:
            self.store.append(
                [
                    self.placeholder_pixbuf,
                    f"{res['name']} ({res['appid']})",
                    res["appid"],
                ]
            )
            self.fetch_queue.put((self.search_id, res["appid"], res["name"]))

        self.lbl_status.set_markup(f"Найдено игр: {len(results)}")

    def on_selection_changed(self, selection):
        model, tree_iter = selection.get_selected()
        self.btn_ok.set_sensitive(tree_iter is not None)

    def on_row_activated(self, treeview, path, column):
        if self.btn_ok.get_sensitive():
            self.response(Gtk.ResponseType.OK)

    def fetch_worker(self):
        while True:
            try:
                search_id, appid, name = self.fetch_queue.get(timeout=1)
            except queue.Empty:
                continue

            if search_id != self.search_id:
                continue

            icon_path = self.get_cached_icon_path(appid)
            if not icon_path:
                icon_path = self.download_steam_icon(appid)

            if (
                search_id == self.search_id
                and icon_path
                and os.path.exists(icon_path)
            ):
                try:
                    scale = self.get_scale_factor()
                    size = 64 * scale
                    pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(
                        icon_path, size, size, True
                    )
                    GLib.idle_add(
                        self.update_store_icon, search_id, appid, pixbuf
                    )
                except Exception:
                    pass

    def get_cached_icon_path(self, appid):
        p = os.path.expanduser(f"~/.cache/umu/icons/steam-{appid}.png")
        return p if os.path.exists(p) else None

    def update_store_icon(self, search_id, appid, pixbuf):
        if search_id != self.search_id:
            return False
        model = self.store
        iter_ = model.get_iter_first()
        while iter_ is not None:
            if model.get_value(iter_, 2) == appid:
                model.set_value(iter_, 0, pixbuf)
                break
            iter_ = model.iter_next(iter_)
        return False

    def _fetch_with_retry(self, url, max_retries=50, timeout=0.5):
        req = urllib.request.Request(
            url, headers={"User-Agent": "Mozilla/5.0"}
        )
        for attempt in range(max_retries):
            try:
                with urllib.request.urlopen(req, timeout=timeout) as r:
                    return r.read()
            except Exception:
                pass
        return None

    def download_steam_icon(self, appid):
        try:
            api_url = f"https://api.steamcmd.net/v1/info/{appid}"
            meta_data = self._fetch_with_retry(api_url)
            if not meta_data:
                return None

            metadata = json.loads(meta_data.decode("utf-8"))
            app_data = metadata.get("data", {}).get(str(appid), {})
            client_icon_hash = app_data.get("common", {}).get("clienticon")

            if not client_icon_hash:
                return None

            ico_url = f"https://cdn.cloudflare.steamstatic.com/steamcommunity/public/images/apps/{appid}/{client_icon_hash}.ico"
            cache_dir = os.path.expanduser("~/.cache/umu/icons")
            os.makedirs(cache_dir, exist_ok=True)
            dest_png = os.path.join(cache_dir, f"steam-{appid}.png")

            img_data = self._fetch_with_retry(ico_url)
            if not img_data:
                return None

            work_dir = tempfile.mkdtemp()
            try:
                tmp_ico = os.path.join(work_dir, "icon.ico")
                with open(tmp_ico, "wb") as f_img:
                    f_img.write(img_data)

                subprocess.run(
                    ["magick", tmp_ico, os.path.join(work_dir, "icon.png")],
                    stderr=subprocess.DEVNULL,
                )

                pngs = [
                    f
                    for f in os.listdir(work_dir)
                    if f.startswith("icon") and f.endswith(".png")
                ]
                if pngs:
                    pngs.sort(
                        key=lambda x: os.path.getsize(
                            os.path.join(work_dir, x)
                        ),
                        reverse=True,
                    )
                    shutil.copy(os.path.join(work_dir, pngs[0]), dest_png)
                    return dest_png
            finally:
                shutil.rmtree(work_dir, ignore_errors=True)

            return None
        except Exception:
            return None

    def get_selected_game(self):
        model, tree_iter = self.treeview.get_selection().get_selected()
        if tree_iter:
            raw_text = model.get_value(tree_iter, 1)
            appid = model.get_value(tree_iter, 2)
            name = (
                raw_text.replace(f" ({appid})", "")
                if f" ({appid})" in raw_text
                else raw_text
            )
            icon_path = self.get_cached_icon_path(appid)
            return name, appid, icon_path
        return None


class EditDialog(Gtk.Dialog):
    def __init__(self, parent, desktop_path):
        super().__init__(
            title="Редактирование ярлыка",
            transient_for=parent,
            modal=True,
            destroy_with_parent=True,
        )
        self.set_border_width(15)
        self.set_default_size(500, -1)
        self.set_position(Gtk.WindowPosition.CENTER_ON_PARENT)
        self.set_resizable(False)  # <-- REVERTED to False

        self.desktop_path = desktop_path
        self.amd_id, self.nvidia_id, self.intel_id = scan_gpus()

        self.config = configparser.ConfigParser(
            interpolation=None, strict=False
        )
        self.config.optionxform = str
        self.config.read(desktop_path, encoding="utf-8")

        self.current_name = self.config.get(
            "Desktop Entry", "Name", fallback=""
        )
        self.current_icon = self.config.get(
            "Desktop Entry", "Icon", fallback="wine"
        )
        self.raw_args = self.config.get(
            "Desktop Entry", "X-UMU-Raw-Args", fallback=""
        )
        self.actual_exe = self.config.get(
            "Desktop Entry", "X-UMU-Actual-Exe", fallback=""
        )
        self.lnk_path = self.config.get(
            "Desktop Entry", "X-UMU-Lnk-Path", fallback=""
        )
        self.prefix_name = self.config.get(
            "Desktop Entry", "X-UMU-Prefix-Name", fallback="default"
        )
        self.gpu_select = self.config.get(
            "Desktop Entry", "X-UMU-GPU-Select", fallback="Автоматически"
        )

        exec_line = self.config.get("Desktop Entry", "Exec", fallback="")
        self.wayland_enabled = "PROTON_ENABLE_WAYLAND=0" not in exec_line
        self.gamemode_enabled = "USE_GAMEMODE=0" not in exec_line
        self.mangohud_enabled = "USE_MANGOHUD=0" not in exec_line

        gameid_match = re.search(r"GAMEID=([^\s]+)", exec_line)
        self.gameid = ""
        if gameid_match:
            self.gameid = gameid_match.group(1).replace('"', "")
        self.gameid = self.config.get(
            "Desktop Entry", "X-UMU-Game-ID", fallback=self.gameid
        )

        self.proton_type = self.config.get(
            "Desktop Entry", "X-UMU-Proton-Type", fallback=default_proton_name
        )

        steam_val = self.config.get(
            "Desktop Entry", "X-UMU-Steam-Integration", fallback="0"
        )
        self.steam_enabled = steam_val == "1"

        overlay_val = self.config.get(
            "Desktop Entry", "X-UMU-Steam-Overlay", fallback="0"
        )
        self.overlay_enabled = overlay_val == "1"

        vpn_val = self.config.get("Desktop Entry", "X-UMU-VPN", fallback="0")
        self.vpn_enabled = vpn_val == "1"

        content_area = self.get_content_area()
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        content_area.pack_start(vbox, True, True, 0)

        title_hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=5)
        vbox.pack_start(title_hbox, False, False, 0)

        lbl_prefix = Gtk.Label()
        lbl_prefix.set_markup("<b>Редактирование:</b>")
        title_hbox.pack_start(lbl_prefix, False, False, 0)

        lbl_file = Gtk.Label()
        lbl_file.set_markup(f"<b>{self.current_name}</b>")
        title_hbox.pack_start(lbl_file, False, False, 0)

        grid = Gtk.Grid(column_spacing=15, row_spacing=10)
        vbox.pack_start(grid, False, False, 0)

        lbl_proton = Gtk.Label(label="Версия Proton:")
        lbl_proton.set_alignment(0, 0.5)
        self.cmb_proton = Gtk.ComboBoxText()
        for v in proton_versions:
            self.cmb_proton.append(v["name"], v["name"])
        if not self.cmb_proton.set_active_id(self.proton_type):
            self.cmb_proton.set_active(0)
        grid.attach(lbl_proton, 0, 0, 1, 1)
        grid.attach(self.cmb_proton, 1, 0, 1, 1)

        lbl_gamemode = Gtk.Label(label="Использовать GameMode:")
        lbl_gamemode.set_alignment(0, 0.5)
        self.chk_gamemode = Gtk.CheckButton()
        self.chk_gamemode.set_active(self.gamemode_enabled)
        grid.attach(lbl_gamemode, 0, 1, 1, 1)
        grid.attach(self.chk_gamemode, 1, 1, 1, 1)

        lbl_mangohud = Gtk.Label(label="Использовать MangoHud:")
        lbl_mangohud.set_alignment(0, 0.5)
        self.chk_mangohud = Gtk.CheckButton()
        self.chk_mangohud.set_active(self.mangohud_enabled)
        grid.attach(lbl_mangohud, 0, 2, 1, 1)
        grid.attach(self.chk_mangohud, 1, 2, 1, 1)

        lbl_wayland = Gtk.Label(label="Использовать Wayland:")
        lbl_wayland.set_alignment(0, 0.5)
        self.chk_wayland = Gtk.CheckButton()
        self.chk_wayland.set_active(self.wayland_enabled)
        grid.attach(lbl_wayland, 0, 3, 1, 1)
        grid.attach(self.chk_wayland, 1, 3, 1, 1)

        lbl_steam = Gtk.Label(label="Интеграция со Steam:")
        lbl_steam.set_alignment(0, 0.5)
        self.chk_steam = Gtk.CheckButton()
        self.chk_steam.set_active(self.steam_enabled)
        grid.attach(lbl_steam, 0, 4, 1, 1)
        grid.attach(self.chk_steam, 1, 4, 1, 1)

        lbl_overlay = Gtk.Label(label="Оверлей Steam:")
        lbl_overlay.set_alignment(0, 0.5)
        self.chk_overlay = Gtk.CheckButton()
        self.chk_overlay.set_active(self.overlay_enabled)
        grid.attach(lbl_overlay, 0, 5, 1, 1)
        grid.attach(self.chk_overlay, 1, 5, 1, 1)

        lbl_vpn = Gtk.Label(label="Через VPN:")
        lbl_vpn.set_alignment(0, 0.5)
        self.chk_vpn = Gtk.CheckButton()
        self.chk_vpn.set_active(self.vpn_enabled)
        grid.attach(lbl_vpn, 0, 6, 1, 1)
        grid.attach(self.chk_vpn, 1, 6, 1, 1)

        self.lock_signals = False
        self.chk_overlay.connect("toggled", self.on_overlay_toggled)
        self.chk_wayland.connect("toggled", self.on_wayland_toggled)

        if self.overlay_enabled:
            self.chk_wayland.set_active(False)
            self.chk_wayland.set_sensitive(False)
        elif self.wayland_enabled:
            self.chk_overlay.set_active(False)
            self.chk_overlay.set_sensitive(False)

        lbl_prefix = Gtk.Label(label="Имя префикса (в ~/.umu/):")
        lbl_prefix.set_alignment(0, 0.5)
        self.prefix_entry = Gtk.Entry()
        self.prefix_entry.set_text(self.prefix_name)
        grid.attach(lbl_prefix, 0, 7, 1, 1)
        grid.attach(self.prefix_entry, 1, 7, 1, 1)

        lbl_gpu = Gtk.Label(label="Видеокарта:")
        lbl_gpu.set_alignment(0, 0.5)

        gpu_cb_list = [self.gpu_select]
        for opt in ["Автоматически", "AMD", "Nvidia", "Intel"]:
            if opt != self.gpu_select:
                gpu_cb_list.append(opt)

        self.gpu_combo = Gtk.ComboBoxText()
        for opt in gpu_cb_list:
            self.gpu_combo.append_text(opt)
        self.gpu_combo.set_active(0)
        grid.attach(lbl_gpu, 0, 8, 1, 1)
        grid.attach(self.gpu_combo, 1, 8, 1, 1)

        lbl_name = Gtk.Label(label="Название:")
        lbl_name.set_alignment(0, 0.5)
        self.name_entry = Gtk.Entry()
        self.name_entry.set_text(self.current_name)
        grid.attach(lbl_name, 0, 9, 1, 1)
        grid.attach(self.name_entry, 1, 9, 1, 1)

        lbl_icon = Gtk.Label(label="Иконка (файл):")
        lbl_icon.set_alignment(0, 0.5)
        self.icon_chooser = Gtk.FileChooserButton(
            title="Выберите иконку", action=Gtk.FileChooserAction.OPEN
        )
        self.icon_chooser.set_filename(self.current_icon)
        grid.attach(lbl_icon, 0, 10, 1, 1)

        icon_hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=5)
        icon_hbox.pack_start(self.icon_chooser, True, True, 0)

        self.btn_icon_search = Gtk.Button(label="Поиск в Steam")
        self.btn_icon_search.connect("clicked", self.on_icon_search_clicked)
        icon_hbox.pack_start(self.btn_icon_search, False, False, 0)

        self.btn_reset = Gtk.Button(label="Сбросить")
        self.btn_reset.connect("clicked", self.on_reset_clicked)
        icon_hbox.pack_start(self.btn_reset, False, False, 0)
        grid.attach(icon_hbox, 1, 10, 1, 1)

        lbl_args = Gtk.Label(label="Аргументы запуска:")
        lbl_args.set_alignment(0, 0.5)
        self.args_entry = Gtk.Entry()
        self.args_entry.set_text(self.raw_args)
        self.args_entry.set_placeholder_text("ENV=1 %command% --arg-here")
        grid.attach(lbl_args, 0, 11, 1, 1)
        grid.attach(self.args_entry, 1, 11, 1, 1)

        lbl_gameid = Gtk.Label(label="Game ID / App ID:")
        lbl_gameid.set_alignment(0, 0.5)

        gameid_hbox = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL, spacing=5
        )
        self.gameid_entry = Gtk.Entry()
        self.gameid_entry.set_text(self.gameid)
        self.gameid_entry.set_placeholder_text("Например: umu-292030")
        gameid_hbox.pack_start(self.gameid_entry, True, True, 0)

        self.btn_steam_search = Gtk.Button(label="Поиск в Steam")
        self.btn_steam_search.connect("clicked", self.on_steam_search_clicked)
        gameid_hbox.pack_start(self.btn_steam_search, False, False, 0)

        grid.attach(lbl_gameid, 0, 12, 1, 1)
        grid.attach(gameid_hbox, 1, 12, 1, 1)

        preview_hbox = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL, spacing=10
        )
        vbox.pack_start(preview_hbox, False, False, 5)

        lbl_p_title = Gtk.Label(label="Предпросмотр иконки:")
        preview_hbox.pack_start(lbl_p_title, False, False, 0)

        self.img_preview = Gtk.Image()
        preview_hbox.pack_start(self.img_preview, False, False, 0)

        self.btn_zoom = Gtk.Button(label="Увеличить")
        self.btn_zoom.connect("clicked", self.on_zoom_clicked)
        preview_hbox.pack_start(self.btn_zoom, False, False, 0)

        path_hash = (
            os.path.basename(self.desktop_path)
            .replace("umu-", "")
            .replace(".desktop", "")
        )
        self.default_icon_spec = os.path.expanduser(
            f"~/.local/share/icons/umu/umu-{path_hash}.png"
        )
        if not os.path.exists(self.default_icon_spec):
            self.default_icon_spec = "wine"

        self.update_preview_image(self.current_icon)
        self.icon_chooser.connect("file-set", self.on_icon_file_set)

        self.add_button("Отмена", Gtk.ResponseType.CANCEL)
        self.add_button("Сохранить изменения", Gtk.ResponseType.OK)

        self.show_all()

    def on_steam_search_clicked(self, widget):
        dialog = SteamSearchDialog(self)
        response = dialog.run()
        if response == Gtk.ResponseType.OK:
            selected = dialog.get_selected_game()
            if selected:
                name, appid, icon_path = selected
                game_id = f"umu-{appid}" if appid.isdigit() else appid
                self.gameid_entry.set_text(game_id)
                self.name_entry.set_text(name)
                if icon_path:
                    self.icon_chooser.set_filename(icon_path)
                    self.update_preview_image(icon_path)
        dialog.destroy()

    def on_icon_search_clicked(self, widget):
        dialog = SteamSearchDialog(self)
        response = dialog.run()
        if response == Gtk.ResponseType.OK:
            selected = dialog.get_selected_game()
            if selected:
                name, appid, icon_path = selected
                if icon_path:
                    self.icon_chooser.set_filename(icon_path)
                    self.update_preview_image(icon_path)
                self.name_entry.set_text(name)
        dialog.destroy()

    def on_overlay_toggled(self, widget):
        if self.lock_signals:
            return
        self.lock_signals = True
        if widget.get_active():
            self.chk_wayland.set_active(False)
            self.chk_wayland.set_sensitive(False)
        else:
            self.chk_wayland.set_sensitive(True)
        self.lock_signals = False

    def on_wayland_toggled(self, widget):
        if self.lock_signals:
            return
        self.lock_signals = True
        if widget.get_active():
            self.chk_overlay.set_active(False)
            self.chk_overlay.set_sensitive(False)
        else:
            self.chk_overlay.set_sensitive(True)
        self.lock_signals = False

    def on_icon_file_set(self, widget):
        self.update_preview_image(widget.get_filename())

    def on_reset_clicked(self, widget):
        if self.default_icon_spec:
            self.icon_chooser.set_filename(self.default_icon_spec)
            self.update_preview_image(self.default_icon_spec)

    def on_zoom_clicked(self, widget):
        path = self.icon_chooser.get_filename() or self.default_icon_spec
        if not path or not os.path.exists(path):
            return
        zoom_win = Gtk.Window(title="Предпросмотр")
        zoom_win.set_border_width(10)
        zoom_win.set_position(Gtk.WindowPosition.CENTER_ON_PARENT)
        zoom_win.set_type_hint(Gdk.WindowTypeHint.DIALOG)
        zoom_win.set_resizable(False)  # <-- REVERTED to False
        zoom_win.set_transient_for(self)
        zoom_win.set_modal(True)

        def on_key(w, event):
            if event.keyval == Gdk.keyval_from_name("Escape"):
                w.destroy()
                return True
            return False

        zoom_win.connect("key-press-event", on_key)
        zoom_win.connect("delete-event", lambda w, e: w.destroy() or True)

        img = Gtk.Image()
        try:
            scale = self.get_scale_factor()
            size = 256 * scale
            pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(
                path, size, size, True
            )
            if scale > 1:
                surface = Gdk.cairo_surface_create_from_pixbuf(
                    pixbuf, scale, None
                )
                img.set_from_surface(surface)
            else:
                img.set_from_pixbuf(pixbuf)
        except Exception:
            img.set_from_icon_name("wine", Gtk.IconSize.DIALOG)
        zoom_win.add(img)
        zoom_win.show_all()

    def update_preview_image(self, path):
        if path and os.path.exists(path):
            try:
                scale = self.get_scale_factor()
                size = 48 * scale
                pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(
                    path, size, size, True
                )
                if scale > 1:
                    surface = Gdk.cairo_surface_create_from_pixbuf(
                        pixbuf, scale, None
                    )
                    self.img_preview.set_from_surface(surface)
                else:
                    self.img_preview.set_from_pixbuf(pixbuf)
            except Exception:
                self.img_preview.set_from_icon_name(
                    "wine", Gtk.IconSize.DIALOG
                )
        else:
            self.img_preview.set_from_icon_name("wine", Gtk.IconSize.DIALOG)

    def save_changes(self):
        new_name = self.name_entry.get_text().strip()
        new_icon = self.icon_chooser.get_filename() or "wine"
        new_args = self.args_entry.get_text().strip()
        new_prefix = self.prefix_entry.get_text().strip()
        new_gpu = self.gpu_combo.get_active_text()
        new_proton = self.cmb_proton.get_active_id() or default_proton_name
        new_gameid = self.gameid_entry.get_text().strip()

        env_gamemode = "1" if self.chk_gamemode.get_active() else "0"
        env_mangohud = "1" if self.chk_mangohud.get_active() else "0"
        env_wayland = "1" if self.chk_wayland.get_active() else "0"
        env_steam = "1" if self.chk_steam.get_active() else "0"
        env_overlay = "1" if self.chk_overlay.get_active() else "0"
        env_vpn = "1" if self.chk_vpn.get_active() else "0"

        gpu_env = ""
        if new_gpu == "Nvidia":
            gpu_env = "__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only"
            if self.nvidia_id:
                gpu_env += f" DRI_PRIME={self.nvidia_id}! MESA_VK_DEVICE_SELECT={self.nvidia_id}!"
        elif new_gpu == "AMD" and self.amd_id:
            gpu_env = f"DRI_PRIME={self.amd_id}! MESA_VK_DEVICE_SELECT={self.amd_id}!"
        elif new_gpu == "Intel" and self.intel_id:
            gpu_env = f"DRI_PRIME={self.intel_id}! MESA_VK_DEVICE_SELECT={self.intel_id}!"

        exec_base = f'env GAMEID={new_gameid} USE_GAMEMODE={env_gamemode} USE_MANGOHUD={env_mangohud} PROTON_ENABLE_WAYLAND={env_wayland} UMU_PREFIX_NAME={new_prefix} UMU_PROTON_TYPE="{new_proton}" USE_STEAM_INTEGRATION={env_steam} USE_STEAM_OVERLAY={env_overlay} USE_VPN={env_vpn} {gpu_env}'.strip()
        exec_base += " umu-run-wrapper"

        if "%command%" in new_args:
            exec_cmd = new_args.replace(
                "%command%", f'{exec_base} "{self.actual_exe}"'
            )
        else:
            exec_cmd = f'{exec_base} "{self.actual_exe}" {new_args}'

        self.config["Desktop Entry"]["Name"] = new_name
        self.config["Desktop Entry"]["Icon"] = new_icon
        self.config["Desktop Entry"]["Exec"] = exec_cmd
        self.config["Desktop Entry"]["X-UMU-Raw-Args"] = new_args
        self.config["Desktop Entry"]["X-UMU-Prefix-Name"] = new_prefix
        self.config["Desktop Entry"]["X-UMU-GPU-Select"] = new_gpu
        self.config["Desktop Entry"]["X-UMU-Steam-Integration"] = env_steam
        self.config["Desktop Entry"]["X-UMU-Steam-Overlay"] = env_overlay
        self.config["Desktop Entry"]["X-UMU-Proton-Type"] = new_proton
        self.config["Desktop Entry"]["X-UMU-VPN"] = env_vpn
        self.config["Desktop Entry"]["X-UMU-Game-ID"] = new_gameid

        with open(self.desktop_path, "w", encoding="utf-8") as f:
            self.config.write(f, space_around_delimiters=False)


class ShortcutsManager(Gtk.Window):
    def __init__(self):
        super().__init__(title="Manage UMU Shortcuts")
        self.set_default_size(750, 480)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_border_width(10)

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.add(vbox)

        search_hbox = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL, spacing=5
        )
        vbox.pack_start(search_hbox, False, False, 0)

        search_lbl = Gtk.Label(label="Поиск ярлыков:")
        search_hbox.pack_start(search_lbl, False, False, 5)

        self.search_entry = Gtk.Entry()
        self.search_entry.connect("changed", self.on_search_changed)
        search_hbox.pack_start(self.search_entry, True, True, 5)

        self.store = Gtk.ListStore(GdkPixbuf.Pixbuf, str, str)
        self.filter_store = self.store.filter_new()
        self.filter_store.set_visible_func(self.filter_search_results)

        self.treeview = Gtk.TreeView(model=self.filter_store)
        scroll = Gtk.ScrolledWindow()
        scroll.add(self.treeview)
        vbox.pack_start(scroll, True, True, 0)

        renderer_px = Gtk.CellRendererPixbuf()
        renderer_px.set_property("ypad", 6)
        renderer_px.set_property("xpad", 6)
        col_px = Gtk.TreeViewColumn("Иконка", renderer_px)
        col_px.set_cell_data_func(renderer_px, self.set_icon_cell)
        self.treeview.append_column(col_px)

        renderer_txt = Gtk.CellRendererText()
        renderer_txt.set_property("ypad", 6)
        renderer_txt.set_property("xpad", 6)
        col_txt = Gtk.TreeViewColumn("Название", renderer_txt, text=1)
        col_txt.set_expand(True)
        self.treeview.append_column(col_txt)

        self.treeview.connect("row-activated", self.on_row_double_clicked)

        bbox = Gtk.ButtonBox(
            orientation=Gtk.Orientation.HORIZONTAL, spacing=10
        )
        bbox.set_layout(Gtk.ButtonBoxStyle.END)
        vbox.pack_start(bbox, False, False, 0)

        self.btn_edit = Gtk.Button(label="Редактировать")
        self.btn_edit.connect("clicked", self.on_edit_clicked)
        bbox.pack_start(self.btn_edit, True, True, 0)

        self.btn_delete = Gtk.Button(label="Удалить ярлык")
        self.btn_delete.connect("clicked", self.on_delete_clicked)
        bbox.pack_start(self.btn_delete, True, True, 0)

        self.btn_close = Gtk.Button(label="Закрыть")
        self.btn_close.connect("clicked", Gtk.main_quit)
        bbox.pack_start(self.btn_close, True, True, 0)

        self.connect("destroy", Gtk.main_quit)
        self.populate_list()
        self.show_all()

    def set_icon_cell(self, tree_column, cell, model, iter, data):
        pixbuf = model.get_value(iter, 0)
        if pixbuf:
            scale = self.get_scale_factor()
            if scale > 1:
                try:
                    surface = Gdk.cairo_surface_create_from_pixbuf(
                        pixbuf, scale, None
                    )
                    cell.set_property("surface", surface)
                    return
                except Exception:
                    pass
            cell.set_property("pixbuf", pixbuf)
        else:
            cell.set_property("pixbuf", None)

    def load_scaled_icon(self, icon_path):
        scale = self.get_scale_factor()
        size = 64 * scale
        try:
            if icon_path and os.path.exists(icon_path):
                return GdkPixbuf.Pixbuf.new_from_file_at_scale(
                    icon_path, size, size, True
                )
            else:
                theme = Gtk.IconTheme.get_default()
                return theme.load_icon("wine", size, 0)
        except Exception:
            try:
                theme = Gtk.IconTheme.get_default()
                return theme.load_icon("wine", size, 0)
            except Exception:
                return None

    def populate_list(self):
        self.store.clear()
        desktop_dir = os.path.expanduser("~/.local/share/applications")
        if not os.path.exists(desktop_dir):
            return

        for f in os.listdir(desktop_dir):
            if f.startswith("umu-") and f.endswith(".desktop"):
                path = os.path.join(desktop_dir, f)
                try:
                    config = configparser.ConfigParser(
                        interpolation=None, strict=False
                    )
                    config.optionxform = str
                    config.read(path, encoding="utf-8")
                    if "Desktop Entry" in config:
                        name = config.get("Desktop Entry", "Name", fallback=f)
                        icon = config.get(
                            "Desktop Entry", "Icon", fallback="wine"
                        )
                        pixbuf = self.load_scaled_icon(icon)
                        self.store.append([pixbuf, name, path])
                except Exception:
                    pass

    def on_search_changed(self, widget):
        self.filter_store.refilter()

    def filter_search_results(self, model, iter, data):
        search_query = self.search_entry.get_text().strip().lower()
        if not search_query:
            return True
        name = model[iter][1]
        return search_query in name.lower() if name else False

    def on_row_double_clicked(self, treeview, path, column):
        self.on_edit_clicked(None)

    def on_edit_clicked(self, widget):
        selection = self.treeview.get_selection()
        model, iter = selection.get_selected()
        if iter:
            desktop_path = model[iter][2]
            dialog = EditDialog(self, desktop_path)
            response = dialog.run()
            if response == Gtk.ResponseType.OK:
                dialog.save_changes()
                self.populate_list()
            dialog.destroy()

    def on_delete_clicked(self, widget):
        selection = self.treeview.get_selection()
        model, iter = selection.get_selected()
        if iter:
            name = model[iter][1]
            desktop_path = model[iter][2]

            confirm = Gtk.MessageDialog(
                transient_for=self,
                modal=True,
                destroy_with_parent=True,
                type=Gtk.MessageType.QUESTION,
                buttons=Gtk.ButtonsType.YES_NO,
                message_format=f"Вы уверены, что хотите полностью удалить ярлык '{name}'?",
            )
            res = confirm.run()
            confirm.destroy()
            if res == Gtk.ResponseType.YES:
                os.remove(desktop_path)
                self.populate_list()


if __name__ == "__main__":
    ShortcutsManager()
    Gtk.main()
