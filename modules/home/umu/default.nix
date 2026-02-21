{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  openal = (pkgs.pkgsCross.mingw32.openal.override {
    alsaSupport = false;
    pulseSupport = false;
    dbusSupport = false;
  }).overrideAttrs (old: {
    buildInputs = [];
    nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.cmake pkgs.ninja ];
    meta = old.meta // { platforms = [ "i686-windows" ]; };
    preConfigure = (old.preConfigure or "") + ''
      export LDFLAGS="$LDFLAGS -static -static-libgcc -static-libstdc++"
    '';
    cmakeFlags = (old.cmakeFlags or []) ++ [
      "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
      "-DALSOFT_REQUIRE_WINMM=ON"
      "-DALSOFT_REQUIRE_DSOUND=ON"
      "-DALSOFT_BACKEND_ALSA=OFF"
      "-DALSOFT_BACKEND_OSS=OFF"
      "-DALSOFT_BACKEND_PULSEAUDIO=OFF"
      "-DALSOFT_BACKEND_JACK=OFF"
      "-DALSOFT_EXAMPLES=OFF"
      "-DALSOFT_UTILS=OFF"
    ];
  });
  cfg = config.umu;
  runtime = pkgs.fetchurl {
    url = "https://github.com/DADA30000/dotfiles/releases/download/vmware/umu.tar.zstd";
    hash = "sha256-uMAAWUGNEp5UYGs3hBtWXtf0BnaqEPzcX1yJ105vB1w=";
  };
  umu-tar = (
    pkgs.writeShellScriptBin "umu-tar" ''
      HOME="${config.home.homeDirectory}"
      LOCAL_DIR="$HOME/.local/share"
      PATH="$PATH:${pkgs.coreutils-full}/bin:${pkgs.zstd}/bin:${pkgs.gnutar}/bin"
      if [[ ! -d "$LOCAL_DIR/umu" ]]; then
        mkdir -p "$LOCAL_DIR"
        umount -qf "$LOCAL_DIR/umu"
        rm -rf "$LOCAL_DIR/umu"
        tar -xaf "${runtime}" -C "$LOCAL_DIR"
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
        Type = "oneshot";
      };
    };
    xdg.mimeApps.defaultApplications = {
      "application/vnd.microsoft.portable-executable" = "run-exe.desktop";
      "application/x-msi" = "run-exe.desktop";
      "application/x-msdownload" = "run-exe.desktop";
      "application/x-ms-shortcut" = "run-exe.desktop";
      "application/x-mswinurl" = "run-exe.desktop";
      "application/x-ms-dos-executable" = "run-exe.desktop";
      "application/x-bat" = "run-exe.desktop";
    };
    xdg.desktopEntries.run-exe.settings = {
      #Exec = "run-exe %f";
      Exec = "umu-run-wrapper %f";
      MimeType = "application/vnd.microsoft.portable-executable;application/x-msi;application/x-msdownload;application/x-ms-shortcut;application/x-bat;application/x-ms-dos-executable;application/x-mswinurl";
      Name = "Execute Windows file";
      StartupWMClass = "run-exe";
      Type = "Application";
      Icon = "wine";
    };
    home.packages = [
      pkgs.zenity
      #(pkgs.writeShellScriptBin "run-exe" ''
      #  if [[ ! -n "$1" ]]; then
      #    selected_file=$(zenity --file-selection --title="Выберите файл для запуска")
      #    if [ -n "$selected_file" ]; then
      #      run-exe "$selected_file"
      #    fi
      #    exit 0
      #  fi
      #  choice=$(zenity --info \
      #    --title="run-exe" \
      #    --text="Запустить $1 через:" \
      #    --ok-label="soda (не работает)" \
      #    --extra-button="umu" \
      #    --extra-button="Выбрать другой файл")

      #  exit_code=$?

      #  case $exit_code in
      #    0)
      #      ${"soda"}/bin/wine64 "$1";;
      #    1)
      #      case "$choice" in
      #        "umu")
      #          umu-run-wrapper "$1";;
      #        "Выбрать другой файл")
      #          selected_file=$(zenity --file-selection --title="Выберите файл для запуска")
      #          if [ -n "$selected_file" ]; then
      #            run-exe "$selected_file"
      #          fi;;
      #      esac
      #      ;;
      #  esac
      #'')
      (pkgs.writeShellScriptBin "umu-run-wrapper" ''
        export WINEPREFIX=$HOME/.umu
        if [[ ! -d ~/.local/share/umu ]]; then
          ${pkgs.libnotify}/bin/notify-send "Please wait..." "Waiting for umu-check service to finish"
          if ! ${pkgs.systemd}/bin/systemctl --user start umu-check.service; then
            ${pkgs.libnotify}/bin/notify-send "Error" "umu-check.service failed"
          fi
        fi
        if [[ ! -f "$WINEPREFIX/check-do_not_delete_this" ]]; then
          mkdir -p "$WINEPREFIX/drive_c/windows/syswow64"
          cp --no-preserve=mode "${openal}/bin/OpenAL32.dll" "$WINEPREFIX/drive_c/windows/syswow64/OpenAL32.dll"
          touch "$WINEPREFIX/check-do_not_delete_this"
        fi
        while [[ ! -d ~/.local/share/umu ]]; do
          sleep 0.2
        done
        ${pkgs.libnotify}/bin/notify-send "Starting UMU"
        UMU_RUNTIME_UPDATE=0 PROTONPATH=${pkgs.proton-ge-bin.steamcompattool} ${pkgs.gamemode}/bin/gamemoderun ${pkgs.umu-launcher}/bin/umu-run "$@"
        ${pkgs.libnotify}/bin/notify-send "Closed" "UMU exited (if you didn't close the app, app might've crashed)"
        (
          ICON_DIR="$HOME/.local/share/icons/umu"
          DESKTOP_DIR="$HOME/.local/share/applications"
          mkdir -p "$ICON_DIR" "$DESKTOP_DIR"

          for d_file in "$DESKTOP_DIR"/umu-*.desktop; do
            if [[ -f "$d_file" ]]; then
               exe_path=$(grep '^Exec=' "$d_file" | sed -n 's/^Exec=umu-run-wrapper "\([^"]*\)".*/\1/p')
               if [[ -n "$exe_path" && ! -f "$exe_path" ]]; then
                  game_name=$(grep '^Name=' "$d_file" | head -n 1 | cut -d= -f2-)
                  icon_path=$(grep '^Icon=' "$d_file" | head -n 1 | cut -d= -f2)
                  ${pkgs.libnotify}/bin/notify-send -u normal -i "$icon_path" "Cleanup" "Removing shortcut for: $game_name"
                  rm "$d_file"
                  if [[ "$icon_path" == "$ICON_DIR"* && -f "$icon_path" ]]; then
                    rm "$icon_path"
                  fi
               fi
            fi
          done
      
          find "$WINEPREFIX/drive_c/users" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | while IFS= read -r -d "" USER_PROFILE; do

            find "$USER_PROFILE/Desktop" "$USER_PROFILE/AppData/Roaming/Microsoft/Windows/Start Menu/Programs" "$WINEPREFIX/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs" -type f -name "*.lnk" -print0 2>/dev/null | while IFS= read -r -d ''' lnk; do
              
              win_path=$(${pkgs.exiftool}/bin/exiftool -s3 -LocalBasePath "$lnk" | tr -d '\r')

              if [[ -z "$win_path" ]]; then
                  rm "$lnk"
                  continue
              fi
              
              args=$(${pkgs.exiftool}/bin/exiftool -s3 -CommandLineArguments "$lnk" | tr -d '\r')
              rel_path=$(echo "$win_path" | sed 's/^[A-Z]://; s/\\/\//g')
              actual_exe="$WINEPREFIX/drive_c$rel_path"
      
              if [[ -f "$actual_exe" ]]; then
                PATH_HASH=$(echo "$actual_exe$args" | md5sum | cut -c1-8)
                DESKTOP_FILE="$DESKTOP_DIR/umu-$PATH_HASH.desktop"
                ICON_FILE="umu-$PATH_HASH.png"
                LNK_DISPLAY_NAME=$(basename "$lnk" .lnk)
      
                if [[ ! -f "$DESKTOP_FILE" ]]; then
                  WORK_DIR=$(mktemp -d)

                  ICON_SRC_WIN=$(${pkgs.exiftool}/bin/exiftool -s3 -IconFileName "$lnk" | tr -d '\r')
                  
                  if [[ -n "$ICON_SRC_WIN" ]]; then
                    REL_ICON_PATH=$(echo "$ICON_SRC_WIN" | sed 's/^[A-Z]://; s/\\/\//g')
                    ICON_SOURCE="$WINEPREFIX/drive_c$REL_ICON_PATH"
                  else
                    ICON_SOURCE="$actual_exe"
                  fi
                  
                  if [[ "$ICON_SOURCE" == *.ico || "$ICON_SOURCE" == *.ICO ]]; then
                    cp "$ICON_SOURCE" "$WORK_DIR/icon.ico" 2>/dev/null
                  else
                    ${pkgs.icoutils}/bin/wrestool -x -t 14 "$ICON_SOURCE" > "$WORK_DIR/icon.ico" 2>/dev/null
                    
                    if [[ ! -s "$WORK_DIR/icon.ico" ]]; then
                        ${pkgs.icoutils}/bin/wrestool -x -t 14 "$actual_exe" > "$WORK_DIR/icon.ico" 2>/dev/null
                    fi
                  fi
                  
                  if [[ -s "$WORK_DIR/icon.ico" ]]; then
                    ${pkgs.icoutils}/bin/icotool -x -o "$WORK_DIR" "$WORK_DIR/icon.ico"
                    BIGGEST_PNG=$(ls -S "$WORK_DIR"/*.png 2>/dev/null | head -n 1)
                    
                    if [[ -n "$BIGGEST_PNG" ]]; then
                      cp "$BIGGEST_PNG" "$ICON_DIR/$ICON_FILE"
                      ICON_SPEC="$ICON_DIR/$ICON_FILE"
                    else
                      ICON_SPEC="wine"
                    fi
                  else
                    ICON_SPEC="wine"
                  fi
                  
                  rm -rf "$WORK_DIR"
      
                  cat <<EOF > "$DESKTOP_FILE"
[Desktop Entry]
Name=$LNK_DISPLAY_NAME (UMU)
Exec=umu-run-wrapper "$actual_exe" $args
Icon=$ICON_SPEC
Type=Application
Categories=Game;
Path=$(dirname "$actual_exe")
Terminal=false
EOF
                  chmod +x "$DESKTOP_FILE"

                  ${pkgs.libnotify}/bin/notify-send -i "$ICON_SPEC" "New game added" "Shortcut created for $LNK_DISPLAY_NAME"
                fi
                mv "$lnk" "$lnk".done
              else
                rm "$lnk"
              fi
            done
          done
        ) & disown
      '')
      #(pkgs.writeShellScriptBin "umu-run-wrapper-secure" ''
      #  cleanup() {
      #    echo -e "\nCtrl+C pressed. Terminating script and all child processes..."
      #    kill -s TERM 0
      #    exit 130
      #  }
      #  trap cleanup INT
      #  kek1=$(realpath "$1")
      #  kek=$(dirname "$kek1")
      #  if [[ "$kek" != "$HOME"/Downloads ]] && [[ "$kek" != "$HOME"/Загрузки ]]; then
      #    if ${pkgs.zenity}/bin/zenity --question --text="Вы пытаетесь запустить программу в директории $kek, после запуска у неё будет полный доступ к данной директории, вы уверены что хотите её запустить?"; then
      #      gamemoderun firejail --noprofile --read-only=all --whitelist="$kek" --whitelist=~/.umu --whitelist=~/.local/share/umu --private-dev umu-run-wrapper "$kek1"
      #    fi
      #  fi
      #'')
    ];
  };
}
