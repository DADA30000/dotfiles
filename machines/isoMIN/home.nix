{ ... }:
{

  # Import original home.nix
  imports = [ (import ../../machines/iso/home.nix) {min-flag = true;} ];
 
 }
