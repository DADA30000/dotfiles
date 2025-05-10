{
  lib,
  fetchPypi,
  python3Packages,
  pkgs,
}:
let
  httpxkek = python3Packages.httpx.overrideAttrs (
    finalAttrs: previousAttrs: {
      src = pkgs.fetchFromGitHub {
        owner = "encode";
        repo = previousAttrs.pname;
        tag = "0.28.1";
        hash = "sha256-tB8uZm0kPRnmeOvsDdrkrHcMVIYfGanB4l/xHsTKpgE=";
      };
    }
  );
  attrskek = python3Packages.attrs.overrideAttrs (
    finalAttrs: previousAttrs: {
      src = pkgs.fetchPypi {
        pname = previousAttrs.pname;
        version = "25.3.0";
        hash = "sha256-ddfO/H+1dnR7LIG0RC1NShzgkAlzUnwBHRAw/Tv0rxs=";
      };
      patches = [
        (pkgs.replaceVars ./remove-hatch-plugins.patch {
          # hatch-vcs and hatch-fancy-pypi-readme depend on pytest, which depends on attrs
          version = "25.3.0";
        })
      ];
    }
  );
in
python3Packages.buildPythonApplication rec {

  pname = "anicli_api";
  version = "0.7.14";
  pyproject = true;

  src = fetchPypi {
    pname = "anicli_api";
    inherit version;
    hash = "sha256-zmB2U4jyDPCLuykUc6PyrlcTULaXDxQ8ZvyTmJfOI0s=";
  };

  build-system = with python3Packages; [
    poetry-core
    hatchling
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
