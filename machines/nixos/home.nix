{ config, pkgs, inputs, lib, ... }:
{
  home.homeDirectory = "/home/${config.home.username}";
  home.stateVersion = "24.05";
  services.arrpc.enable = true;
  nixpkgs.config.allowUnfree = true;
  imports = [
    #inputs.ags.homeManagerModules.default
    inputs.nix-flatpak.homeManagerModules.nix-flatpak
    ./zsh.nix
    ./kitty.nix
    ./hyprland.nix
    ./waybar.nix
    ./swaync.nix
  ];
  home.packages = with pkgs; [
  ];
  services.flatpak = {
    enable = true;
    uninstallUnmanaged = true;
    packages = [];
    update.auto = {
      enable = true;
      onCalendar = "daily";
    };
  };
  #programs.ags = {
  #  enable = true;
  #};
  systemd.user.services.mpvpaper = {
    Unit = {
      Description = "Play video wallpaper.";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.mpvpaper}/bin/mpvpaper -s -o 'no-audio loop input-ipc-server=/tmp/mpvpaper-socket hwdec=auto' '*' ${./stuff/wallpaper.mp4}";
    };
  };
  dconf.settings = {
    "org/nemo/preferences" = {
      default-folder-viewer = "list-view";
      show-hidden-files = true;
      thumbnail-limit = lib.hm.gvariant.mkUint64 68719476736;
    };
    "org/gnome/nautilus/preferences" = {
      default-folder-viewer = "list-view";
      migrated-gtk-settings = true;
    };
    "org/gnome/desktop/interface" = { 
      color-scheme = "prefer-dark"; 
    };
  };
  qt = {
    enable = true;
    platformTheme.name = "gtk3";
  };
  programs.obs-studio = {
    enable = true;
  };
  home.pointerCursor = {
    gtk.enable = true;
    x11.enable = true;
    package = pkgs.google-cursor;
    name = "GoogleDot-Black";
    size = 24;
  };
  gtk = {
    enable = true;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
    gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
    cursorTheme.name = "GoogleDot-Black";
    iconTheme = {
      name = "MoreWaita";
      package = pkgs.morewaita-icon-theme;
    };
    theme.name = "Materia-dark";
    font.name = "Noto Sans Medium";
    font.size = 11;
  };
  home.file = {
    ".themes".source = ./stuff/.themes;
    ".config/nvim/init.vim".source = ./stuff/init.vim;
    ".config/mpv".source = ./stuff/mpv;
  };
  xdg.userDirs = {
    createDirectories = true;
    enable = true;
  };
  xdg.mimeApps.defaultApplications = {
    "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
    "application/x-compressed-tar" = "org.gnome.FileRoller.desktop";
    "application/x-bzip2-compressed-tar" = "org.gnome.FileRoller.desktop";
    "application/x-bzip1-compressed-tar" = "org.gnome.FileRoller.desktop";
    "application/x-tzo" = "org.gnome.FileRoller.desktop";
    "application/x-xz"= "org.gnome.FileRoller.desktop";
    "application/x-lzma-compressed-tar" = "org.gnome.FileRoller.desktop";
    "application/zstd" = "org.gnome.FileRoller.desktop";
    "application/x-7z-compressed" = "org.gnome.FileRoller.desktop";
    "application/x-zstd-compressed-tar" = "org.gnome.FileRoller.desktop";
    "application/x-lzma" = "org.gnome.FileRoller.desktop";
    "application/x-lz4" = "org.gnome.FileRoller.desktop";
    "application/x-xz-compressed-tar" = "org.gnome.FileRoller.desktop";
    "application/x-lz4-compressed-tar" = "org.gnome.FileRoller.desktop";
    "application/x-archive" = "org.gnome.FileRoller.desktop";
    "application/x-cpio" = "org.gnome.FileRoller.desktop";
    "application/x-lzop" = "org.gnome.FileRoller.desktop";
    "application/x-bzip1" = "org.gnome.FileRoller.desktop";
    "application/x-tar" = "org.gnome.FileRoller.desktop";
    "application/x-bzip2" = "org.gnome.FileRoller.desktop";
    "application/gzip" = "org.gnome.FileRoller.desktop";
    "application/x-lzip-compressed-tar" = "org.gnome.FileRoller.desktop";
    "application/x-tarz "= "org.gnome.FileRoller.desktop";
    "application/zip" = "org.gnome.FileRoller.desktop";
    "inode/directory" = "nemo.desktop";
    "text/html" = "firefox.desktop";
    "video/mp4" = "mpv.desktop";
    "audio/mpeg" = "mpv.desktop";
    "audio/flac" = "mpv.desktop";
  };
  xdg.mimeApps.enable = true;
  services.mpd = {
    enable = true;
    dataDir = "${config.xdg.dataHome}/.mpd";
  };
  programs.neovim = {
    enable = true;
    viAlias = true;
    defaultEditor = true;
    vimAlias = true;
    vimdiffAlias = true;
  };
  programs.ncmpcpp = {
    enable = true;
    settings = {
      mpd_host = "127.0.0.1";
      mpd_port = "6600";
      mouse_list_scroll_whole_page = "yes";
      lines_scrolled = "1";
      visualizer_in_stereo = "yes";
      visualizer_fifo_path = "/tmp/mpd.fifo";
      visualizer_output_name = "my_fifo";
      visualizer_type = "wave_filled";
      visualizer_look = "▄▍";
      visualizer_color = "blue";
      progressbar_look = "▄▄";
      mouse_support = "yes";
      allow_for_physical_item_deletion = "yes";
      statusbar_color = "blue";
      current_item_prefix = " ";
      song_columns_list_format = "(6)[]{} (25)[green]{a} (34)[white]{t|f} (5f)[magenta]{l} (1)[]{}";
      color1 = "white";
      color2 = "blue";
      header_window_color = "blue";
      main_window_color = "blue";
      song_list_format = " $7%t$9 $R$3%a                      ";
      song_status_format = "$b$7♫ $2%a $4⟫$3⟫ $8%t $4⟫$3⟫ $5%b ";
      song_window_title_format = " ♬ {%a}  {%t}";
    };
  };
  services.mpd-discord-rpc.enable = true;
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
  programs.btop = {
    enable = true;
    settings = {
      color_theme = "${pkgs.btop}/share/btop/themes/dracula.theme";
      update_ms = 200;
      theme_background = false;
    };
  };
  programs.cava = {
  enable = true;
  settings = {
    general = {
      framerate = 60;
      bar_width = 4;
      };
    color = {
      gradient = 1;
      gradient_count = 2;
      gradient_color_1 = "'#4575da'";
      gradient_color_2 = "'#6804b5'";
      };
    };
  };
}
