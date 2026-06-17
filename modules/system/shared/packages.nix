{
  pkgs,
  lib,
  inputs,
  mkSandbox,
  listFiles,
  ...
}:
let
  # Возвращаемся на clangStdenv для получения move_only_function из GCC libstdc++
  waywallen = pkgs.clangStdenv.mkDerivation rec {
    pname = "waywallen";
    version = src.shortRev;

    src = inputs.waywallen;

    patches = [ ../../../stuff/patches/0001-use-system-deps-waywallen.patch ];

    hardeningDisable = [ "fortify" ];

    cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
      inherit src;
      name = "${pname}-${version}-vendor";
      hash = "sha256-aFIWolhaOIReNrVJVpDZWGcFhcsaWTdbPnQGEZzvXUw=";
    };

    nativeBuildInputs = with pkgs; [
      cmake
      ninja
      lld
      grpc
      protobuf
      rustPlatform.cargoSetupHook
      cargo
      rustc
      pkg-config
      qt6.wrapQtAppsHook
      glslang
    ];

    buildInputs = with pkgs; [
      ffmpeg
      grpc
      protobuf
      pulseaudio
      curl
      mesa
      sqlite
      vulkan-loader
      qt6.qtbase
      qt6.qtdeclarative
      qt6.qtgrpc
      pipewire
      asio
      pegtl
      corrosion
      nlohmann_json
      hicolor-icon-theme
    ];

    cmakeFlags = [
      "-DCMAKE_C_COMPILER=clang"
      "-DCMAKE_CXX_COMPILER=clang++"
      "-DCMAKE_LINKER_TYPE=LLD"
      "-DFETCHCONTENT_FULLY_DISCONNECTED=ON"
      "-DFETCHCONTENT_SOURCE_DIR_RSTD=/build/rstd"
      "-DFETCHCONTENT_SOURCE_DIR_QEXTRA=/build/qextra"
      "-DFETCHCONTENT_SOURCE_DIR_QML_MATERIAL=/build/qml_material"
      "-DFETCHCONTENT_SOURCE_DIR_NCREQUEST=${inputs.ncrequest}"
      "-DFETCHCONTENT_SOURCE_DIR_WAVSEN=${inputs.wavsen}"
      "-DCMAKE_MODULE_PATH=${pkgs.qt6.qtgrpc}/lib/cmake/Qt6"
      "-DWAYWALLEN_BUILD_MPV_PLUGIN=OFF"
      "-DWAYWALLEN_CARGO_OFFLINE=ON"
    ];

    preConfigure = ''
      sed -i '1s|^|#include <cstdlib>\n#include <cmath>\n#include <string>\n#include <string_view>\n|' plugins/org.waywallen.video/src/main.cpp
      sed -i '1s|^|#include <cstdlib>\n#include <cmath>\n#include <string>\n#include <string_view>\n|' plugins/org.waywallen.image/src/main.cpp

      cp -r ${inputs.rstd} /build/rstd
      chmod -R +w /build/rstd
      sed -i '/export using std::make_shared;/d' /build/rstd/src/cppstd/cppstd.cppm
      sed -i '/export using std::allocate_shared;/d' /build/rstd/src/cppstd/cppstd.cppm

      sed -i '/export using std::operator==;/d' /build/rstd/src/cppstd/cppstd.cppm
      sed -i '/export using std::operator!=;/d' /build/rstd/src/cppstd/cppstd.cppm
      sed -i '/export using std::operator</d' /build/rstd/src/cppstd/cppstd.cppm
      sed -i '/export using std::operator>/d' /build/rstd/src/cppstd/cppstd.cppm

      cp -r ${inputs.qmlmaterial} /build/qml_material
      chmod -R +w /build/qml_material

      cp -r ${inputs.qextra} /build/qextra
      chmod -R +w /build/qextra
      sed -i 's|^module;|module;\n#include <memory>|' /build/qextra/src/global_static.cpp

      declare -a inc_paths
      next_is_path=0
      for flag in $NIX_CFLAGS_COMPILE; do
        if [ "$next_is_path" -eq 1 ]; then
          inc_paths+=("$flag")
          next_is_path=0
        elif [ "$flag" = "-isystem" ] || [ "$flag" = "-I" ]; then
          next_is_path=1
        elif [[ "$flag" == -I* ]]; then
          inc_paths+=("''${flag#-I}")
        fi
      done

      declare -a qt_inc_paths
      for path in "''${inc_paths[@]}"; do
        if [[ "$path" == *"/include" ]]; then
          qt_inc_paths+=("$path/qt6")
        fi
      done

      declare -a std_paths
      while read -r line; do
        clean_path=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -d "$clean_path" ]; then
          std_paths+=("$clean_path")
        fi
      done < <(clang++ -v -E -x c++ - < /dev/null 2>&1 | sed -n '/#include <...>/,/End of search list./p' | grep -v '#include' | grep -v 'End of search list')

      IFS=: eval 'inc_paths_str="''${inc_paths[*]}"'
      IFS=: eval 'qt_inc_paths_str="''${qt_inc_paths[*]}"'
      IFS=: eval 'std_paths_str="''${std_paths[*]}"'

      export C_INCLUDE_PATH="$inc_paths_str:$qt_inc_paths_str:$std_paths_str:$C_INCLUDE_PATH"
      export CPLUS_INCLUDE_PATH="$inc_paths_str:$qt_inc_paths_str:$std_paths_str:$CPLUS_INCLUDE_PATH"
    '';
  };
  open-wallpaper-engine = pkgs.clangStdenv.mkDerivation rec {
    pname = "open-wallpaper-engine";
    version = src.shortRev;

    src = inputs.open-wallpaper-engine;

    patches = [ ../../../stuff/patches/0001-use-system-deps-open-wallpaper-engine.patch ];

    nativeBuildInputs = with pkgs; [
      cmake
      ninja
      lld
    ];

    buildInputs = with pkgs; [
      lz4
      freetype
      libpulseaudio
      ffmpeg
      vulkan-loader
      vulkan-headers
      cef-binary
      glslang
      fontconfig
      quickjs-ng
      argparse
      eigen
      python3Packages.glad
      glfw
      nlohmann_json
      waywallen
    ];

    cmakeFlags = [
      "-DCMAKE_C_COMPILER=clang"
      "-DCMAKE_CXX_COMPILER=clang++"
      "-DCMAKE_LINKER_TYPE=LLD"
      "-DFETCHCONTENT_FULLY_DISCONNECTED=ON"
      "-DFETCHCONTENT_SOURCE_DIR_SPIRV_REFLECT=${inputs.spirv-reflect}"
      "-DFETCHCONTENT_SOURCE_DIR_RSTD=${inputs.rstd}"
      "-DFETCHCONTENT_SOURCE_DIR_WAVSEN=${inputs.wavsen}"
    ];

    preConfigure = ''
      export NIX_CFLAGS_COMPILE="$(echo "$NIX_CFLAGS_COMPILE" | sed 's/-Wp,-D_FORTIFY_SOURCE=3//')"
      export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -Wno-error=undefined-var-template -Wno-error=unused-private-field"
    '';
  };
  stripExtension =
    filename:
    let
      matchResult = builtins.match "(.*)\\.[^.]*" filename;
    in
    if matchResult == null then filename else builtins.head matchResult;

  listDirs = listFiles;

  targetDirs = [
    ../../../stuff/scripts
  ];

  excludeList = [
    "notify_trunc.py"
  ];

  handlers = {
    sh =
      path:
      pkgs.writeShellScriptBin (stripExtension (baseNameOf path)) (evalAndSubstitute {
        string = (builtins.readFile path);
      });
    py =
      path:
      pkgs.writers.writePython3Bin (stripExtension (baseNameOf path)) { } (evalAndSubstitute {
        string = (builtins.readFile path);
      });
  };

  getExtension =
    filename:
    let
      matchResult = builtins.match ".*\\.([^.]*)" filename;
    in
    if matchResult == null then "" else builtins.head matchResult;

  allPaths = listDirs targetDirs;

  filteredPaths = builtins.filter (
    path:
    let
      name = baseNameOf path;
    in
    !builtins.elem name excludeList
  ) allPaths;

  processedResults = map (
    path:
    let
      name = baseNameOf path;
      ext = getExtension name;
    in
    if builtins.hasAttr ext handlers then
      (builtins.getAttr ext handlers) path
    else
      throw "Error: No extension handler matched for '${name}' (extension: '${ext}') at path '${toString path}'."
  ) filteredPaths;

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
            GEOM="AdnQywADAAAAAAAAAAAAAAAABDYAAAO/AAAAAAAAAAD////+/////gAAAAACAAAABkAAAAAAAAAAAAAABDYAAAO/"
            
            mkdir -p "$CONF_DIR"

            if [ ! -f "$CONF" ]; then
              echo "MainWindowGeometry=$GEOM" > "$CONF"
            else
              sed -i "s|^MainWindowGeometry=.*|MainWindowGeometry=$GEOM|" "$CONF"
            fi
          '
      '';
    };

  evalNix =
    scope: code:
    (import (builtins.toFile "eval.nix" "{ pkgs, lib ? pkgs.lib, ... } @ scope: with scope; ( ${code} )")) scope;

  evalAndSubstitute =
    {
      string,
      scope ? { inherit pkgs lib; },
      openPattern ? "%{{{",
      closePattern ? "}}}",
    }:
    let
      parts = lib.splitString openPattern string;

      process =
        part:
        let
          sub = lib.splitString closePattern part;
        in
        if builtins.length sub > 1 then
          toString (evalNix scope (builtins.head sub))
          + builtins.concatStringsSep closePattern (builtins.tail sub)
        else
          openPattern + part;
    in
    builtins.head parts + builtins.concatStringsSep "" (map process (builtins.tail parts));
