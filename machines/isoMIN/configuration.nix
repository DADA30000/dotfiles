{
  user,
  ...
}:
{
  imports = [ ../iso/configuration.nix ];
  home-manager.users."${user}" = import ./home.nix;
}
