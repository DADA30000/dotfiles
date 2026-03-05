{ pkgs, ... }:
pkgs.stdenv.mkDerivation {
  pname = "nautilus-listener";
  version = "1.0.0";

  src = ./nautilus-listener.c;

  dontUnpack = true;

  buildPhase = ''
    runHook preBuild
    gcc $src -o nautilus-listener
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp nautilus-listener $out/bin/
    runHook postInstall
  '';
}
