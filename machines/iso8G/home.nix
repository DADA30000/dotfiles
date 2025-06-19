{ lib, ... }:
{

  # Import original home.nix
  imports = [ ../../machines/iso/home.nix ];
  
  obs.enable = lib.mkForce false;
 }
