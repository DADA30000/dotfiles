{
  lib,
  inputs,
  pkgs,
  options,
  config,
  ...
}:
let
  collectUniqueInputs =
    inputsMap: seenPaths:
    let
      results = lib.mapAttrsToList (
        name: value:
        if value == null || !(value ? outPath) || (lib.elem value.outPath seenPaths) then
          [ ]
        else
          let
            currentInput = {
              inherit name;
              path = value.outPath;
            };
            children =
              if value ? inputs then collectUniqueInputs value.inputs (seenPaths ++ [ value.outPath ]) else [ ];
          in
          [ currentInput ] ++ children
      ) inputsMap;
    in
    lib.flatten results;

  allInputsRaw = collectUniqueInputs (removeAttrs inputs [ "self" ]) [ ];

  uniqueInputs = lib.attrValues (
    lib.listToAttrs (
      map (item: {
        name = "${item.name}\n${builtins.unsafeDiscardStringContext (toString item.path)}";
        value = item;
      }) allInputsRaw
    )
  );

  groupedByName = lib.groupBy (x: x.name) uniqueInputs;

  finalInputsList = lib.flatten (
    lib.mapAttrsToList (
      name: group:
      if (lib.length group) == 1 then
        group
      else
        lib.imap0 (idx: item: {
          name = "${item.name}-${toString idx}";
          path = item.path;
        }) group
    ) groupedByName
  );

  inputsFarm = pkgs.linkFarm "flake-inputs" finalInputsList;

  offline-python = pkgs.python3.withPackages (
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
  );

  # Extract system packages safely
  sysPkgs =
    if options ? environment.systemPackages then lib.flatten config.environment.systemPackages else [ ];

  systemPkgsFarm = pkgs.linkFarm "system-pkgs-farm" (
    lib.imap0 (idx: pkg: {
      name = "${pkg.name or "pkg"}-${toString idx}";
      path = pkg;
    }) (lib.filter (p: p != null) sysPkgs)
  );

  # Extract home packages safely
  hmPkgs = if options ? home.packages then lib.flatten config.home.packages else [ ];

  homePkgsFarm = pkgs.linkFarm "home-pkgs-farm" (
    lib.imap0 (idx: pkg: {
      name = "${pkg.name or "pkg"}-${toString idx}";
      path = pkg;
    }) (lib.filter (p: p != null) hmPkgs)
  );

in
{
  options = {
    offline-path = lib.mkOption {
      type = lib.types.package;
      internal = true;
      visible = false;
    };
    offline-rev = lib.mkOption {
      type = lib.types.str;
      internal = true;
      visible = false;
    };
    offline-narHash = lib.mkOption {
      type = lib.types.str;
      internal = true;
      visible = false;
    };
  };

  config =
    lib.optionalAttrs (options ? environment.etc) {
      environment.etc = {
        inputs.source = inputsFarm;
        offline-python.source = offline-python;
        pkgsFarm.source = systemPkgsFarm;
      };
    }
    // lib.optionalAttrs (options ? xdg.dataFile) {
      xdg.dataFile = {
        inputs.source = inputsFarm;
        offline-python.source = offline-python;
        pkgsFarm.source = homePkgsFarm;
      };
    };
}
