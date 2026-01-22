{
  config,
  min-flag, # Needed for minimal ISO version
  avg-flag, # Needed for 8G ISO version
  home-modules,
  ...
}:
{

  # Import other modulessss
  imports = home-modules;

  xdg.configFile."bookmarks.html".source = ../../stuff/bookmarks.html;
  
  # Docs are generated in NixOS conf
  manual.manpages.enable = false;

  umu.enable = true;

  # Enable rich presence
  services.arrpc.enable = false;

  thunderbird.enable = true;

  services.easyeffects.enable = true;

  zen.enable = true;

  # Enable firefox customization
  firefox.enable = false;

  # Version at which home-manager was first configured (Don't change it)
  home.stateVersion = "25.05";

  # Enable spotify with theme
  spicetify.enable = true;

  # Enable Anime4K non-AI upscaler
  home.file.".config/mpv".source = ../../stuff/mpv;

  # Enable neovim, console based text editor
  neovim.enable = true;

  # Enable theming stuff like cursor theme, icon theme and etc
  theming.enable = true;

  # Enable cava audio visualizer
  cava.enable = true;

  # Enable swaync notification manager
  swaync.enable = true;

  # Enable kitty terminal emulator
  kitty.enable = true;

  # Enable zsh shell
  zsh.enable = true;

  # Enable file associations
  file-associations.enable = true;

  # Enable waybar panel
  waybar.enable = true;

  # Enable btop process manager
  btop.enable = true;

  xdg.userDirs = {

    # Create folders like Downloads, Documents automatically
    createDirectories = true;
    enable = true;

    documents = "/home/${config.home.username}/Документы";

    download = "/home/${config.home.username}/Загрузки";

    music = "/home/${config.home.username}/Музыка";

    pictures = "/home/${config.home.username}/Изображения";

    videos = "/home/${config.home.username}/Видео";

  };

  mpd = {

    # Enable mpd music daemon
    enable = false;

    # Enable ncmpcpp, program to access and control mpd daemon
    ncmpcpp = false;

  };

  flatpak =
    if !(avg-flag || min-flag) then
      {

        # Enable system flatpak
        enable = true;

        # Packages to install from flatpak
        packages = [
          "io.github.Soundux"
        ];

      }
    else
      { };

  hyprland = {

    # Enable base Hyprland configuration (required for options below)
    enable = true;

    # Use Hyprland package from UNSTABLE nixpkgs
    from-unstable = false;

    # Use Hyprland package from nixpkgs
    stable = false;

    # Enable Hyprland plugins
    enable-plugins = false;

    # Enable video wallpapers with mpvpaper
    mpvpaper = false;

    # Enable image wallpapers with hyprpaper
    hyprpaper = true;

    # Enable power options menu
    wlogout = true;

    # Enable locking program
    hyprlock = true;

    # Enable rofi (used as applauncher and dmenu)
    rofi = true;

  };

  fastfetch = {

    # Enable fastfetch configuration (required for options below)
    enable = true;

    # Enable fastfetch printing when zsh starts up
    zsh-start = true;

    # Path to the logo that fastfetch will output
    logo-path = ../../stuff/logo.png;

  };
}
