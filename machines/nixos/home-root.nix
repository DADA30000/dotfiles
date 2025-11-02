{
  inputs,
  umport,
  ...
}:
{

  imports = [
    inputs.nix-index-database.homeModules.nix-index
  ] ++ umport { paths = [ ../../modules/home ]; recursive = false; };
  home.stateVersion = "25.05";
  neovim.enable = true;
  zsh.enable = true;
  btop.enable = true;

}

