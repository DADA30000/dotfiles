{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.zsh;
in
{
  options.zsh = {
    enable = mkEnableOption "Enable zsh shell";
  };

  config = mkIf cfg.enable {
    programs = {
      direnv = {
        enable = true;
        enableZshIntegration = true;
        nix-direnv.enable = true;
      };
      nix-index = {
        enable = true;
        enableZshIntegration = true;
        package = inputs.nix-index-database.packages.${pkgs.system}.nix-index-with-small-db;
      };
      starship = {
        enable = true;
        enableZshIntegration = true;
        settings = {
          directory = {
            style = "bold blue";
          };
        };
      };
      zsh = {
        oh-my-zsh.enable = true;
        oh-my-zsh.plugins = [ "sudo" ];
        syntaxHighlighting.enable = true;
        autosuggestion.enable = true;
        enable = true;
        initContent =
          let
            zshConfig = ''
              nixos_ascii () {
              echo -n $'\E[34m'
              cat << "EOF"
                _  _ _      ___  ___ 
               | \| (_)_ __/ _ \/ __|
               | .` | \ \ / (_) \__ \
               |_|\_|_/_\_\\___/|___/
              EOF
              }
              export MANPAGER='nvim +Man!'
              printf '\n%.0s' {1..100}
              setopt correct
              # Ad-hoc python with modules env
              ns-py () {
                local args=()
                for arg in "$@"; do
                    args+=(''${arg})
                done
                nix shell --expr "with import (builtins.getFlake \"git+file://$NIX_PATH?rev=${inputs.nixpkgs.rev}&shallow=1\") { system = \"${pkgs.system}\"; config.allowUnfree = true; }; python3.withPackages (ps: with ps; [ ''${args[*]} ])"
              }
              # Ad-hoc nix-develop devShell
              ns-dev () { 
                local args=()
                for arg in "$@"; do
                    args+=(''${arg})
                done
                nix develop --expr "with import (builtins.getFlake \"git+file://$NIX_PATH?rev=${inputs.nixpkgs.rev}&shallow=1\") { system = \"${pkgs.system}\"; config.allowUnfree = true; }; mkShell { buildInputs = [ ''${args[*]} ]; }"
              }
              ns () {
                local args=()
                for arg in "$@"; do
                    args+=(--expr "with import (builtins.getFlake \"git+file://$NIX_PATH?rev=${inputs.nixpkgs.rev}&shallow=1\") { system = \"${pkgs.system}\"; config.allowUnfree = true; }; ''${arg}")
                done
                nix shell ''${args[@]}
              }
            '';
            zshEarly = mkOrder 500 ''
              DISABLE_MAGIC_FUNCTIONS=true
            '';
          in
          mkMerge [
            zshConfig
            zshEarly
          ];
        shellAliases = {
          umu-run = "umu-run-wrapper-secure";
          ls = "lsd";
          ll = "ls -l";
          # Dirty ass workaround for getting ad-hoc stuff working in pure mode
          u-full = "(cd /etc/nixos/stuff; sudo rm -rf nixpkgs.tar.zst; sudo git clone https://github.com/NixOS/nixpkgs -b nixos-unstable --depth 5; sudo tar -cv --zstd -f nixpkgs.tar.zst nixpkgs; sudo rm -rf nixpkgs; sudo nix flake update --flake /etc/nixos; nh os switch /etc/nixos)";
          u = "nh os switch /etc/nixos";
          nix-locate-full = "${inputs.nix-index-database.packages.${pkgs.system}.default}/bin/nix-locate";
          #update-nvidia = "sudo nixos-rebuild switch --specialisation nvidia;update-desktop-database -v ~/.local/share/applications";
          u-test = "nh os test /etc/nixos";
          u-boot = "nh os boot /etc/nixos";
          u-build = "nh os build /etc/nixos";
          #update-home = "home-manager switch;update-desktop-database -v ~/.local/share/applications";
          fastfetch = "fastfetch --logo-color-1 'blue' --logo-color-2 'blue'";
          cps = "rsync -ahr --progress";
          res = "screen -r";
          record-h264 = "gpu-screen-recorder -k h264 -w screen -f 60 -a 'default_output|default_input' -o";
          nvide = "neovide --no-fork";
          c = "clear;printf '\n%.0s' {1..100};fastfetch";
          cl = "clear;printf '\n%.0s' {1..100};fastfetch --pipe false|lolcat -b -g 4f05fc:4287f5";
          sudoe = "sudo -E";
          suvide = "sudo -E neovide --no-fork";
          cwp = "swww img --transition-type wipe --transition-fps 60 --transition-step 255";
          record = "gpu-screen-recorder -w screen -f 60 -a 'default_output|default_input' -o";
          fzfd = "fzf | xargs xdg-open";
        };
      };
    };
  };
}
