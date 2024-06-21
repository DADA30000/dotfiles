{ config, pkgs, inputs, lib, ... }:
{
  home.homeDirectory = "/home/${config.home.username}";
  home.stateVersion = "24.05";
  services.arrpc.enable = true;
  nixpkgs.config.allowUnfree = true;
  imports = [
    ./zsh.nix
    ./kitty.nix
    ./btop.nix
    ./cava.nix
    ./hyprland.nix
    ./waybar.nix
    ./fastfetch.nix
    ./swaync.nix
  ];
  home.packages = with pkgs; [
    fzf
    remmina
    python311
    dmenu-wayland
    winetricks
    gnome.zenity
    wine
    telegram-desktop
    xorg.xeyes
    bat
    tldr
    espeak
    bottles
    steam-run
    vesktop
  ];
  programs.imv = {
    enable = true;
    settings = {
      options.upscaling_method = "nearest_neighbour";
    };
  };
  programs.rofi = {
    enable = true;
    package = pkgs.rofi-wayland;
    font = "JetBrainsMono NF 14";
    theme = ./theme.rasi;
  };
  programs.obs-studio = {
    enable = true;
    #plugins = [ pkgs.obs-studio-plugins.obs-ndi ];
  };
  home.pointerCursor = {
    gtk.enable = true;
    x11.enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Classic";
    size = 24;
  };
  gtk = {
    enable = true;
    gtk3.extraConfig.gtk-decoration-layout = "menu:";
    gtk4.extraConfig.gtk-hint-font-metrics = 1;
    cursorTheme.name = "Bibata-Modern-Classic";
    iconTheme.name = "Nordzy";
    theme.name = "Materia-dark";
    font.name = "Noto Sans Medium";
    font.size = 11;
  };
  home.file = {
    ".themes".source = ./.themes;
    ".config/nvim/init.vim".source = ./init.vim;
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
  programs.wlogout = {
    enable = true;
    layout = [
      {
          label = "lock";
          action = "hyprlock";
          text = "Lock";
          keybind = "l";
      }
      {
          label = "logout";
          action = "hyprctl dispatch exit";
          text = "Logout";
          keybind = "e";
      }
      {
          label = "shutdown";
          action = "systemctl poweroff";
          text = "Shutdown";
          keybind = "s";
      }
      {
          label = "reboot";
          action = "systemctl reboot";
          text = "Reboot";
          keybind = "r";
      }
    ];
    style = ''
      * {
      	background-image: none;
      	font-family: "JetBrainsMono Nerd Font";
      	font-size: 16px;
      }
      window {
      	background-color: rgba(0, 0, 0, 0);
      }
      button {
          color: #FFFFFF;
              border-style: solid;
      	border-radius: 15px;
      	border-width: 3px;
      	background-color: rgba(0, 0, 0, 0);
      	background-repeat: no-repeat;
      	background-position: center;
      	background-size: 25%;
      }
      
      button:focus, button:active, button:hover {
      	background-color: rgba(0, 0, 0, 0);
      	color: #4470D2;
      }
      
      #lock {
          background-image: image(url("${./lock.png}"));
      }
      
      #logout {
          background-image: image(url("${./logout.png}"));
      }
      
      #shutdown {
          background-image: image(url("${./shutdown.png}"));
      }
      
      #reboot {
          background-image: image(url("${./reboot.png}"));
      }
    '';
  };
  services.mpd-discord-rpc.enable = true;
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
}
