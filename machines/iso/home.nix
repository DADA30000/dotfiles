{ lib, ... }:
{

  # Import original home.nix
  imports = [ ../../machines/nixos/home.nix ];

  firefox.enable = lib.mkForce true;

  flatpak.enable = lib.mkForce false;

  systemd.user.services.replays.enable = false;

 }
