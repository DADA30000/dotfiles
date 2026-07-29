import sys
import os
import configparser
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, GLib


class FixPathDialog(Gtk.Window):
    def __init__(self, desktop_path):
        super().__init__(title="Исправление пути к файлу - UMU")
        self.set_default_size(520, -1)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_border_width(15)

        self.set_resizable(False)
        GLib.timeout_add(150, lambda: self.set_resizable(True) or False)

        self.desktop_path = desktop_path
        self.config = configparser.ConfigParser(
            interpolation=None, strict=False
        )
        self.config.optionxform = str
        self.config.read(desktop_path, encoding="utf-8")

        current_name = self.config.get(
            "Desktop Entry", "Name", fallback="Game"
        )
        clean_name = current_name.replace(" (Inactive)", "").strip()
        self.actual_exe = self.config.get(
            "Desktop Entry", "X-UMU-Actual-Exe", fallback=""
        )

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.add(vbox)

        lbl_info = Gtk.Label()
        lbl_info.set_markup(
            f"<b>Файл запуска для '{clean_name}' не найден!</b>\n"
            f"<span foreground='gray'>Текущий путь: {self.actual_exe}</span>\n\n"
            "Укажите новое местоположение исполняемого файла (.exe):"
        )
        lbl_info.set_xalign(0.0)
        lbl_info.set_line_wrap(True)
        vbox.pack_start(lbl_info, False, False, 0)

        path_hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=5)
        vbox.pack_start(path_hbox, False, False, 0)

        self.ent_path = Gtk.Entry()
        self.ent_path.set_text(self.actual_exe)
        path_hbox.pack_start(self.ent_path, True, True, 0)

        btn_browse = Gtk.Button(label="Обзор...")
        btn_browse.connect("clicked", self.on_browse_clicked)
        path_hbox.pack_start(btn_browse, False, False, 0)

        bbox = Gtk.ButtonBox(
            orientation=Gtk.Orientation.HORIZONTAL, spacing=10
        )
        bbox.set_layout(Gtk.ButtonBoxStyle.END)
        vbox.pack_start(bbox, False, False, 0)

        btn_ok = Gtk.Button(label="Сохранить и активировать")
        btn_ok.connect("clicked", self.on_save_clicked)
        bbox.pack_start(btn_ok, True, True, 0)

        btn_cancel = Gtk.Button(label="Отмена")
        btn_cancel.connect("clicked", Gtk.main_quit)
        bbox.pack_start(btn_cancel, True, True, 0)

        self.connect("destroy", Gtk.main_quit)
        self.show_all()

    def on_browse_clicked(self, widget):
        dialog = Gtk.FileChooserDialog(
            title="Выберите исполняемый файл (.exe)",
            parent=self,
            action=Gtk.FileChooserAction.OPEN,
        )
        dialog.add_buttons(
            Gtk.STOCK_CANCEL,
            Gtk.ResponseType.CANCEL,
            Gtk.STOCK_OPEN,
            Gtk.ResponseType.OK,
        )
        if dialog.run() == Gtk.ResponseType.OK:
            self.ent_path.set_text(dialog.get_filename())
        dialog.destroy()

    def on_save_clicked(self, widget):
        new_exe = self.ent_path.get_text().strip()
        if not new_exe or not os.path.exists(new_exe):
            dialog = Gtk.MessageDialog(
                transient_for=self,
                modal=True,
                destroy_with_parent=True,
                type=Gtk.MessageType.ERROR,
                buttons=Gtk.ButtonsType.OK,
                message_format="Указанный файл не существует! Пожалуйста, выберите действительный файл.",
            )
            dialog.run()
            dialog.destroy()
            return

        current_name = self.config.get("Desktop Entry", "Name", fallback="")
        clean_name = current_name.replace(" (Inactive)", "").strip()

        raw_args = self.config.get(
            "Desktop Entry", "X-UMU-Raw-Args", fallback=""
        )
        prefix_name = self.config.get(
            "Desktop Entry", "X-UMU-Prefix-Name", fallback="default"
        )
        gpu_select = self.config.get(
            "Desktop Entry", "X-UMU-GPU-Select", fallback="Автоматически"
        )
        steam_int = self.config.get(
            "Desktop Entry", "X-UMU-Steam-Integration", fallback="0"
        )
        steam_ov = self.config.get(
            "Desktop Entry", "X-UMU-Steam-Overlay", fallback="0"
        )
        proton_type = self.config.get(
            "Desktop Entry", "X-UMU-Proton-Type", fallback=""
        )
        vpn = self.config.get("Desktop Entry", "X-UMU-VPN", fallback="0")
        gameid = self.config.get("Desktop Entry", "X-UMU-Game-ID", fallback="")

        env_vars = [
            f"GAMEID={gameid}",
            "USE_GAMEMODE=1",
            "USE_MANGOHUD=1",
            "PROTON_ENABLE_WAYLAND=1",
            f"UMU_PREFIX_NAME={prefix_name}",
            f'UMU_PROTON_TYPE="{proton_type}"',
            f"USE_STEAM_INTEGRATION={steam_int}",
            f"USE_STEAM_OVERLAY={steam_ov}",
            f"USE_VPN={vpn}",
            f'UMU_GPU_SELECT="{gpu_select}"',
        ]
        env_base = "env " + " ".join(env_vars)

        if "%command%" in raw_args:
            parts = raw_args.split("%command%", 1)
            prefix_args = parts[0].strip()
            suffix_args = parts[1].strip()
            exec_cmd = f'{env_base} {prefix_args} umu-run-wrapper "{new_exe}" {suffix_args}'.strip()
        else:
            exec_cmd = (
                f'{env_base} umu-run-wrapper "{new_exe}" {raw_args}'.strip()
            )

        self.config["Desktop Entry"]["Name"] = clean_name
        self.config["Desktop Entry"]["X-UMU-Actual-Exe"] = new_exe
        self.config["Desktop Entry"]["Exec"] = exec_cmd
        self.config["Desktop Entry"]["Path"] = os.path.dirname(new_exe)

        with open(self.desktop_path, "w", encoding="utf-8") as f:
            self.config.write(f, space_around_delimiters=False)

        os.system(
            f'notify-send "Ярлык обновлен" "Новый путь установлен для {clean_name}"'
        )
        Gtk.main_quit()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)
    FixPathDialog(sys.argv[1])
    Gtk.main()
