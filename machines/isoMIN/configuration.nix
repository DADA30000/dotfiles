{
  user,
  lib,
  ...
}:
{
  imports = [ ../iso/configuration.nix ];
  home-manager.users.${user} = import ./home.nix;
  networking.hostName = lib.mkForce "isoMIN";
}
