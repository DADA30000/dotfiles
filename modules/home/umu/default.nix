{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.umu;
  runtime = pkgs.fetchurl {
    url = "https://github.com/DADA30000/dotfiles/releases/download/vmware/umu.tar.zstd";
    hash = "sha256-uMAAWUGNEp5UYGs3hBtWXtf0BnaqEPzcX1yJ105vB1w=";
  };
  umu-tar = (pkgs.writeShellScriptBin "umu-tar" ''
    HOME="${config.home.homeDirectory}"
    PATH="$PATH:${pkgs.coreutils-full}/bin:${pkgs.zstd}/bin:${pkgs.gnutar}/bin"
    TEMPDIR="$(mktemp -d)"
    cd "$TEMPDIR"
    if [[ ! -d "$HOME/.local/share/umu" ]]; then
      mkdir -p "$HOME/.local/share"
      tar xaf "${runtime}"
      mv ./umu "$HOME/.local/share"
      cd "$HOME"
    fi
    UMU_RUNTIME_UPDATE=0 PROTONPATH=${pkgs.proton-ge-bin.steamcompattool} WINEPREFIX=~/.umu ${pkgs.umu-launcher}/bin/umu-run winetricks sandbox
    wait
    rm -rf "$TEMPDIR"
  '');
in
{
  options.umu = {
    enable = mkEnableOption "Enable umu - universal windows apps launcher";
  };

  config = mkIf cfg.enable {
    systemd.user.services.umu-check = {
      Install.WantedBy = [ "graphical-session.target" ];
      Service = {
        ExecStart = "${umu-tar}/bin/umu-tar";
        Type = "oneshot";
      };
    };
    xdg.mimeApps.defaultApplications = {
      "application/vnd.microsoft.portable-executable" = "umu.desktop";
      "application/x-msi" = "umu.desktop";
      "application/x-msdownload" = "umu.desktop";
    };
    xdg.desktopEntries.umu.settings = {
      Exec = "umu-run-wrapper %f";
      MimeType = "application/vnd.microsoft.portable-executable;application/x-msi;application/x-msdownload";
      Name = "Quickly run windows apps";
      StartupWMClass = "umu";
      Type = "Application";
    };
    home.packages = [
      (pkgs.writeShellScriptBin "umu-run-wrapper" ''
      while systemctl --user is-active --quiet umu-check.service; do
        sleep 0.2
      done
      UMU_RUNTIME_UPDATE=0 PROTONPATH=${pkgs.proton-ge-bin.steamcompattool} WINEPREFIX=~/.umu ${pkgs.umu-launcher}/bin/umu-run $*
    '')
      (pkgs.writeShellScriptBin "umu-run-wrapper-secure" '' 
      cleanup() {
        echo -e "\nCtrl+C pressed. Terminating script and all child processes..."
        kill -s TERM 0
        exit 130
      }
      trap cleanup INT
      kek1=$(realpath "$1")
      kek=$(dirname "$kek1")
      if [[ "$kek" != "$HOME"/Downloads ]] && [[ "$kek" != "$HOME"/Загрузки ]]; then
        if ${pkgs.zenity}/bin/zenity --question --text="Вы пытаетесь запустить программу в директории $kek, после запуска у неё будет полный доступ к данной директории, вы уверены что хотите её запустить?"; then
          gamemoderun firejail --noprofile --read-only=all --whitelist="$kek" --whitelist=~/.umu --whitelist=~/.local/share/umu --private-dev umu-run-wrapper "$kek1"
        fi
      fi
      '')
    ];
  };
}

