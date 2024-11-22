{
  config,
  lib,
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
    programs.nix-index = {
      enable = true;
      enableZshIntegration = true;
    };
    programs.starship = {
      enable = true;
      enableZshIntegration = true;
      settings = {
        directory = {
          style = "bold blue";
        };
      };
    };
    programs.zsh = {
      oh-my-zsh.enable = true;
      oh-my-zsh.plugins = [ "sudo" ];
      syntaxHighlighting.enable = true;
      autosuggestion.enable = true;
      enable = true;
      # Must be without indents/tabs/spaces (that's just dumb)
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
export MANPAGER='nvim +Man!'
printf '\n%.0s' {1..100}
if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
  Hyprland
fi
setopt correct
ns () {
  nix shell ''${@/#/nixpkgs#}
}
ns-unfree () {
  nix shell ''${@/#/nixpkgs#} --impure
}
      '';
      shellAliases = {
        ls = "lsd";
        ll = "ls -l";
        u-full = "(cd /etc/nixos; sudo nix flake update; nh os switch /etc/nixos)";
        u = "nh os switch /etc/nixos";
        #update-nvidia = "sudo nixos-rebuild switch --specialisation nvidia;update-desktop-database -v ~/.local/share/applications";
        u-test = "nh os test /etc/nixos";
        u-boot = "nh os boot /etc/nixos";
        u-build = "nh os build /etc/nixos";
        #update-home = "home-manager switch;update-desktop-database -v ~/.local/share/applications";
        fastfetch = "fastfetch --logo-color-1 'blue' --logo-color-2 'blue'";
        cps = "rsync -ahr --progress";
        res = "screen -r";
        nsp = "nix-search";
        record-discord = "gpu-screen-recorder -k h264 -w screen -f 60 -a $(pactl get-default-sink).monitor -o";
        nvide = "neovide --no-fork";
        c = "clear;printf '\n%.0s' {1..100};fastfetch";
        cl = "clear;printf '\n%.0s' {1..100};fastfetch --pipe false|lolcat -b -g 4f05fc:4287f5";
        sudoe = "sudo -E";
        suvide = "sudo -E neovide --no-fork";
        cwp = "swww img --transition-type wipe --transition-fps 60 --transition-step 255";
        record = "gpu-screen-recorder -w screen -f 60 -a $(pactl get-default-sink).monitor -o";
        fzfd = "fzf | xargs xdg-open";
      };
    };
  };
}
