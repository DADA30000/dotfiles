from gi import require_version
require_version('Gtk', '4.0')
from gi.repository import Nautilus, GObject
import subprocess
from urllib.parse import unquote

class OpenAsRootExtension(GObject.GObject, Nautilus.MenuProvider):
    def __init__(self):
        super().__init__()

    def _open_with_admin_privileges(self, menu, folder):
        """
        The callback function. It constructs an admin:// URI and opens it.
        'folder' is a Nautilus.FileInfo object.
        """
        uri = folder.get_uri()
        
        if not uri.startswith('file://'):
            return # Only works for local files

        path = unquote(uri[7:])
        admin_uri = f"admin://{path}"
        
        try:
            subprocess.Popen(['nautilus', admin_uri])
        except Exception as e:
            print(f"Open as Root Error: {e}")

    def get_file_items(self, files):
        """
        Called when right-clicking on a file or folder.
        """
        # We only want this for a single, selected, local directory
        if len(files) != 1:
            return []
        
        item = files[0]
        if not item.is_directory() or not item.get_uri().startswith('file://'):
            return []

        menu_item = Nautilus.MenuItem(
            name="OpenAsRootExtension::OpenFileAsRoot",
            label="Открыть как администратор",
            tip="Открывает эту папку с правами суперпользователя"
        )
        menu_item.connect("activate", self._open_with_admin_privileges, item)
        return [menu_item]

    def get_background_items(self, current_folder):
        """
        Called when right-clicking on the background of a directory.
        """
        # Ensure we are in a local directory
        if not current_folder.get_uri().startswith('file://'):
            return []
        
        menu_item = Nautilus.MenuItem(
            name="OpenAsRootExtension::OpenBackgroundAsRoot",
            label="Открыть как администратор",
            tip="Открывает текущую папку с правами суперпользователя"
        )
        menu_item.connect("activate", self._open_with_admin_privileges, current_folder)
        return [menu_item]
