{ lib }:
rec {
  env = name: "\$${name}";
  envOr = name: default: "\${${name}:-${default}}";
  homeDir = "\$HOME";
  runtimeDir = "\$XDG_RUNTIME_DIR";
  concat = list: lib.concatStringsSep "" (map toString list);
  concat' = a: b: "${toString a}${toString b}";
  mkdir = toString;
}
