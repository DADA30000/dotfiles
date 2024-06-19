{
  lib
, pkgs 
, fetchPypi
, python3Packages
}:

python3Packages.buildPythonApplication rec{

  pname = "ani-cli-ru";
  version = "5.0.10";
  pyproject = true;

  src = fetchPypi {
    pname = "anicli_ru";
    inherit version;
    hash = "sha256-N1JN8MDtIF8Mqgm929qgS3d9zunj7ZlSiC+g6P736mA=";
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
