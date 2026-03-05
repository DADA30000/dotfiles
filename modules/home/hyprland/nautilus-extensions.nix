{ pkgs, ... }:
pkgs.stdenv.mkDerivation {
  pname = "custom-nautilus-extensions";
  version = "1.0.0";

  src = ./nautilus-extensions-src;

  nativeBuildInputs = [ pkgs.wrapGAppsHook4 ];
  buildInputs = [
    pkgs.python3
    pkgs.python3.pkgs.pygobject3
    pkgs.gtk4
    pkgs.nautilus-python
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/nautilus-python/extensions

    cp $src/new_file_extension.py $out/share/nautilus-python/extensions/
    cp $src/open_as_root_extension.py $out/share/nautilus-python/extensions/

    runHook postInstall
  '';
}
