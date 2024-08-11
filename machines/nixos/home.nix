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
    ./fastfetch.nix
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
      ExecStart = "${pkgs.mpvpaper}/bin/mpvpaper -s -o 'no-audio loop input-ipc-server=/tmp/mpvpaper-socket' '*' ${./stuff/wallpaper.mp4}";
    };
  };
  dconf.settings = {
    "org/nemo/preferences" = {
      default-folder-viewer = "list-view";
      show-hidden-files = true;
      thumbnail-limit = lib.hm.gvariant.mkUint64 68719476736;
    };
    "org/gnome/desktop/interface" = { 
      color-scheme = "prefer-dark"; 
    };
  };
  programs.imv = {
    enable = true;
    settings = {
      options.upscaling_method = "nearest_neighbour";
    };
  };
  qt = {
    enable = true;
    platformTheme.name = "gtk3";
    #style = {
    #  name = "lightly";
    #  package = pkgs.lightly-qt;
    #};
  };
  programs.obs-studio = {
    enable = true;
    #plugins = [ pkgs.obs-studio-plugins.obs-ndi ];
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
    cursorTheme.name = "Bibata-Modern-Classic";
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
