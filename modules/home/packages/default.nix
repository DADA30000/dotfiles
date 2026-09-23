{
  pkgs,
  lib,
  inputs,
  osConfig,
  mkSandbox,
  ...
}:
let
  fixPrism =
    pkg:
    pkgs.symlinkJoin {
      inherit (pkg) name;
      paths = [ pkg ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        rm $out/bin/prismlauncher
        makeWrapper ${pkg}/bin/prismlauncher $out/bin/prismlauncher \
          --run '
            CONF_DIR="$XDG_DATA_HOME/PrismLauncher"
            CONF="$CONF_DIR/prismlauncher.cfg"
            GEOM="\"AdnQywADAAAAAAAAAAAAAAAABDYAAAO/AAAAAAAAAAD////+/////gAAAAACAAAABkAAAAAAAAAAAAAABDYAAAO/\""
            mkdir -p "$CONF_DIR"
            if [ ! -f "$CONF" ]; then
              echo "MainWindowGeometry=$GEOM" > "$CONF"
            else
              sed -i "s|^MainWindowGeometry=.*|MainWindowGeometry=$GEOM|" "$CONF"
            fi
          '
      '';
    };

  # ---------------------------------------------------------------------------
  # Sandboxed Applications
  # ---------------------------------------------------------------------------
  rustdeskSandbox = mkSandbox rec {
    appId = "com.rustdesk.RustDesk";
    network = true;
    audio = true;
    wayland = true;
    gpu = true;
    package = pkgs.rustdesk-flutter;
    additional_outside_commands = ''
      ln -sf "$HOME/.nixpak/${appId}/home/''${XDG_CONFIG_HOME#"$HOME/"}/rustdesk" "$XDG_CONFIG_HOME/rustdesk"
    '';
  };

  prismLauncherSandbox = mkSandbox rec {
    appId = "org.prismlauncher.PrismLauncher";
    network_singbox = true;
    audio = true;
    wayland = true;
    gpu = true;
    x11 = true;
    additional_args =
      { sloth, ... }:
      {
        dbus.policies."com.feralinteractive.GameMode" = "talk";
        bubblewrap.bind.ro = [
          (sloth.mkdir (sloth.concat' (sloth.env "XDG_CONFIG_HOME") "/openvr"))
          (sloth.mkdir (sloth.concat' (sloth.env "XDG_CONFIG_HOME") "/openxr"))
          (sloth.mkdir (sloth.concat' (sloth.env "XDG_RUNTIME_DIR") "/wivrn"))
        ];
      };
    additional_outside_commands = ''
      ln -sf "$HOME/.nixpak/${appId}/home/''${XDG_DATA_HOME#"$HOME/"}/PrismLauncher" "$XDG_DATA_HOME/PrismLauncher"
    '';
    package = fixPrism (
      pkgs.prismlauncher.override {
        prismlauncher-unwrapped = pkgs.prismlauncher-unwrapped.overrideAttrs (prev: {
          patches = prev.patches or [ ] ++ [ ../../../stuff/patches/prismlauncher.patch ];
        });
      }
    );
  };

  discordCanarySandbox = mkSandbox rec {
    appId = "com.discordapp.DiscordCanary";
    network_singbox = true;
    audio = true;
    wayland = true;
    gpu = true;
    x11 = true;
    webcam = 5;
    additional_args =
      { sloth, ... }:
      {
        bubblewrap = {
          sharePid = true;
          bind.rw = [ (sloth.concat' (sloth.env "XDG_CONFIG_HOME") "/Vencord") ];
        };
      };
    additional_outside_commands = ''
      ln -sf "$HOME/.nixpak/${appId}/home/''${XDG_CONFIG_HOME#"$HOME/"}/discordcanary" "$XDG_CONFIG_HOME/discordcanary"
      ln -sf "$XDG_RUNTIME_DIR/.nixpak/${appId}/runtime/discord-ipc-0" "$XDG_RUNTIME_DIR/discord-ipc-0"
    '';
    package = pkgs.discord-canary.override {
      withOpenASAR = true;
      withVencord = true;
      openasar = pkgs.openasar.overrideAttrs (prev: {
        patches = (prev.patches or [ ]) ++ [ ../../../stuff/patches/openasar.patch ];
      });
    };
  };

  sounduxSandbox = mkSandbox {
    appId = "io.github.Soundux";
    network = true;
    audio = true;
    wayland = true;
    gpu = true;
    x11 = true;
    package = sounduxPkg;
    additional_args =
      { sloth, ... }:
      {
        bubblewrap.bind.rw = [ (sloth.mkdir (sloth.concat' (sloth.env "HOME") "/Music/Soundux")) ];
      };
  };

  ayugramDesktopSandbox = mkSandbox rec {
    appId = "com.ayugram.desktop";
    network_singbox = true;
    audio = true;
    wayland = true;
    gpu = true;
    webcam = 5;
    additional_outside_commands = ''
      ln -sf "$HOME/.nixpak/${appId}/home/''${XDG_DATA_HOME#"$HOME/"}/AyuGramDesktop" "$XDG_DATA_HOME/AyuGramDesktop"
    '';
    package = pkgs.ayugram-desktop;
  };

  # ---------------------------------------------------------------------------
  # Custom Derivations & Overrides
  # ---------------------------------------------------------------------------
  sounduxPkg = pkgs.stdenv.mkDerivation {
    pname = "soundux";
    version = "0.2.8-unstable";

    src = pkgs.fetchgit {
      url = "https://github.com/Soundux/Soundux.git";
      rev = "e02845233221aff3261865afb7ea158d4a51bd52";
      fetchSubmodules = true;
      deepClone = false;
      hash = "sha256-Dc+6EqH/2TriT2zUYsF+Xe3O3+7DBTdbXqIEHu053Ik=";
    };

    nativeBuildInputs = with pkgs; [
      cmake
      pkg-config
      wrapGAppsHook3
    ];

    buildInputs = with pkgs; [
      pipewire
      libpulseaudio
      libx11
      libxi
      libxtst
      libwnck
      gtk3
      webkitgtk_4_1
      libappindicator-gtk3
      tl-expected
      openssl
      glib
      gst_all_1.gstreamer
      gst_all_1.gst-plugins-base
      gst_all_1.gst-plugins-good
    ];

    cmakeFlags = [ "-DCMAKE_POLICY_VERSION_MINIMUM=3.5" ];

    postPatch = ''
      substituteInPlace src/ui/impl/webview/lib/webviewpp/CMakeLists.txt \
        --replace-fail "webkit2gtk-4.0" "webkit2gtk-4.1"
      substituteInPlace CMakeLists.txt \
        --replace-fail 'set(CMAKE_INSTALL_PREFIX "/opt/soundux" CACHE PATH "Install path prefix, prepended onto install directories." FORCE)' "" \
        --replace-fail 'install(TARGETS soundux DESTINATION .)' 'install(TARGETS soundux DESTINATION bin)' \
        --replace-fail 'install(DIRECTORY "''${CMAKE_SOURCE_DIR}/build/dist" DESTINATION .)' 'install(DIRECTORY "''${CMAKE_SOURCE_DIR}/build/dist" DESTINATION bin)' \
        --replace-fail 'DESTINATION /usr/share/' 'DESTINATION share/'
      substituteInPlace lib/guardpp/CMakeLists.txt \
        --replace-fail 'include(FetchContent)' 'find_package(tl-expected REQUIRED)' \
        --replace-fail 'FetchContent_Declare(expected GIT_REPOSITORY "https://github.com/TartanLlama/expected")' "" \
        --replace-fail 'FetchContent_MakeAvailable(expected)' ""
      substituteInPlace deployment/soundux.desktop \
        --replace-fail "/opt/soundux/soundux" "soundux"
      substituteInPlace src/ui/impl/webview/webview.cpp \
        --replace-fail '"/usr/share/pixmaps/soundux.png"' "\"$out/share/pixmaps/soundux.png\""
      substituteInPlace src/helper/audio/linux/pipewire/forward.cpp \
        --replace-fail '"libpipewire-0.3.so.0"' '"${pkgs.pipewire}/lib/libpipewire-0.3.so.0"'
      substituteInPlace src/helper/audio/linux/pulseaudio/forward.cpp \
        --replace-fail '"libpulse.so.0"' '"${pkgs.libpulseaudio}/lib/libpulse.so.0"'
      substituteInPlace src/helper/icons/forward.cpp \
        --replace-fail '"libwnck-3.so.0"' '"${pkgs.libwnck}/lib/libwnck-3.so.0"'
      substituteInPlace src/helper/ytdl/youtube-dl.cpp \
        --replace-fail '"youtube-dl ' '"yt-dlp '
    '';

    preFixup = ''
      gappsWrapperArgs+=(
        --prefix PATH : ${
          pkgs.lib.makeBinPath (
            with pkgs;
            [
              ffmpeg
              yt-dlp
            ]
          )
        }
        --prefix LD_LIBRARY_PATH : ${
          pkgs.lib.makeLibraryPath (
            with pkgs;
            [
              pipewire
              libpulseaudio
              libwnck
            ]
          )
        }
      )
    '';
  };

  gtkshutdownPkg =
    (pkgs.callPackage (inputs.gtkshutdown + "/nix") {
      inputs = inputs.gtkshutdown.inputs;
      toolchain = pkgs.symlinkJoin {
        name = "rust-toolchain";
        paths = [
          pkgs.rustc
          pkgs.cargo
        ];
      };
    }).overrideAttrs
      (oldAttrs: {
        patches = (oldAttrs.patches or [ ]) ++ [
          ../../../stuff/patches/gtkshutdown.patch
        ];
      });

  rustHelpersPkg = inputs.rust-helpers.packages.${pkgs.stdenv.hostPlatform.system}.default;
  json2xPkg = pkgs.callPackage "${inputs.nixpkgs}/pkgs/pkgs-lib/formats/json2x/package.nix" { };
  app2unitPkg = pkgs.app2unit.overrideAttrs (oldAttrs: {
    postPatch = (oldAttrs.postPatch or "") + ''
      echo "app2unit(1)" > app2unit.1.scd
    '';
  });

  pythonPkg = pkgs.python3.withPackages (
    ps: with ps; [
      tkinter
      debugpy
      pynvim
    ]
  );

  nhPkg = pkgs.nh.override {
    nix-output-monitor = nixOutputMonitorPkg;
  };

  nixOutputMonitorPkg = pkgs.nix-output-monitor.overrideAttrs (prev: {
    patches = (prev.patches or [ ]) ++ [ ../../../stuff/patches/nom.patch ];
  });

  nixAlienPkg = inputs.nix-alien.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
    python3 = pkgs.python3.override {
      packageOverrides = pyFinal: pyPrev: {
        dpcontracts = pyPrev.dpcontracts.overridePythonAttrs (oldAttrs: {
          doCheck = false;
        });
      };
    };
  };

  nixSearchPkg = inputs.nix-search.packages.${pkgs.stdenv.hostPlatform.system}.default;
  heliumPkg = inputs.helium.packages.${pkgs.stdenv.hostPlatform.system}.default;

  translateZapretNixosPkg = pkgs.writeShellScriptBin "translate-zapret-nixos" (
    builtins.readFile ../../../stuff/system/packages/translate-zapret-nixos.sh
  );

  qt6ctPkg = pkgs.kdePackages.qt6ct.overrideAttrs (prev: {
    patches = prev.patches or [ ] ++ [ ../../../stuff/patches/qt6ct-shenanigans.patch ];
    buildInputs = prev.buildInputs or [ ] ++ [
      pkgs.kdePackages.kconfig
      pkgs.kdePackages.kcolorscheme
      pkgs.kdePackages.kiconthemes
      pkgs.kdePackages.qqc2-desktop-style
    ];
  });

  aria2Pkg = pkgs.aria2.overrideAttrs (prev: {
    patches = prev.patches or [ ] ++ [ ../../../stuff/patches/max-connection-to-unlimited.patch ];
  });

  anicliRuPkg =
    let
      workspace = inputs.uv2nix.lib.workspace.loadWorkspace {
        workspaceRoot = inputs.anicli-ru;
      };
      overlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };
      pythonSet =
        (pkgs.callPackage inputs.pyproject-nix.build.packages { python = pkgs.python312; }).overrideScope
          (
            lib.composeManyExtensions [
              inputs.pyproject-build-systems.overlays.default
              overlay
            ]
          );
      anicliPkg = pythonSet.anicli-ru;
      venv = pythonSet.mkVirtualEnv "anicli-ru-env" (
        workspace.deps.default // { anicli-ru = [ "all" ]; }
      );
    in
    pkgs.runCommand "anicli-ru-${anicliPkg.version or "latest"}"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
      }
      ''
        mkdir -p $out/bin
        makeWrapper ${venv}/bin/anicli-ru $out/bin/anicli-ru \
          --prefix PATH : ${lib.makeBinPath [ pkgs.mpv ]}
      '';

  diskoPkg = inputs.disko.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
    path = inputs.nixpkgs;
  };

  ventoyFullGtkPkg = pkgs.ventoy-full-gtk.overrideAttrs (
    finalAttrs: prevAttrs: {
      postInstall = (prevAttrs.postInstall or "") + ''
        GUI_BIN="$(echo "$out"/share/ventoy/tool/*/Ventoy2Disk.gtk3)"
        cat << EOF > "$out/bin/ventoy-gui"
        #!${pkgs.bash}/bin/bash
        set -euo pipefail
        VENTOY_PATH="$out/share/ventoy"
        GUI_BIN="$GUI_BIN"
        if [ "\''${EUID}" -ne 0 ]; then
          exec pkexec env \
            PATH="\$PATH" \
            HOME="\$HOME" \
            WAYLAND_DISPLAY="\''${WAYLAND_DISPLAY:-}" \
            XDG_RUNTIME_DIR="\''${XDG_RUNTIME_DIR:-}" \
            DISPLAY="\''${DISPLAY:-}" \
            GTK_THEME="\''${GTK_THEME:-}" \
            "\$0" "\$@"
        fi
        cd "\$VENTOY_PATH"
        exec "\$GUI_BIN" "\$@"
        EOF
        chmod +x "$out/bin/ventoy-gui"
        wrapProgram "$out/bin/ventoy-gui" \
          --prefix PATH : "${pkgs.lib.makeBinPath prevAttrs.buildInputs}"
      '';
    }
  );

  aero-control-center = pkgs.stdenv.mkDerivation {
    pname = "aero-control-center";
    version = "0.1.0";
    src = inputs.aero-control-center;

    nativeBuildInputs = with pkgs; [
      cmake
      pkg-config
      qt6.wrapQtAppsHook
    ];

    buildInputs = with pkgs; [
      qt6.qtbase
      libusb1
    ];

    postInstall = ''
      if [ ! -d $out/bin ]; then
        mkdir -p $out/bin
        mv $out/AeroControlCenter $out/bin/ || true
      fi
      mkdir -p $out/lib/udev/rules.d
      if [ -f ../70-keyboard.rules ]; then
        cp ../70-keyboard.rules $out/lib/udev/rules.d/70-keyboard.rules
      fi
    '';
  };

in
{
  home.extraOutputsToInstall = osConfig.environment.extraOutputsToInstall;

  home.packages = osConfig.environment.systemPackages ++ [
    (lib.hiPrio pkgs.clang)
    (lib.hiPrio pkgs.gnutar)
    (lib.hiPrio pkgs.procps)
    pkgs.dash
    pkgs.openrgb-with-all-plugins
    pkgs.stress-ng
    pkgs.furmark
    pkgs.xrdb
    pkgs.nix-tree
    pkgs.n-m3u8dl-re
    pkgs.yt-dlp
    pkgs.pi-coding-agent
    pkgs.gcc
    pkgs.libcap-text-verifier
    pkgs.curl
    pkgs.libxkbcommon
    pkgs.sbsigntool
    pkgs.slurp
    pkgs.w3m-nographics
    pkgs.testdisk
    pkgs.ms-sys
    pkgs.efivar
    pkgs.parted
    pkgs.gptfdisk
    pkgs.ccrypt
    pkgs.cryptsetup
    pkgs.fuse
    pkgs.fuse3
    pkgs.sshfs-fuse
    pkgs.screen
    pkgs.tcpdump
    pkgs.sdparm
    pkgs.hdparm
    pkgs.pciutils
    pkgs.innoextract
    pkgs.btrfs-progs
    pkgs.unzip
    pkgs.dosfstools
    pkgs.gum
    pkgs.tpm2-tools
    pkgs.uefi-firmware-parser
    pkgs.uefitool
    pkgs.flashrom
    pkgs.acpica-tools
    pkgs.lolcat
    pkgs.openssl
    pkgs.gparted
    pkgs.neovim-remote
    pkgs.stylua
    pkgs.delve
    pkgs.rustup
    pkgs.vscode-extensions.ms-vscode.cpptools
    pkgs.hexpatch
    pkgs.tinyxxd
    pkgs.bash-language-server
    pkgs.vscode-langservers-extracted
    pkgs.jdt-language-server
    pkgs.lua-language-server
    pkgs.taplo
    pkgs.yaml-language-server
    pkgs.shellcheck
    pkgs.shellcheck.out
    pkgs.shfmt
    pkgs.asm-lsp
    pkgs.tmux
    pkgs.tree-sitter
    pkgs.ripgrep
    pkgs.ruff
    pkgs.basedpyright
    pkgs.cmake-lint
    pkgs.clang-tools
    pkgs.clang
    pkgs.cmake-language-server
    pkgs.flatpak
    pkgs.duperemove
    pkgs.psmisc
    pkgs.woeusb-ng
    pkgs.wimlib
    pkgs.lsof
    pkgs.ddrescue
    pkgs.smartmontools
    pkgs.uv
    pkgs.bindfs
    pkgs.imagemagick
    pkgs.tonelib-gfx
    pkgs.sbctl
    pkgs.virt-manager
    pkgs.jq
    pkgs.wayvr
    pkgs.xhost
    pkgs.dante
    pkgs.ente-auth
    pkgs.patchelf
    pkgs.file
    pkgs.gnome-boxes
    pkgs.lsd
    pkgs.e2fsprogs
    pkgs.efitools
    pkgs.efibootmgr
    pkgs.kdiskmark
    pkgs.nixfmt
    pkgs.sshfs
    pkgs.gdu
    pkgs.nixd
    pkgs.go
    pkgs.gopls
    pkgs.delve
    pkgs.gotools
    pkgs.wget
    pkgs.zenity
    pkgs.procps
    pkgs.linuxConsoleTools
    pkgs.evtest
    pkgs.bat
    pkgs.nvme-cli
    pkgs.ethtool
    pkgs.killall
    pkgs.unrar
    pkgs.zip
    pkgs.dmidecode
    pkgs.usbutils
    pkgs.adwaita-icon-theme
    pkgs.vmpk
    pkgs.socat
    pkgs.neovide
    pkgs._7zz-rar
    pkgs.crudini
    pkgs.lndir
    pkgs.texinfoInteractive
    pkgs.xkbcomp
    pkgs.nvtopPackages.full
    pkgs.xkeyboard-config
    pkgs.libX11
    pkgs.scanmem
    pkgs.comma
    pkgs.remmina
    pkgs.mangohud
    pkgs.jdk25
    pkgs.moonlight-qt
    pkgs.osu-lazer-bin
    pkgs.xonotic
    pkgs.supertux
    pkgs.supertuxkart
    pkgs.pavucontrol
    pkgs.qalculate-gtk
    pkgs.distrobox
    pkgs.qbittorrent
    pkgs.gdb
    pkgs.wiggle
    pkgs.nodejs
    pkgs.libreoffice
    pkgs.protonplus
    pkgs.gimp3-with-plugins
    pkgs.gamescope
    pkgs.android-tools
    pkgs.compsize
    pkgs.erofs-utils
    pkgs.gsettings-desktop-schemas
    pkgs.resources
    pkgs.quickshell
    pkgs.hunspell
    pkgs.hunspellDicts.en_US-large
    pkgs.hunspellDicts.ru_RU
    pkgs.libsForQt5.qt5ct
    pkgs.libsForQt5.qtstyleplugin-kvantum
    pkgs.kdePackages.qtstyleplugin-kvantum
    pkgs.kdePackages.qtdeclarative
    pkgs.kdePackages.kdenlive
    pkgs.kdePackages.kdeconnect-kde
    pkgs.yad
    pkgs.rsync
    pkgs.strace
    pkgs.go
    pkgs.nix-diff
    pkgs.migrate-to-uv
    pkgs.ssdeep
    pkgs.gtk3
    pkgs.kdePackages.kservice
    pkgs.libsForQt5.qtsvg
    pkgs.kdePackages.qtsvg
    pkgs.kdePackages.dolphin
    pkgs.kdePackages.ark
    pkgs.pulseaudio
    pkgs.nautilus
    pkgs.file-roller
    pkgs.libnotify
    pkgs.brightnessctl
    pkgs.qimgv
    pkgs.myxer
    pkgs.ffmpeg-full
    pkgs.ffmpegthumbnailer
    pkgs.hyprpicker
    pkgs.wttrbar
    pkgs.makeWrapper
    pkgs.makeBinaryWrapper
    pkgs.dieHook
    pkgs.shellcheck.doc
    pkgs.python3Packages.xmltodict

    aero-control-center
    rustHelpersPkg
    json2xPkg
    diskoPkg
    ventoyFullGtkPkg
    translateZapretNixosPkg
    nhPkg
    app2unitPkg
    pythonPkg
    nixOutputMonitorPkg
    nixAlienPkg
    nixSearchPkg
    heliumPkg
    qt6ctPkg
    aria2Pkg
    gtkshutdownPkg
    anicliRuPkg

    sounduxSandbox
    rustdeskSandbox
    prismLauncherSandbox
    discordCanarySandbox
    ayugramDesktopSandbox
  ];
}
