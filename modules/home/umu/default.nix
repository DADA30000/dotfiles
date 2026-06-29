{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  patched-umu = pkgs.umu-launcher-unwrapped.overrideAttrs (oldAttrs: {
    postPatch = (oldAttrs.postPatch or "") + ''
      substituteInPlace umu/umu_run.py --replace-fail 'env["SteamGameId"] = env["SteamAppId"]' 'env["SteamGameId"] = os.environ.get("SteamGameId", env["SteamAppId"])'
    '';
  });
  umu = pkgs.steam.buildRuntimeEnv {
    pname = "umu-launcher";
    inherit (patched-umu) version meta;

    extraPkgs = pkgs: [ patched-umu ];
    executableName = patched-umu.meta.mainProgram;
    runScript = lib.getExe patched-umu;

    privateTmp = false;

    dieWithParent = false;

    extraInstallCommands = ''
      ln -s ${patched-umu}/lib $out/lib
      ln -s ${patched-umu}/share $out/share
    '';
  };
  proton-umu = pkgs.stdenv.mkDerivation (finalAttrs: {
    name = "proton-umu";
    version = "10.0-4";
    src = pkgs.fetchurl {
      url = "https://github.com/Open-Wine-Components/umu-proton/releases/download/UMU-Proton-${finalAttrs.version}/UMU-Proton-${finalAttrs.version}.tar.gz";
      hash = "sha256-YumeApoY+jE+b6Y9QjkJGBAXMKlA40kcVNnVjKuIfGk=";
    };
    installPhase = ''
      mkdir -p "$out"
      tar -xaf "$src" --strip-components=1 -C "$out"
    '';
  });
  openal =
    (pkgs.pkgsCross.mingw32.openal.override {
      alsaSupport = false;
      pulseSupport = false;
      dbusSupport = false;
    }).overrideAttrs
      (old: {
        buildInputs = [ ];
        nativeBuildInputs = old.nativeBuildInputs ++ [
          pkgs.cmake
          pkgs.ninja
        ];
        meta = old.meta // {
          platforms = [ "i686-windows" ];
        };
        preConfigure = (old.preConfigure or "") + ''
          export LDFLAGS="$LDFLAGS -static -static-libgcc -static-libstdc++"
        '';
        cmakeFlags = (old.cmakeFlags or [ ]) ++ [
          "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
          "-DALSOFT_REQUIRE_WINMM=ON"
          "-DALSOFT_REQUIRE_DSOUND=ON"
          "-DALSOFT_BACKEND_ALSA=OFF"
          "-DALSOFT_BACKEND_OSS=OFF"
          "-DALSOFT_BACKEND_PULSEAUDIO=OFF"
          "-DALSOFT_BACKEND_JACK=OFF"
          "-DALSOFT_EXAMPLES=OFF"
          "-DALSOFT_UTILS=OFF"
        ];
      });
  cfg = config.umu;
  runtime_data = fromJSON (readFile ../../../stuff/steamrt3.json);
  runtime = pkgs.fetchurl {
    url = "https://repo.steampowered.com/steamrt3/images/${runtime_data.version}/SteamLinuxRuntime_sniper.tar.xz";
    hash = runtime_data.hash;
  };
  umu-tar = (
    pkgs.writeShellScriptBin "umu-tar" ''
      LOCAL_DIR="${config.xdg.dataHome}"
      LOCK_FILE="$LOCAL_DIR/umu-extraction.lock"
      mkdir -p "$LOCAL_DIR"
      exec 9> "$LOCK_FILE"
      flock 9
      PATH="$PATH:${pkgs.coreutils-full}/bin:${pkgs.xz}/bin:${pkgs.gnutar}/bin:${pkgs.util-linux}/bin"
      if [[ ! -d "$LOCAL_DIR/umu" ]]; then
        rm -rf "$LOCAL_DIR/steamrt3.tmp"; mkdir -p "$LOCAL_DIR/steamrt3.tmp"
        tar -xaf "${runtime}" --strip-components=1 -C "$LOCAL_DIR/steamrt3.tmp"
        cd "$LOCAL_DIR/steamrt3.tmp"
        ln -s "_v2-entry-point" "umu"
        echo "ok" > ".installed.ok"
        umount -qf "$LOCAL_DIR/umu" 2>/dev/null || true 
        rm -rf "$LOCAL_DIR/umu"; mkdir -p "$LOCAL_DIR/umu"
        mv "$LOCAL_DIR/steamrt3.tmp" "$LOCAL_DIR/umu/steamrt3"
      fi
      flock -u 9
    ''
  );

  # Automatically constructs a complete GI_TYPELIB_PATH covering all transitively called GTK3 dependencies
  giTypelibPath = lib.makeSearchPathOutput "lib" "lib/girepository-1.0" [
    pkgs.gtk3
    pkgs.pango
    pkgs.gdk-pixbuf
    pkgs.at-spi2-core
    pkgs.harfbuzz
    pkgs.glib
    pkgs.cairo
    pkgs.gobject-introspection
  ];
