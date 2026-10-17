{ pkgs, ... }:
pkgs.stdenv.mkDerivation {
  pname = "custom-nautilus-extensions";
  version = "1.0.0";
  nativeBuildInputs = [ pkgs.wrapGAppsHook4 ];
  dontUnpack = true;
  buildInputs = [
    pkgs.python3
    pkgs.python3.pkgs.pygobject3
    pkgs.gtk4
    pkgs.nautilus-python
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/nautilus-python/extensions

    cp ${../../../stuff/home/hyprland/new_file_extension.py} $out/share/nautilus-python/extensions/new_file_extension.py
    cp ${../../../stuff/home/hyprland/open_as_root_extension.py} $out/share/nautilus-python/extensions/open_as_root_extension.py
    ln -s ${pkgs.nautilus-open-any-terminal}/share/nautilus-python/extensions/nautilus_open_any_terminal.py $out/share/nautilus-python/extensions/nautilus_open_any_terminal.py

    runHook postInstall
  '';
}
