{
  pkgs,
  lib,
  inputs,
  mkSandbox,
  listFiles,
  ...
}:
let
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
        ungoogled-chromium
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
        quickshell.packages.${system}.default
        nix-alien.packages.${system}.nix-alien
        nix-search.packages.${system}.default
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
      ++ processedResults;
  };

}
