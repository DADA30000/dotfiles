import sys
import os
import subprocess
import shutil
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk


class PrefixManager(Gtk.Window):
    def __init__(self):
        super().__init__(title="UMU Prefix Manager")
        self.set_default_size(500, 350)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_border_width(10)

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.add(vbox)

        lbl = Gtk.Label()
        lbl.set_markup("<b>Выберите префикс для настройки или управления:</b>")
        lbl.set_alignment(0, 0.5)
        vbox.pack_start(lbl, False, False, 5)

        self.store = Gtk.ListStore(str, str)
        self.treeview = Gtk.TreeView(model=self.store)
        scroll = Gtk.ScrolledWindow()
        scroll.add(self.treeview)
        vbox.pack_start(scroll, True, True, 0)

        renderer_txt = Gtk.CellRendererText()
        renderer_txt.set_property("ypad", 6)
        renderer_txt.set_property("xpad", 6)
        col_txt = Gtk.TreeViewColumn("Префикс", renderer_txt, text=0)
        col_txt.set_expand(True)
        self.treeview.append_column(col_txt)

        self.populate_list()

        bbox = Gtk.ButtonBox(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        bbox.set_layout(Gtk.ButtonBoxStyle.END)
        vbox.pack_start(bbox, False, False, 0)

        self.btn_winetricks = Gtk.Button(label="Winetricks")
        self.btn_winetricks.connect("clicked", self.on_winetricks_clicked)
        bbox.pack_start(self.btn_winetricks, True, True, 0)

        self.btn_protontricks = Gtk.Button(label="Protontricks")
        self.btn_protontricks.connect("clicked", self.on_protontricks_clicked)
        bbox.pack_start(self.btn_protontricks, True, True, 0)

        self.btn_open = Gtk.Button(label="Открыть папку")
        self.btn_open.connect("clicked", self.on_open_clicked)
        bbox.pack_start(self.btn_open, True, True, 0)

        self.btn_delete = Gtk.Button(label="Удалить")
        self.btn_delete.connect("clicked", self.on_delete_clicked)
        bbox.pack_start(self.btn_delete, True, True, 0)

        self.btn_close = Gtk.Button(label="Закрыть")
        self.btn_close.connect("clicked", Gtk.main_quit)
        bbox.pack_start(self.btn_close, True, True, 0)

        self.connect("destroy", Gtk.main_quit)
        self.show_all()

    def populate_list(self):
        self.store.clear()
        umu_dir = os.path.expanduser("~/.umu")
        os.makedirs(umu_dir, exist_ok=True)
        os.makedirs(os.path.join(umu_dir, "default"), exist_ok=True)

        for f in os.listdir(umu_dir):
            path = os.path.join(umu_dir, f)
            if os.path.isdir(path) and f not in ["steamrt3", "umu"]:
                self.store.append([f, path])

    def get_selected(self):
        selection = self.treeview.get_selection()
        model, iter = selection.get_selected()
        if iter:
            return model[iter][0], model[iter][1]
        return None, None

    def on_winetricks_clicked(self, widget):
        name, path = self.get_selected()
        if path:
            env = os.environ.copy()
            env["WINEPREFIX"] = path
            subprocess.Popen(["winetricks"], env=env)

    def on_protontricks_clicked(self, widget):
        name, path = self.get_selected()
        if path:
            subprocess.Popen(["protontricks", "--gui"])

    def on_open_clicked(self, widget):
        name, path = self.get_selected()
        if path:
            drive_c = os.path.join(path, "drive_c")
            os.makedirs(drive_c, exist_ok=True)
            subprocess.Popen(["xdg-open", drive_c])

    def on_delete_clicked(self, widget):
        name, path = self.get_selected()
        if not name:
            return

        if name == "default":
            dialog = Gtk.MessageDialog(
                transient_for=self,
                flags=Gtk.DialogFlags.MODAL,
                type=Gtk.MessageType.ERROR,
                buttons=Gtk.ButtonsType.OK,
                message_format="Нельзя удалить префикс по умолчанию ('default')!",
            )
            dialog.run()
            dialog.destroy()
            return

        confirm = Gtk.MessageDialog(
            transient_for=self,
            flags=Gtk.DialogFlags.MODAL,
            type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.YES_NO,
            message_format=f"Вы уверены, что хотите полностью удалить префикс '{name}'? Все установленные туда игры и сохранения будут утеряны!",
        )
        res = confirm.run()
        confirm.destroy()
        if res == Gtk.ResponseType.YES:
            try:
                shutil.rmtree(path)
                self.populate_list()
                subprocess.run(
                    ["notify-send", "Prefix Deleted", f"Удален префикс {name}"]
                )
            except Exception as e:
                err_dialog = Gtk.MessageDialog(
                    transient_for=self,
                    flags=Gtk.DialogFlags.MODAL,
                    type=Gtk.MessageType.ERROR,
                    buttons=Gtk.ButtonsType.OK,
                    message_format=f"Ошибка удаления префикса: {e}",
                )
                err_dialog.run()
                err_dialog.destroy()


if __name__ == "__main__":
    PrefixManager()
    Gtk.main()
