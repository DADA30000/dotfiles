import sys
import os
import re
import shlex
import subprocess
import tempfile
import hashlib
import shutil
import json
import threading
import queue
import urllib.request
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

        # WM Floating Hack
        self.set_resizable(False)
        GLib.timeout_add(150, lambda: self.set_resizable(True) or False)

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


class LauncherWindow(Gtk.Window):
    def __init__(self, filepath):
        super().__init__(title="UMU Launcher")
        self.filepath = os.path.abspath(filepath)
        self.set_border_width(15)
        self.set_default_size(460, -1)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_type_hint(Gdk.WindowTypeHint.DIALOG)

        # WM Floating Hack
        self.set_resizable(False)
        GLib.timeout_add(150, lambda: self.set_resizable(True) or False)

        self.amd_id, self.nvidia_id, self.intel_id = scan_gpus()

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.add(vbox)

        title_hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=5)
        vbox.pack_start(title_hbox, False, False, 0)

        lbl_prefix = Gtk.Label()
        lbl_prefix.set_markup("<b>Запуск:</b>")
        title_hbox.pack_start(lbl_prefix, False, False, 0)

        lbl_file = Gtk.Label()
        lbl_file.set_markup(f"<b>{os.path.basename(self.filepath)}</b>")
        title_hbox.pack_start(lbl_file, False, False, 0)

        grid = Gtk.Grid(column_spacing=15, row_spacing=10)
        vbox.pack_start(grid, False, False, 0)

        lbl_proton = Gtk.Label(label="Версия Proton:")
        lbl_proton.set_xalign(0.0)
        lbl_proton.set_yalign(0.5)
        self.cmb_proton = Gtk.ComboBoxText()
        for v in proton_versions:
            self.cmb_proton.append(v["name"], v["name"])
        cur_proton = os.environ.get("UMU_PROTON_TYPE", default_proton_name)
        if not self.cmb_proton.set_active_id(cur_proton):
            self.cmb_proton.set_active(0)
        grid.attach(lbl_proton, 0, 0, 1, 1)
        grid.attach(self.cmb_proton, 1, 0, 1, 1)

        lbl_gamemode = Gtk.Label(label="Использовать GameMode:")
        lbl_gamemode.set_xalign(0.0)
        lbl_gamemode.set_yalign(0.5)
        self.chk_gamemode = Gtk.CheckButton()
        self.chk_gamemode.set_active(
            os.environ.get("USE_GAMEMODE", "1") != "0"
        )
        grid.attach(lbl_gamemode, 0, 1, 1, 1)
        grid.attach(self.chk_gamemode, 1, 1, 1, 1)

        lbl_mangohud = Gtk.Label(label="Использовать MangoHud:")
        lbl_mangohud.set_xalign(0.0)
        lbl_mangohud.set_yalign(0.5)
        self.chk_mangohud = Gtk.CheckButton()
        self.chk_mangohud.set_active(
            os.environ.get("USE_MANGOHUD", "1") != "0"
        )
        grid.attach(lbl_mangohud, 0, 2, 1, 1)
        grid.attach(self.chk_mangohud, 1, 2, 1, 1)

        lbl_wayland = Gtk.Label(label="Использовать Wayland:")
        lbl_wayland.set_xalign(0.0)
        lbl_wayland.set_yalign(0.5)
        self.chk_wayland = Gtk.CheckButton()
        self.chk_wayland.set_active(
            os.environ.get("PROTON_ENABLE_WAYLAND", "1") != "0"
        )
        grid.attach(lbl_wayland, 0, 3, 1, 1)
        grid.attach(self.chk_wayland, 1, 3, 1, 1)

        lbl_steam = Gtk.Label(label="Интеграция со Steam:")
        lbl_steam.set_xalign(0.0)
        lbl_steam.set_yalign(0.5)
        self.chk_steam = Gtk.CheckButton()
        self.chk_steam.set_active(
            os.environ.get("USE_STEAM_INTEGRATION", "0") == "1"
        )
        grid.attach(lbl_steam, 0, 4, 1, 1)
        grid.attach(self.chk_steam, 1, 4, 1, 1)

        lbl_overlay = Gtk.Label(label="Оверлей Steam:")
        lbl_overlay.set_xalign(0.0)
        lbl_overlay.set_yalign(0.5)
        self.chk_overlay = Gtk.CheckButton()
        self.chk_overlay.set_active(
            os.environ.get("USE_STEAM_OVERLAY", "0") == "1"
        )
        grid.attach(lbl_overlay, 0, 5, 1, 1)
        grid.attach(self.chk_overlay, 1, 5, 1, 1)

        lbl_vpn = Gtk.Label(label="Через VPN:")
        lbl_vpn.set_xalign(0.0)
        lbl_vpn.set_yalign(0.5)
        self.chk_vpn = Gtk.CheckButton()
        self.chk_vpn.set_active(os.environ.get("USE_VPN", "0") == "1")
        grid.attach(lbl_vpn, 0, 6, 1, 1)
        grid.attach(self.chk_vpn, 1, 6, 1, 1)

        self.lock_signals = False
        self.chk_overlay.connect("toggled", self.on_overlay_toggled)
        self.chk_wayland.connect("toggled", self.on_wayland_toggled)

        if self.chk_overlay.get_active():
            self.chk_wayland.set_active(False)
            self.chk_wayland.set_sensitive(False)
        elif self.chk_wayland.get_active():
            self.chk_overlay.set_active(False)
            self.chk_overlay.set_sensitive(False)

        lbl_prefix = Gtk.Label(label="Имя префикса (в ~/.umu/):")
        lbl_prefix.set_xalign(0.0)
        lbl_prefix.set_yalign(0.5)
        self.ent_prefix = Gtk.Entry()
        self.ent_prefix.set_text(os.environ.get("UMU_PREFIX_NAME", "default"))
        grid.attach(lbl_prefix, 0, 7, 1, 1)
        grid.attach(self.ent_prefix, 1, 7, 1, 1)

        lbl_gpu = Gtk.Label(label="Видеокарта:")
        lbl_gpu.set_xalign(0.0)
        lbl_gpu.set_yalign(0.5)
        self.cmb_gpu = Gtk.ComboBoxText()
        gpu_opts = ["Автоматически", "AMD", "Nvidia", "Intel"]
        for opt in gpu_opts:
            self.cmb_gpu.append_text(opt)

        cur_gpu = os.environ.get("UMU_GPU_SELECT", "Автоматически")
        if cur_gpu in gpu_opts:
            self.cmb_gpu.set_active(gpu_opts.index(cur_gpu))
        else:
            self.cmb_gpu.set_active(0)
        grid.attach(lbl_gpu, 0, 8, 1, 1)
        grid.attach(self.cmb_gpu, 1, 8, 1, 1)

        lbl_gameid = Gtk.Label(label="Game ID / App ID:")
        lbl_gameid.set_xalign(0.0)
        lbl_gameid.set_yalign(0.5)

        gameid_hbox = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL, spacing=5
        )
        self.ent_gameid = Gtk.Entry()
        self.ent_gameid.set_text(os.environ.get("GAMEID", ""))
        self.ent_gameid.set_placeholder_text("Например: 292030 (AppID)")
        gameid_hbox.pack_start(self.ent_gameid, True, True, 0)

        self.btn_steam_search = Gtk.Button(label="Поиск в Steam")
        self.btn_steam_search.connect("clicked", self.on_steam_search_clicked)
        gameid_hbox.pack_start(self.btn_steam_search, False, False, 0)

        grid.attach(lbl_gameid, 0, 9, 1, 1)
        grid.attach(gameid_hbox, 1, 9, 1, 1)

        self.desktop_box = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL, spacing=10
        )
        vbox.pack_start(self.desktop_box, False, False, 0)

        lbl_sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        self.desktop_box.pack_start(lbl_sep, False, False, 5)

        c_grid = Gtk.Grid(column_spacing=15, row_spacing=10)
        self.desktop_box.pack_start(c_grid, False, False, 0)

        lbl_name = Gtk.Label(label="Название ярлыка:")
        lbl_name.set_xalign(0.0)
        lbl_name.set_yalign(0.5)
        self.ent_name = Gtk.Entry()

        if self.filepath.lower().endswith(".lnk"):
            self.default_name = os.path.basename(self.filepath)[:-4]
        else:
            self.default_name = (
                os.path.basename(self.filepath)[:-4]
                if self.filepath.lower().endswith(".exe")
                else os.path.basename(self.filepath)
            )
        self.ent_name.set_text(self.default_name)
        c_grid.attach(lbl_name, 0, 0, 1, 1)
        c_grid.attach(self.ent_name, 1, 0, 1, 1)

        orig_args = ""
        if self.filepath.lower().endswith(".lnk"):
            try:
                args_out = (
                    subprocess.check_output(
                        [
                            "exiftool",
                            "-s3",
                            "-CommandLineArguments",
                            self.filepath,
                        ]
                    )
                    .decode()
                    .strip()
                )
                if args_out and args_out != "-":
                    orig_args = args_out
            except Exception:
                pass

        lbl_args = Gtk.Label(label="Аргументы запуска:")
        lbl_args.set_xalign(0.0)
        lbl_args.set_yalign(0.5)
        self.ent_args = Gtk.Entry()
        self.ent_args.set_text(orig_args)
        self.ent_args.set_placeholder_text("ENV=1 %command% --arg-here")
        c_grid.attach(lbl_args, 0, 1, 1, 1)
        c_grid.attach(self.ent_args, 1, 1, 1, 1)

        lbl_icon = Gtk.Label(label="Иконка (файл):")
        lbl_icon.set_xalign(0.0)
        lbl_icon.set_yalign(0.5)
        self.btn_icon = Gtk.FileChooserButton(
            title="Выберите иконку", action=Gtk.FileChooserAction.OPEN
        )
        c_grid.attach(lbl_icon, 0, 2, 1, 1)

        icon_hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=5)
        icon_hbox.pack_start(self.btn_icon, True, True, 0)

        self.btn_icon_search = Gtk.Button(label="Поиск в Steam")
        self.btn_icon_search.connect("clicked", self.on_icon_search_clicked)
        icon_hbox.pack_start(self.btn_icon_search, False, False, 0)

        self.btn_reset = Gtk.Button(label="Сбросить")
        icon_hbox.pack_start(self.btn_reset, False, False, 0)
        c_grid.attach(icon_hbox, 1, 2, 1, 1)

        preview_hbox = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL, spacing=10
        )
        self.desktop_box.pack_start(preview_hbox, False, False, 5)

        lbl_p_title = Gtk.Label(label="Предпросмотр иконки:")
        preview_hbox.pack_start(lbl_p_title, False, False, 0)

        self.img_preview = Gtk.Image()
        preview_hbox.pack_start(self.img_preview, False, False, 0)

        self.btn_zoom = Gtk.Button(label="Увеличить")
        self.btn_zoom.connect("clicked", self.on_zoom_clicked)
        preview_hbox.pack_start(self.btn_zoom, False, False, 0)

        self.default_icon = self.extract_default_icon()
        if self.default_icon:
            self.btn_icon.set_filename(self.default_icon)
            self.update_preview_image(self.default_icon)
        else:
            self.update_preview_image("wine")

        self.btn_icon.connect("file-set", self.on_icon_file_set)
        self.btn_reset.connect("clicked", self.on_reset_clicked)

        self.launcher_bbox = Gtk.ButtonBox(
            orientation=Gtk.Orientation.HORIZONTAL, spacing=10
        )
        self.launcher_bbox.set_layout(Gtk.ButtonBoxStyle.END)
        vbox.pack_start(self.launcher_bbox, False, False, 0)

        self.btn_run = Gtk.Button(label="Запустить")
        self.btn_run.connect("clicked", self.on_run_clicked)
        self.launcher_bbox.pack_start(self.btn_run, True, True, 0)

        self.btn_create_prompt = Gtk.Button(label="Создать .desktop")
        self.btn_create_prompt.connect(
            "clicked", self.on_create_prompt_clicked
        )
        self.launcher_bbox.pack_start(self.btn_create_prompt, True, True, 0)

        self.btn_cancel = Gtk.Button(label="Отмена")
        self.btn_cancel.connect("clicked", Gtk.main_quit)
        self.launcher_bbox.pack_start(self.btn_cancel, True, True, 0)

        self.creator_bbox = Gtk.ButtonBox(
            orientation=Gtk.Orientation.HORIZONTAL, spacing=10
        )
        self.creator_bbox.set_layout(Gtk.ButtonBoxStyle.END)
        vbox.pack_start(self.creator_bbox, False, False, 0)

        self.btn_save = Gtk.Button(label="Сохранить ярлык")
        self.btn_save.connect("clicked", self.on_save_clicked)
        self.creator_bbox.pack_start(self.btn_save, True, True, 0)

        self.btn_back = Gtk.Button(label="Назад")
        self.btn_back.connect("clicked", self.on_back_clicked)
        self.creator_bbox.pack_start(self.btn_back, True, True, 0)

        self.connect("destroy", Gtk.main_quit)
        self.show_all()
        self.desktop_box.hide()
        self.creator_bbox.hide()

    def on_steam_search_clicked(self, widget):
        dialog = SteamSearchDialog(self)
        response = dialog.run()
        if response == Gtk.ResponseType.OK:
            selected = dialog.get_selected_game()
            if selected:
                name, appid, icon_path = selected
                self.ent_gameid.set_text(appid)

                current_name = self.ent_name.get_text().strip()
                if not current_name or current_name == self.default_name:
                    self.ent_name.set_text(name)

                if icon_path:
                    self.btn_icon.set_filename(icon_path)
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
                    self.btn_icon.set_filename(icon_path)
                    self.update_preview_image(icon_path)

                current_name = self.ent_name.get_text().strip()
                if not current_name or current_name == self.default_name:
                    self.ent_name.set_text(name)
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
        if self.default_icon:
            self.btn_icon.set_filename(self.default_icon)
            self.update_preview_image(self.default_icon)
        else:
            self.update_preview_image("wine")

    def on_zoom_clicked(self, widget):
        path = self.btn_icon.get_filename() or self.default_icon
        if not path or not os.path.exists(path):
            return
        zoom_win = Gtk.Window(title="Предпросмотр")
        zoom_win.set_border_width(10)
        zoom_win.set_position(Gtk.WindowPosition.CENTER_ON_PARENT)
        zoom_win.set_type_hint(Gdk.WindowTypeHint.DIALOG)

        # WM Floating Hack
        zoom_win.set_resizable(False)
        GLib.timeout_add(150, lambda: zoom_win.set_resizable(True) or False)

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

    def extract_default_icon(self):
        icon_dir = os.path.expanduser("~/.cache/umu/icons")
        os.makedirs(icon_dir, exist_ok=True)
        path_hash = hashlib.md5(self.filepath.encode()).hexdigest()[:8]
        target_path = os.path.join(icon_dir, f"umu-{path_hash}.png")
        if os.path.exists(target_path):
            return target_path

        exe_for_icon = self.filepath
        if self.filepath.lower().endswith(".lnk"):
            try:
                win_path = (
                    subprocess.check_output(
                        ["exiftool", "-s3", "-LocalBasePath", self.filepath]
                    )
                    .decode()
                    .strip()
                )
                if win_path and win_path != "-":
                    rel_path = re.sub(r"^[A-Za-z]:", "", win_path).replace(
                        "\\", "/"
                    )
                    prefix_name = (
                        self.ent_prefix.get_text().strip() or "default"
                    )
                    exe_for_icon = os.path.join(
                        os.path.expanduser(f"~/.umu/{prefix_name}"),
                        "drive_c",
                        rel_path.lstrip("/"),
                    )
            except Exception:
                pass

        work_dir = tempfile.mkdtemp()
        ico_path = os.path.join(work_dir, "icon.ico")
        try:
            with open(ico_path, "wb") as f:
                subprocess.run(
                    ["wrestool", "-x", "-t", "14", exe_for_icon],
                    stdout=f,
                    stderr=subprocess.DEVNULL,
                )
            if os.path.exists(ico_path) and os.path.getsize(ico_path) > 0:
                subprocess.run(
                    ["magick", ico_path, os.path.join(work_dir, "icon.png")],
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
                    shutil.copy(os.path.join(work_dir, pngs[0]), target_path)
                    return target_path
        except Exception:
            pass
        finally:
            shutil.rmtree(work_dir, ignore_errors=True)
        return ""

    def on_create_prompt_clicked(self, widget):
        self.launcher_bbox.hide()
        self.desktop_box.show_all()
        self.creator_bbox.show_all()

    def on_back_clicked(self, widget):
        self.desktop_box.hide()
        self.creator_bbox.hide()
        self.launcher_bbox.show_all()

    def on_run_clicked(self, widget):
        env = os.environ.copy()
        env["UMU_PROTON_TYPE"] = (
            self.cmb_proton.get_active_id() or default_proton_name
        )
        env["USE_GAMEMODE"] = "1" if self.chk_gamemode.get_active() else "0"
        env["USE_MANGOHUD"] = "1" if self.chk_mangohud.get_active() else "0"
        env["PROTON_ENABLE_WAYLAND"] = (
            "1" if self.chk_wayland.get_active() else "0"
        )
        env["UMU_PREFIX_NAME"] = self.ent_prefix.get_text().strip()
        env["UMU_GPU_SELECT"] = self.cmb_gpu.get_active_text()
        env["USE_STEAM_INTEGRATION"] = (
            "1" if self.chk_steam.get_active() else "0"
        )
        env["USE_STEAM_OVERLAY"] = (
            "1" if self.chk_overlay.get_active() else "0"
        )
        env["USE_VPN"] = "1" if self.chk_vpn.get_active() else "0"
        env["GAMEID"] = self.ent_gameid.get_text().strip()

        cmd = f"umu-run-wrapper {shlex.quote(self.filepath)}; scan-umu-for-lnk"
        subprocess.Popen(cmd, shell=True, env=env)
        Gtk.main_quit()

    def on_save_clicked(self, widget):
        env = os.environ.copy()
        env["UMU_PROTON_TYPE"] = (
            self.cmb_proton.get_active_id() or default_proton_name
        )
        env["USE_GAMEMODE"] = "1" if self.chk_gamemode.get_active() else "0"
        env["USE_MANGOHUD"] = "1" if self.chk_mangohud.get_active() else "0"
        env["PROTON_ENABLE_WAYLAND"] = (
            "1" if self.chk_wayland.get_active() else "0"
        )
        env["UMU_PREFIX_NAME"] = self.ent_prefix.get_text().strip()
        env["UMU_GPU_SELECT"] = self.cmb_gpu.get_active_text()
        env["USE_STEAM_INTEGRATION"] = (
            "1" if self.chk_steam.get_active() else "0"
        )
        env["USE_STEAM_OVERLAY"] = (
            "1" if self.chk_overlay.get_active() else "0"
        )
        env["USE_VPN"] = "1" if self.chk_vpn.get_active() else "0"
        env["GAMEID"] = self.ent_gameid.get_text().strip()

        name = self.ent_name.get_text().strip()
        icon = self.btn_icon.get_filename() or ""
        args = self.ent_args.get_text().strip()

        actual_exe = self.filepath
        lnk_arg = ""

        if self.filepath.lower().endswith(".lnk"):
            lnk_arg = self.filepath
            try:
                win_path = (
                    subprocess.check_output(
                        ["exiftool", "-s3", "-LocalBasePath", self.filepath]
                    )
                    .decode()
                    .strip()
                )
                if win_path and win_path != "-":
                    rel_path = re.sub(r"^[A-Za-z]:", "", win_path).replace(
                        "\\", "/"
                    )
                    prefix_name = env.get("UMU_PREFIX_NAME", "default")
                    actual_exe = os.path.join(
                        os.path.expanduser(f"~/.umu/{prefix_name}"),
                        "drive_c",
                        rel_path.lstrip("/"),
                    )
            except Exception:
                pass

        subprocess.run(
            ["create-desktop-with-umu", actual_exe, lnk_arg, args, name, icon],
            env=env,
        )
        Gtk.main_quit()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        dialog = Gtk.FileChooserDialog(
            title="Выберите файл",
            action=Gtk.FileChooserAction.OPEN,
            transient_for=None,
        )
        dialog.set_modal(True)
        dialog.set_type_hint(Gdk.WindowTypeHint.DIALOG)
        dialog.set_position(Gtk.WindowPosition.CENTER)
        dialog.add_button(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL)
        dialog.add_button(Gtk.STOCK_OPEN, Gtk.ResponseType.OK)
        if dialog.run() == Gtk.ResponseType.OK:
            filepath = dialog.get_filename()
            dialog.destroy()
            LauncherWindow(filepath)
            Gtk.main()
        else:
            dialog.destroy()
    else:
        LauncherWindow(sys.argv[1])
        Gtk.main()
