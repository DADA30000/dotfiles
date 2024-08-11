{ config, ... }:
{
  imports = [
    ./configuration.nix
    ../../modules/system/anicli-ru
    ../../modules/system/zapret
  ];
  # Enable russian anicli
  anicli-ru.enable = true;
  
  # Enable DPI (Deep packet inspection) bypass
  zapret.enable = true;
}
