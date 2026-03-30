{
  home-modules,
  ...
}:
{

  imports = home-modules;
  home.stateVersion = "25.05";
  neovim.enable = true;
  zsh.enable = true;
  btop.enable = true;

}
