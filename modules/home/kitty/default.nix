{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.kitty;
in
{
  options.kitty = {
    enable = mkEnableOption "Enable kitty terminal emulator";
  };

  config = mkIf cfg.enable {
    programs.kitty = {
      enable = true;
      shellIntegration.enableZshIntegration = true;
      font = {
        name = "JetBrainsMono NF";
        size = 12;
      };
      keybindings = {
        "ctrl+left" = "neighboring_window left";
        "shift+left" = "move_window right";
        "ctrl+down" = "neighboring_window down";
        "shift+down" = "move_window up";
      };
      extraConfig = ''
        mouse_hide_wait         2.0
        url_color               #0087bd
        url_style               dotted
        enable_audio_bell       no
        confirm_os_window_close 0
        background_opacity      0.2
        window_margin_width     5
        tab_bar_edge            top
        tab_bar_style           powerline
        tab_bar_align           center
        tab_bar_min_tabs        2
        tab_switch_strategy     previous
        wheel_scroll_multiplier 10
        cursor_blink_interval   0.5 linear ease-out
        cursor_trail            3
        cursor_trail_decay      0.1 0.4
        cursor_trail_start_threshold 0
        background              #000000
        foreground              #bbddff
        cursor                  #aaaaaa
        selection_background    #002a3a
        color0                  #222222
        color8                  #444444
        color1                  #ff000f
        color9                  #ff273f
        color2                  #8ce00a
        color10                 #abe05a
        color3                  #ffb900
        color11                 #ffd141
        color4                  #008df8
        color12                 #0092ff
        color5                  #6c43a5
        color13                 #9a5feb
        color6                  #00d7eb
        color14                 #67ffef
        color7                  #ffffff
        color15                 #ffffff
        selection_foreground    #0d0f18
      '';
    };
  };
}
