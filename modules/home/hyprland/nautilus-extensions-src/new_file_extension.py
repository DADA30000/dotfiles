from gi import require_version
require_version('Gtk', '4.0')
from gi.repository import Nautilus, GObject, Gtk, Gio
from urllib.parse import quote
import os

xdg_runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
if xdg_runtime_dir:
    PIPE_PATH = os.path.join(xdg_runtime_dir, "nautilus_select_pipe")
else:
    PIPE_PATH = f"/tmp/nautilus_select_pipe_{os.getuid()}"


class EntryDialog(Gtk.Dialog):
    def __init__(self, parent, title, message, default_text=""):
        super().__init__(title=title, transient_for=parent, modal=True)
        self.add_buttons("_Cancel", Gtk.ResponseType.CANCEL, "_Ok", Gtk.ResponseType.OK)
        self.set_default_size(300, 100)
        self.set_resizable(False)
        box = self.get_content_area()
        label = Gtk.Label(label=message)
        box.append(label)
        self.entry = Gtk.Entry()
        self.entry.set_text(default_text)
        self.entry.connect("activate", self._on_entry_activate)
        self.entry.grab_focus()
        box.append(self.entry)

    def _on_entry_activate(self, entry):
        self.response(Gtk.ResponseType.OK)

    def get_text(self):
        return self.entry.get_buffer().get_text()


class NewFileExtension(GObject.GObject, Nautilus.MenuProvider):
    def __init__(self):
        super().__init__()

    def _on_dialog_response(self, dialog, response_id, folder):
        if response_id == Gtk.ResponseType.OK:
            filename = dialog.get_text()
            if filename:
                folder_uri = folder.get_uri()
                if not folder_uri.endswith('/'):
                    folder_uri += '/'
                new_file_uri = folder_uri + quote(filename)

                try:
                    new_file = Gio.File.new_for_uri(new_file_uri)
                    ostream = new_file.create(Gio.FileCreateFlags.NONE, None)
                    ostream.close(None)

                    with open(PIPE_PATH, "w") as fifo:
                        fifo.write(new_file_uri)

                except Exception as e:
                    print(f"Extension Error: {e}")
        dialog.destroy()

    def menu_activate_cb(self, menu, folder):
        app = Gtk.Application.get_default()
        window = app.get_active_window() if app else None
        dialog = EntryDialog(window, "Создать новый файл", "Введите название файла:", "")
        dialog.present()
        dialog.connect("response", self._on_dialog_response, folder)

    def get_background_items(self, folder):
        item = Nautilus.MenuItem(name="NewFileExtension::CreateNewFile", label="Создать новый файл", tip="Создаёт новый файл в текущей директории")
        item.connect("activate", self.menu_activate_cb, folder)
        return [item]
