{
  lib,
  inputs,
  pkgs,
  options,
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
  groupedByName = lib.groupBy (x: x.name) allInputsRaw;
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
  nix-path = pkgs.stdenvNoCC.mkDerivation {
    name = "offline-bridge";
    src = ../../../flake.nix;
    nativeBuildInputs = [ pkgs.git ];
    
    GIT_AUTHOR_NAME = "Nix Builder";
    GIT_AUTHOR_EMAIL = "nix@example.com";
    GIT_COMMITTER_NAME = "Nix Builder";
    GIT_COMMITTER_EMAIL = "nix@example.com";
    GIT_AUTHOR_DATE = "1970-01-01T00:00:01Z";
    GIT_COMMITTER_DATE = "1970-01-01T00:00:01Z";

    phases = [ "installPhase" ];

    installPhase = ''
      mkdir -p "$out"
      cp "$src" "$out"/flake.nix
      cp "${../../../flake.lock}" "$out"/flake.lock
      cd $out
      echo "rev" > .gitignore
      git init --initial-branch=main
      git add .
      git commit -m "Deterministic bridge"
      git rev-parse HEAD | tr -d '\n' > "$out/rev"
      echo finished
    '';
  };
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
  };
  config = {
    # rev generation can be moved to u-full if needed
    offline-rev = builtins.readFile "${nix-path}/rev";
    offline-path = nix-path;
  } // lib.optionalAttrs (options ? environment) {
    environment.etc.inputs.source = inputsFarm;
  } // lib.optionalAttrs (options.xdg ? dataFile) {
    xdg.dataFile.inputs.source = inputsFarm;
  };
}
