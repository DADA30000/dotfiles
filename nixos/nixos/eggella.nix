{
  lib
, fetchPypi
, python3Packages
}:

python3Packages.buildPythonApplication rec{

  pname = "eggella";
  version = "0.1.6";
  pyproject = true;

  src = fetchPypi {
    pname = "eggella";
    inherit version;
    hash = "sha256-2vnfiiS9g8O8k426PYvhiw9NUvKHDunGNeld83hUfYM=";
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
