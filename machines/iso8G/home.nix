{ lib, ... }:
{

  # Import original home.nix
  imports = [ ../../machines/iso/home.nix ];
 
  btop.enable = lib.mkForce false;
 }
