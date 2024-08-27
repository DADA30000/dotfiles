{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.neovim;
in
{
  options.neovim = {
    enable = mkEnableOption "Enable neovim, console based text editor";
  };
  


  config = mkIf cfg.enable {
    programs.neovim = {
      enable = true;
      viAlias = true;
      defaultEditor = true;
      vimAlias = true;
      vimdiffAlias = true;
    };
    home.file.".config/nvim/init.vim".source = ../../../stuff/init.vim;
  };
}
