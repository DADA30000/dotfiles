{
  pkgs,
  inputs,
  config,
  lib,
  evalAndSubstitute,
  ...
}:
let
  nixpkgsPath = if inputs ? nixpkgs then inputs.nixpkgs else <nixpkgs>;
  systemPathFile = nixpkgsPath + "/nixos/modules/config/system-path.nix";
  rawSystemPath = builtins.readFile systemPathFile;

  patchedSystemPath =
    lib.replaceStrings [ "ignoreCollisions = true;" ] [ "ignoreCollisions = false;" ]
      rawSystemPath;

  patchedModule = builtins.toFile "system-path-no-collisions.nix" patchedSystemPath;
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
      --ignore-mtime \
      --workers "$NIX_BUILD_CORES" \
      --zD=1 \
      --tar=f \
      -z zstd,19 \
      -C 65536 \
      -E 48bit,dedupe,all-fragments,fragdedupe=full,dot-omitted,force-inode-compact \
      -T 0 \
      -m 65536:zstd,19 \
      -x -1 \
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

in
{
  disabledModules = [ "config/system-path.nix" ];
  imports = [
    patchedModule
  ];
  boot.extraModulePackages = [
    gigabyte-laptop-wmi
  ];
  services.udev.packages = [
    aero-control-center
  ];
  environment.systemPackages = [ aero-control-center ];
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
}
