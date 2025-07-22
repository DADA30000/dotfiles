{
  user,
  ...
}:
{
  imports = [ (import ../iso/configuration.nix { min-flag = true; }) ];
  home-manager.users."${user}" = import ./home.nix;
}
