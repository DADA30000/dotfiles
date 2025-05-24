{ user, config, ... }:
{
  home.username = user;
  home.homeDirectory = "/home/${config.home.username}";
  imports = [ ./home.nix ];
}
