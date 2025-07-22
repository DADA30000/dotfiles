{ ... }:
{

  # Import original home.nix
  imports = [ (import ../../machines/iso/home.nix {avg-flag = true;}) ];

 }
