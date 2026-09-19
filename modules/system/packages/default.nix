# System-Level Packages Module
# Keeps strictly what is used from /run/current-system/sw/bin or as PATH in services.
# All user applications & sandboxes are in Home Manager.

{
  pkgs,
  lib,
  inputs,
  listFiles,
  config,
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

  # ---------------------------------------------------------------------------
  # Dynamic Script Handler Processing (stuff/system/packages)
  # Provides: run-exe, cgroup-executioner, hardware-control-daemon,
  # update-cloudflare-dns, sandbox-migrator, landlock, u, neovide-term, etc.
  # ---------------------------------------------------------------------------
  listDirs = listFiles;
  targetDirs = [ ../../../stuff/system/packages ];
  excludeList = [ "translate-zapret-nixos.sh" ];

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

        nativeBuildInputs = [ pkgs.pkgsStatic.rustc ];

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
    c =
      path:
      pkgs.pkgsStatic.stdenv.mkDerivation rec {
        pname = "${stripExtension (baseNameOf path)}";
        name = pname;
        dontUnpack = true;

        buildPhase = ''
          $CC -O2 -Wall ${path} -o ${pname}
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

  system-package-list = processedResults;

  extra-paths = [
    "/share/waywallen"
    "/share/zsh"
    "/share/xdg-desktop-portal"
    "/share/applications"
  ];
in
{
  nixpkgs.config.permittedInsecurePackages = [
    pkgs.ventoy-full-gtk.name
  ];

  _module.args = {
    inherit evalAndSubstitute mkPyApp;
  };

  # Export helpers to Home Manager
  home-manager.sharedModules = [
    {
      config._module.args = { inherit evalAndSubstitute mkPyApp; };
    }
  ];

  environment = {
    defaultPackages = [ ];
    pathsToLink = extra-paths;
    systemPackages = system-package-list;
  };

  boot.extraModulePackages = [
    gigabyte-laptop-wmi
  ];
}
