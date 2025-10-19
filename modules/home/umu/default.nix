{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.umu;
  ratarmount =
    (pkgs.ratarmount.override {
      ratarmountcore = pkgs.python3Packages.ratarmountcore.overridePythonAttrs { doCheck = false; };
    }).overridePythonAttrs
      (prev: {
        dependencies = prev.dependencies ++ [
          (pkgs.python3Packages.buildPythonPackage rec {
            pname = "mfusepy";
            version = "1.0.0";
            pyproject = true;
            propagatedBuildInputs = [ pkgs.fuse ];
            build-system = [ pkgs.python3Packages.setuptools ];
            src = pkgs.fetchPypi {
              inherit pname version;
              hash = "sha256-vpIjTLMw4l3wBPsR8uK9wghNTRD7awDy9TRUC8ZsGKI=";
            };
          })
        ];
      });
  runtime = pkgs.fetchurl {
    url = "https://github.com/DADA30000/dotfiles/releases/download/vmware/umu.tar.zstd";
    hash = "sha256-uMAAWUGNEp5UYGs3hBtWXtf0BnaqEPzcX1yJ105vB1w=";
  };
  umu-tar = (
    pkgs.writeShellScriptBin "umu-tar" ''
      HOME="${config.home.homeDirectory}"
      LOCAL_DIR="$HOME/.local/share"
      PATH="$PATH:${pkgs.coreutils-full}/bin:${pkgs.zstd}/bin:${pkgs.gnutar}/bin:${ratarmount}/bin/ratarmount"
      if umount "$LOCAL_DIR/umu"; then
        ratarmount -o modules=subdir,subdir=umu/ --write-overlay "$LOCAL_DIR/umu-overlay" "${runtime}" "$LOCAL_DIR/umu"
      else
        mkdir -p "$LOCAL_DIR"
        rm -rf "$LOCAL_DIR/umu"
        ratarmount -o modules=subdir,subdir=umu/ --write-overlay "$LOCAL_DIR/umu-overlay" "${runtime}" "$LOCAL_DIR/umu"
      fi
    ''
  );
in
{
  options.umu = {
    enable = mkEnableOption "Enable umu - universal windows apps launcher";
  };

  config = mkIf cfg.enable {
    systemd.user.services.umu-check = {
      Install.WantedBy = [ "graphical-session.target" ];
      Unit.After = [ "graphical-session.target" ];
      Service = {
        ExecStart = "${umu-tar}/bin/umu-tar";
        Type = "forking";
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
      ratarmount # as a bonus
      (pkgs.writeShellScriptBin "umu-run-wrapper" ''
        if [[ ! -e ~/.local/share/umu ]]; then
          ${pkgs.libnotify}/bin/notify-send "Please wait..." "Waiting for umu-check service to finish"
          systemctl --user start umu-check.service
        fi
        while [[ ! -e ~/.local/share/umu ]]; do
          sleep 0.2
        done
        ${pkgs.libnotify}/bin/notify-send "Starting UMU"
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
