{ lib, ... }:
{

  # Import original home.nix
  imports = [ ../../machines/nixos/home.nix ];

  firefox.enable = lib.mkForce true;

 }