in
{
  options.umu = {
    enable = mkEnableOption "umu - universal windows apps launcher";
  };

  config = mkIf cfg.enable {
    xdg.mimeApps.defaultApplications = {
      "application/vnd.microsoft.portable-executable" = "run-exe.desktop";
      "application/x-msi" = "run-exe.desktop";
      "application/x-msdownload" = "run-exe.desktop";
      "application/x-ms-shortcut" = "run-exe.desktop";
      "application/x-mswinurl" = "run-exe.desktop";
      "application/x-ms-dos-executable" = "run-exe.desktop";
      "application/x-bat" = "run-exe.desktop";
    };
    xdg.desktopEntries.run-exe = {
      exec = "run-exe %f";
      mimeType = [
        "application/vnd.microsoft.portable-executable"
        "application/x-msi"
        "application/x-msdownload"
        "application/x-ms-shortcut"
        "application/x-bat"
        "application/x-ms-dos-executable"
        "application/x-mswinurl"
      ];
      name = "Execute Windows file";
      type = "Application";
      icon = "wine";
      settings.StartupWMClass = "run-exe";
    };
    xdg.desktopEntries.manage-umu-shortcuts = {
      exec = "manage-umu-shortcuts";
      name = "Manage UMU Shortcuts";
      type = "Application";
      icon = "system-run";
      categories = [
        "Settings"
        "Utility"
      ];
      settings.StartupWMClass = "manage-umu-shortcuts";
    };
    xdg.desktopEntries.manage-umu-prefixes = {
      exec = "manage-umu-prefixes";
      name = "Manage UMU Prefixes";
      type = "Application";
      icon = "folder-wine";
      categories = [
        "Settings"
        "Utility"
      ];
      settings.StartupWMClass = "manage-umu-prefixes";
    };
    home.packages = [
      pkgs.yad
      (pkgs.writeScriptBin "run-exe" ''
        #!${pkgs.bash}/bin/bash
        export GI_TYPELIB_PATH="${giTypelibPath}"
        # Set XDG_DATA_DIRS to expose required desktop schemas to the GIO backend
        export XDG_DATA_DIRS="${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}:${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}:${pkgs.adwaita-icon-theme}/share:${pkgs.hicolor-icon-theme}/share:$XDG_DATA_DIRS"
        # Dynamically resolve GDK_PIXBUF_MODULE_FILE via findutils to prevent hardcoded version directory conflicts
        GDK_PIXBUF_CACHE_FILE=$(${pkgs.findutils}/bin/find "${pkgs.librsvg}/lib/gdk-pixbuf-2.0" -name "loaders.cache" -print -quit 2>/dev/null)
        if [[ -n "$GDK_PIXBUF_CACHE_FILE" ]]; then
          export GDK_PIXBUF_MODULE_FILE="$GDK_PIXBUF_CACHE_FILE"
        fi
        exec ${
          pkgs.python3.withPackages (ps: [ ps.pygobject3 ])
        }/bin/python3 "${pkgs.writeText "run-exe-python" ''
          import sys
          import os
          import re
          import shlex
          import subprocess
          import tempfile
          import hashlib
          import shutil
          import gi
          gi.require_version("Gtk", "3.0")
          from gi.repository import Gtk, Gdk, GdkPixbuf

          def scan_gpus():
              amd, nvidia, intel = "", "", ""
              try:
                  res = subprocess.run(["${pkgs.pciutils}/bin/lspci", "-nn"], capture_output=True, text=True)
                  for line in res.stdout.splitlines():
                      if any(x in line for x in ["VGA compatible controller", "3D controller", "Display controller"]):
                          match = re.search(r"\[([0-9a-fA-F]{4}:[0-9a-fA-F]{4})\]", line)
                          if match:
                              pci_id = match.group(1)
                              l = line.lower()
                              if "nvidia" in l:
                                  nvidia_id = pci_id
                              elif any(x in l for x in ["amd", "advanced micro devices", "ati"]):
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
                  # Sets Gdk Dialog type hint to force tiling WMs to float this window
                  self.set_type_hint(Gdk.WindowTypeHint.DIALOG)

                  self.amd_id, self.nvidia_id, self.intel_id = scan_gpus()

                  vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
                  self.add(vbox)

                  # Горизонтальный контейнер для независимого смещения элементов
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

                  # proton-umu toggle
                  lbl_umu = Gtk.Label(label="Использовать Proton UMU:")
                  lbl_umu.set_alignment(0, 0.5)
                  self.chk_umu = Gtk.CheckButton()
                  self.chk_umu.set_active(os.environ.get("USE_PROTON_UMU") == "1")
                  grid.attach(lbl_umu, 0, 0, 1, 1)
                  grid.attach(self.chk_umu, 1, 0, 1, 1)

                  # gamemode toggle
                  lbl_gamemode = Gtk.Label(label="Использовать GameMode:")
                  lbl_gamemode.set_alignment(0, 0.5)
                  self.chk_gamemode = Gtk.CheckButton()
                  self.chk_gamemode.set_active(os.environ.get("USE_GAMEMODE", "1") != "0")
                  grid.attach(lbl_gamemode, 0, 1, 1, 1)
                  grid.attach(self.chk_gamemode, 1, 1, 1, 1)

                  # mangohud toggle
                  lbl_mangohud = Gtk.Label(label="Использовать MangoHud:")
                  lbl_mangohud.set_alignment(0, 0.5)
                  self.chk_mangohud = Gtk.CheckButton()
                  self.chk_mangohud.set_active(os.environ.get("USE_MANGOHUD", "1") != "0")
                  grid.attach(lbl_mangohud, 0, 2, 1, 1)
                  grid.attach(self.chk_mangohud, 1, 2, 1, 1)

                  # wayland toggle (Grouped cleanly at the top)
                  lbl_wayland = Gtk.Label(label="Использовать Wayland:")
                  lbl_wayland.set_alignment(0, 0.5)
                  self.chk_wayland = Gtk.CheckButton()
                  self.chk_wayland.set_active(os.environ.get("PROTON_ENABLE_WAYLAND", "1") != "0")
                  grid.attach(lbl_wayland, 0, 3, 1, 1)
                  grid.attach(self.chk_wayland, 1, 3, 1, 1)

                  # steam integration toggle
                  lbl_steam = Gtk.Label(label="Интеграция со Steam:")
                  lbl_steam.set_alignment(0, 0.5)
                  self.chk_steam = Gtk.CheckButton()
                  self.chk_steam.set_active(os.environ.get("USE_STEAM_INTEGRATION", "0") == "1")
                  grid.attach(lbl_steam, 0, 4, 1, 1)
                  grid.attach(self.chk_steam, 1, 4, 1, 1)

                  # steam overlay toggle
                  lbl_overlay = Gtk.Label(label="Оверлей Steam:")
                  lbl_overlay.set_alignment(0, 0.5)
                  self.chk_overlay = Gtk.CheckButton()
                  self.chk_overlay.set_active(os.environ.get("USE_STEAM_OVERLAY", "0") == "1")
                  grid.attach(lbl_overlay, 0, 5, 1, 1)
                  grid.attach(self.chk_overlay, 1, 5, 1, 1)

                  # Mutual exclusion live callbacks using robust state variables
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

                  # Hidden desktop parameters vbox
                  self.desktop_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
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
                      default_name = os.path.basename(self.filepath)[:-4] if self.filepath.lower().endswith(".exe") else os.path.basename(self.filepath)
                  self.ent_name.set_text(default_name)
                  c_grid.attach(lbl_name, 0, 0, 1, 1)
                  c_grid.attach(self.ent_name, 1, 0, 1, 1)

                  orig_args = ""
                  if self.filepath.lower().endswith(".lnk"):
                      try:
                          args_out = subprocess.check_output(["${pkgs.exiftool}/bin/exiftool", "-s3", "-CommandLineArguments", self.filepath]).decode().strip()
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
                  self.btn_icon = Gtk.FileChooserButton(title="Выберите иконку", action=Gtk.FileChooserAction.OPEN)
                  c_grid.attach(lbl_icon, 0, 2, 1, 1)
                  
                  icon_hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=5)
                  icon_hbox.pack_start(self.btn_icon, True, True, 0)
                  
                  self.btn_reset = Gtk.Button(label="Сбросить")
                  icon_hbox.pack_start(self.btn_reset, False, False, 0)
                  c_grid.attach(icon_hbox, 1, 2, 1, 1)

                  preview_hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
                  self.desktop_box.pack_start(preview_hbox, False, False, 5)
                  
                  lbl_p_title = Gtk.Label(label="Предпросмотр иконки:")
                  preview_hbox.pack_start(lbl_p_title, False, False, 0)
                  
                  self.img_preview = Gtk.Image()
                  preview_hbox.pack_start(self.img_preview, False, False, 0)

                  # Icon zoom expansion button
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
                  self.launcher_bbox = Gtk.ButtonBox(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
                  self.launcher_bbox.set_layout(Gtk.ButtonBoxStyle.END)
                  vbox.pack_start(self.launcher_bbox, False, False, 0)

                  self.btn_run = Gtk.Button(label="Запустить")
                  self.btn_run.connect("clicked", self.on_run_clicked)
                  self.launcher_bbox.pack_start(self.btn_run, True, True, 0)

                  self.btn_create_prompt = Gtk.Button(label="Создать .desktop")
                  self.btn_create_prompt.connect("clicked", self.on_create_prompt_clicked)
                  self.launcher_bbox.pack_start(self.btn_create_prompt, True, True, 0)

                  self.btn_cancel = Gtk.Button(label="Отмена")
                  self.btn_cancel.connect("clicked", Gtk.main_quit)
                  self.launcher_bbox.pack_start(self.btn_cancel, True, True, 0)

                  self.creator_bbox = Gtk.ButtonBox(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
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
                  path = self.icon_chooser.get_filename() if hasattr(self, "icon_chooser") else self.btn_icon.get_filename()
                  if not path:
                      path = self.default_icon_spec if hasattr(self, "default_icon_spec") else self.default_icon
                  if not path or not os.path.exists(path):
                      return
                  zoom_win = Gtk.Window(title="Предпросмотр")
                  zoom_win.set_border_width(10)
                  zoom_win.set_position(Gtk.WindowPosition.CENTER_ON_PARENT)
                  zoom_win.set_type_hint(Gdk.WindowTypeHint.DIALOG)
                  zoom_win.set_resizable(False)
                  zoom_win.set_transient_for(self)
                  zoom_win.set_modal(True)

                  # Закрытие строго по Escape или действиям оконного менеджера
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
                      pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, size, size, True)
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
                          pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, size, size, True)
                          surface = Gdk.cairo_surface_create_from_pixbuf(pixbuf, scale, None)
                          self.img_preview.set_from_surface(surface)
                      except Exception:
                          self.img_preview.set_from_icon_name("wine", Gtk.IconSize.DIALOG)
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
                          win_path = subprocess.check_output(["${pkgs.exiftool}/bin/exiftool", "-s3", "-LocalBasePath", self.filepath]).decode().strip()
                          if win_path and win_path != "-":
                              rel_path = re.sub(r"^[A-Za-z]:", "", win_path).replace("\\", "/")
                              prefix_name = self.ent_prefix.get_text().strip() or "default"
                              exe_for_icon = os.path.join(os.path.expanduser(f"~/.umu/{prefix_name}"), "drive_c", rel_path.lstrip("/"))
                      except Exception:
                          pass
                      
                  work_dir = tempfile.mkdtemp()
                  ico_path = os.path.join(work_dir, "icon.ico")
                  try:
                      with open(ico_path, "wb") as f:
                          subprocess.run(["${pkgs.icoutils}/bin/wrestool", "-x", "-t", "14", exe_for_icon], stdout=f, stderr=subprocess.DEVNULL)
                      if os.path.exists(ico_path) and os.path.getsize(ico_path) > 0:
                          subprocess.run(["${pkgs.imagemagick}/bin/magick", ico_path, os.path.join(work_dir, "icon.png")], stderr=subprocess.DEVNULL)
                          pngs = [f for f in os.listdir(work_dir) if f.endswith(".png")]
                          if pngs:
                              pngs.sort(key=lambda x: os.path.getsize(os.path.join(work_dir, x)), reverse=True)
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
                  env["USE_PROTON_UMU"] = "1" if self.chk_umu.get_active() else "0"
                  env["USE_GAMEMODE"] = "1" if self.chk_gamemode.get_active() else "0"
                  env["USE_MANGOHUD"] = "1" if self.chk_mangohud.get_active() else "0"
                  env["PROTON_ENABLE_WAYLAND"] = "1" if self.chk_wayland.get_active() else "0"
                  env["UMU_PREFIX_NAME"] = self.ent_prefix.get_text().strip()
                  env["UMU_GPU_SELECT"] = self.cmb_gpu.get_active_text()
                  env["USE_STEAM_INTEGRATION"] = "1" if self.chk_steam.get_active() else "0"
                  env["USE_STEAM_OVERLAY"] = "1" if self.chk_overlay.get_active() else "0"

                  # Safe asynchronous chain triggered on UI close. Runs wrapper synchronously and scans on completion.
                  cmd = f"umu-run-wrapper {shlex.quote(self.filepath)}; scan-umu-for-lnk"
                  subprocess.Popen(cmd, shell=True, env=env)
                  Gtk.main_quit()

              def on_save_clicked(self, widget):
                  env = os.environ.copy()
                  env["USE_PROTON_UMU"] = "1" if self.chk_umu.get_active() else "0"
                  env["USE_GAMEMODE"] = "1" if self.chk_gamemode.get_active() else "0"
                  env["USE_MANGOHUD"] = "1" if self.chk_mangohud.get_active() else "0"
                  env["PROTON_ENABLE_WAYLAND"] = "1" if self.chk_wayland.get_active() else "0"
                  env["UMU_PREFIX_NAME"] = self.ent_prefix.get_text().strip()
                  env["UMU_GPU_SELECT"] = self.cmb_gpu.get_active_text()
                  env["USE_STEAM_INTEGRATION"] = "1" if self.chk_steam.get_active() else "0"
                  env["USE_STEAM_OVERLAY"] = "1" if self.chk_overlay.get_active() else "0"

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
                          win_path = subprocess.check_output(["${pkgs.exiftool}/bin/exiftool", "-s3", "-LocalBasePath", self.filepath]).decode().strip()
                          if win_path and win_path != "-":
                              rel_path = re.sub(r"^[A-Za-z]:", "", win_path).replace("\\", "/")
                              prefix_name = env.get("UMU_PREFIX_NAME", "default")
                              actual_exe = os.path.join(os.path.expanduser(f"~/.umu/{prefix_name}"), "drive_c", rel_path.lstrip("/"))
                      except Exception:
                          pass

                  # Synchronous creation triggers scan on completion
                  subprocess.run(["create-desktop-with-umu", actual_exe, lnk_arg, args, name, icon], env=env)
                  Gtk.main_quit()

          if __name__ == "__main__":
              if len(sys.argv) < 2:
                  dialog = Gtk.FileChooserDialog(
                      title="Выберите файл",
                      action=Gtk.FileChooserAction.OPEN,
                      transient_for=None
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
        ''}" "$@"
      '')
      (pkgs.writeShellScriptBin "umu-run-wrapper" ''
        if [[ -z "$WINEPREFIX" ]]; then
          prefix_name=''${UMU_PREFIX_NAME:-default}
          export WINEPREFIX=$HOME/.umu/$prefix_name
        fi
        if [[ ! -d "${config.xdg.dataHome}/umu" ]]; then
          ${pkgs.libnotify}/bin/notify-send "Please wait..." "Preparing umu runtime (only on first launch)"
          ${umu-tar}/bin/umu-tar
        fi
        if [[ ! -f "$WINEPREFIX/check-do_not_delete_this" ]]; then
          mkdir -p "$WINEPREFIX/drive_c/windows/syswow64"
          cp --no-preserve=mode "${openal}/bin/OpenAL32.dll" "$WINEPREFIX/drive_c/windows/syswow64/OpenAL32.dll"
          touch "$WINEPREFIX/check-do_not_delete_this"
        fi
        while [[ ! -d "${config.xdg.dataHome}/umu" ]]; do
          sleep 0.2
        done
        ${pkgs.libnotify}/bin/notify-send "Starting UMU"
        if [[ -z "$(printenv PROTONPATH)" ]]; then
          if [[ "$USE_PROTON_UMU" == 1 ]]; then
            export PROTONPATH="${proton-umu}"
          else
            export PROTONPATH="${pkgs.proton-ge-bin.steamcompattool}"
          fi
        fi

        # Steam client DLL copy operations are executed unconditionally
        mkdir -p "$WINEPREFIX/drive_c/Program Files (x86)/Steam"
        cp --no-preserve=mode "$PROTONPATH/files/lib/wine/x86_64-windows/lsteamclient.dll" "$WINEPREFIX/drive_c/Program Files (x86)/Steam/steamclient64.dll"
        cp --no-preserve=mode "$PROTONPATH/files/lib/wine/i386-windows/lsteamclient.dll" "$WINEPREFIX/drive_c/Program Files (x86)/Steam/steamclient.dll"

        # Apply specific overlay parameters dynamically based on user preferences
        if [[ "$USE_STEAM_INTEGRATION" == "1" ]]; then
          export WINEDLLOVERRIDES="steamclient64,voices38,dxgi,winhttp,winmm,SteamFix64,steam_api64,OnlineFix64,SteamOverlay64,version=n,b"
        else
          export WINEDLLOVERRIDES="voices38,dxgi,winhttp,winmm,version=n,b"
        fi

        if [[ "$USE_STEAM_OVERLAY" == "1" ]]; then
          export SteamGameId=480
          export ENABLE_VK_LAYER_VALVE_steam_overlay_1=1
          export LD_PRELOAD="$LD_PRELOAD:$HOME/.steam/bin32/gameoverlayrenderer.so:$HOME/.steam/bin64/gameoverlayrenderer.so"
          export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${pkgs.libGL}/lib:${pkgs.pkgsi686Linux.libGL}/lib"
        fi

        export UMU_RUNTIME_UPDATE=0
        export PROTON_ENABLE_WAYLAND=''${PROTON_ENABLE_WAYLAND:-1}
        cd "$(dirname "$1")" &> /dev/null || true

        # Local hardware probe (incorporating Display Controller check for Krackan AMD APUs)
        AMD_PCI_ID=$(${pkgs.pciutils}/bin/lspci -nn | grep -E "VGA compatible controller|3D controller|Display controller" | grep -i -E "AMD|Advanced Micro Devices" | grep -o -E "\[[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\]" | head -n 1 | tr -d '[]')
        NVIDIA_PCI_ID=$(${pkgs.pciutils}/bin/lspci -nn | grep -E "VGA compatible controller|3D controller|Display controller" | grep -i "NVIDIA" | grep -o -E "\[[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\]" | head -n 1 | tr -d '[]')
        INTEL_PCI_ID=$(${pkgs.pciutils}/bin/lspci -nn | grep -E "VGA compatible controller|3D controller|Display controller" | grep -i "Intel" | grep -o -E "\[[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\]" | head -n 1 | tr -d '[]')

        # Apply specific PCI ID routing with strict ! exclusion masks
        case "$UMU_GPU_SELECT" in
          "AMD")
            if [[ -n "$AMD_PCI_ID" ]]; then
              export DRI_PRIME="$AMD_PCI_ID!"
              export MESA_VK_DEVICE_SELECT="$AMD_PCI_ID!"
            fi
          ;;
          "Intel")
            if [[ -n "$INTEL_PCI_ID" ]]; then
              export DRI_PRIME="$INTEL_PCI_ID!"
              export MESA_VK_DEVICE_SELECT="$INTEL_PCI_ID!"
            fi
          ;;
          "Nvidia")
            export __NV_PRIME_RENDER_OFFLOAD=1
            export __GLX_VENDOR_LIBRARY_NAME=nvidia
            export __VK_LAYER_NV_optimus=NVIDIA_only
            if [[ -n "$NVIDIA_PCI_ID" ]]; then
              export DRI_PRIME="$NVIDIA_PCI_ID!"
              export MESA_VK_DEVICE_SELECT="$NVIDIA_PCI_ID!"
            fi
          ;;
        esac

        CMD=()
        if [[ "$USE_GAMEMODE" != "0" ]]; then
          CMD+=(${pkgs.gamemode}/bin/gamemoderun)
        fi
        if [[ "$USE_MANGOHUD" != "0" ]]; then
          CMD+=(${pkgs.mangohud}/bin/mangohud)
        fi
        CMD+=(${umu}/bin/umu-run "$@")

        "''${CMD[@]}"
        ${pkgs.libnotify}/bin/notify-send "Closed" "UMU exited (if you didn't close the app, app might've crashed)"
      '')
      (pkgs.writeShellScriptBin "scan-umu-for-lnk" ''
        if [[ -z "$WINEPREFIX" ]]; then
          prefix_name=''${UMU_PREFIX_NAME:-default}
          export WINEPREFIX=$HOME/.umu/$prefix_name
        fi

        cleanup-desktop-with-umu

        pids=()
        MAX_JOBS=16

        throttle_jobs() {
          local temp_pids=()
          for pid in "''${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
              temp_pids+=("$pid")
            fi
          done
          pids=("''${temp_pids[@]}")
          while [[ ''${#pids[@]} -ge $MAX_JOBS ]]; do
            sleep 0.05
            temp_pids=()
            for pid in "''${pids[@]}"; do
              if kill -0 "$pid" 2>/dev/null; then
                temp_pids+=("$pid")
              fi
            done
            pids=("''${temp_pids[@]}")
          done
        }

        while IFS= read -r -d "" USER_PROFILE; do
          while IFS= read -r -d "" lnk; do
            
            if grep -Fq "X-UMU-Lnk-Path=$lnk" "${config.xdg.dataHome}/applications"/umu-*.desktop 2>/dev/null; then
              continue
            fi

            throttle_jobs
            
            (
              metadata=$(${pkgs.exiftool}/bin/exiftool -f -p '$LocalBasePath|$CommandLineArguments' "$lnk" 2>/dev/null)
              IFS='|' read -r win_path args <<< "$metadata"

              win_path=$(echo "$win_path" | tr -d '\r')
              args=$(echo "$args" | tr -d '\r')

              if [[ "$win_path" == "-" || -z "$win_path" ]]; then
                rm -f "$lnk"
                exit 0
              fi

              if [[ "$args" == "-" ]]; then
                args=""
              fi

              rel_path=$(echo "$win_path" | sed 's/^[A-Z]://; s/\\/\//g')
              actual_exe="$WINEPREFIX/drive_c$rel_path"

              create-desktop-with-umu "$actual_exe" "$lnk" "$args"
            ) &
            pids+=("$!")

          done < <(find "$USER_PROFILE/Desktop" "$USER_PROFILE/AppData/Roaming/Microsoft/Windows/Start Menu/Programs" "$WINEPREFIX/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs" -type f -name "*.lnk" -print0 2>/dev/null)
        done < <(find "$WINEPREFIX/drive_c/users" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

        wait
      '')
      (pkgs.writeShellScriptBin "cleanup-desktop-with-umu" ''
        PATH="${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:$PATH"
        ICON_DIR="${config.xdg.dataHome}/icons/umu"
        DESKTOP_DIR="${config.xdg.dataHome}/applications"
        CACHE_ICON_DIR="$HOME/.cache/umu/icons"

        # Silently clear temporary preview cache without any notifications
        if [[ -d "$CACHE_ICON_DIR" ]]; then
          rm -rf "$CACHE_ICON_DIR"/* 2>/dev/null || true
        fi

        for d_file in "$DESKTOP_DIR"/umu-*.desktop; do
          if [[ -f "$d_file" ]]; then
            exe_path=$(grep '^Exec=' "$d_file" | sed -n 's/^.*umu-run-wrapper "\([^"]*\)".*/\1/p')
            if [[ -n "$exe_path" && ! -f "$exe_path" ]]; then
              game_name=$(grep '^Name=' "$d_file" | head -n 1 | cut -d= -f2-)
              icon_path=$(grep '^Icon=' "$d_file" | head -n 1 | cut -d= -f2)
              ${pkgs.libnotify}/bin/notify-send -u normal -i "$icon_path" "Cleanup" "Removing shortcut for: $game_name"
              rm "$d_file"
              if [[ "$icon_path" == "$ICON_DIR"* && -f "$icon_path" ]]; then
                rm -f "$icon_path"
              fi
            fi
          fi
        done
        for i_file in "$ICON_DIR"/*; do
          [[ -e "$i_file" ]] || continue
          base=$(basename "$i_file" .png)
          
          if [[ ! -f "$DESKTOP_DIR/$base.desktop" && ! -f "$DESKTOP_DIR/$base-umu.desktop" ]]; then
            ${pkgs.libnotify}/bin/notify-send -u normal -i "$i_file" "Cleanup" "Removing stale icon $(basename "$i_file")"
            rm "$i_file"
          fi
        done
      '')
      (pkgs.writeShellScriptBin "create-desktop-with-umu" ''
                PATH="${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:$PATH"
                ICON_DIR="${config.xdg.dataHome}/icons/umu"
                DESKTOP_DIR="${config.xdg.dataHome}/applications"
                mkdir -p "$ICON_DIR" "$DESKTOP_DIR"
                actual_exe="$1"
                lnk="$2"
                args="$3"
                name="$4"
                custom_icon="$5"

                env_gamemode=''${USE_GAMEMODE:-1}
                env_mangohud=''${USE_MANGOHUD:-1}
                env_wayland=''${PROTON_ENABLE_WAYLAND:-1}
                env_prefix_name=''${UMU_PREFIX_NAME:-default}
                env_umu=''${USE_PROTON_UMU:-0}
                env_gpu_select=''${UMU_GPU_SELECT:-Автоматически}
                env_steam=''${USE_STEAM_INTEGRATION:-0}
                env_overlay=''${USE_STEAM_OVERLAY:-0}

                export WINEPREFIX=$HOME/.umu/$env_prefix_name

                if [[ -f "$actual_exe" ]]; then
                  PATH_HASH=$(echo "$actual_exe$args" | md5sum | cut -c1-8)
                  DESKTOP_FILE="$DESKTOP_DIR/umu-$PATH_HASH.desktop"
                  ICON_FILE="umu-$PATH_HASH.png"

                  # If .desktop file already exists, exit immediately to prevent overwriting
                  if [[ -f "$DESKTOP_FILE" ]]; then
                    exit 0
                  fi

                  if [[ -n "$name" ]]; then
                    LNK_DISPLAY_NAME="$name"
                  elif [[ -n "$lnk" ]]; then
                    LNK_DISPLAY_NAME=$(basename "$lnk" | sed 's/\.[lL][nN][kK]$//')
                  else
                    LNK_DISPLAY_NAME=$(basename "$actual_exe" | sed 's/\.[eE][xX][eE]$//')
                  fi

                  if [[ -n "$custom_icon" && "$custom_icon" != "wine" ]]; then
                    if [[ "$custom_icon" == *"/umu/icons/"* || "$custom_icon" == *"/cache/umu/"* ]]; then
                      # It is a temporary cache icon from python GUI. Copy it to permanent ICON_DIR.
                      cp "$custom_icon" "$ICON_DIR/$ICON_FILE" 2>/dev/null
                      ICON_SPEC="$ICON_DIR/$ICON_FILE"
                    else
                      ICON_SPEC="$custom_icon"
                    fi
                  else
                    ICON_SPEC="$ICON_DIR/$ICON_FILE"
                    if [[ ! -f "$ICON_SPEC" ]]; then
                      WORK_DIR=$(mktemp -d)

                      if [[ -n "$lnk" && -f "$lnk" ]]; then
                        ICON_SRC_WIN=$(${pkgs.exiftool}/bin/exiftool -s3 -IconFileName "$lnk" | tr -d '\r')
                      else
                        ICON_SRC_WIN=""
                      fi            

                      if [[ -n "$ICON_SRC_WIN" ]]; then
                        REL_ICON_PATH=$(echo "$ICON_SRC_WIN" | sed 's/^[A-Z]://; s/\\/\//g')
                        ICON_SOURCE="$WINEPREFIX/drive_c$REL_ICON_PATH"
                      else
                        ICON_SOURCE="$actual_exe"
                      fi
                      
                      if [[ "$ICON_SOURCE" == *.ico || "$ICON_SOURCE" == *.ICO ]]; then
                        cp "$ICON_SOURCE" "$WORK_DIR/icon.ico" 2>/dev/null
                      else
                        ${pkgs.icoutils}/bin/wrestool -x -t 14 "$ICON_SOURCE" > "$WORK_DIR/icon.ico" 2>/dev/null
                        
                        if [[ ! -s "$WORK_DIR/icon.ico" ]]; then
                            ${pkgs.icoutils}/bin/wrestool -x -t 14 "$actual_exe" > "$WORK_DIR/icon.ico" 2>/dev/null
                        fi
                      fi
                      
                      if [[ -s "$WORK_DIR/icon.ico" ]]; then
                        ${pkgs.imagemagick}/bin/magick "$WORK_DIR/icon.ico" "$WORK_DIR/icon.png"
                        BIGGEST_PNG=$(ls -S "$WORK_DIR"/*.png 2>/dev/null | head -n 1)
                        
                        if [[ -n "$BIGGEST_PNG" ]]; then
                          cp "$BIGGEST_PNG" "$ICON_DIR/$ICON_FILE"
                          ICON_SPEC="$ICON_DIR/$ICON_FILE"
                        else
                          ICON_SPEC="wine"
                        fi
                      else
                        ICON_SPEC="wine"
                      fi
                      
                      rm -rf "$WORK_DIR"
                    fi
                  fi

                  # Hardware device scan during shortcut compilation
                  AMD_PCI_ID=$(${pkgs.pciutils}/bin/lspci -nn | grep -E "VGA compatible controller|3D controller|Display controller" | grep -i -E "AMD|Advanced Micro Devices" | grep -o -E "\[[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\]" | head -n 1 | tr -d '[]')
                  NVIDIA_PCI_ID=$(${pkgs.pciutils}/bin/lspci -nn | grep -E "VGA compatible controller|3D controller|Display controller" | grep -i "NVIDIA" | grep -o -E "\[[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\]" | head -n 1 | tr -d '[]')
                  INTEL_PCI_ID=$(${pkgs.pciutils}/bin/lspci -nn | grep -E "VGA compatible controller|3D controller|Display controller" | grep -i "Intel" | grep -o -E "\[[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\]" | head -n 1 | tr -d '[]')

                  GPU_ENV=""
                  case "$env_gpu_select" in
                    "AMD")
                      if [[ -n "$AMD_PCI_ID" ]]; then
                        GPU_ENV="DRI_PRIME=$AMD_PCI_ID! MESA_VK_DEVICE_SELECT=$AMD_PCI_ID!"
                      fi
                    ;;
                    "Intel")
                      if [[ -n "$INTEL_PCI_ID" ]]; then
                        GPU_ENV="DRI_PRIME=$INTEL_PCI_ID! MESA_VK_DEVICE_SELECT=$INTEL_PCI_ID!"
                      fi
                    ;;
                    "Nvidia")
                      GPU_ENV="__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only"
                      if [[ -n "$NVIDIA_PCI_ID" ]]; then
                        GPU_ENV="$GPU_ENV DRI_PRIME=$NVIDIA_PCI_ID! MESA_VK_DEVICE_SELECT=$NVIDIA_PCI_ID!"
                      fi
                    ;;
                  esac

                  EXEC_BASE="env USE_GAMEMODE=$env_gamemode USE_MANGOHUD=$env_mangohud PROTON_ENABLE_WAYLAND=$env_wayland UMU_PREFIX_NAME=$env_prefix_name USE_PROTON_UMU=$env_umu USE_STEAM_INTEGRATION=$env_steam USE_STEAM_OVERLAY=$env_overlay $GPU_ENV umu-run-wrapper \"$actual_exe\""

                  if [[ "$args" == *"%command%"* ]]; then
                    EXEC_CMD=$(echo "$args" | sed "s|%command%|$EXEC_BASE|g")
                  else
                    EXEC_CMD="$EXEC_BASE $args"
                  fi

                  # Added '--' parameter separator to prevent getopt from parsing fields starting with dashes as CLI flags
                  cat <<EOF > "$DESKTOP_FILE"
        [Desktop Entry]
        Name=$LNK_DISPLAY_NAME
        Exec=$EXEC_CMD
        Icon=$ICON_SPEC
        Type=Application
        Categories=Game;
        Path=$(dirname "$actual_exe")
        Terminal=false
        X-UMU-Lnk-Path=$lnk
        X-UMU-Raw-Args=$args
        X-UMU-Actual-Exe=$actual_exe
        X-UMU-Prefix-Name=$env_prefix_name
        X-UMU-GPU-Select=$env_gpu_select
        X-UMU-Steam-Integration=$env_steam
        X-UMU-Steam-Overlay=$env_overlay
        EOF

                  chmod +x "$DESKTOP_FILE"

                  ${pkgs.libnotify}/bin/notify-send -i "$ICON_SPEC" "New game added" "Shortcut created for $LNK_DISPLAY_NAME"
                fi
      '')
      (pkgs.writeScriptBin "manage-umu-shortcuts" ''
        #!${pkgs.bash}/bin/bash
        # Dynamically resolve GDK_PIXBUF_MODULE_FILE via findutils to prevent hardcoded version directory conflicts
        GDK_PIXBUF_CACHE_FILE=$(${pkgs.findutils}/bin/find "${pkgs.librsvg}/lib/gdk-pixbuf-2.0" -name "loaders.cache" -print -quit 2>/dev/null)
        if [[ -n "$GDK_PIXBUF_CACHE_FILE" ]]; then
          export GDK_PIXBUF_MODULE_FILE="$GDK_PIXBUF_CACHE_FILE"
        fi
        export GI_TYPELIB_PATH="${giTypelibPath}"
        # Set XDG_DATA_DIRS to expose required desktop schemas to the GIO backend
        export XDG_DATA_DIRS="${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}:${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}:${pkgs.adwaita-icon-theme}/share:${pkgs.hicolor-icon-theme}/share:$XDG_DATA_DIRS"
        exec ${
          pkgs.python3.withPackages (ps: [ ps.pygobject3 ])
        }/bin/python3 "${pkgs.writeText "manage-shortcuts-python" ''
          import sys
          import os
          import re
          import subprocess
          import configparser
          import gi
          gi.require_version("Gtk", "3.0")
          from gi.repository import Gtk, Gdk, GdkPixbuf

          def scan_gpus():
              amd, nvidia, intel = "", "", ""
              try:
                  res = subprocess.run(["${pkgs.pciutils}/bin/lspci", "-nn"], capture_output=True, text=True)
                  for line in res.stdout.splitlines():
                      if any(x in line for x in ["VGA compatible controller", "3D controller", "Display controller"]):
                          match = re.search(r"\[([0-9a-fA-F]{4}:[0-9a-fA-F]{4})\]", line)
                          if match:
                              pci_id = match.group(1)
                              l = line.lower()
                              if "nvidia" in l:
                                  nvidia_id = pci_id
                              elif any(x in l for x in ["amd", "advanced micro devices", "ati"]):
                                  amd = pci_id
                              elif "intel" in l:
                                  intel = pci_id
              except Exception:
                  pass
              return amd, nvidia, intel

          class EditDialog(Gtk.Dialog):
              def __init__(self, parent, desktop_path):
                  super().__init__(title="Редактирование ярлыка", transient_for=parent, flags=0)
                  self.set_border_width(15)
                  self.set_default_size(500, -1)
                  self.set_position(Gtk.WindowPosition.CENTER_ON_PARENT)
                  self.set_resizable(False)

                  self.desktop_path = desktop_path
                  self.amd_id, self.nvidia_id, self.intel_id = scan_gpus()

                  # Load desktop entry configuration using casing-preserving configparser
                  self.config = configparser.ConfigParser(interpolation=None, strict=False)
                  self.config.optionxform = str
                  self.config.read(desktop_path, encoding="utf-8")

                  self.current_name = self.config.get("Desktop Entry", "Name", fallback="")
                  self.current_icon = self.config.get("Desktop Entry", "Icon", fallback="wine")
                  self.raw_args = self.config.get("Desktop Entry", "X-UMU-Raw-Args", fallback="")
                  self.actual_exe = self.config.get("Desktop Entry", "X-UMU-Actual-Exe", fallback="")
                  self.lnk_path = self.config.get("Desktop Entry", "X-UMU-Lnk-Path", fallback="")
                  self.prefix_name = self.config.get("Desktop Entry", "X-UMU-Prefix-Name", fallback="default")
                  self.gpu_select = self.config.get("Desktop Entry", "X-UMU-GPU-Select", fallback="Автоматически")
                  
                  exec_line = self.config.get("Desktop Entry", "Exec", fallback="")
                  self.umu_enabled = "USE_PROTON_UMU=1" in exec_line
                  self.wayland_enabled = "PROTON_ENABLE_WAYLAND=0" not in exec_line
                  self.gamemode_enabled = "USE_GAMEMODE=0" not in exec_line
                  self.mangohud_enabled = "USE_MANGOHUD=0" not in exec_line
                  
                  # Parse defaults reliably to avoid false true evaluations
                  steam_val = self.config.get("Desktop Entry", "X-UMU-Steam-Integration", fallback="0")
                  self.steam_enabled = steam_val == "1"

                  overlay_val = self.config.get("Desktop Entry", "X-UMU-Steam-Overlay", fallback="0")
                  self.overlay_enabled = overlay_val == "1"

                  # Setup content layout
                  content_area = self.get_content_area()
                  vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
                  content_area.pack_start(vbox, True, True, 0)

                  # Горизонтальный контейнер для независимого смещения элементов
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

                  # 1. proton-umu toggle
                  lbl_umu = Gtk.Label(label="Использовать Proton UMU:")
                  lbl_umu.set_alignment(0, 0.5)
                  self.chk_umu = Gtk.CheckButton()
                  self.chk_umu.set_active(self.umu_enabled)
                  grid.attach(lbl_umu, 0, 0, 1, 1)
                  grid.attach(self.chk_umu, 1, 0, 1, 1)

                  # 2. gamemode toggle
                  lbl_gamemode = Gtk.Label(label="Использовать GameMode:")
                  lbl_gamemode.set_alignment(0, 0.5)
                  self.chk_gamemode = Gtk.CheckButton()
                  self.chk_gamemode.set_active(self.gamemode_enabled)
                  grid.attach(lbl_gamemode, 0, 1, 1, 1)
                  grid.attach(self.chk_gamemode, 1, 1, 1, 1)

                  # 3. mangohud toggle
                  lbl_mangohud = Gtk.Label(label="Использовать MangoHud:")
                  lbl_mangohud.set_alignment(0, 0.5)
                  self.chk_mangohud = Gtk.CheckButton()
                  self.chk_mangohud.set_active(self.mangohud_enabled)
                  grid.attach(lbl_mangohud, 0, 2, 1, 1)
                  grid.attach(self.chk_mangohud, 1, 2, 1, 1)

                  # 4. wayland toggle (Grouped cleanly at the top)
                  lbl_wayland = Gtk.Label(label="Использовать Wayland:")
                  lbl_wayland.set_alignment(0, 0.5)
                  self.chk_wayland = Gtk.CheckButton()
                  self.chk_wayland.set_active(self.wayland_enabled)
                  grid.attach(lbl_wayland, 0, 3, 1, 1)
                  grid.attach(self.chk_wayland, 1, 3, 1, 1)

                  # 5. steam integration toggle
                  lbl_steam = Gtk.Label(label="Интеграция со Steam:")
                  lbl_steam.set_alignment(0, 0.5)
                  self.chk_steam = Gtk.CheckButton()
                  self.chk_steam.set_active(self.steam_enabled)
                  grid.attach(lbl_steam, 0, 4, 1, 1)
                  grid.attach(self.chk_steam, 1, 4, 1, 1)

                  # 6. steam overlay toggle
                  lbl_overlay = Gtk.Label(label="Оверлей Steam:")
                  lbl_overlay.set_alignment(0, 0.5)
                  self.chk_overlay = Gtk.CheckButton()
                  self.chk_overlay.set_active(self.overlay_enabled)
                  grid.attach(lbl_overlay, 0, 5, 1, 1)
                  grid.attach(self.chk_overlay, 1, 5, 1, 1)

                  # Mutual exclusion live callbacks using robust state variables
                  self.lock_signals = False
                  self.chk_overlay.connect("toggled", self.on_overlay_toggled)
                  self.chk_wayland.connect("toggled", self.on_wayland_toggled)

                  if self.overlay_enabled:
                      self.chk_wayland.set_active(False)
                      self.chk_wayland.set_sensitive(False)
                  elif self.wayland_enabled:
                      self.chk_overlay.set_active(False)
                      self.chk_overlay.set_sensitive(False)

                  # prefix name
                  lbl_prefix = Gtk.Label(label="Имя префикса (в ~/.umu/):")
                  lbl_prefix.set_alignment(0, 0.5)
                  self.prefix_entry = Gtk.Entry()
                  self.prefix_entry.set_text(self.prefix_name)
                  grid.attach(lbl_prefix, 0, 6, 1, 1)
                  grid.attach(self.prefix_entry, 1, 6, 1, 1)

                  # gpu selection
                  lbl_gpu = Gtk.Label(label="Видеокарта:")
                  lbl_gpu.set_alignment(0, 0.5)
                  
                  # Format CB choices cleanly
                  gpu_cb_list = [self.gpu_select]
                  for opt in ["Автоматически", "AMD", "Nvidia", "Intel"]:
                      if opt != self.gpu_select:
                          gpu_cb_list.append(opt)
                          
                  self.gpu_combo = Gtk.ComboBoxText()
                  for opt in gpu_cb_list:
                      self.gpu_combo.append_text(opt)
                  self.gpu_combo.set_active(0)
                  grid.attach(lbl_gpu, 0, 7, 1, 1)
                  grid.attach(self.gpu_combo, 1, 7, 1, 1)

                  # Name textfield
                  lbl_name = Gtk.Label(label="Название:")
                  lbl_name.set_alignment(0, 0.5)
                  self.name_entry = Gtk.Entry()
                  self.name_entry.set_text(self.current_name)
                  grid.attach(lbl_name, 0, 8, 1, 1)
                  grid.attach(self.name_entry, 1, 8, 1, 1)

                  # Icon picker
                  lbl_icon = Gtk.Label(label="Иконка (файл):")
                  lbl_icon.set_alignment(0, 0.5)
                  self.icon_chooser = Gtk.FileChooserButton(title="Выберите иконку", action=Gtk.FileChooserAction.OPEN)
                  self.icon_chooser.set_filename(self.current_icon)
                  grid.attach(lbl_icon, 0, 9, 1, 1)

                  icon_hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=5)
                  icon_hbox.pack_start(self.icon_chooser, True, True, 0)
                  
                  self.btn_reset = Gtk.Button(label="Сбросить")
                  self.btn_reset.connect("clicked", self.on_reset_clicked)
                  icon_hbox.pack_start(self.btn_reset, False, False, 0)
                  grid.attach(icon_hbox, 1, 9, 1, 1)

                  # Arguments Entry
                  lbl_args = Gtk.Label(label="Аргументы запуска:")
                  lbl_args.set_alignment(0, 0.5)
                  self.args_entry = Gtk.Entry()
                  self.args_entry.set_text(self.raw_args)
                  self.args_entry.set_placeholder_text("ENV=1 %command% --arg-here")
                  grid.attach(lbl_args, 0, 10, 1, 1)
                  grid.attach(self.args_entry, 1, 10, 1, 1)

                  # Preview Section
                  preview_hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
                  vbox.pack_start(preview_hbox, False, False, 5)
                  
                  lbl_p_title = Gtk.Label(label="Предпросмотр иконки:")
                  preview_hbox.pack_start(lbl_p_title, False, False, 0)
                  
                  self.img_preview = Gtk.Image()
                  preview_hbox.pack_start(self.img_preview, False, False, 0)

                  # Icon zoom expansion button
                  self.btn_zoom = Gtk.Button(label="Увеличить")
                  self.btn_zoom.connect("clicked", self.on_zoom_clicked)
                  preview_hbox.pack_start(self.btn_zoom, False, False, 0)

                  path_hash = os.path.basename(self.desktop_path).replace("umu-", "").replace(".desktop", "")
                  self.default_icon_spec = os.path.expanduser(f"~/.local/share/icons/umu/umu-{path_hash}.png")
                  if not os.path.exists(self.default_icon_spec):
                      self.default_icon_spec = "wine"

                  self.update_preview_image(self.current_icon)
                  self.icon_chooser.connect("file-set", self.on_icon_file_set)

                  # Standard dialog control triggers
                  self.add_button("Отмена", Gtk.ResponseType.CANCEL)
                  self.add_button("Сохранить изменения", Gtk.ResponseType.OK)

                  self.show_all()

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
                  path = self.icon_chooser.get_filename() if hasattr(self, "icon_chooser") else None
                  if not path:
                      path = self.default_icon_spec if hasattr(self, "default_icon_spec") else None
                  if not path or not os.path.exists(path):
                      return
                  zoom_win = Gtk.Window(title="Предпросмотр")
                  zoom_win.set_border_width(10)
                  zoom_win.set_position(Gtk.WindowPosition.CENTER_ON_PARENT)
                  zoom_win.set_type_hint(Gdk.WindowTypeHint.DIALOG)
                  zoom_win.set_resizable(False)
                  zoom_win.set_transient_for(self)
                  zoom_win.set_modal(True)

                  # Закрытие строго по Escape или действиям оконного менеджера
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
                      pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, size, size, True)
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
                          pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, size, size, True)
                          surface = Gdk.cairo_surface_create_from_pixbuf(pixbuf, scale, None)
                          self.img_preview.set_from_surface(surface)
                      except Exception:
                          self.img_preview.set_from_icon_name("wine", Gtk.IconSize.DIALOG)
                  else:
                      self.img_preview.set_from_icon_name("wine", Gtk.IconSize.DIALOG)

              def save_changes(self):
                  new_name = self.name_entry.get_text().strip()
                  new_icon = self.icon_chooser.get_filename() or "wine"
                  new_args = self.args_entry.get_text().strip()
                  new_prefix = self.prefix_entry.get_text().strip()
                  new_gpu = self.gpu_combo.get_active_text()
                  
                  env_umu = "1" if self.chk_umu.get_active() else "0"
                  env_gamemode = "1" if self.chk_gamemode.get_active() else "0"
                  env_mangohud = "1" if self.chk_mangohud.get_active() else "0"
                  env_wayland = "1" if self.chk_wayland.get_active() else "0"
                  env_steam = "1" if self.chk_steam.get_active() else "0"
                  env_overlay = "1" if self.chk_overlay.get_active() else "0"

                  gpu_env = ""
                  if new_gpu == "Nvidia":
                      gpu_env = "__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only"
                      if self.nvidia_id:
                          gpu_env += f" DRI_PRIME={self.nvidia_id}! MESA_VK_DEVICE_SELECT={self.nvidia_id}!"
                  elif new_gpu == "AMD" and self.amd_id:
                      gpu_env = f"DRI_PRIME={self.amd_id}! MESA_VK_DEVICE_SELECT={self.amd_id}!"
                  elif new_gpu == "Intel" and self.intel_id:
                      gpu_env = f"DRI_PRIME={self.intel_id}! MESA_VK_DEVICE_SELECT={self.intel_id}!"

                  exec_base = f"env USE_GAMEMODE={env_gamemode} USE_MANGOHUD={env_mangohud} PROTON_ENABLE_WAYLAND={env_wayland} UMU_PREFIX_NAME={new_prefix} USE_PROTON_UMU={env_umu} USE_STEAM_INTEGRATION={env_steam} USE_STEAM_OVERLAY={env_overlay} {gpu_env}".strip()
                  exec_base += " umu-run-wrapper"

                  if "%command%" in new_args:
                      exec_cmd = new_args.replace("%command%", f'{exec_base} "{self.actual_exe}"')
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

                  with open(self.desktop_path, "w", encoding="utf-8") as f:
                      self.config.write(f, space_around_delimiters=False)

          class ShortcutsManager(Gtk.Window):
              def __init__(self):
                  super().__init__(title="Manage UMU Shortcuts")
                  self.set_default_size(750, 480) # Сбалансированный размер
                  self.set_position(Gtk.WindowPosition.CENTER)
                  self.set_border_width(10)

                  vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
                  self.add(vbox)

                  search_hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=5)
                  vbox.pack_start(search_hbox, False, False, 0)
                  
                  search_lbl = Gtk.Label(label="Поиск ярлыков:")
                  search_hbox.pack_start(search_lbl, False, False, 5)
                  
                  self.search_entry = Gtk.Entry()
                  self.search_entry.connect("changed", self.on_search_changed)
                  search_hbox.pack_start(self.search_entry, True, True, 5)

                  # Храним стандартный Pixbuf (это безопасно и стабильно)
                  self.store = Gtk.ListStore(GdkPixbuf.Pixbuf, str, str)
                  
                  self.filter_store = self.store.filter_new()
                  self.filter_store.set_visible_func(self.filter_search_results)

                  self.treeview = Gtk.TreeView(model=self.filter_store)
                  scroll = Gtk.ScrolledWindow()
                  scroll.add(self.treeview)
                  vbox.pack_start(scroll, True, True, 0)

                  # Отрисовщик иконки через Cairo-поверхность
                  renderer_px = Gtk.CellRendererPixbuf()
                  renderer_px.set_property("ypad", 4)
                  renderer_px.set_property("xpad", 4)
                  col_px = Gtk.TreeViewColumn("Иконка", renderer_px)
                  col_px.set_cell_data_func(renderer_px, self.set_icon_cell) # Подключаем резкую отрисовку
                  self.treeview.append_column(col_px)

                  renderer_txt = Gtk.CellRendererText()
                  renderer_txt.set_property("ypad", 4)
                  renderer_txt.set_property("xpad", 4)
                  col_txt = Gtk.TreeViewColumn("Название", renderer_txt, text=1)
                  col_txt.set_expand(True)
                  self.treeview.append_column(col_txt)

                  self.treeview.connect("row-activated", self.on_row_double_clicked)

                  bbox = Gtk.ButtonBox(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
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
                      # Конвертируем GdkPixbuf в бритвенно-резкую Cairo-поверхность с учетом масштаба
                      surface = Gdk.cairo_surface_create_from_pixbuf(pixbuf, scale, None)
                      cell.set_property("surface", surface)
                  else:
                      cell.set_property("surface", None)

              def load_scaled_icon(self, icon_path):
                  scale = self.get_scale_factor()
                  size = 40 * scale  # Подгружаем иконку в высоком разрешении под ваш масштаб
                  try:
                      if icon_path and os.path.exists(icon_path):
                          return GdkPixbuf.Pixbuf.new_from_file_at_scale(icon_path, size, size, True)
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
                              config = configparser.ConfigParser(interpolation=None, strict=False)
                              config.optionxform = str
                              config.read(path, encoding="utf-8")
                              if "Desktop Entry" in config:
                                  name = config.get("Desktop Entry", "Name", fallback=f)
                                  icon = config.get("Desktop Entry", "Icon", fallback="wine")
                                  
                                  pixbuf = self.load_scaled_icon(icon)
                                  self.store.append([pixbuf, name, path])
                          except Exception as e:
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
                          flags=Gtk.DialogFlags.MODAL,
                          type=Gtk.MessageType.QUESTION,
                          buttons=Gtk.ButtonsType.YES_NO,
                          message_format=f"Вы уверены, что хотите полностью удалить ярлык '{name}'?"
                      )
                      res = confirm.run()
                      confirm.destroy()
                      if res == Gtk.ResponseType.YES:
                          os.remove(desktop_path)
                          self.populate_list()

          if __name__ == "__main__":
              ShortcutsManager()
              Gtk.main()
        ''}" "$@"
      '')
      (pkgs.writeScriptBin "manage-umu-prefixes" ''
        #!${pkgs.bash}/bin/bash
        # Dynamically resolve GDK_PIXBUF_MODULE_FILE via findutils to prevent hardcoded version directory conflicts
        GDK_PIXBUF_CACHE_FILE=$(${pkgs.findutils}/bin/find "${pkgs.librsvg}/lib/gdk-pixbuf-2.0" -name "loaders.cache" -print -quit 2>/dev/null)
        if [[ -n "$GDK_PIXBUF_CACHE_FILE" ]]; then
          export GDK_PIXBUF_MODULE_FILE="$GDK_PIXBUF_CACHE_FILE"
        fi
        export GI_TYPELIB_PATH="${giTypelibPath}"
        # Set XDG_DATA_DIRS to expose required desktop schemas to the GIO backend when launched from console
        export XDG_DATA_DIRS="${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}:${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}:${pkgs.adwaita-icon-theme}/share:${pkgs.hicolor-icon-theme}/share:$XDG_DATA_DIRS"
        exec ${
          pkgs.python3.withPackages (ps: [ ps.pygobject3 ])
        }/bin/python3 "${pkgs.writeText "manage-prefixes-python" ''
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

                  # Header Label
                  lbl = Gtk.Label()
                  lbl.set_markup("<b>Выберите префикс для настройки или управления:</b>")
                  lbl.set_alignment(0, 0.5)
                  vbox.pack_start(lbl, False, False, 5)

                  # ListStore and TreeView Setup
                  self.store = Gtk.ListStore(str, str) # name, path
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

                  # Button Actions Box
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
                          message_format="Нельзя удалить префикс по умолчанию ('default')!"
                      )
                      dialog.run()
                      dialog.destroy()
                      return

                  confirm = Gtk.MessageDialog(
                      transient_for=self,
                      flags=Gtk.DialogFlags.MODAL,
                      type=Gtk.MessageType.QUESTION,
                      buttons=Gtk.ButtonsType.YES_NO,
                      message_format=f"Вы уверены, что хотите полностью удалить префикс '{name}'? Все установленные туда игры и сохранения будут утеряны!"
                  )
                  res = confirm.run()
                  confirm.destroy()
                  if res == Gtk.ResponseType.YES:
                      try:
                          shutil.rmtree(path)
                          self.populate_list()
                          subprocess.run(["${pkgs.libnotify}/bin/notify-send", "Prefix Deleted", f"Удален префикс {name}"])
                      except Exception as e:
                          err_dialog = Gtk.MessageDialog(
                              transient_for=self,
                              flags=Gtk.DialogFlags.MODAL,
                              type=Gtk.MessageType.ERROR,
                              buttons=Gtk.ButtonsType.OK,
                              message_format=f"Ошибка удаления префикса: {e}"
                          )
                          err_dialog.run()
                          err_dialog.destroy()

          if __name__ == "__main__":
              PrefixManager()
              Gtk.main()
        ''}" "$@"
      '')
    ];
  };
}
