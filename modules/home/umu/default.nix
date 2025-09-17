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
    url = "https://github.com/DADA30000/dotfiles/releases/download/vmware/SteamLinuxRuntime_sniper.tar.xz";
    hash = "sha256-QIWdJqVGqN3PYh1FxO9ewHJPk3PIQ6hOol+9oh4rb6s=";
  };
  umu-tar = (pkgs.writeShellScriptBin "umu-tar" ''
    if [[ ! -d "${config.home.homeDirectory}/.local/share/umu/steamrt3" ]]; then
      ${pkgs.coreutils-full}/bin/mkdir -p "${config.home.homeDirectory}/.local/share/umu/steamrt3"
      ${pkgs.coreutils-full}/bin/touch "${config.home.homeDirectory}/.local/share/umu/pfx.lock"
      ${pkgs.coreutils-full}/bin/touch "${config.home.homeDirectory}/.local/share/umu/umu.lock"
      cd "$(${pkgs.coreutils-full}/bin/mktemp -d)"
      ${pkgs.gnutar}/bin/tar xaf "${runtime}"
      ${pkgs.coreutils-full}/bin/cp -a SteamLinuxRuntime_sniper/* "${config.home.homeDirectory}/.local/share/umu/steamrt3"
      ${pkgs.coreutils-full}/bin/rm -rf "$PWD"
    fi
    PROTONPATH=${pkgs.proton-ge-bin.steamcompattool} WINEPREFIX=~/.umu ${pkgs.umu-launcher-unwrapped}/bin/umu-run winetricks sandbox
  '');
in
{
  options.umu = {
    enable = mkEnableOption "Enable umu - universal windows apps launcher";
  };

  config = mkIf cfg.enable {
    systemd.user.services.umu-check = {
      Install.WantedBy = [ "graphical-session.target" ];
      Service.ExecStart = "${umu-tar}/bin/umu-tar";
    };
    xdg.mimeApps.defaultApplications = {
      "application/vnd.microsoft.portable-executable" = "umu.desktop";
      "application/x-msi" = "umu.desktop";
      "application/x-msdownload" = "umu.desktop";
    };
    xdg.desktopEntries.umu.settings = {
      Exec = "umu-run-wrapper-secure %f";
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
      PROTONPATH=${pkgs.proton-ge-bin.steamcompattool} WINEPREFIX=~/.umu ${pkgs.umu-launcher}/bin/umu-run "$1"
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

