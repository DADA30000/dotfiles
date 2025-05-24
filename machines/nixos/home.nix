{
  inputs,
  config,
  ...
}:
{

  # Import other modules
  imports = [
    ../../modules/home
    inputs.nix-index-database.hmModules.nix-index
  ];

  # Enable rich presence
  services.arrpc.enable = true;

  #systemd.user.services = {
  #  plymouth-quit = {
  #    Install= {  
  #      WantedBy = [ "default.target" ];
  #    };
  #    Unit = {
  #      DefaultDependencies = "no";
  #      Before = [ "default.target" ];
  #    };
  #    Service = {
  #      Type = "oneshot";
  #      ExecStart = [ "/run/wrappers/bin/sudo ${pkgs.plymouth}/bin/plymouth quit" "/run/wrappers/bin/sudo ${pkgs.plymouth}/bin/plymouth quit" "/run/wrappers/bin/sudo ${pkgs.plymouth}/bin/plymouth quit" "/run/wrappers/bin/sudo ${pkgs.plymouth}/bin/plymouth quit" "/run/wrappers/bin/sudo ${pkgs.plymouth}/bin/plymouth quit" ];
  #    };
  #  };
  #};

  # Enable firefox customization
  firefox.enable = false; # Reminder for dumb me to change it later <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

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

  flatpak = {

    # Enable user flatpak
    enable = false;

    # Packages to install from flatpak
    packages = [ "io.github.Soundux" ];

  };

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
