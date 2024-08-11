{ config, ... }:
{
  imports = [
    ./home.nix
    ../../modules/home/hyprland
  ];
  hyprland = {

    # Enable Hyprland configuration
    enable = true;

    # Whether to use release from nixpkgs, or use latest git
    stable = false;

    # Enable Hyprland plugins
    enable-plugins = true;

  };
}
