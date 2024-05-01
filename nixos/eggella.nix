{
  lib
, fetchPypi
, python3Packages
}:

python3Packages.buildPythonApplication rec{

  pname = "eggella";
  version = "0.1.5";
  pyproject = true;

  src = fetchPypi {
    pname = "eggella";
    inherit version;
    hash = "sha256-Aq5Tm2WBE7SAEvDDVNDDw1DD6bvu+iYHnpjrea4SnUM=";
  };

  build-system = with python3Packages; [
    hatchling
    setuptools
  ];

  dependencies = [
    python3Packages.prompt-toolkit
  ];

  meta = with lib; {
    description = "Framework for easy creating REPL applications.";
    homepage = "https://github.com/vypivshiy/eggella";
    maintainers = with maintainers; [ DADA30000 ];
    mainProgram = "eggella";
    platforms = platforms.unix;
  };

}
