{
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "xubuntu-adapted-to-nixos";
  version = "newest";

  src = ../plymouth;

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/plymouth/themes/logo
    cp logo/* $out/share/plymouth/themes/logo
    substituteInPlace $out/share/plymouth/themes/logo/logo.plymouth \
      --replace-fail "/usr/" "$out/"
    runHook postInstall
  '';

}
