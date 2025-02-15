{
  lib
, fetchPypi
, python3Packages
, pkgs
}:
let
  httpxkek = python3Packages.httpx.overrideAttrs (finalAttrs: previousAttrs: {
    src = pkgs.fetchFromGitHub {
      owner = "encode";
      repo = previousAttrs.pname;
      tag = "0.25.2";
      hash = "sha256-rGtIrs4dffs7Ndtjb400q7JrZh+HG9k0uwHw9pRlC5s=";
    };
  });
  attrskek = python3Packages.attrs.overrideAttrs (finalAttrs: previousAttrs: {
    src = pkgs.fetchPypi {
      pname = previousAttrs.pname;
      version = "23.2.0";
      hash = "sha256-k13DtSnCYvbPduUId9NaS9PB3hlP1B9HoreujxmXHzA=";
    };
    patches = [
      (pkgs.substituteAll {
        src = ./remove-hatch-plugins.patch;
        version = "23.2.0";
      })
    ];
  });
in
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
    attrskek
    httpxkek
    httpxkek.optional-dependencies.http2
    parsel
    tqdm
    (pkgs.callPackage ./chompjs.nix { })
  ];
  meta = with lib; {
    description = "anicli-api";
    homepage = "https://github.com/vypivshiy/anicli-api";
    maintainers = with maintainers; [ DADA30000 ];
    mainProgram = "anicli-api";
    platforms = platforms.unix;
  };

}
