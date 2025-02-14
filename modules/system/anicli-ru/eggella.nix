{
  lib
, fetchPypi
, python3Packages
}:

python3Packages.buildPythonApplication rec{

  pname = "eggella";
  version = "0.1.7";
  pyproject = true;

  src = fetchPypi {
    pname = "eggella";
    inherit version;
    hash = "sha256-8Vo39BePA86wcLKs/F+u2N7tpIpPrEyEPp3POszy050=";
  };

  build-system = with python3Packages; [
    hatchling
    setuptools
  ];

  dependencies = [
    python3Packages.prompt-toolkit
    python3Packages.rich
    python3Packages.typer
  ];

  meta = with lib; {
    description = "Framework for easy creating REPL applications.";
    homepage = "https://github.com/vypivshiy/eggella";
    maintainers = with maintainers; [ DADA30000 ];
    mainProgram = "eggella";
    platforms = platforms.unix;
  };

}
