{
  pkgs,
  lib,
  inputs,
  mkSandbox,
  listFiles,
  config,
  ...
}:
let
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
    pkgs.symlinkJoin {
      name = "anicli-ru-${anicliPkg.version or "latest"}";
      paths = [ venv ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        rm $out/bin/anicli-ru
        makeWrapper ${venv}/bin/anicli-ru $out/bin/anicli-ru \
          --prefix PATH : ${
            lib.makeBinPath [
              pkgs.mpv
            ]
          }
      '';
    };
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
            fetchGit {
              shallow = true;
              url = dep.url;
              rev = dep.commit;
              lfs = dep.x-cmake.name == "qml_material";
            }
          else if dep.type or "" == "archive" || dep.type or "" == "file" then
            fetchTarball {
              url = dep.url;
              sha256 =
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
                  dep.sha256;
            }
          else
            throw "Unsupported dependency type: ${dep.type or "unknown"}";
      };
    in
    builtins.listToAttrs (map fetchDep filteredDepsList);

  # Dynamically evaluate the correct dependency trees
  waywallenDeps = fetchDepsFromJSON inputs.waywallen;
  oweDeps = fetchDepsFromJSON inputs.open-wallpaper-engine;
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
  proton-umu-10 = pkgs.stdenv.mkDerivation (finalAttrs: {
    name = "proton-umu-10";
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
    buildInputs = [ pkgs.erofs-utils ];
    phases = [ "installPhase" ];
    installPhase = ''
      mkdir build
      cd build
      ln -s ${steamrt3} steamrt3
      ln -s ${steamrt4} steamrt4
      mkdir proton
      ln -s ${proton-umu-10} proton/proton-umu-10
      ln -s ${proton-umu-9} proton/proton-umu-9
      ln -s ${proton-umu-8} proton/proton-umu-8
      ln -s ${pkgs.proton-ge-bin.steamcompattool} proton/proton-ge-latest
      tar -chf - --mode='u+w' . | mkfs.erofs \
      --force-uid=0 \
      --force-gid=0 \
      -z zstd,3 \
      -C 65536 \
      -E dedupe,all-fragments,fragdedupe=full,dot-omitted,force-inode-compact \
      -T 0 \
      --ignore-mtime \
      -m 65536:zstd,3 \
      --zD \
      --tar=f \
      "$out" \
      /dev/stdin
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
  mkPyApp =
    {
      name,
      src,
      pathDeps ? [ ],
    }:
    pkgs.stdenv.mkDerivation {
      pname = name;
      version = "1.0";
      src = pkgs.writeText "${name}-src" src;
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
  waywallen-layer-shell = pkgs.rustPlatform.buildRustPackage rec {
    pname = "waywallen-layer-shell";
    version = src.shortRev;

    src = inputs.waywallen-display;

    cargoLock.lockFile = "${inputs.waywallen-display}/Cargo.lock";

    nativeBuildInputs = with pkgs; [
      pkg-config
      makeWrapper
    ];

    buildInputs = with pkgs; [
      wayland
      libxkbcommon
      libGL
      vulkan-loader
    ];

    # Prepend vulkan-loader to LD_LIBRARY_PATH so dlopen can find libvulkan.so.1
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
      hash = "sha256-AM+dd/4OJ7iRjM7XpdoQZS/xLSLA7/URff2A+eULXXM=";
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
      (curl.override { websocketSupport = true; })
      mesa
      libgbm
      sqlite
      vulkan-loader
      qt6.qtbase
      qt6.qtdeclarative
      qt6.qtgrpc
      qt6.qtwebsockets
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
      "-DFETCHCONTENT_SOURCE_DIR_RSTD=/build/rstd" # Point to the patched, writable copy
      "-DFETCHCONTENT_SOURCE_DIR_QEXTRA=/build/qextra"
      "-DFETCHCONTENT_SOURCE_DIR_QML_MATERIAL=/build/qml_material"
      "-DFETCHCONTENT_SOURCE_DIR_NCREQUEST=${waywallenDeps.ncrequest}"
      "-DFETCHCONTENT_SOURCE_DIR_WAVSEN=${waywallenDeps.wavsen}"
      "-DCMAKE_MODULE_PATH=${pkgs.qt6.qtgrpc}/lib/cmake/Qt6"
      "-DWAYWALLEN_BUILD_MPV_PLUGIN=OFF"
      "-DWAYWALLEN_CARGO_OFFLINE=ON"
      "-DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON"
      "-DQML_MATERIAL_BUILD_TYPE=STATIC"
    ];

    qtWrapperArgs = [
      "--prefix QML2_IMPORT_PATH : $out/lib/qt6/qml"
    ];

    postPatch = ''
      # Remove CMAKE_INSTALL_RPATH overrides that strip Nix store paths during installation
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

      # Patch rstd's equality trait constraint to avoid incomplete type dependency under Clang 21
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

      # Ensure waywallen-ui is compiled with correct RPATH store paths to resolve Qt6 dependencies
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

      # Patch all internal shared libraries in $out/lib to ensure they can resolve system dependencies
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

    # No patch needed. We build with default FetchContent using sandboxed Nix paths.
    patches = [ ];

    nativeBuildInputs = with pkgs; [
      cmake
      ninja
      lld
      pkg-config
      file
      glslang
      removeReferencesTo
      addDriverRunpath
    ];

    buildInputs = with pkgs; [
      libpulseaudio
      lz4
      freetype
      ffmpeg
      vulkan-loader
      vulkan-headers
      fontconfig
      glfw
      nlohmann_json
      waywallen
      libgbm
      glslang
      quickjs-ng
      argparse
      eigen
      # CEF and Chromium dependencies
      alsa-lib
      gtk3
      nss
      nspr
      libxkbcommon
      wayland
      libx11
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxrandr
      libxrender
      libxscrnsaver
      libxcb
      glib
      atk
      at-spi2-atk
      cairo
      gdk-pixbuf
      pango
      dbus
      expat
      cups
      udev
      at-spi2-core
    ];

    cmakeFlags = [
      "-DCMAKE_C_COMPILER=clang"
      "-DCMAKE_CXX_COMPILER=clang++"
      "-DCMAKE_LINKER_TYPE=LLD"
      "-DFETCHCONTENT_FULLY_DISCONNECTED=ON"
      "-DFETCHCONTENT_SOURCE_DIR_EIGEN=${oweDeps.eigen}"
      "-DFETCHCONTENT_SOURCE_DIR_SPIRV_REFLECT=${oweDeps.spirv_reflect}"
      "-DFETCHCONTENT_SOURCE_DIR_GLSLANG=${oweDeps.glslang}"
      "-DFETCHCONTENT_SOURCE_DIR_ARGPARSE=${oweDeps.argparse}"
      "-DFETCHCONTENT_SOURCE_DIR_RSTD=/build/rstd"
      "-DFETCHCONTENT_SOURCE_DIR_WAVSEN=${oweDeps.wavsen}"
      "-DFETCHCONTENT_SOURCE_DIR_QUICKJS=${oweDeps.quickjs}"
      "-DFETCHCONTENT_SOURCE_DIR_CEF=${oweDeps.cef}"
      "-DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON"
    ];

    hardeningDisable = [ "fortify" ];

    postPatch = ''
      # Remove CMake version check that fails on Nixpkgs CMake 3.x
      substituteInPlace CMakeLists.txt \
        --replace-fail 'if(CMAKE_VERSION VERSION_LESS_EQUAL "4.3.0")' 'if(FALSE)'

      # Fix Clang 21 + GCC 15 transitive module header bugs by explicitly including <memory> and <algorithm>
      # in all C++ source files across the entire repository
      find src waywallen viewer -type f \( -name "*.cpp" -o -name "*.cppm" -o -name "*.hpp" -o -name "*.h" \) | while read -r file; do
        if grep -q -E '^[[:space:]]*module;$' "$file"; then
          # Already has a global module fragment header -> insert headers right after it
          substituteInPlace "$file" --replace-fail "module;" $'module;\n#include <memory>\n#include <algorithm>'
        elif grep -q -E '^[[:space:]]*(export[[:space:]]+)?module[[:space:]]+[a-zA-Z0-9_.:]+;' "$file"; then
          # Is a C++20 module file but lacks a global module fragment -> prepend module; and headers
          sed -i '1s|^|module;\n#include <memory>\n#include <algorithm>\n|' "$file"
        else
          # Traditional C++ source or header file -> prepend headers
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

      # Patch rstd (C++20 module library) to compile cleanly under Clang 21 and GCC 15
      cp -r ${oweDeps.rstd} /build/rstd
      chmod -R +w /build/rstd
      sed -i '/export using std::make_shared;/d' /build/rstd/src/cppstd/cppstd.cppm
      sed -i '/export using std::allocate_shared;/d' /build/rstd/src/cppstd/cppstd.cppm

      sed -i '/export using std::copy;/d' /build/rstd/src/cppstd/cppstd.cppm
      sed -i '/export using std::find;/d' /build/rstd/src/cppstd/cppstd.cppm
      sed -i '/export using std::advance;/d' /build/rstd/src/cppstd/cppstd.cppm

      # Patch rstd's equality trait constraint to avoid incomplete type dependency under Clang 21
      substituteInPlace /build/rstd/src/core/include/rstd/macro.hpp \
        --replace-fail "requires rstd::Impled<Self, rstd::cmp::PartialEq<_USE_TRAIT_T>>" "requires true"
    '';

    postBuild = ''
      unset C_INCLUDE_PATH
      unset CPLUS_INCLUDE_PATH
    '';

    postInstall = ''
      # 1. Patch waywallen-wescene-renderer (does NOT need weweb in its RPATH)
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

      # 2. Patch waywallen-weweb-renderer and other CEF binaries (needs weweb in RPATH, but AFTER system libraries to prioritize the system's patched Vulkan loader)
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

      # 3. Add driver runpath and remove-references-to for all built binaries
      for bin in $out/bin/waywallen-wescene-renderer $(find $out/bin/weweb -type f 2>/dev/null || true); do
        if [ -f "$bin" ] && (file "$bin" | grep -q "ELF"); then
          # Add OpenGL/Vulkan driver path to RPATH for NixOS compatibility (resolves VK_ERROR_INCOMPATIBLE_DRIVER on Nvidia)
          addDriverRunpath "$bin"

          # Selectively remove build-time source references from the binary, leaving Glibc/Vulkan intact
          remove-references-to -t ${src} "$bin"
          for src_path in ${builtins.concatStringsSep " " (builtins.attrValues oweDeps)}; do
            remove-references-to -t "$src_path" "$bin"
          done
        fi
      done
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
    "power-menu.py"
    "singbox-control.py"
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
    _module.args = {
      evalAndSubstitute = evalAndSubstitute;
      mkPyApp = mkPyApp;
    };
    environment.pathsToLink = [
      "/share/waywallen"
    ];
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
        e2fsprogs
        efitools
        efibootmgr
        kdiskmark
        nixfmt
        sshfs
        gdu
        nixd
        wget
        zenity
        killall
        unrar
        zip
        dmidecode
        usbutils
        adwaita-icon-theme
        vmpk
        socat
        wl-clipboard
        networkmanager_dmenu
        neovide
        _7zz-rar
        crudini
        lndir
        texinfo
        xkbcomp
        nvtopPackages.full
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
        wiggle
        gcc
        nodejs
        libreoffice
        protonplus
        gimp3-with-plugins
        gamescope
        android-tools
        heroic
        compsize
        erofs-utils
        gsettings-desktop-schemas
        resources
        quickshell
        hunspell
        hunspellDicts.en_US-large
        hunspellDicts.ru_RU
        libsForQt5.qt5ct
        libsForQt5.qtstyleplugin-kvantum
        kdePackages.qtstyleplugin-kvantum
        kdePackages.qtdeclarative
        kdePackages.kdenlive
        kdePackages.kdeconnect-kde
        (nix-alien.packages.${stdenv.hostPlatform.system}.default.override {
          python3 = pkgs.python3.override {
            packageOverrides = pyFinal: pyPrev: {
              dpcontracts = pyPrev.dpcontracts.overridePythonAttrs (oldAttrs: {
                doCheck = false;
              });
            };
          };
        })
        nix-search.packages.${stdenv.hostPlatform.system}.default
        (helium.packages.${stdenv.hostPlatform.system}.default.overrideAttrs (prev: {
          src = (import <nix/fetchurl.nix>) {
            url = prev.src.url;
            hash = prev.src.hash;
          };
        }))
        (mkPyApp {
          name = "power-menu";
          src = (
            evalAndSubstitute {
              string = builtins.readFile ../../../stuff/scripts/power-menu.py;
            }
          );
        })
        (mkPyApp {
          name = "notify_trunc";
          src = (
            evalAndSubstitute {
              string = builtins.readFile ../../../stuff/scripts/notify_trunc.py;
            }
          );
        })
        (mkPyApp {
          name = "singbox-control";
          src = (
            evalAndSubstitute {
              string = builtins.readFile ../../../stuff/scripts/singbox-control.py;
            }
          );
        })
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
          additional_outside_commands = "ln -sf \"$XDG_RUNTIME_DIR/.nixpak/${appId}/runtime/discord-ipc-0\" \"$XDG_RUNTIME_DIR/discord-ipc-0\"";
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
        waywallen
        open-wallpaper-engine
        aero-control-center
        anicli-ru
      ]
      ++ processedResults;
  };

}
