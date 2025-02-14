{
  lib
, fetchPypi
, python3Packages
#, python3
}:

python3Packages.buildPythonApplication rec{

  pname = "anicli_api";
  version = "0.7.2";
  pyproject = true;

  src = fetchPypi {
    pname = "anicli_api";
    inherit version;
    hash = "sha256-nnJWi87WDr8pDEUb9IQocDoPFS41DlS/l7qKjeTD73Q=";
  };

  build-system = with python3Packages; [
    poetry-core
  ];

  dependencies = with python3Packages; [
    #(python3.withPackages(ps: with ps; [ httpx ] ++ httpx.optional-dependencies.http2 ))
    attrs
    parsel
    tqdm
    (pkgs.callPackage ./chompjs.nix { })
  ];
  dontCheckRuntimeDeps = true;
  meta = with lib; {
    description = "anicli-api";
    homepage = "https://github.com/vypivshiy/anicli-api";
    maintainers = with maintainers; [ DADA30000 ];
    mainProgram = "anicli-api";
    platforms = platforms.unix;
  };

}
