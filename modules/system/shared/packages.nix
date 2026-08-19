{
  pkgs,
  lib,
  inputs,
  mkSandbox,
  listFiles,
  config,
  user,
  ...
}:
let
  # ---------------------------------------------------------------------------
  # Helper & Evaluation Utilities
  # ---------------------------------------------------------------------------
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

  stripExtension =
    filename:
    let
      matchResult = builtins.match "(.*)\\.[^.]*" filename;
    in
    if matchResult == null then filename else builtins.head matchResult;

  getExtension =
    filename:
    let
      matchResult = builtins.match ".*\\.([^.]*)" filename;
    in
    if matchResult == null then "" else builtins.head matchResult;

  # ---------------------------------------------------------------------------
  # Dependency Fetching & CMake Helpers
  # ---------------------------------------------------------------------------
  fetchDepsFromJSON =
    srcPath:
    let
      depsFile = srcPath + "/deps.json";
      depsList =
        if builtins.pathExists depsFile then builtins.fromJSON (builtins.readFile depsFile) else [ ];

      isCorrectArch =
        dep:
        if !(dep ? "only-arches") then
          true
        else
          builtins.elem (builtins.head (
            lib.splitString "-" pkgs.stdenv.hostPlatform.system
          )) dep."only-arches";

      filteredDepsList = builtins.filter isCorrectArch depsList;

      fetchDep = dep: {
        name = dep.x-cmake.name;
        value =
          if dep.type or "" == "git" then
            if dep ? hash || dep ? sha256 then
              pkgs.fetchgit {
                url = dep.url;
                rev = dep.commit;
                fetchLFS = (dep.x-cmake.name or "") == "qml_material";
                deepClone = false;
                hash = dep.hash or dep.sha256;
              }
            else
              # Fallback to builtins.fetchGit if hash is not present in deps.json
              fetchGit {
                shallow = true;
                url = dep.url;
                rev = dep.commit;
                lfs = (dep.x-cmake.name or "") == "qml_material";
              }
          else if dep.type or "" == "archive" || dep.type or "" == "file" then
            let
              sha256Val =
                if
                  dep.url
                  == "https://github.com/KhronosGroup/SPIRV-Reflect/archive/refs/tags/vulkan-sdk-1.4.321.0.tar.gz"
                then
                  "0c62j4hpaw5grxf4winpgs8ri68fxa59ah63aa7phra3fn82zs64"
                else if
                  dep.url
                  == "https://cef-builds.spotifycdn.com/cef_binary_149.0.4%2Bg2f1bfd8%2Bchromium-149.0.7827.156_linux64_minimal.tar.bz2"
                then
                  "056abl41zbh4wdh7cf5pg9v3hx5w1n39daavkymg887623qajh8i"
                else
                  dep.sha256 or dep.hash;
            in
            pkgs.fetchzip {
              url = dep.url;
              sha256 = sha256Val;
            }
          else
            throw "Unsupported dependency type: ${dep.type or "unknown"}";
      };
    in
    builtins.listToAttrs (map fetchDep filteredDepsList);

  # Helper to dynamically generate -DFETCHCONTENT_SOURCE_DIR_<UPPER_NAME>=<path>
  # Accepts an optional set of overrides for paths patched in build phases (e.g. /build/rstd)
  mkFetchContentFlags =
    deps: overrides:
    lib.mapAttrsToList (
      name: drv:
      let
        upperName = lib.toUpper name;
        path = overrides.${name} or overrides.${upperName} or drv;
      in
      "-DFETCHCONTENT_SOURCE_DIR_${upperName}=${path}"
    ) deps;

  mkPyApp =
    {
      name,
      src,
      pathDeps ? [ ],
    }:
    pkgs.stdenv.mkDerivation {
      pname = name;
      version = "1.0";
      src = if builtins.isPath src then src else pkgs.writeText "${name}-src" src;
      dontUnpack = true;

      nativeBuildInputs = [
        pkgs.wrapGAppsHook3
        pkgs.gobject-introspection
      ];
      buildInputs = [
        pkgs.gtk3
        pkgs.gsettings-desktop-schemas
        pkgs.adwaita-icon-theme
      ];

      pythonEnv = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);

      installPhase = ''
        mkdir -p $out/bin
        echo "#!$pythonEnv/bin/python" > $out/bin/${name}
        cat $src >> $out/bin/${name}
        chmod +x $out/bin/${name}
      '';

      preFixup = ''
        gappsWrapperArgs+=(
          --prefix PATH : "${lib.makeBinPath pathDeps}"
        )
      '';
    };

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
  # Priority Whitelist Rules
  # ---------------------------------------------------------------------------
  # Only packages in this list retain custom priorities; all others are normalized to 5
  priorityWhitelist = [
    pkgs.clang
    pkgs.procps
    pkgs.util-linux
    pkgs.systemd
  ];

  whitelistedNames = map (
    p: if builtins.isString p then p else p.pname or p.name or ""
  ) priorityWhitelist;

  # ---------------------------------------------------------------------------
  # Complex Custom Derivations & Hardware Tools
  # ---------------------------------------------------------------------------
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

  proton-ge-10 = pkgs.stdenv.mkDerivation (finalAttrs: {
    name = "proton-ge";
    version = "10-34";
    phases = [ "installPhase" ];
    src = pkgs.fetchurl {
      url = "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton${finalAttrs.version}/GE-Proton${finalAttrs.version}.tar.gz";
      hash = "sha256-UcWAtmqDPHOZj+APBxfurFcZdlQECi8u1RiePuaNdz0=";
    };
    installPhase = ''
      mkdir -p "$out"
      tar -C "$out" --strip-components=1 -xf "$src"
    '';
  });

  proton-umu-10 = pkgs.stdenv.mkDerivation (finalAttrs: {
    name = "proton-umu";
    version = "10.0-4";
    phases = [ "installPhase" ];
    src = pkgs.fetchurl {
      url = "https://github.com/Open-Wine-Components/umu-proton/releases/download/UMU-Proton-${finalAttrs.version}/UMU-Proton-${finalAttrs.version}.tar.gz";
      hash = "sha256-YumeApoY+jE+b6Y9QjkJGBAXMKlA40kcVNnVjKuIfGk=";
    };
    installPhase = ''
      mkdir -p "$out"
      tar -C "$out" --strip-components=1 -xf "$src"
    '';
  });

  proton-umu-9 = pkgs.stdenv.mkDerivation (finalAttrs: {
    name = "proton-umu";
    version = "9.0-4e";
    phases = [ "installPhase" ];
    src = pkgs.fetchurl {
      url = "https://github.com/Open-Wine-Components/umu-proton/releases/download/UMU-Proton-${finalAttrs.version}/UMU-Proton-${finalAttrs.version}.tar.gz";
      hash = "sha256-1TYX073YlPTVyP1D6Cf/+7zbtJv0c9f7O+JhjdRx6/M=";
    };
    installPhase = ''
      mkdir -p "$out"
      tar -C "$out" --strip-components=1 -xf "$src"
    '';
  });

  proton-umu-8 = pkgs.stdenv.mkDerivation (finalAttrs: {
    name = "proton-umu";
    version = "8.0-5-3";
    phases = [ "installPhase" ];
    src = pkgs.fetchurl {
      url = "https://github.com/Open-Wine-Components/umu-proton/releases/download/ULWGL-Proton-${finalAttrs.version}/ULWGL-Proton-${finalAttrs.version}.tar.gz";
      hash = "sha256-JmBo/hk5pBnzi3JrRkv9WlEoCPYpe9AWs7Mcns7j0bA=";
    };
    installPhase = ''
      mkdir -p "$out"
      tar -C "$out" --strip-components=1 -xf "$src"
    '';
  });

  steamrt4_data = builtins.fromJSON (builtins.readFile ../../../stuff/steamrt4.json);
  steamrt3_data = builtins.fromJSON (builtins.readFile ../../../stuff/steamrt3.json);

  steamrt3 = pkgs.stdenv.mkDerivation {
    name = "steamrt3";
    version = steamrt3_data.version;
    phases = [ "installPhase" ];
    src = pkgs.fetchurl {
      url = "https://repo.steampowered.com/steamrt3/images/${steamrt3_data.version}/SteamLinuxRuntime_sniper.tar.xz";
      hash = steamrt3_data.hash;
    };
    installPhase = ''
      mkdir -p "$out"
      cd "$out"
      tar -C . --strip-components=1 -xf "$src"
      ln -s "_v2-entry-point" "umu"
      echo "ok" > ".installed.ok"
    '';
  };

  steamrt4 = pkgs.stdenv.mkDerivation {
    name = "steamrt4";
    version = steamrt4_data.version;
    phases = [ "installPhase" ];
    src = pkgs.fetchurl {
      url = "https://repo.steampowered.com/steamrt4/images/${steamrt4_data.version}/SteamLinuxRuntime_4.tar.xz";
      hash = steamrt4_data.hash;
    };
    installPhase = ''
      mkdir -p "$out"
      cd "$out"
      tar -C . --strip-components=1 -xf "$src"
      ln -s "_v2-entry-point" "umu"
      echo "ok" > ".installed.ok"
    '';
  };

  runtime = pkgs.stdenv.mkDerivation {
    name = "umu-runtime.img";
    version = steamrt4_data.version;
    nativeBuildInputs = [ pkgs.erofs-utils ];
    phases = [ "installPhase" ];
    installPhase = ''
      mkdir -p build/proton
      cp -aL "${steamrt3}" build/steamrt3
      cp -aL "${steamrt4}" build/steamrt4
      cp -aL "${proton-ge-10}" build/proton/proton-ge-10
      cp -aL "${proton-umu-10}" build/proton/proton-umu-10
      cp -aL "${proton-umu-9}" build/proton/proton-umu-9
      cp -aL "${proton-umu-8}" build/proton/proton-umu-8
      cp -aL "${pkgs.proton-ge-bin.steamcompattool}" build/proton/proton-ge-latest

      # Adds write permissions to all files & dirs to satisfy pressure-vessel
      chmod -R u+w build

      mkfs.erofs \
        --force-uid=0 \
        --force-gid=0 \
        --workers "$NIX_BUILD_CORES" \
        --ignore-mtime \
        --zD=1 \
        -z zstd,19 \
        -C 65536 \
        -m 65536:zstd,19 \
        -E 48bit,all-fragments,dot-omitted,fragdedupe=inode \
        -T 0 \
        -x -1 \
        "$out" \
        build
    '';
  };

  prepare-umu-src = pkgs.writeText "prepare-umu.c" (evalAndSubstitute {
    string = builtins.readFile ../../../stuff/prepare_umu.c;
    scope = { inherit pkgs runtime; };
  });

  prepare-umu-bin = pkgs.stdenv.mkDerivation {
    pname = "prepare-umu";
    version = "1.0";
    src = prepare-umu-src;
    dontUnpack = true;
    buildPhase = ''
      gcc -O2 -Wall $src -o prepare-umu
    '';
    installPhase = ''
      mkdir -p $out/bin
      install -m 0755 prepare-umu $out/bin/prepare-umu
    '';
  };

  nv-blindfold-pkg = pkgs.stdenv.mkDerivation {
    name = "nv-blindfold";
    src = pkgs.writeText "nv-blindfold.c" (builtins.readFile ../../../stuff/nv-blindfold.c);
    unpackPhase = "true";
    buildPhase = ''
      gcc -O2 $src -o nv-blindfold
    '';
    installPhase = ''
      mkdir -p $out/bin
      cp nv-blindfold $out/bin/
    '';
  };

  fan-control-pkg = pkgs.stdenv.mkDerivation {
    name = "fan-control";
    src = pkgs.writeText "fan-control.c" (builtins.readFile ../../../stuff/fan-control.c);
    unpackPhase = "true";
    buildPhase = "gcc -O2 $src -o fan-control";
    installPhase = "mkdir -p $out/bin && cp fan-control $out/bin/";
  };

  gigabyte-laptop-wmi = pkgs.stdenv.mkDerivation {
    pname = "aorus-laptop";
    version = inputs.gigabyte-laptop-wmi.shortRev;

    src = inputs.gigabyte-laptop-wmi;

    makeFlags = [
      "KDIR=${config.boot.kernelPackages.kernel.dev}/lib/modules/${config.boot.kernelPackages.kernel.modDirVersion}/build"
    ];

    installPhase = ''
      dir=$out/lib/modules/${config.boot.kernelPackages.kernel.modDirVersion}/kernel/drivers/platform/x86
      mkdir -p $dir
      cp aorus-laptop.ko $dir/
    '';
  };

  anicli-ru =
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

  waywallenDeps = fetchDepsFromJSON inputs.waywallen;
  oweDeps = fetchDepsFromJSON inputs.open-wallpaper-engine;

  waywallen-layer-shell = pkgs.rustPlatform.buildRustPackage rec {
    pname = "waywallen-layer-shell";
    version = src.shortRev;

    src = inputs.waywallen-display;

    cargoLock.lockFile = "${inputs.waywallen-display}/Cargo.lock";

    nativeBuildInputs = [
      pkgs.pkg-config
      pkgs.makeWrapper
    ];

    buildInputs = [
      pkgs.wayland
      pkgs.libxkbcommon
      pkgs.libGL
      pkgs.vulkan-loader
    ];

    postFixup = ''
      wrapProgram $out/bin/waywallen-layer-shell \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ pkgs.vulkan-loader ]}
    '';
  };

  waywallen = pkgs.clangStdenv.mkDerivation rec {
    pname = "waywallen";
    version = src.shortRev;

    src = inputs.waywallen;

    patches = [ "${inputs.waywallen-aur}/0001-use-system-deps.diff" ];

    hardeningDisable = [ "fortify" ];

    cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
      inherit src;
      name = "${pname}-${version}-vendor";
      hash = "sha256-M6LQixcLvub3QpFPrYS5Cc63AYQ7xLJoMvpuhKonbT4=";
    };

    nativeBuildInputs = [
      pkgs.cmake
      pkgs.ninja
      pkgs.lld
      pkgs.grpc
      pkgs.protobuf
      pkgs.rustPlatform.cargoSetupHook
      pkgs.cargo
      pkgs.rustc
      pkgs.pkg-config
      pkgs.qt6.wrapQtAppsHook
      pkgs.glslang
    ];

    buildInputs = [
      pkgs.ffmpeg
      pkgs.grpc
      pkgs.protobuf
      pkgs.pulseaudio
      (pkgs.curl.override { websocketSupport = true; })
      pkgs.mesa
      pkgs.libgbm
      pkgs.sqlite
      pkgs.vulkan-loader
      pkgs.qt6.qtbase
      pkgs.qt6.qtdeclarative
      pkgs.qt6.qtgrpc
      pkgs.qt6.qtwebsockets
      pkgs.pipewire
      pkgs.asio
      pkgs.pegtl
      pkgs.corrosion
      pkgs.nlohmann_json
      pkgs.hicolor-icon-theme
    ];

    cmakeFlags = [
      "-DCMAKE_C_COMPILER=clang"
      "-DCMAKE_CXX_COMPILER=clang++"
      "-DCMAKE_LINKER_TYPE=LLD"
      "-DFETCHCONTENT_FULLY_DISCONNECTED=ON"
      "-DCMAKE_MODULE_PATH=${pkgs.qt6.qtgrpc}/lib/cmake/Qt6"
      "-DWAYWALLEN_BUILD_MPV_PLUGIN=OFF"
      "-DWAYWALLEN_CARGO_OFFLINE=ON"
      "-DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON"
      "-DQML_MATERIAL_BUILD_TYPE=STATIC"
    ]
    ++ (mkFetchContentFlags waywallenDeps {
      rstd = "/build/rstd";
      qextra = "/build/qextra";
      qml_material = "/build/qml_material";
    });

    qtWrapperArgs = [
      "--prefix QML2_IMPORT_PATH : $out/lib/qt6/qml"
    ];

    postPatch = ''
      substituteInPlace CMakeLists.txt \
        --replace-fail "set(CMAKE_INSTALL_RPATH_USE_LINK_PATH FALSE)" "" \
        --replace-fail "set(CMAKE_BUILD_WITH_INSTALL_RPATH FALSE)" ""

      substituteInPlace ui/CMakeLists.txt \
        --replace-fail 'INSTALL_RPATH "''${WAYWALLEN_BIN_RPATH}"' "CXX_SCAN_FOR_MODULES ON" \
        --replace-fail "set(QT_QML_GENERATE_QMLLS_INI ON)" "set(QT_QML_GENERATE_QMLLS_INI OFF)"

      substituteInPlace plugins/org.waywallen.image/CMakeLists.txt \
        --replace-fail 'INSTALL_RPATH "''${WAYWALLEN_BIN_RPATH}"' "POSITION_INDEPENDENT_CODE ON"

      substituteInPlace plugins/org.waywallen.video/CMakeLists.txt \
        --replace-fail 'INSTALL_RPATH "''${WAYWALLEN_BIN_RPATH}"' "POSITION_INDEPENDENT_CODE ON"
    '';

    preConfigure = ''
      sed -i '1s|^|#include <cstdlib>\n#include <cmath>\n#include <string>\n#include <string_view>\n|' plugins/org.waywallen.video/src/main.cpp
      sed -i '1s|^|#include <cstdlib>\n#include <cmath>\n#include <string>\n#include <string_view>\n|' plugins/org.waywallen.image/src/main.cpp

      cp -r ${waywallenDeps.rstd} /build/rstd
      chmod -R +w /build/rstd
      sed -i '/export using std::make_shared;/d' /build/rstd/src/cppstd/cppstd.cppm
      sed -i '/export using std::allocate_shared;/d' /build/rstd/src/cppstd/cppstd.cppm

      sed -i '/export using std::operator==;/d' /build/rstd/src/cppstd/cppstd.cppm
      sed -i '/export using std::operator!=;/d' /build/rstd/src/cppstd/cppstd.cppm
      sed -i '/export using std::operator</d' /build/rstd/src/cppstd/cppstd.cppm
      sed -i '/export using std::operator>/d' /build/rstd/src/cppstd/cppstd.cppm

      substituteInPlace /build/rstd/src/core/include/rstd/macro.hpp \
        --replace-fail "requires rstd::Impled<Self, rstd::cmp::PartialEq<_USE_TRAIT_T>>" "requires true"

      cp -r ${waywallenDeps.qml_material} /build/qml_material
      chmod -R +w /build/qml_material

      cp -r ${waywallenDeps.QExtra} /build/qextra
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

    postBuild = ''
      unset C_INCLUDE_PATH
      unset CPLUS_INCLUDE_PATH
    '';

    postInstall = ''
      ln -s ${waywallen-layer-shell}/bin/waywallen-layer-shell $out/bin/waywallen-layer-shell

      patchelf --add-rpath "$out/lib:${
        lib.makeLibraryPath [
          pkgs.qt6.qtgrpc
          pkgs.qt6.qtbase
          pkgs.qt6.qtdeclarative
          pkgs.qt6.qtwebsockets
          (pkgs.curl.override { websocketSupport = true; })
          pkgs.ffmpeg
          pkgs.vulkan-loader
          pkgs.pipewire
          pkgs.pulseaudio
          pkgs.libgbm
          pkgs.stdenv.cc.cc.lib
        ]
      }" $out/bin/waywallen-ui

      for bin in $out/bin/waywallen-image-renderer $out/bin/waywallen-video-renderer; do
        if [ -f "$bin" ]; then
          patchelf --add-rpath "$out/lib:${
            lib.makeLibraryPath [
              pkgs.ffmpeg
              pkgs.vulkan-loader
              pkgs.pipewire
              pkgs.pulseaudio
              (pkgs.curl.override { websocketSupport = true; })
              pkgs.libgbm
              pkgs.stdenv.cc.cc.lib
            ]
          }" "$bin"
        fi
      done

      for lib_file in $out/lib/*.so*; do
        if [ -f "$lib_file" ] && [ ! -L "$lib_file" ]; then
          patchelf --add-rpath "${
            lib.makeLibraryPath [
              pkgs.ffmpeg
              pkgs.vulkan-loader
              pkgs.pipewire
              pkgs.pulseaudio
              (pkgs.curl.override { websocketSupport = true; })
              pkgs.libgbm
              pkgs.stdenv.cc.cc.lib
            ]
          }" "$lib_file"
        fi
      done
    '';
  };

  open-wallpaper-engine = pkgs.clangStdenv.mkDerivation rec {
    pname = "open-wallpaper-engine";
    version = src.shortRev;

    src = inputs.open-wallpaper-engine;

    patches = [ ];

    nativeBuildInputs = [
      pkgs.cmake
      pkgs.ninja
      pkgs.lld
      pkgs.pkg-config
      pkgs.file
      pkgs.glslang
      pkgs.removeReferencesTo
      pkgs.addDriverRunpath
    ];

    buildInputs = [
      waywallen
      pkgs.libpulseaudio
      pkgs.lz4
      pkgs.freetype
      pkgs.ffmpeg
      pkgs.vulkan-loader
      pkgs.vulkan-headers
      pkgs.fontconfig
      pkgs.glfw
      pkgs.nlohmann_json
      pkgs.libgbm
      pkgs.glslang
      pkgs.quickjs-ng
      pkgs.argparse
      pkgs.eigen
      pkgs.alsa-lib
      pkgs.gtk3
      pkgs.nss
      pkgs.nspr
      pkgs.libxkbcommon
      pkgs.wayland
      pkgs.libx11
      pkgs.libxcomposite
      pkgs.libxdamage
      pkgs.libxext
      pkgs.libxfixes
      pkgs.libxrandr
      pkgs.libxrender
      pkgs.libxscrnsaver
      pkgs.libxcb
      pkgs.glib
      pkgs.atk
      pkgs.at-spi2-atk
      pkgs.cairo
      pkgs.gdk-pixbuf
      pkgs.pango
      pkgs.dbus
      pkgs.expat
      pkgs.cups
      pkgs.udev
      pkgs.at-spi2-core
    ];

    cmakeFlags = [
      "-DCMAKE_C_COMPILER=clang"
      "-DCMAKE_CXX_COMPILER=clang++"
      "-DCMAKE_LINKER_TYPE=LLD"
      "-DFETCHCONTENT_FULLY_DISCONNECTED=ON"
      "-DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON"
    ]
    ++ (mkFetchContentFlags oweDeps {
      rstd = "/build/rstd";
    });

    hardeningDisable = [ "fortify" ];

    postPatch = ''
      substituteInPlace CMakeLists.txt \
        --replace-fail 'if(CMAKE_VERSION VERSION_LESS_EQUAL "4.3.0")' 'if(FALSE)'

      find src waywallen viewer -type f \( -name "*.cpp" -o -name "*.cppm" -o -name "*.hpp" -o -name "*.h" \) | while read -r file; do
        if grep -q -E '^[[:space:]]*module;$' "$file"; then
          substituteInPlace "$file" --replace-fail "module;" $'module;\n#include <memory>\n#include <algorithm>'
        elif grep -q -E '^[[:space:]]*(export[[:space:]]+)?module[[:space:]]+[a-zA-Z0-9_.:]+;' "$file"; then
          sed -i '1s|^|module;\n#include <memory>\n#include <algorithm>\n|' "$file"
        else
          sed -i '1s|^|#include <memory>\n#include <algorithm>\n|' "$file"
        fi
      done
    '';

    preConfigure = ''
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

      declare -a std_paths
      while read -r line; do
        clean_path=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -d "$clean_path" ]; then
          std_paths+=("$clean_path")
        fi
      done < <(clang++ -v -E -x c++ - < /dev/null 2>&1 | sed -n '/#include <...>/,/End of search list./p' | grep -v '#include' | grep -v 'End of search list')

      IFS=: eval 'inc_paths_str="''${inc_paths[*]}"'
      IFS=: eval 'std_paths_str="''${std_paths[*]}"'

      export C_INCLUDE_PATH="$inc_paths_str:$C_INCLUDE_PATH"
      export CPLUS_INCLUDE_PATH="$inc_paths_str:$std_paths_str:$CPLUS_INCLUDE_PATH"

      cp -r ${oweDeps.rstd} /build/rstd
      chmod -R +w /build/rstd
      sed -i '/export using std::make_shared;/d' /build/rstd/src/cppstd/cppstd.cppm
      sed -i '/export using std::allocate_shared;/d' /build/rstd/src/cppstd/cppstd.cppm

      sed -i '/export using std::copy;/d' /build/rstd/src/cppstd/cppstd.cppm
      sed -i '/export using std::find;/d' /build/rstd/src/cppstd/cppstd.cppm
      sed -i '/export using std::advance;/d' /build/rstd/src/cppstd/cppstd.cppm

      substituteInPlace /build/rstd/src/core/include/rstd/macro.hpp \
        --replace-fail "requires rstd::Impled<Self, rstd::cmp::PartialEq<_USE_TRAIT_T>>" "requires true"
    '';

    postBuild = ''
      unset C_INCLUDE_PATH
      unset CPLUS_INCLUDE_PATH
    '';

    postInstall = ''
      patchelf --set-rpath "$out/lib:${waywallen}/lib:${
        lib.makeLibraryPath [
          pkgs.vulkan-loader
          pkgs.ffmpeg
          pkgs.libgbm
          pkgs.freetype
          pkgs.fontconfig
          pkgs.glfw
          pkgs.libpulseaudio
          pkgs.lz4
          pkgs.stdenv.cc.cc.lib
        ]
      }" $out/bin/waywallen-wescene-renderer

      for bin in $(find $out/bin/weweb -type f 2>/dev/null || true); do
        if [ -f "$bin" ] && (file "$bin" | grep -q "ELF"); then
          patchelf --set-rpath "${
            lib.makeLibraryPath [
              pkgs.vulkan-loader
              pkgs.ffmpeg
              pkgs.libgbm
              pkgs.freetype
              pkgs.fontconfig
              pkgs.glfw
              pkgs.libpulseaudio
              pkgs.lz4
              pkgs.alsa-lib
              pkgs.gtk3
              pkgs.nss
              pkgs.nspr
              pkgs.libxkbcommon
              pkgs.wayland
              pkgs.libx11
              pkgs.libxcomposite
              pkgs.libxdamage
              pkgs.libxext
              pkgs.libxfixes
              pkgs.libxrandr
              pkgs.libxrender
              pkgs.libxscrnsaver
              pkgs.libxcb
              pkgs.stdenv.cc.cc.lib
              pkgs.glib
              pkgs.atk
              pkgs.at-spi2-atk
              pkgs.cairo
              pkgs.gdk-pixbuf
              pkgs.pango
              pkgs.dbus
              pkgs.expat
              pkgs.cups
              pkgs.udev
              pkgs.at-spi2-core
            ]
          }:$out/bin/weweb:$out/lib:${waywallen}/lib" "$bin"
        fi
      done

      for bin in $out/bin/waywallen-wescene-renderer $(find $out/bin/weweb -type f 2>/dev/null || true); do
        if [ -f "$bin" ] && (file "$bin" | grep -q "ELF"); then
          addDriverRunpath "$bin"
          remove-references-to -t ${src} "$bin"
          for src_path in ${builtins.concatStringsSep " " (builtins.attrValues oweDeps)}; do
            remove-references-to -t "$src_path" "$bin"
          done
        fi
      done
    '';
  };

  # ---------------------------------------------------------------------------
  # Dynamic Script Handler Processing
  # ---------------------------------------------------------------------------
  listDirs = listFiles;
  targetDirs = [ ../../../stuff/scripts ];
  excludeList = [
    "translate-zapret-nixos.sh"
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
    rs =
      path:
      pkgs.pkgsStatic.stdenv.mkDerivation rec {
        pname = "${stripExtension (baseNameOf path)}";
        name = pname;
        dontUnpack = true;

        nativeBuildInputs = [
          pkgs.pkgsStatic.rustc
          pkgs.pkgsStatic.stdenv.cc
        ];

        buildPhase = ''
          rustc --target x86_64-unknown-linux-musl \
            -C target-feature=+crt-static \
            -C linker=$CC \
            -C opt-level=s \
            -C lto=fat \
            -C codegen-units=1 \
            -C panic=abort \
            -C strip=symbols \
            -O ${path} -o ${pname}
        '';

        installPhase = ''
          mkdir -p $out/bin
          install -m 0755 ${pname} $out/bin/${pname}
        '';
      };
  };

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

  # ---------------------------------------------------------------------------
  # Individual Package Overrides & Apps
  # ---------------------------------------------------------------------------
  rustHelpersPkg = inputs.rust-helpers.packages.${pkgs.stdenv.hostPlatform.system}.default;

  json2xPkg = pkgs.callPackage "${inputs.nixpkgs}/pkgs/pkgs-lib/formats/json2x/package.nix" { };

  app2unitPkg = pkgs.app2unit.overrideAttrs (oldAttrs: {
    postPatch = (oldAttrs.postPatch or "") + ''
      echo "app2unit(1)" > app2unit.1.scd
    '';
  });

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

  diskoPkg = inputs.disko.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
    path = inputs.nixpkgs;
  };

  nixSearchPkg = inputs.nix-search.packages.${pkgs.stdenv.hostPlatform.system}.default;

  heliumPkg = inputs.helium.packages.${pkgs.stdenv.hostPlatform.system}.default;

  translateZapretNixosPkg = pkgs.writeShellScriptBin "translate-zapret-nixos" (
    builtins.readFile ../../../stuff/scripts/translate-zapret-nixos.sh
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
          bind.ro = [ (sloth.concat' (sloth.env "XDG_CONFIG_HOME") "/Vencord") ];
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
  # Main Package List
  # ---------------------------------------------------------------------------
  package-list = [
    pkgs.gcc
    pkgs.libcap-text-verifier
    pkgs.curl
    pkgs.stdenvNoCC
    pkgs.libxkbcommon
    pkgs.stdenv
    pkgs.gawk
    pkgs.sbsigntool
    pkgs.wl-clip-persist
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
    pkgs.zfs
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
    pkgs.bash
    pkgs.bash-language-server
    pkgs.vscode-langservers-extracted
    pkgs.inotify-tools
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
    pkgs.findutils
    pkgs.patchelf
    pkgs.file
    pkgs.mpv
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
    pkgs.wget
    pkgs.zenity
    pkgs.procps
    pkgs.util-linux
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
    pkgs.wl-clipboard
    pkgs.networkmanager_dmenu
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
    pkgs.mindustry
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
    pkgs.localsearch
    pkgs.tinysparql
    pkgs.go
    pkgs.nix-diff
    pkgs.migrate-to-uv
    pkgs.ssdeep
    pkgs.gtk3
    pkgs.kdePackages.kservice
    pkgs.rofi-bluetooth
    pkgs.tesseract
    pkgs.imagemagick
    pkgs.libsForQt5.qtsvg
    pkgs.kdePackages.qtsvg
    pkgs.kdePackages.dolphin
    pkgs.kdePackages.ark
    pkgs.pulseaudio
    pkgs.hyprshot
    pkgs.nautilus
    pkgs.file-roller
    pkgs.cliphist
    pkgs.libnotify
    pkgs.brightnessctl
    pkgs.qimgv
    pkgs.myxer
    pkgs.ffmpeg-full
    pkgs.gpu-screen-recorder
    pkgs.ffmpegthumbnailer
    pkgs.hyprpicker
    pkgs.wttrbar
    pkgs.makeWrapper
    pkgs.makeBinaryWrapper
    pkgs.dieHook
    pkgs.shellcheck.doc
    pkgs.python3Packages.xmltodict
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
    rustdeskSandbox
    prismLauncherSandbox
    discordCanarySandbox
    ayugramDesktopSandbox
    #waywallen
    #open-wallpaper-engine
    anicli-ru
  ]
  ++ processedResults;

  extra-paths = [
    "/share/waywallen"
    "/share/zsh"
    "/share/xdg-desktop-portal"
    "/share/applications"
  ];
in
{
  nixpkgs.config.permittedInsecurePackages = [
    ventoyFullGtkPkg.name
  ];

  _module.args = {
    inherit evalAndSubstitute mkPyApp;
  };

  home-manager.sharedModules = [
    {
      _module.args = { inherit evalAndSubstitute mkPyApp; };
      home.extraOutputsToInstall = extra-paths;
      dbus.packages = [
        pkgs.localsearch
        pkgs.tinysparql
      ];
      systemd.user.packages = [
        pkgs.localsearch
        pkgs.tinysparql
      ];
    }
  ];

  # Direct override of system.path with priority normalization and collision checking
  system.path = lib.mkForce (
    pkgs.buildEnv {
      name = "system-path";
      paths = map (
        p:
        if !(builtins.isAttrs p) then
          p
        else if
          (builtins.elem (p.pname or "") whitelistedNames) || (builtins.elem (p.name or "") whitelistedNames)
        then
          p
        else
          lib.setPrio 5 p
      ) config.environment.systemPackages;
      inherit (config.environment) pathsToLink extraOutputsToInstall;
      ignoreCollisions = false;
      postBuild = ''
        # Remove wrapped binaries, they shouldn't be accessible via PATH.
        find $out/bin -maxdepth 1 -name ".*-wrapped" -type l -delete
        find $out/bin -maxdepth 1 -name ".*-wrapped_*" -type l -delete

        if [ -x $out/bin/glib-compile-schemas -a -w $out/share/glib-2.0/schemas ]; then
            $out/bin/glib-compile-schemas $out/share/glib-2.0/schemas
        fi

        ${config.environment.extraSetup}
      '';
    }
  );

  environment = {
    defaultPackages = [ ];
    pathsToLink = extra-paths;
    systemPackages =
      package-list ++ [ aero-control-center ] ++ config.home-manager.users.${user}.home.packages;
  };

  boot.extraModulePackages = [
    gigabyte-laptop-wmi
  ];

  services.udev.packages = [
    aero-control-center
  ];

  systemd.services.load-aorus-laptop = {
    description = "Load Gigabyte Aorus Laptop driver asynchronously";
    after = [ "basic.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.kmod}/bin/modprobe aorus_laptop";
      RemainAfterExit = true;
    };
  };

  security.wrappers = {
    ryzenadj = {
      owner = "root";
      group = "root";
      source = "${pkgs.ryzenadj}/bin/ryzenadj";
      setuid = true;
    };
    prepare-umu = {
      owner = "root";
      group = "root";
      source = "${prepare-umu-bin}/bin/prepare-umu";
      setuid = true;
    };
    nv-blindfold = {
      setuid = true;
      owner = "root";
      group = "root";
      source = "${nv-blindfold-pkg}/bin/nv-blindfold";
    };
    fan-control = {
      setuid = true;
      owner = "root";
      group = "root";
      source = "${fan-control-pkg}/bin/fan-control";
    };
  };
}
