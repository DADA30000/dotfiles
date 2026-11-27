{
  config,
  lib,
  pkgs,
  inputs,
  mkSandbox,
  zypakPkg,
  ...
}:
with lib;
let
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  pmparser = pkgs.stdenv.mkDerivation {
    pname = "pmparser";
    version = "1.0";
    src = inputs.pmparser;
    patchPhase = ''
      substituteInPlace Makefile \
        --replace 'CFLAGS=-std=gnu99 -pedantic  -Wall' 'CFLAGS=-std=gnu99 -pedantic -fpic -Wall'
    '';
    installPhase = ''
      rm -rf .git
      cp -r ./. $out
    '';
  };
  libcef = pkgs.stdenv.mkDerivation {
    pname = "libcef-transparency-linux";
    version = "1.0";
    src = inputs.libcef-transparency-linux;
    buildPhase = ''
      gcc -O3 -Wall -Wno-parentheses -masm=intel -I${pmparser}/include -shared -fpic -z defs -std=c++23 -o patcher_lib.so patcher_lib.cc -lc -l:libpmparser.a -L${pmparser}/build
    '';
    installPhase = ''
      cp -r ./. $out
    '';
  };
  hazy_orig = inputs.hazy;
  hazy = pkgs.runCommand "patch-hazy" { } ''
    cp -r --no-preserve=mode ${hazy_orig} $out
    mv "$out/hazy.js" "$out/theme.js"
    #patch "$out/theme.js" < "${../../../stuff/patches/hazy.patch}"
  '';
  cfg = config.spicetify;
in
{
  options.spicetify = {
    enable = mkEnableOption "spotify with theme";
  };

  imports = [ inputs.spicetify-nix.homeManagerModules.default ];
  config = mkIf cfg.enable {
    home.packages = [
      (mkSandbox {
        appId = "com.spotify.Client";
        network = "singbox";
        pulse = "sandboxed";
        gpu = true;
        wayland = "sandboxed";
        x11 = "sandboxed";
        portals = false;
        flatpak_portal = true;
        seccomp.allow = [ "capset" ];
        dbus.owns = [ "org.mpris.MediaPlayer2.spotify" ];
        package = config.programs.spicetify.spicedSpotify.overrideAttrs {
          fixupPhase = ''
            runHook preFixup

            wrapProgramShell $out/share/spotify/spotify \
              ''${gappsWrapperArgs[@]} \
              --prefix LD_LIBRARY_PATH : "$librarypath" \
              --set ZYPAK_CEF_LIBRARY_PATH "$out/share/spotify/libcef.so"

            substituteInPlace $out/share/spotify/spotify \
              --replace-fail \
                "exec -a \"\$0\" \"$out/share/spotify/.spotify-wrapped\"" \
                "exec ${zypakPkg}/bin/zypak-wrapper \"$out/share/spotify/.spotify-wrapped\""

            runHook postFixup
          '';
        };
      })
    ];
    programs.spicetify = {
      enabledExtensions = with spicePkgs.extensions; [
        adblock
        hidePodcasts
        shuffle
      ];
      theme = {
        name = "Hazy";
        src = hazy;
        injectCss = true;
        injectThemeJs = true;
        replaceColors = true;
        homeConfig = true;
        overwriteAssets = true;
      };
    };
  };
}
