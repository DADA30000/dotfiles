{
  lib
, pkgs 
, fetchPypi
, python3Packages
}:

python3Packages.buildPythonApplication rec{

  pname = "chompjs";
  version = "1.2.3";
  pyproject = true;

  src = fetchPypi {
    pname = "chompjs";
    inherit version;
    hash = "sha256-IiXSiVJOTmUDeZFyESg7f+katJijkr8qHpPb0VY4Llw=";
  };

  build-system = with python3Packages; [
    setuptools
  ];

  dependencies = with python3Packages; [
    setuptools
  ];

  meta = with lib; {
    description = "chompjs";
    homepage = "https://github.com/Nykakin/chompjs";
    license = with licenses; [ mit ];
    maintainers = with maintainers; [ DADA30000 ];
    mainProgram = "chompjs";
    platforms = platforms.unix;
  };

}
