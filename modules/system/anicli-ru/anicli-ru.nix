{
  lib
, pkgs 
, fetchPypi
, python3Packages
}:

python3Packages.buildPythonApplication rec{

  pname = "ani-cli-ru";
  version = "5.0.12";
  pyproject = true;

  src = fetchPypi {
    pname = "anicli_ru";
    inherit version;
    hash = "sha256-s8uI0ch+SPqthHy+d0jcB6o5/Zqx89JHM68Q00nwCFA=";
  };

  build-system = with python3Packages; [
    hatchling
    setuptools
  ];

  dependencies = [
    python3Packages.hatchling
    (pkgs.callPackage ./eggella.nix { })
    (pkgs.callPackage ./anicli-api.nix { })
  ];

  meta = with lib; {
    description = "Script to watch anime from terminal with russian translation, written in python.";
    homepage = "https://github.com/vypivshiy/ani-cli-ru";
    license = with licenses; [ gpl3Plus ];
    maintainers = with maintainers; [ DADA30000 ];
    mainProgram = "anicli-ru";
    platforms = platforms.unix;
  };

}
