import sys
import os
import re
import shlex
import subprocess
import tempfile
import hashlib
import shutil
import json
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, GdkPixbuf

# Verify and parse environment configuration. Exit with printed error if missing.
proton_versions_json = os.environ.get("UMU_PROTON_VERSIONS_JSON")
if not proton_versions_json:
    print(
        "Error: UMU_PROTON_VERSIONS_JSON environment variable is not set. Please run this application through the proper Nix wrapper.",
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

# Find configured Nix default version name, otherwise fallback to the first entry in the list
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


class LauncherWindow(Gtk.Window):
    def __init__(self, filepath):
        super().__init__(title="UMU Launcher")
        self.filepath = os.path.abspath(filepath)
        self.set_border_width(15)
        self.set_default_size(460, -1)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_resizable(False)
        self.set_type_hint(Gdk.WindowTypeHint.DIALOG)

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

        # Proton selection dropdown (using version name as unique ID)
        lbl_proton = Gtk.Label(label="Версия Proton:")
        lbl_proton.set_alignment(0, 0.5)
        self.cmb_proton = Gtk.ComboBoxText()
        for v in proton_versions:
            self.cmb_proton.append(v["name"], v["name"])
        cur_proton = os.environ.get("UMU_PROTON_TYPE", default_proton_name)
        if not self.cmb_proton.set_active_id(cur_proton):
            self.cmb_proton.set_active(0)
        grid.attach(lbl_proton, 0, 0, 1, 1)
        grid.attach(self.cmb_proton, 1, 0, 1, 1)

        # gamemode toggle
        lbl_gamemode = Gtk.Label(label="Использовать GameMode:")
        lbl_gamemode.set_alignment(0, 0.5)
        self.chk_gamemode = Gtk.CheckButton()
        self.chk_gamemode.set_active(
            os.environ.get("USE_GAMEMODE", "1") != "0"
        )
        grid.attach(lbl_gamemode, 0, 1, 1, 1)
        grid.attach(self.chk_gamemode, 1, 1, 1, 1)

        # mangohud toggle
        lbl_mangohud = Gtk.Label(label="Использовать MangoHud:")
        lbl_mangohud.set_alignment(0, 0.5)
        self.chk_mangohud = Gtk.CheckButton()
        self.chk_mangohud.set_active(
            os.environ.get("USE_MANGOHUD", "1") != "0"
        )
        grid.attach(lbl_mangohud, 0, 2, 1, 1)
        grid.attach(self.chk_mangohud, 1, 2, 1, 1)

        # wayland toggle
        lbl_wayland = Gtk.Label(label="Использовать Wayland:")
        lbl_wayland.set_alignment(0, 0.5)
        self.chk_wayland = Gtk.CheckButton()
        self.chk_wayland.set_active(
            os.environ.get("PROTON_ENABLE_WAYLAND", "1") != "0"
        )
        grid.attach(lbl_wayland, 0, 3, 1, 1)
        grid.attach(self.chk_wayland, 1, 3, 1, 1)

        # steam integration toggle
        lbl_steam = Gtk.Label(label="Интеграция со Steam:")
        lbl_steam.set_alignment(0, 0.5)
        self.chk_steam = Gtk.CheckButton()
        self.chk_steam.set_active(
            os.environ.get("USE_STEAM_INTEGRATION", "0") == "1"
        )
        grid.attach(lbl_steam, 0, 4, 1, 1)
        grid.attach(self.chk_steam, 1, 4, 1, 1)

        # steam overlay toggle
        lbl_overlay = Gtk.Label(label="Оверлей Steam:")
        lbl_overlay.set_alignment(0, 0.5)
        self.chk_overlay = Gtk.CheckButton()
        self.chk_overlay.set_active(
            os.environ.get("USE_STEAM_OVERLAY", "0") == "1"
        )
        grid.attach(lbl_overlay, 0, 5, 1, 1)
        grid.attach(self.chk_overlay, 1, 5, 1, 1)

        self.lock_signals = False
        self.chk_overlay.connect("toggled", self.on_overlay_toggled)
        self.chk_wayland.connect("toggled", self.on_wayland_toggled)

        if self.chk_overlay.get_active():
            self.chk_wayland.set_active(False)
            self.chk_wayland.set_sensitive(False)
        elif self.chk_wayland.get_active():
            self.chk_overlay.set_active(False)
            self.chk_overlay.set_sensitive(False)

        # prefix name
        lbl_prefix = Gtk.Label(label="Имя префикса (в ~/.umu/):")
        lbl_prefix.set_alignment(0, 0.5)
        self.ent_prefix = Gtk.Entry()
        self.ent_prefix.set_text(os.environ.get("UMU_PREFIX_NAME", "default"))
        grid.attach(lbl_prefix, 0, 6, 1, 1)
        grid.attach(self.ent_prefix, 1, 6, 1, 1)

        # GPU combo selection
        lbl_gpu = Gtk.Label(label="Видеокарта:")
        lbl_gpu.set_alignment(0, 0.5)
        self.cmb_gpu = Gtk.ComboBoxText()
        gpu_opts = ["Автоматически", "AMD", "Nvidia", "Intel"]
        for opt in gpu_opts:
            self.cmb_gpu.append_text(opt)

        cur_gpu = os.environ.get("UMU_GPU_SELECT", "Автоматически")
        if cur_gpu in gpu_opts:
            self.cmb_gpu.set_active(gpu_opts.index(cur_gpu))
        else:
            self.cmb_gpu.set_active(0)
        grid.attach(lbl_gpu, 0, 7, 1, 1)
        grid.attach(self.cmb_gpu, 1, 7, 1, 1)

        self.desktop_box = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL, spacing=10
        )
        vbox.pack_start(self.desktop_box, False, False, 0)

        lbl_sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        self.desktop_box.pack_start(lbl_sep, False, False, 5)

        c_grid = Gtk.Grid(column_spacing=15, row_spacing=10)
        self.desktop_box.pack_start(c_grid, False, False, 0)

        lbl_name = Gtk.Label(label="Название ярлыка:")
        lbl_name.set_alignment(0, 0.5)
        self.ent_name = Gtk.Entry()

        if self.filepath.lower().endswith(".lnk"):
            default_name = os.path.basename(self.filepath)[:-4]
        else:
            default_name = (
                os.path.basename(self.filepath)[:-4]
                if self.filepath.lower().endswith(".exe")
                else os.path.basename(self.filepath)
            )
        self.ent_name.set_text(default_name)
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
        lbl_args.set_alignment(0, 0.5)
        self.ent_args = Gtk.Entry()
        self.ent_args.set_text(orig_args)
        self.ent_args.set_placeholder_text("ENV=1 %command% --arg-here")
        c_grid.attach(lbl_args, 0, 1, 1, 1)
        c_grid.attach(self.ent_args, 1, 1, 1, 1)

        lbl_icon = Gtk.Label(label="Иконка (файл):")
        lbl_icon.set_alignment(0, 0.5)
        self.btn_icon = Gtk.FileChooserButton(
            title="Выберите иконку", action=Gtk.FileChooserAction.OPEN
        )
        c_grid.attach(lbl_icon, 0, 2, 1, 1)

        icon_hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=5)
        icon_hbox.pack_start(self.btn_icon, True, True, 0)

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

        # Dialog Buttons
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
        path = (
            self.icon_chooser.get_filename()
            if hasattr(self, "icon_chooser")
            else self.btn_icon.get_filename()
        )
        if not path:
            path = (
                self.default_icon_spec
                if hasattr(self, "default_icon_spec")
                else self.default_icon
            )
        if not path or not os.path.exists(path):
            return
        zoom_win = Gtk.Window(title="Предпросмотр")
        zoom_win.set_border_width(10)
        zoom_win.set_position(Gtk.WindowPosition.CENTER_ON_PARENT)
        zoom_win.set_type_hint(Gdk.WindowTypeHint.DIALOG)
        zoom_win.set_resizable(False)
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
            surface = Gdk.cairo_surface_create_from_pixbuf(pixbuf, scale, None)
            img.set_from_surface(surface)
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
                surface = Gdk.cairo_surface_create_from_pixbuf(
                    pixbuf, scale, None
                )
                self.img_preview.set_from_surface(surface)
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
                pngs = [f for f in os.listdir(work_dir) if f.endswith(".png")]
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

        name = self.ent_name.get_text().strip()
        icon = self.btn_icon.get_filename()
        if not icon:
            icon = ""
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
        response = dialog.run()
        if response == Gtk.ResponseType.OK:
            filepath = dialog.get_filename()
            dialog.destroy()
            LauncherWindow(filepath)
            Gtk.main()
        else:
            dialog.destroy()
    else:
        LauncherWindow(sys.argv[1])
        Gtk.main()
