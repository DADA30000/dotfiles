{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.mpd;
in
{
  options.mpd = {
    enable = mkEnableOption "Enable mpd music daemon";
    ncmpcpp = mkEnableOption "Enable ncmpcpp, program to access and control mpd daemon";
  };
  


  config = mkIf cfg.enable {
    services.mpd = {
      enable = true;
      dataDir = "${config.xdg.dataHome}/.mpd";
    };
    programs.ncmpcpp = mkIf cfg.ncmpcpp {
      enable = true;
      settings = {
        mpd_host = "127.0.0.1";
        mpd_port = "6600";
        mouse_list_scroll_whole_page = "yes";
        lines_scrolled = "1";
        visualizer_in_stereo = "yes";
        visualizer_fifo_path = "/tmp/mpd.fifo";
        visualizer_output_name = "my_fifo";
        visualizer_type = "wave_filled";
        visualizer_look = "▄▍";
        visualizer_color = "blue";
        progressbar_look = "▄▄";
        mouse_support = "yes";
        allow_for_physical_item_deletion = "yes";
        statusbar_color = "blue";
        current_item_prefix = " ";
        song_columns_list_format = "(6)[]{} (25)[green]{a} (34)[white]{t|f} (5f)[magenta]{l} (1)[]{}";
        color1 = "white";
        color2 = "blue";
        header_window_color = "blue";
        main_window_color = "blue";
        song_list_format = " $7%t$9 $R$3%a                      ";
        song_status_format = "$b$7♫ $2%a $4⟫$3⟫ $8%t $4⟫$3⟫ $5%b ";
        song_window_title_format = " ♬ {%a}  {%t}";
      };
    };
  };
}
