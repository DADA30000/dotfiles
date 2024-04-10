{ config, pkgs, inputs, ... }:
{
  home.username = "l0lk3k";
  home.homeDirectory = "/home/${config.home.username}";
  home.stateVersion = "24.05";
  services.arrpc.enable = true;
  nixpkgs.config.allowUnfree = true;
  imports = [
    ./zsh.nix
    ./kitty.nix
    ./btop.nix
    ./cava.nix
  ];
  home.packages = with pkgs; [
    realvnc-vnc-viewer
    fzf
    hyprpaper
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
  ];
  gtk = {
    enable = true;
    gtk3.extraConfig.gtk-decoration-layout = "menu:";
    cursorTheme.name = "Bibata-Modern-Classic";
    iconTheme.name = "Nordzy";
    theme.name = "Materia-dark";
    font.name = "Noto Sans Medium";
    font.size = 11;
  };
  services.mpd-discord-rpc.enable = true;
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
}
