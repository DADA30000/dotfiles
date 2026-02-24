{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  proton-umu = pkgs.stdenv.mkDerivation (finalAttrs: {
    name = "proton-umu";
    version = "9.0-4e";
    src = pkgs.fetchurl {
      url = "https://github.com/Open-Wine-Components/umu-proton/releases/download/UMU-Proton-${finalAttrs.version}/UMU-Proton-${finalAttrs.version}.tar.gz";
      hash = "sha256-1TYX073YlPTVyP1D6Cf/+7zbtJv0c9f7O+JhjdRx6/M=";
    };
    installPhase = ''
      mkdir -p "$out"
      tar -xaf "$src" --strip-components=1 -C "$out"
    '';
  });
  openal =
    (pkgs.pkgsCross.mingw32.openal.override {
      alsaSupport = false;
      pulseSupport = false;
      dbusSupport = false;
    }).overrideAttrs
      (old: {
        buildInputs = [ ];
        nativeBuildInputs = old.nativeBuildInputs ++ [
          pkgs.cmake
          pkgs.ninja
        ];
        meta = old.meta // {
          platforms = [ "i686-windows" ];
        };
        preConfigure = (old.preConfigure or "") + ''
          export LDFLAGS="$LDFLAGS -static -static-libgcc -static-libstdc++"
        '';
        cmakeFlags = (old.cmakeFlags or [ ]) ++ [
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
      LOCAL_DIR="${config.xdg.dataHome}"
      PATH="$PATH:${pkgs.coreutils-full}/bin:${pkgs.zstd}/bin:${pkgs.gnutar}/bin:${pkgs.util-linux}/bin"
      if [[ ! -d "$LOCAL_DIR/umu" ]]; then
        mkdir -p "$LOCAL_DIR/umu.tmp"
        rm -rf "$LOCAL_DIR/umu.tmp/umu"
        tar -xaf "${runtime}" -C "$LOCAL_DIR/umu.tmp"
        umount -qf "$LOCAL_DIR/umu" 2>/dev/null || true 
        rm -rf "$LOCAL_DIR/umu"
        mv "$LOCAL_DIR/umu.tmp/umu" "$LOCAL_DIR"
      fi
    ''
  );
in
{
  options.umu = {
    enable = mkEnableOption "umu - universal windows apps launcher";
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
    xdg.desktopEntries.run-exe = {
      exec = "run-exe %f";
      mimeType = [
        "application/vnd.microsoft.portable-executable"
        "application/x-msi"
        "application/x-msdownload"
        "application/x-ms-shortcut"
        "application/x-bat"
        "application/x-ms-dos-executable"
        "application/x-mswinurl"
      ];
      name = "Execute Windows file";
      type = "Application";
      icon = "wine";
      settings.StartupWMClass = "run-exe";
    };
    home.packages = [
      pkgs.zenity
      (pkgs.writeShellScriptBin "run-exe" ''
        export WINEPREFIX=$HOME/.umu
        if [[ -z "$1" ]]; then
          selected_file=$(${pkgs.zenity}/bin/zenity --file-selection --title="Выберите файл")
          if [[ -n "$selected_file" ]]; then
            run-exe "$selected_file"
          fi
          exit 0
        fi
        choice=$(${pkgs.zenity}/bin/zenity --info \
          --title="run-exe" \
          --text="Выберите действие для $1:" \
          --ok-label="Запустить с помощью Proton GE" \
          --extra-button="Запустить с помощью Proton UMU v${proton-umu.version}" \
          --extra-button="Выбрать другой файл" \
          --extra-button="Создать .desktop файл")

        exit_code=$?

        case $exit_code in
          0)
            umu-run-wrapper "$1"
          ;;
          1)
            case "$choice" in
              "Запустить с помощью Proton UMU v${proton-umu.version}")
                USE_PROTON_UMU=1 umu-run-wrapper "$1"
              ;;
              "Выбрать другой файл")
                selected_file=$(${pkgs.zenity}/bin/zenity --file-selection --title="Выберите файл для запуска")
                if [[ -n "$selected_file" ]]; then
                  run-exe "$selected_file"
                fi
              ;;
              "Создать .desktop файл")
                if [[ "$1" == *.lnk ]]; then
                  args=$(${pkgs.zenity}/bin/zenity --entry --title="Введите доп. аргументы для программы" --text="Например: --help --all\n\nМожно оставить пустым")
                  name=$(${pkgs.zenity}/bin/zenity --entry --title="Введите название программы (для отображения)" --text="Например: Backpack Hero\n\nМожно оставить пустым (тогда будет использоваться название файла без .lnk)")
                  orig_args=$(${pkgs.exiftool}/bin/exiftool -s3 -CommandLineArguments "$1" | tr -d '\r')
                  win_path=$(${pkgs.exiftool}/bin/exiftool -s3 -LocalBasePath "$1" | tr -d '\r')
                  rel_path=$(echo "$win_path" | sed 's/^[A-Z]://; s/\\/\//g')
                  actual_exe="$WINEPREFIX/drive_c$rel_path"
                  create-desktop-with-umu "$actual_exe" "$1" "$orig_args $args" "$name"
                else
                  args=$(${pkgs.zenity}/bin/zenity --entry --title="Введите аргументы для программы" --text="Например: --help --all\n\nМожно оставить пустым")
                  name=$(${pkgs.zenity}/bin/zenity --entry --title="Введите название программы (для отображения)" --text="Например: Backpack Hero\n\nМожно оставить пустым (тогда будет использоваться название файла без .exe)")
                  create-desktop-with-umu "$1" "" "$args" "$name"
                fi
              ;;
            esac
          ;;
        esac
      '')
      (pkgs.writeShellScriptBin "umu-run-wrapper" ''
        export WINEPREFIX=$HOME/.umu
        if [[ ! -d "${config.xdg.dataHome}/umu" ]]; then
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
        while [[ ! -d "${config.xdg.dataHome}/umu" ]]; do
          sleep 0.2
        done
        ${pkgs.libnotify}/bin/notify-send "Starting UMU"
        if [[ "$USE_PROTON_UMU" == 1 ]]; then
          export PROTONPATH="${proton-umu}"
        else
          export PROTONPATH="${pkgs.proton-ge-bin.steamcompattool}"
        fi
        UMU_RUNTIME_UPDATE=0 ${pkgs.gamemode}/bin/gamemoderun ${pkgs.umu-launcher}/bin/umu-run "$@"
        ${pkgs.libnotify}/bin/notify-send "Closed" "UMU exited (if you didn't close the app, app might've crashed)"
        scan-umu-for-lnk & disown
      '')
      (pkgs.writeShellScriptBin "scan-umu-for-lnk" ''
        export WINEPREFIX=$HOME/.umu

        cleanup-desktop-with-umu

        find "$WINEPREFIX/drive_c/users" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | while IFS= read -r -d "" USER_PROFILE; do

          find "$USER_PROFILE/Desktop" "$USER_PROFILE/AppData/Roaming/Microsoft/Windows/Start Menu/Programs" "$WINEPREFIX/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs" -type f -name "*.lnk" -print0 2>/dev/null | while IFS= read -r -d "" lnk; do
            
            if grep -Fq "X-UMU-Lnk-Path=$lnk" "${config.xdg.dataHome}/applications"/umu-*.desktop 2>/dev/null; then
              continue
            fi

            win_path=$(${pkgs.exiftool}/bin/exiftool -s3 -LocalBasePath "$lnk" | tr -d '\r')

            if [[ -z "$win_path" ]]; then
                rm "$lnk"
                continue
            fi
            
            args=$(${pkgs.exiftool}/bin/exiftool -s3 -CommandLineArguments "$lnk" | tr -d '\r')
            rel_path=$(echo "$win_path" | sed 's/^[A-Z]://; s/\\/\//g')
            actual_exe="$WINEPREFIX/drive_c$rel_path"

            create-desktop-with-umu "$actual_exe" "$lnk" "$args"
          done
        done
      '')
      (pkgs.writeShellScriptBin "cleanup-desktop-with-umu" ''
        PATH="${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:$PATH"
        ICON_DIR="${config.xdg.dataHome}/icons/umu"
        DESKTOP_DIR="${config.xdg.dataHome}/applications"
        for d_file in "$DESKTOP_DIR"/umu-*.desktop; do
          if [[ -f "$d_file" ]]; then
            exe_path=$(grep '^Exec=' "$d_file" | sed -n 's/^.*umu-run-wrapper "\([^"]*\)".*/\1/p')
            if [[ -n "$exe_path" && ! -f "$exe_path" ]]; then
              game_name=$(grep '^Name=' "$d_file" | head -n 1 | cut -d= -f2-)
              icon_path=$(grep '^Icon=' "$d_file" | head -n 1 | cut -d= -f2)
              ${pkgs.libnotify}/bin/notify-send -u normal -i "$icon_path" "Cleanup" "Removing shortcut for: $game_name"
              rm "$d_file"
              if [[ "$icon_path" == "$ICON_DIR"* && -f "$icon_path" ]]; then
                rm -f "$icon_path"
              fi
            fi
          fi
        done
        for i_file in "$ICON_DIR"/*; do
          [[ -e "$i_file" ]] || continue
          base=$(basename "$i_file" .png)
          
          if [[ ! -f "$DESKTOP_DIR/$base.desktop" && ! -f "$DESKTOP_DIR/$base-umu.desktop" ]]; then
            ${pkgs.libnotify}/bin/notify-send -u normal -i "$i_file" "Cleanup" "Removing stale icon $(basename "$i_file")"
            rm "$i_file"
          fi
        done
      '')
      (pkgs.writeShellScriptBin "create-desktop-with-umu" ''
        PATH="${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:$PATH"
        export WINEPREFIX=$HOME/.umu
        ICON_DIR="${config.xdg.dataHome}/icons/umu"
        DESKTOP_DIR="${config.xdg.dataHome}/applications"
        mkdir -p "$ICON_DIR" "$DESKTOP_DIR"
        actual_exe="$1"
        lnk="$2"
        args="$3"
        name="$4"
        if [[ -f "$actual_exe" ]]; then
          PATH_HASH=$(echo "$actual_exe$args" | md5sum | cut -c1-8)
          DESKTOP_FILE="$DESKTOP_DIR/umu-$PATH_HASH.desktop"
          DESKTOP_FILE_UMU="$DESKTOP_DIR/umu-$PATH_HASH-umu.desktop"
          ICON_FILE="umu-$PATH_HASH.png"
          if [[ -n "$name" ]]; then
            LNK_DISPLAY_NAME="$name"
          elif [[ -n "$lnk" ]]; then
            LNK_DISPLAY_NAME=$(basename "$lnk" | sed 's/\.[lL][nN][kK]$//')
          else
            LNK_DISPLAY_NAME=$(basename "$actual_exe" | sed 's/\.[eE][xX][eE]$//')
          fi
          if [[ ! -f "$DESKTOP_FILE" || ! -f "$DESKTOP_FILE_UMU" ]]; then
            WORK_DIR=$(mktemp -d)

            if [[ -n "$lnk" && -f "$lnk" ]]; then
              ICON_SRC_WIN=$(${pkgs.exiftool}/bin/exiftool -s3 -IconFileName "$lnk" | tr -d '\r')
            else
              ICON_SRC_WIN=""
            fi            

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
              ${pkgs.imagemagick}/bin/magick "$WORK_DIR/icon.ico" "$WORK_DIR/icon.png"
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
        Name=$LNK_DISPLAY_NAME (Proton GE)
        Exec=umu-run-wrapper "$actual_exe" $args
        Icon=$ICON_SPEC
        Type=Application
        Categories=Game;
        Path=$(dirname "$actual_exe")
        Terminal=false
        X-UMU-Lnk-Path=$lnk
        EOF

            cat <<EOF > "$DESKTOP_FILE_UMU"
        [Desktop Entry]
        Name=$LNK_DISPLAY_NAME (Proton UMU)
        Exec=env USE_PROTON_UMU=1 umu-run-wrapper "$actual_exe" $args
        Icon=$ICON_SPEC
        Type=Application
        Categories=Game;
        Path=$(dirname "$actual_exe")
        Terminal=false
        X-UMU-Lnk-Path=$lnk
        EOF

            chmod +x "$DESKTOP_FILE" "$DESKTOP_FILE_UMU"

            ${pkgs.libnotify}/bin/notify-send -i "$ICON_SPEC" "New game added" "Shortcut created for $LNK_DISPLAY_NAME"
          fi
        else
          if [[ -n "$lnk" ]]; then 
            rm "$lnk"; 
          fi
        fi
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
      #      gamemoderun firejail --noprofile --read-only=all --whitelist="$kek" --whitelist=~/.umu --whitelist=${config.xdg.dataHome}/umu --private-dev umu-run-wrapper "$kek1"
      #    fi
      #  fi
      #'')
    ];
  };
}
