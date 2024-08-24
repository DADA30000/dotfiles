{ config, ... }:
{
  imports = [
    ./home.nix
    ../../modules/home/hyprland
    ../../modules/home/fastfetch
  ];

  hyprland = {

    # Enable base Hyprland configuration (required for options below)
    enable = true;

    # Whether to use release from nixpkgs, or use latest git
    stable = false;

    # Enable Hyprland plugins
    enable-plugins = true;

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
