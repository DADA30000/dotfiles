{
  config,
  lib,
  ...
}:
let
  cfg = config.file-associations;
in
{
  options.file-associations = {
    enable = lib.mkEnableOption "declarative file associations";
  };

  config = lib.mkIf cfg.enable {
    xdg.mimeApps = {
      enable = true;
      defaultApplications = {

        # -------------------------------------------------------------------
        # Web & PDF (Zen Browser)
        # -------------------------------------------------------------------
        "application/pdf" = "zen-twilight.desktop";
        "application/vnd.mozilla.xul+xml" = "zen-twilight.desktop";
        "application/xhtml+xml" = "zen-twilight.desktop";
        "text/html" = "zen-twilight.desktop";
        "x-scheme-handler/about" = "zen-twilight.desktop";
        "x-scheme-handler/http" = "zen-twilight.desktop";
        "x-scheme-handler/https" = "zen-twilight.desktop";
        "x-scheme-handler/unknown" = "zen-twilight.desktop";

        # -------------------------------------------------------------------
        # File Manager (Nautilus)
        # -------------------------------------------------------------------
        "inode/directory" = "org.gnome.Nautilus.desktop";

        # -------------------------------------------------------------------
        # Image Viewer (qimgv)
        # -------------------------------------------------------------------
        "image/*" = "qimgv.desktop";
        "image/apng" = "qimgv.desktop";
        "image/avci" = "qimgv.desktop";
        "image/avif" = "qimgv.desktop";
        "image/bmp" = "qimgv.desktop";
        "image/dds" = "qimgv.desktop";
        "image/g3-fax" = "qimgv.desktop";
        "image/gif" = "qimgv.desktop";
        "image/heic" = "qimgv.desktop";
        "image/heif" = "qimgv.desktop";
        "image/hej2k" = "qimgv.desktop";
        "image/jp2" = "qimgv.desktop";
        "image/jpeg" = "qimgv.desktop";
        "image/jxl" = "qimgv.desktop";
        "image/openraster" = "qimgv.desktop";
        "image/png" = "qimgv.desktop";
        "image/qoi" = "qimgv.desktop";
        "image/svg+xml" = "qimgv.desktop";
        "image/svg+xml-compressed" = "qimgv.desktop";
        "image/tiff" = "qimgv.desktop";
        "image/vnd.microsoft.icon" = "qimgv.desktop";
        "image/vnd.wap.wbmp" = "qimgv.desktop";
        "image/webp" = "qimgv.desktop";
        "image/x-bmp" = "qimgv.desktop";
        "image/x-dcm" = "qimgv.desktop";
        "image/x-dcx" = "qimgv.desktop";
        "image/x-emf" = "qimgv.desktop";
        "image/x-exr" = "qimgv.desktop";
        "image/x-fits" = "qimgv.desktop";
        "image/x-flic" = "qimgv.desktop";
        "image/x-freehand" = "qimgv.desktop";
        "image/x-icns" = "qimgv.desktop";
        "image/x-ico" = "qimgv.desktop";
        "image/x-icon" = "qimgv.desktop";
        "image/x-ilbm" = "qimgv.desktop";
        "image/x-jp2-codestream" = "qimgv.desktop";
        "image/x-pcx" = "qimgv.desktop";
        "image/x-pixmap" = "qimgv.desktop";
        "image/x-png" = "qimgv.desktop";
        "image/x-portable-anymap" = "qimgv.desktop";
        "image/x-psd" = "qimgv.desktop";
        "image/x-psp" = "qimgv.desktop";
        "image/x-seattle-filmcamera" = "qimgv.desktop";
        "image/x-sgi" = "qimgv.desktop";
        "image/x-sun-raster" = "qimgv.desktop";
        "image/x-tga" = "qimgv.desktop";
        "image/x-wmf" = "qimgv.desktop";
        "image/x-xbitmap" = "qimgv.desktop";
        "image/x-xwindowdump" = "qimgv.desktop";

        # -------------------------------------------------------------------
        # Image Editor (GIMP)
        # -------------------------------------------------------------------
        "application/postscript" = "gimp.desktop";
        "application/x-navi-animation" = "gimp.desktop";
        "image/x-xcf" = "gimp.desktop";

        # -------------------------------------------------------------------
        # Media Player (MPV)
        # -------------------------------------------------------------------
        "application/mxf" = "mpv.desktop";
        "application/ogg" = "mpv.desktop";
        "application/sdp" = "mpv.desktop";
        "application/smil" = "mpv.desktop";
        "application/streamingmedia" = "mpv.desktop";
        "application/vnd.apple.mpegurl" = "mpv.desktop";
        "application/vnd.ms-asf" = "mpv.desktop";
        "application/vnd.rn-realmedia" = "mpv.desktop";
        "application/vnd.rn-realmedia-vbr" = "mpv.desktop";
        "application/x-cue" = "mpv.desktop";
        "application/x-extension-m4a" = "mpv.desktop";
        "application/x-extension-mp4" = "mpv.desktop";
        "application/x-matroska" = "mpv.desktop";
        "application/x-mpegurl" = "mpv.desktop";
        "application/x-ogg" = "mpv.desktop";
        "application/x-ogm" = "mpv.desktop";
        "application/x-ogm-audio" = "mpv.desktop";
        "application/x-ogm-video" = "mpv.desktop";
        "application/x-shorten" = "mpv.desktop";
        "application/x-smil" = "mpv.desktop";
        "application/x-streamingmedia" = "mpv.desktop";
        "audio/3gpp" = "mpv.desktop";
        "audio/3gpp2" = "mpv.desktop";
        "audio/AMR" = "mpv.desktop";
        "audio/aac" = "mpv.desktop";
        "audio/ac3" = "mpv.desktop";
        "audio/aiff" = "mpv.desktop";
        "audio/amr-wb" = "mpv.desktop";
        "audio/dv" = "mpv.desktop";
        "audio/eac3" = "mpv.desktop";
        "audio/flac" = "mpv.desktop";
        "audio/m3u" = "mpv.desktop";
        "audio/m4a" = "mpv.desktop";
        "audio/mp1" = "mpv.desktop";
        "audio/mp2" = "mpv.desktop";
        "audio/mp3" = "mpv.desktop";
        "audio/mp4" = "mpv.desktop";
        "audio/mpeg" = "mpv.desktop";
        "audio/mpeg2" = "mpv.desktop";
        "audio/mpeg3" = "mpv.desktop";
        "audio/mpegurl" = "mpv.desktop";
        "audio/mpg" = "mpv.desktop";
        "audio/musepack" = "mpv.desktop";
        "audio/ogg" = "mpv.desktop";
        "audio/opus" = "mpv.desktop";
        "audio/rn-mpeg" = "mpv.desktop";
        "audio/scpls" = "mpv.desktop";
        "audio/vnd.dolby.heaac.1" = "mpv.desktop";
        "audio/vnd.dolby.heaac.2" = "mpv.desktop";
        "audio/vnd.dts" = "mpv.desktop";
        "audio/vnd.dts.hd" = "mpv.desktop";
        "audio/vnd.rn-realaudio" = "mpv.desktop";
        "audio/vnd.wave" = "mpv.desktop";
        "audio/vorbis" = "mpv.desktop";
        "audio/wav" = "mpv.desktop";
        "audio/webm" = "mpv.desktop";
        "audio/x-aac" = "mpv.desktop";
        "audio/x-adpcm" = "mpv.desktop";
        "audio/x-aiff" = "mpv.desktop";
        "audio/x-ape" = "mpv.desktop";
        "audio/x-m4a" = "mpv.desktop";
        "audio/x-matroska" = "mpv.desktop";
        "audio/x-mp1" = "mpv.desktop";
        "audio/x-mp2" = "mpv.desktop";
        "audio/x-mp3" = "mpv.desktop";
        "audio/x-mpegurl" = "mpv.desktop";
        "audio/x-mpg" = "mpv.desktop";
        "audio/x-ms-asf" = "mpv.desktop";
        "audio/x-ms-wma" = "mpv.desktop";
        "audio/x-musepack" = "mpv.desktop";
        "audio/x-pls" = "mpv.desktop";
        "audio/x-pn-au" = "mpv.desktop";
        "audio/x-pn-realaudio" = "mpv.desktop";
        "audio/x-pn-wav" = "mpv.desktop";
        "audio/x-pn-windows-pcm" = "mpv.desktop";
        "audio/x-realaudio" = "mpv.desktop";
        "audio/x-scpls" = "mpv.desktop";
        "audio/x-shorten" = "mpv.desktop";
        "audio/x-tta" = "mpv.desktop";
        "audio/x-vorbis" = "mpv.desktop";
        "audio/x-vorbis+ogg" = "mpv.desktop";
        "audio/x-wav" = "mpv.desktop";
        "audio/x-wavpack" = "mpv.desktop";
        "video/3gp" = "mpv.desktop";
        "video/3gpp" = "mpv.desktop";
        "video/3gpp2" = "mpv.desktop";
        "video/avi" = "mpv.desktop";
        "video/divx" = "mpv.desktop";
        "video/dv" = "mpv.desktop";
        "video/fli" = "mpv.desktop";
        "video/flv" = "mpv.desktop";
        "video/mkv" = "mpv.desktop";
        "video/mp2t" = "mpv.desktop";
        "video/mp4" = "mpv.desktop";
        "video/mp4v-es" = "mpv.desktop";
        "video/mpeg" = "mpv.desktop";
        "video/msvideo" = "mpv.desktop";
        "video/ogg" = "mpv.desktop";
        "video/quicktime" = "mpv.desktop";
        "video/vnd.avi" = "mpv.desktop";
        "video/vnd.divx" = "mpv.desktop";
        "video/vnd.mpegurl" = "mpv.desktop";
        "video/vnd.rn-realvideo" = "mpv.desktop";
        "video/webm" = "mpv.desktop";
        "video/x-avi" = "mpv.desktop";
        "video/x-flc" = "mpv.desktop";
        "video/x-flic" = "mpv.desktop";
        "video/x-flv" = "mpv.desktop";
        "video/x-m4v" = "mpv.desktop";
        "video/x-matroska" = "mpv.desktop";
        "video/x-mpeg2" = "mpv.desktop";
        "video/x-mpeg3" = "mpv.desktop";
        "video/x-ms-afs" = "mpv.desktop";
        "video/x-ms-asf" = "mpv.desktop";
        "video/x-ms-wmv" = "mpv.desktop";
        "video/x-ms-wmx" = "mpv.desktop";
        "video/x-ms-wvxvideo" = "mpv.desktop";
        "video/x-msvideo" = "mpv.desktop";
        "video/x-ogm" = "mpv.desktop";
        "video/x-ogm+ogg" = "mpv.desktop";
        "video/x-theora" = "mpv.desktop";
        "video/x-theora+ogg" = "mpv.desktop";

        # -------------------------------------------------------------------
        # Text Editor, Source Code & Configs (Neovide)
        # -------------------------------------------------------------------
        "application/json" = "neovide.desktop";
        "application/toml" = "neovide.desktop";
        "application/x-nix" = "neovide.desktop";
        "application/x-sh" = "neovide.desktop";
        "application/x-shellscript" = "neovide.desktop";
        "application/x-yaml" = "neovide.desktop";
        "application/x-zerosize" = "neovide.desktop";
        "text/*" = "neovide.desktop";
        "text/calendar" = "neovide.desktop";
        "text/english" = "neovide.desktop";
        "text/markdown" = "neovide.desktop";
        "text/plain" = "neovide.desktop";
        "text/x-c" = "neovide.desktop";
        "text/x-c++" = "neovide.desktop";
        "text/x-c++hdr" = "neovide.desktop";
        "text/x-c++src" = "neovide.desktop";
        "text/x-chdr" = "neovide.desktop";
        "text/x-cmake" = "neovide.desktop";
        "text/x-csrc" = "neovide.desktop";
        "text/x-go" = "neovide.desktop";
        "text/x-java" = "neovide.desktop";
        "text/x-lua" = "neovide.desktop";
        "text/x-makefile" = "neovide.desktop";
        "text/x-moc" = "neovide.desktop";
        "text/x-nix" = "neovide.desktop";
        "text/x-pascal" = "neovide.desktop";
        "text/x-python" = "neovide.desktop";
        "text/x-rust" = "neovide.desktop";
        "text/x-shellscript" = "neovide.desktop";
        "text/x-tcl" = "neovide.desktop";
        "text/x-tex" = "neovide.desktop";
        "text/x-vcard" = "neovide.desktop";
        "text/xml" = "neovide.desktop";
        "text/yaml" = "neovide.desktop";
        "x-scheme-handler/kitty" = "neovide.desktop";

        # -------------------------------------------------------------------
        # Archive & Disk Image Manager (Ark)
        # -------------------------------------------------------------------
        "application/arj" = "org.kde.ark.desktop";
        "application/bzip2" = "org.kde.ark.desktop";
        "application/gzip" = "org.kde.ark.desktop";
        "application/vnd.android.package-archive" = "org.kde.ark.desktop";
        "application/vnd.debian.binary-package" = "org.kde.ark.desktop";
        "application/vnd.efi.iso" = "org.kde.ark.desktop";
        "application/vnd.ms-cab-compressed" = "org.kde.ark.desktop";
        "application/vnd.rar" = "org.kde.ark.desktop";
        "application/x-7z-compressed" = "org.kde.ark.desktop";
        "application/x-7z-compressed-tar" = "org.kde.ark.desktop";
        "application/x-ace" = "org.kde.ark.desktop";
        "application/x-alz" = "org.kde.ark.desktop";
        "application/x-apple-diskimage" = "org.kde.ark.desktop";
        "application/x-ar" = "org.kde.ark.desktop";
        "application/x-archive" = "org.kde.ark.desktop";
        "application/x-arj" = "org.kde.ark.desktop";
        "application/x-bcpio" = "org.kde.ark.desktop";
        "application/x-brotli" = "org.kde.ark.desktop";
        "application/x-bzip" = "org.kde.ark.desktop";
        "application/x-bzip-brotli-tar" = "org.kde.ark.desktop";
        "application/x-bzip-compressed-tar" = "org.kde.ark.desktop";
        "application/x-bzip1" = "org.kde.ark.desktop";
        "application/x-bzip1-compressed-tar" = "org.kde.ark.desktop";
        "application/x-bzip2" = "org.kde.ark.desktop";
        "application/x-bzip2-compressed-tar" = "org.kde.ark.desktop";
        "application/x-bzip3" = "org.kde.ark.desktop";
        "application/x-bzip3-compressed-tar" = "org.kde.ark.desktop";
        "application/x-cabinet" = "org.kde.ark.desktop";
        "application/x-cd-image" = "org.kde.ark.desktop";
        "application/x-chrome-extension" = "org.kde.ark.desktop";
        "application/x-compress" = "org.kde.ark.desktop";
        "application/x-compressed-tar" = "org.kde.ark.desktop";
        "application/x-cpio" = "org.kde.ark.desktop";
        "application/x-cpio-compressed" = "org.kde.ark.desktop";
        "application/x-deb" = "org.kde.ark.desktop";
        "application/x-ear" = "org.kde.ark.desktop";
        "application/x-gtar" = "org.kde.ark.desktop";
        "application/x-gzip" = "org.kde.ark.desktop";
        "application/x-gzpostscript" = "org.kde.ark.desktop";
        "application/x-java-archive" = "org.kde.ark.desktop";
        "application/x-lha" = "org.kde.ark.desktop";
        "application/x-lhz" = "org.kde.ark.desktop";
        "application/x-lrzip" = "org.kde.ark.desktop";
        "application/x-lrzip-compressed-tar" = "org.kde.ark.desktop";
        "application/x-lz4" = "org.kde.ark.desktop";
        "application/x-lz4-compressed-tar" = "org.kde.ark.desktop";
        "application/x-lzip" = "org.kde.ark.desktop";
        "application/x-lzip-compressed-tar" = "org.kde.ark.desktop";
        "application/x-lzma" = "org.kde.ark.desktop";
        "application/x-lzma-compressed-tar" = "org.kde.ark.desktop";
        "application/x-lzop" = "org.kde.ark.desktop";
        "application/x-ms-wim" = "org.kde.ark.desktop";
        "application/x-rar" = "org.kde.ark.desktop";
        "application/x-rar-compressed" = "org.kde.ark.desktop";
        "application/x-raw-disk-image" = "org.kde.ark.desktop";
        "application/x-rpm" = "org.kde.ark.desktop";
        "application/x-rzip" = "org.kde.ark.desktop";
        "application/x-rzip-compressed-tar" = "org.kde.ark.desktop";
        "application/x-source-rpm" = "org.kde.ark.desktop";
        "application/x-stuffit" = "org.kde.ark.desktop";
        "application/x-sv4cpio" = "org.kde.ark.desktop";
        "application/x-sv4crc" = "org.kde.ark.desktop";
        "application/x-tar" = "org.kde.ark.desktop";
        "application/x-tarz" = "org.kde.ark.desktop";
        "application/x-tzo" = "org.kde.ark.desktop";
        "application/x-war" = "org.kde.ark.desktop";
        "application/x-xar" = "org.kde.ark.desktop";
        "application/x-xz" = "org.kde.ark.desktop";
        "application/x-xz-compressed-tar" = "org.kde.ark.desktop";
        "application/x-zip" = "org.kde.ark.desktop";
        "application/x-zip-compressed" = "org.kde.ark.desktop";
        "application/x-zoo" = "org.kde.ark.desktop";
        "application/x-zstd-compressed-tar" = "org.kde.ark.desktop";
        "application/zip" = "org.kde.ark.desktop";
        "application/zlib" = "org.kde.ark.desktop";
        "application/zstd" = "org.kde.ark.desktop";

        # -------------------------------------------------------------------
        # Word Processor (LibreOffice Writer)
        # -------------------------------------------------------------------
        "application/clarisworks" = "writer.desktop";
        "application/docbook+xml" = "writer.desktop";
        "application/macwriteii" = "writer.desktop";
        "application/msword" = "writer.desktop";
        "application/prs.plucker" = "writer.desktop";
        "application/rtf" = "writer.desktop";
        "application/vnd.apple.pages" = "writer.desktop";
        "application/vnd.lotus-wordpro" = "writer.desktop";
        "application/vnd.ms-word" = "writer.desktop";
        "application/vnd.ms-word.document.macroEnabled.12" = "writer.desktop";
        "application/vnd.ms-word.template.macroEnabled.12" = "writer.desktop";
        "application/vnd.ms-works" = "writer.desktop";
        "application/vnd.oasis.opendocument.text" = "writer.desktop";
        "application/vnd.oasis.opendocument.text-flat-xml" = "writer.desktop";
        "application/vnd.oasis.opendocument.text-master" = "writer.desktop";
        "application/vnd.oasis.opendocument.text-master-template" = "writer.desktop";
        "application/vnd.oasis.opendocument.text-template" = "writer.desktop";
        "application/vnd.oasis.opendocument.text-web" = "writer.desktop";
        "application/vnd.openofficeorg.extension" = "writer.desktop";
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document" = "writer.desktop";
        "application/vnd.openxmlformats-officedocument.wordprocessingml.template" = "writer.desktop";
        "application/vnd.palm" = "writer.desktop";
        "application/vnd.stardivision.writer-global" = "writer.desktop";
        "application/vnd.sun.xml.writer" = "writer.desktop";
        "application/vnd.sun.xml.writer.global" = "writer.desktop";
        "application/vnd.sun.xml.writer.template" = "writer.desktop";
        "application/vnd.wordperfect" = "writer.desktop";
        "application/wordperfect" = "writer.desktop";
        "application/x-abiword" = "writer.desktop";
        "application/x-aportisdoc" = "writer.desktop";
        "application/x-doc" = "writer.desktop";
        "application/x-extension-txt" = "writer.desktop";
        "application/x-fictionbook+xml" = "writer.desktop";
        "application/x-hwp" = "writer.desktop";
        "application/x-iwork-pages-sffpages" = "writer.desktop";
        "application/x-mswrite" = "writer.desktop";
        "application/x-pocket-word" = "writer.desktop";
        "application/x-sony-bbeb" = "writer.desktop";
        "application/x-starwriter" = "writer.desktop";
        "application/x-starwriter-global" = "writer.desktop";
        "application/x-t602" = "writer.desktop";
        "text/rtf" = "writer.desktop";
        "x-scheme-handler/ms-access" = "writer.desktop";
        "x-scheme-handler/ms-excel" = "writer.desktop";
        "x-scheme-handler/ms-powerpoint" = "writer.desktop";
        "x-scheme-handler/ms-visio" = "writer.desktop";
        "x-scheme-handler/ms-word" = "writer.desktop";
        "x-scheme-handler/vnd.libreoffice.cmis" = "writer.desktop";
        "x-scheme-handler/vnd.libreoffice.command" = "writer.desktop";
        "x-scheme-handler/vnd.sun.star.webdav" = "writer.desktop";
        "x-scheme-handler/vnd.sun.star.webdavs" = "writer.desktop";

        # -------------------------------------------------------------------
        # Spreadsheets (LibreOffice Calc)
        # -------------------------------------------------------------------
        "application/csv" = "calc.desktop";
        "application/excel" = "calc.desktop";
        "application/msexcel" = "calc.desktop";
        "application/tab-separated-values" = "calc.desktop";
        "application/vnd.apache.parquet" = "calc.desktop";
        "application/vnd.apple.numbers" = "calc.desktop";
        "application/vnd.lotus-1-2-3" = "calc.desktop";
        "application/vnd.ms-excel" = "calc.desktop";
        "application/vnd.ms-excel.sheet.binary.macroEnabled.12" = "calc.desktop";
        "application/vnd.ms-excel.sheet.macroEnabled.12" = "calc.desktop";
        "application/vnd.ms-excel.template.macroEnabled.12" = "calc.desktop";
        "application/vnd.oasis.opendocument.chart" = "calc.desktop";
        "application/vnd.oasis.opendocument.chart-template" = "calc.desktop";
        "application/vnd.oasis.opendocument.spreadsheet" = "calc.desktop";
        "application/vnd.oasis.opendocument.spreadsheet-flat-xml" = "calc.desktop";
        "application/vnd.oasis.opendocument.spreadsheet-template" = "calc.desktop";
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" = "calc.desktop";
        "application/vnd.openxmlformats-officedocument.spreadsheetml.template" = "calc.desktop";
        "application/vnd.stardivision.calc" = "calc.desktop";
        "application/vnd.stardivision.chart" = "calc.desktop";
        "application/vnd.sun.xml.calc" = "calc.desktop";
        "application/vnd.sun.xml.calc.template" = "calc.desktop";
        "application/x-123" = "calc.desktop";
        "application/x-dbase" = "calc.desktop";
        "application/x-dbf" = "calc.desktop";
        "application/x-dos_ms_excel" = "calc.desktop";
        "application/x-excel" = "calc.desktop";
        "application/x-gnumeric" = "calc.desktop";
        "application/x-iwork-numbers-sffnumbers" = "calc.desktop";
        "application/x-ms-excel" = "calc.desktop";
        "application/x-msexcel" = "calc.desktop";
        "application/x-quattropro" = "calc.desktop";
        "application/x-starcalc" = "calc.desktop";
        "application/x-starchart" = "calc.desktop";
        "text/comma-separated-values" = "calc.desktop";
        "text/csv" = "calc.desktop";
        "text/spreadsheet" = "calc.desktop";
        "text/tab-separated-values" = "calc.desktop";
        "text/x-comma-separated-values" = "calc.desktop";
        "text/x-csv" = "calc.desktop";

        # -------------------------------------------------------------------
        # Presentations (LibreOffice Impress)
        # -------------------------------------------------------------------
        "application/mspowerpoint" = "impress.desktop";
        "application/vnd.apple.keynote" = "impress.desktop";
        "application/vnd.ms-powerpoint" = "impress.desktop";
        "application/vnd.ms-powerpoint.presentation.macroEnabled.12" = "impress.desktop";
        "application/vnd.ms-powerpoint.slideshow.macroEnabled.12" = "impress.desktop";
        "application/vnd.ms-powerpoint.template.macroEnabled.12" = "impress.desktop";
        "application/vnd.oasis.opendocument.presentation" = "impress.desktop";
        "application/vnd.oasis.opendocument.presentation-flat-xml" = "impress.desktop";
        "application/vnd.oasis.opendocument.presentation-template" = "impress.desktop";
        "application/vnd.openxmlformats-officedocument.presentationml.presentation" = "impress.desktop";
        "application/vnd.openxmlformats-officedocument.presentationml.slide" = "impress.desktop";
        "application/vnd.openxmlformats-officedocument.presentationml.slideshow" = "impress.desktop";
        "application/vnd.openxmlformats-officedocument.presentationml.template" = "impress.desktop";
        "application/vnd.stardivision.impress" = "impress.desktop";
        "application/vnd.sun.xml.impress" = "impress.desktop";
        "application/vnd.sun.xml.impress.template" = "impress.desktop";
        "application/x-iwork-keynote-sffkey" = "impress.desktop";
        "application/x-starimpress" = "impress.desktop";

        # -------------------------------------------------------------------
        # Diagrams & Graphics (LibreOffice Draw)
        # -------------------------------------------------------------------
        "application/vnd.corel-draw" = "draw.desktop";
        "application/vnd.ms-publisher" = "draw.desktop";
        "application/vnd.oasis.opendocument.graphics" = "draw.desktop";
        "application/vnd.oasis.opendocument.graphics-flat-xml" = "draw.desktop";
        "application/vnd.oasis.opendocument.graphics-template" = "draw.desktop";
        "application/vnd.quark.quarkxpress" = "draw.desktop";
        "application/vnd.stardivision.draw" = "draw.desktop";
        "application/vnd.sun.xml.draw" = "draw.desktop";
        "application/vnd.sun.xml.draw.template" = "draw.desktop";
        "application/vnd.visio" = "draw.desktop";
        "application/x-pagemaker" = "draw.desktop";
        "application/x-stardraw" = "draw.desktop";
        "application/x-wpg" = "draw.desktop";

        # -------------------------------------------------------------------
        # Formulas (LibreOffice Math)
        # -------------------------------------------------------------------
        "application/mathml+xml" = "math.desktop";
        "application/vnd.oasis.opendocument.formula" = "math.desktop";
        "application/vnd.oasis.opendocument.formula-template" = "math.desktop";
        "application/vnd.stardivision.math" = "math.desktop";
        "application/vnd.sun.xml.math" = "math.desktop";
        "application/x-starmath" = "math.desktop";
        "text/mathml" = "math.desktop";

        # -------------------------------------------------------------------
        # Databases (LibreOffice Base)
        # -------------------------------------------------------------------
        "application/vnd.oasis.opendocument.base" = "base.desktop";
        "application/vnd.sun.xml.base" = "base.desktop";

        # -------------------------------------------------------------------
        # Windows Binaries & Scripts (run-exe)
        # -------------------------------------------------------------------
        "application/vnd.microsoft.portable-executable" = "run-exe.desktop";
        "application/x-bat" = "run-exe.desktop";
        "application/x-ms-dos-executable" = "run-exe.desktop";
        "application/x-ms-shortcut" = "run-exe.desktop";
        "application/x-msdownload" = "run-exe.desktop";
        "application/x-msi" = "run-exe.desktop";
        "application/x-mswinurl" = "run-exe.desktop";

        # -------------------------------------------------------------------
        # BitTorrent (qBittorrent)
        # -------------------------------------------------------------------
        "application/x-bittorrent" = "org.qbittorrent.qBittorrent.desktop";
        "x-scheme-handler/magnet" = "org.qbittorrent.qBittorrent.desktop";

        # -------------------------------------------------------------------
        # Messaging (AyuGram Telegram)
        # -------------------------------------------------------------------
        "x-scheme-handler/tg" = "com.ayugram.desktop.desktop";
        "x-scheme-handler/tonsite" = "com.ayugram.desktop.desktop";

        # -------------------------------------------------------------------
        # Messaging (Discord)
        # -------------------------------------------------------------------
        "x-scheme-handler/discord" = "com.discordapp.DiscordCanary.desktop";

        # -------------------------------------------------------------------
        # Email (Thunderbird)
        # -------------------------------------------------------------------
        "message/rfc822" = "thunderbird.desktop";
        "x-scheme-handler/mailto" = "thunderbird.desktop";

        # -------------------------------------------------------------------
        # Remote Desktop (Remmina)
        # -------------------------------------------------------------------
        "application/x-remmina" = "org.remmina.Remmina.desktop";
        "x-scheme-handler/rdp" = "org.remmina.Remmina.desktop";
        "x-scheme-handler/remmina" = "org.remmina.Remmina.desktop";
        "x-scheme-handler/spice" = "org.remmina.Remmina.desktop";
        "x-scheme-handler/ssh" = "org.remmina.Remmina.desktop";
        "x-scheme-handler/vnc" = "org.remmina.Remmina.desktop";

        # -------------------------------------------------------------------
        # Remote Desktop (RustDesk)
        # -------------------------------------------------------------------
        "x-scheme-handler/rustdesk" = "rustdesk-link.desktop";

        # -------------------------------------------------------------------
        # Music (Spotify)
        # -------------------------------------------------------------------
        "x-scheme-handler/spotify" = "com.spotify.Client.desktop";

        # -------------------------------------------------------------------
        # Gaming (Steam)
        # -------------------------------------------------------------------
        "x-scheme-handler/steam" = "com.valvesoftware.Steam.desktop";
        "x-scheme-handler/steamlink" = "com.valvesoftware.Steam.desktop";

        # -------------------------------------------------------------------
        # Gaming (Prism Launcher)
        # -------------------------------------------------------------------
        "application/x-modrinth-modpack+zip" = "org.prismlauncher.PrismLauncher.desktop";
        "x-scheme-handler/curseforge" = "org.prismlauncher.PrismLauncher.desktop";
        "x-scheme-handler/prismlauncher" = "org.prismlauncher.PrismLauncher.desktop";

        # -------------------------------------------------------------------
        # Gaming (osu!)
        # -------------------------------------------------------------------
        "application/x-osu-beatmap" = "osu!.desktop";
        "application/x-osu-beatmap-archive" = "osu!.desktop";
        "application/x-osu-replay" = "osu!.desktop";
        "application/x-osu-skin-archive" = "osu!.desktop";
        "application/x-osu-storyboard" = "osu!.desktop";
        "x-scheme-handler/osu" = "osu!.desktop";

        # -------------------------------------------------------------------
        # Video Editing (Kdenlive)
        # -------------------------------------------------------------------
        "application/vnd.mlt+xml" = "org.kde.kdenlive.desktop";
        "application/x-kdenlive" = "org.kde.kdenlive.desktop";

        # -------------------------------------------------------------------
        # Software Packages (AppImage)
        # -------------------------------------------------------------------
        "application/vnd.appimage" = "appimage-run.desktop";
        "application/x-iso9660-appimage" = "appimage-run.desktop";

        # -------------------------------------------------------------------
        # Certificates & Keys (Seahorse)
        # -------------------------------------------------------------------
        "application/pgp-keys" = "org.gnome.seahorse.Application.desktop";
        "application/pkcs10" = "org.gnome.seahorse.Application.desktop";
        "application/pkcs10+pem" = "org.gnome.seahorse.Application.desktop";
        "application/pkcs12" = "org.gnome.seahorse.Application.desktop";
        "application/pkcs12+pem" = "org.gnome.seahorse.Application.desktop";
        "application/pkcs7-mime" = "org.gnome.seahorse.Application.desktop";
        "application/pkcs7-mime+pem" = "org.gnome.seahorse.Application.desktop";
        "application/pkcs8" = "org.gnome.seahorse.Application.desktop";
        "application/pkcs8+pem" = "org.gnome.seahorse.Application.desktop";
        "application/pkix-cert" = "org.gnome.seahorse.Application.desktop";
        "application/pkix-cert+pem" = "org.gnome.seahorse.Application.desktop";
        "application/pkix-crl" = "org.gnome.seahorse.Application.desktop";
        "application/pkix-crl+pem" = "org.gnome.seahorse.Application.desktop";
        "application/x-pem-file" = "org.gnome.seahorse.Application.desktop";
        "application/x-pem-key" = "org.gnome.seahorse.Application.desktop";
        "application/x-pkcs12" = "org.gnome.seahorse.Application.desktop";
        "application/x-pkcs7-certificates" = "org.gnome.seahorse.Application.desktop";
        "application/x-spkac" = "org.gnome.seahorse.Application.desktop";
        "application/x-spkac+base64" = "org.gnome.seahorse.Application.desktop";
        "application/x-ssh-key" = "org.gnome.seahorse.Application.desktop";
        "application/x-x509-ca-cert" = "org.gnome.seahorse.Application.desktop";
        "application/x-x509-user-cert" = "org.gnome.seahorse.Application.desktop";

        # -------------------------------------------------------------------
        # Mobile Integration (KDE Connect)
        # -------------------------------------------------------------------
        "x-scheme-handler/sms" = "org.kde.kdeconnect.handler.desktop";
        "x-scheme-handler/tel" = "org.kde.kdeconnect.handler.desktop";

        # -------------------------------------------------------------------
        # Audio Tools (ToneLib GFX)
        # -------------------------------------------------------------------
        "application/x-tonelib-gfx-preset" = "ToneLib-GFX.desktop";

        # -------------------------------------------------------------------
        # Authentication (Ente Auth)
        # -------------------------------------------------------------------
        "x-scheme-handler/enteauth" = "io.ente.auth.desktop";

        # -------------------------------------------------------------------
        # System Software Installation
        # -------------------------------------------------------------------
        "x-content/unix-software" = "nautilus-autorun-software.desktop";
      };
    };
  };
}
