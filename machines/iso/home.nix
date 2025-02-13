{ ... }:
{

  # Import other modules
  imports = [ ../../modules/home ];

  # Enable rich presence
  services.arrpc.enable = true;

  # Enable firefox customization
  firefox.enable = true; # Reminder for dumb me to change it later <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

  # Version at which home-manager was first configured (Don't change it)
  home.stateVersion = "24.05";
  
  # Allow installation of proprietary stuff
  nixpkgs.config.allowUnfree = true;

  # Enable Anime4K non-AI upscaler
  home.file.".config/mpv".source = ../../stuff/mpv;

  # Enable neovim, console based text editor
  neovim.enable = true;

  # Enable theming stuff like cursor theme, icon theme and etc
  theming.enable = true;

  # Enable cava audio visualizer
  cava.enable = false;

  # Enable swaync notification manager
  swaync.enable = true;

  # Enable kitty terminal emulator
  kitty.enable = true;

  # Enable zsh shell
  zsh.enable = true;

  # Enable waybar panel
  waybar.enable = true;

  # Enable btop process manager
  btop.enable = true;

  xdg.userDirs = {

    # Create folders like Downloads, Documents automatically
    createDirectories = true;
    enable = true;

  };

  mpd = {

    # Enable mpd music daemon
    enable = false;

    # Enable ncmpcpp, program to access and control mpd daemon
    ncmpcpp = false;

  };

  flatpak = {
    
    # Enable user flatpak
    enable = false;

    # Packages to install from flatpak
    packages = [];

  };

  hyprland = {

    # Enable base Hyprland configuration (required for options below)
    enable = true;

    # Whether to use release from nixpkgs, or use latest git
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