in
{
  config = {
    _module.args.evalAndSubstitute = evalAndSubstitute;
    environment.systemPackages =
      with pkgs;
      with inputs;
      [
        bindfs
        imagemagick
        tonelib-gfx
        sbctl
        virt-manager
        gemini-cli
        jq
        wayvr
        bs-manager
        xhost
        dante
        ente-auth
        mtkclient
        sidequest
        patchelf
        file
        mpv
        gnome-boxes
        lsd
        kdiskmark
        nixfmt
        gdu
        nixd
        wget
        zenity
        killall
        unrar
        zip
        adwaita-icon-theme
        vmpk
        wl-clipboard
        networkmanager_dmenu
        neovide
        _7zz-rar
        stdenv
        crudini
        lndir
        texinfo
        xkbcomp
        xkeyboard-config
        libX11
        scanmem
        comma
        remmina
        mangohud
        jdk25
        moonlight-qt
        osu-lazer-bin
        mindustry
        xonotic
        supertux
        supertuxkart
        pavucontrol
        qalculate-gtk
        distrobox
        qbittorrent
        ayugram-desktop
        gdb
        gcc
        nodejs
        libreoffice
        protonplus
        gimp3-with-plugins
        gamescope
        android-tools
        heroic
        gsettings-desktop-schemas
        resources
        hunspell
        hunspellDicts.en_US-large
        hunspellDicts.ru_RU
        libsForQt5.qt5ct
        libsForQt5.qtstyleplugin-kvantum
        kdePackages.qtstyleplugin-kvantum
        kdePackages.qtdeclarative
        kdePackages.kdenlive
        kdePackages.kdeconnect-kde
        quickshell.packages.${stdenv.hostPlatform.system}.default
        nix-alien.packages.${stdenv.hostPlatform.system}.default
        nix-search.packages.${stdenv.hostPlatform.system}.default
        (helium.packages.${stdenv.hostPlatform.system}.default.overrideAttrs (prev: {
          src = (import <nix/fetchurl.nix>) {
            url = prev.src.url;
            hash = prev.src.hash;
          };
        }))
        (writers.writePython3Bin "notify_trunc"
          {
            libraries = [
              python3Packages.pygobject3
            ];
            makeWrapperArgs = [
              "--prefix GI_TYPELIB_PATH : ${harfbuzz}/lib/girepository-1.0"
              "--prefix GI_TYPELIB_PATH : ${pango}/lib/girepository-1.0"
              "--prefix GI_TYPELIB_PATH : ${gobject-introspection}/lib/girepository-1.0"
            ];
          }
          (evalAndSubstitute {
            string = (builtins.readFile ../../../stuff/scripts/notify_trunc.py);
          })
        )
        (kdePackages.qt6ct.overrideAttrs (prev: {
          patches = prev.patches or [ ] ++ [ ../../../stuff/patches/qt6ct-shenanigans.patch ];
          buildInputs =
            prev.buildInputs or [ ]
            ++ (with kdePackages; [
              kconfig
              kcolorscheme
              kiconthemes
              qqc2-desktop-style
            ]);
        }))
        (aria2.overrideAttrs (prev: {
          patches = prev.patches or [ ] ++ [ ../../../stuff/patches/max-connection-to-unlimited.patch ];
        }))
        (mkSandbox {
          appId = "com.rustdesk.RustDesk";
          network = true;
          audio = true;
          wayland = true;
          gpu = true;
          package = rustdesk-flutter;
        })
        (mkSandbox rec {
          appId = "ru.safib.Assistant";
          network = true;
          audio = true;
          wayland = true;
          gpu = true;
          x11 = true;
          additional_args = {
            bubblewrap.bind.ro = [
              [
                "${package}"
                "/opt/assistant"
              ]
            ];
          };
          package = pkgs.stdenv.mkDerivation {
            pname = "assistant";
            version = "6.5";

            dontStrip = true;

            src = pkgs.fetchurl {
              url = "https://lk2.xn--80akicokc0aablc.xn--p1ai/WebApi/Platforms/Download/1375";
              hash = "sha256-Rk2cjRn4XE0l2dibyII86xTUFmDNHX1uoEszMZsbGqY=";
            };

            nativeBuildInputs = with pkgs; [
              dpkg
              autoPatchelfHook
              findutils
              gnused
            ];

            buildInputs = with pkgs; [
              gtk2
              sqlite
              libx11
              gdk-pixbuf
              glib
              pango
              cairo
              atk
              dbus
              libxtst
              libxi
              libxext
              libxfixes
              pipewire
              pulseaudio
              alsa-lib
            ];

            unpackPhase = ''
              dpkg-deb -x $src .
            '';

            installPhase = ''
              mkdir -p $out
              cp -r opt/assistant/* $out/
              mkdir -p $out/share/applications
              cp $out/scripts/assistant.desktop $out/share/applications/assistant.desktop
              sed -i "s%/opt/assistant%$out%g" $out/share/applications/assistant.desktop
            '';
          };
        })
        (mkSandbox {
          appId = "org.prismlauncher.PrismLauncher";
          network_singbox = true;
          audio = true;
          wayland = true;
          gpu = true;
          x11 = true;
          nvidia_gpu = true;
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
          package = fixPrism (
            prismlauncher.override {
              prismlauncher-unwrapped = prismlauncher-unwrapped.overrideAttrs (prev: {
                patches = prev.patches or [ ] ++ [ ../../../stuff/patches/prismlauncher.patch ];
              });
            }
          );
        })
        (mkSandbox rec {
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
                bind.ro = [ (sloth.concat' (sloth.env "XDG_CONFIG_HOME") "/Vencord") ];
              };
            };
          additional_wrap_commands = "ln -sf \"$XDG_RUNTIME_DIR/.nixpak/${appId}/runtime/discord-ipc-0\" \"$XDG_RUNTIME_DIR/discord-ipc-0\"";
          package = discord-canary.override {
            withOpenASAR = true;
            withVencord = true;
          };
        })
        # Below are for offline build
        (python3.withPackages (
          ps: with ps; [
            iniparse
            markdown-it-py
            mdit-py-plugins
            mdurl
            python-dateutil
            remarshal
            rich
            rich-argparse
            tomli
            tomlkit
            u-msgpack-python
          ]
        ))
      ]
      ++ [
        #waywallen
        #open-wallpaper-engine
      ]
      ++ processedResults;
  };

}
