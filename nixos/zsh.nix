{ config, pkgs, ... }:
{
  programs.zsh = {
  enable = true;
  oh-my-zsh = {
    enable = true;
    plugins = [ "sudo" ];
  };
  autosuggestion.enable = true;
  syntaxHighlighting.enable = true;
  initExtra = ''
    nixos_ascii () {
    echo -n $'\E[34m'
    cat << "EOF"
      _  _ _      ___  ___ 
     | \| (_)_ __/ _ \/ __|
     | .` | \ \ / (_) \__ \
     |_|\_|_/_\_\\___/|___/
    EOF
    }
    nix-sh () {
      nix shell nixpkgs#''${@}
    }
    export PATH="$PATH:$HOME/.local/bin"
    printf '\n%.0s' {1..100}
    if ! [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
      fastfetch --logo-color-1 'blue' --logo-color-2 'blue'
    fi
    [[ ! -f ${./stuff/p10k-config/.p10k.zsh} ]] || source ${./stuff/p10k-config/.p10k.zsh}
    if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
      Hyprland
    fi
    source ${./stuff/p10k-config/p10k.zsh}
    source ${pkgs.nix-index}/etc/profile.d/command-not-found.sh
    setopt correct
    export NIXPKGS_ALLOW_UNFREE=1
  '';
  shellAliases = {
    ll = "ls -l";
    update-full = "(cd /etc/nixos; sudo nix flake update; nh os switch)";
    update = "nh os switch";
    #update-nvidia = "sudo nixos-rebuild switch --specialisation nvidia;update-desktop-database -v ~/.local/share/applications";
    update-test = "nh os test";
    update-boot = "nh os boot";
    #update-home = "home-manager switch;update-desktop-database -v ~/.local/share/applications";
    fastfetch="fastfetch --logo-color-1 'blue' --logo-color-2 'blue'";
    cps="rsync -ahr --progress";
    res="screen -r";
    record-discord="gpu-screen-recorder -k h264 -w screen -f 60 -a $(pactl get-default-sink).monitor -o";
    nvide="neovide --no-fork";
    c="clear;printf '\n%.0s' {1..100};fastfetch";
    cl="clear;printf '\n%.0s' {1..100};fastfetch --pipe false|lolcat -b -g 4f05fc:4287f5";
    sudoe="sudo -E";
    suvide="sudo -E neovide --no-fork";
    cwp="swww img --transition-type wipe --transition-fps 60 --transition-step 255";
    record="gpu-screen-recorder -w screen -f 60 -a '$(pactl get-default-sink).monitor' -o";
    fzfd="fzf | xargs xdg-open";
  };
  };
    programs.zsh.plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
      {
        name = "p10k-config";
	src = ./stuff/p10k-config;
	file = "p10k.zsh";
      }
    ];
}
