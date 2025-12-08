{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.file-associations;
in
{
  options.file-associations = {
    enable = mkEnableOption "Enable declarative file associations";
  };

  config = mkIf cfg.enable {
    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
        "application/x-compressed-tar" = "org.gnome.FileRoller.desktop";
        "application/x-bzip2-compressed-tar" = "org.gnome.FileRoller.desktop";
        "application/x-bzip1-compressed-tar" = "org.gnome.FileRoller.desktop";
        "application/x-tzo" = "org.gnome.FileRoller.desktop";
        "application/x-xz" = "org.gnome.FileRoller.desktop";
        "application/x-lzma-compressed-tar" = "org.gnome.FileRoller.desktop";
        "application/zstd" = "org.gnome.FileRoller.desktop";
        "application/x-7z-compressed" = "org.gnome.FileRoller.desktop";
        "application/x-zstd-compressed-tar" = "org.gnome.FileRoller.desktop";
        "application/x-lzma" = "org.gnome.FileRoller.desktop";
        "application/x-lz4" = "org.gnome.FileRoller.desktop";
        "application/x-xz-compressed-tar" = "org.gnome.FileRoller.desktop";
        "application/x-lz4-compressed-tar" = "org.gnome.FileRoller.desktop";
        "application/x-archive" = "org.gnome.FileRoller.desktop";
        "application/x-cpio" = "org.gnome.FileRoller.desktop";
        "application/x-lzop" = "org.gnome.FileRoller.desktop";
        "application/x-bzip1" = "org.gnome.FileRoller.desktop";
        "application/x-tar" = "org.gnome.FileRoller.desktop";
        "application/x-bzip2" = "org.gnome.FileRoller.desktop";
        "application/gzip" = "org.gnome.FileRoller.desktop";
        "application/x-lzip-compressed-tar" = "org.gnome.FileRoller.desktop";
        "application/x-tarz " = "org.gnome.FileRoller.desktop";
        "application/zip" = "org.gnome.FileRoller.desktop";
        "application/vnd.microsoft.portable-executable" = "umu.desktop";
        "application/x-msi" = "umu.desktop";
        "application/x-msdownload" = "umu.desktop";
        #"inode/directory" = "nemo.desktop";
        "inode/directory" = "org.gnome.Nautilus.desktop";
        "text/html" = "zen-twilight.desktop";
        "video/mp4" = "mpv.desktop";
        "audio/mpeg" = "mpv.desktop";
        "audio/flac" = "mpv.desktop";
        "x-scheme-handler/http" = "zen-twilight.desktop";
        "x-scheme-handler/https" = "zen-twilight.desktop";
        "x-scheme-handler/about" = "zen-twilight.desktop";
        "x-scheme-handler/unknown" = "zen-twilight.desktop";
      };
    };
  };
}
