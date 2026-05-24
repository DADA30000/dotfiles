{
  config,
  lib,
  pkgs,
  inputs,
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
    patch "$out/theme.js" < "${../../../stuff/hazy.patch}"
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
      (config.mkSandbox {
        appId = "com.spotify.Client";
        audio = true;
        gpu = true;
        wayland = true;
        x11 = true;
        network_singbox = true;
        portals_for_files = false;
        additional_args.dbus.policies."org.mpris.MediaPlayer2.spotify" = "own";
        package = config.programs.spicetify.spicedSpotify.overrideAttrs {
          fixupPhase = ''
            runHook preFixup

            wrapProgramShell $out/share/spotify/spotify \
              ''${gappsWrapperArgs[@]} \
              --prefix LD_LIBRARY_PATH : "$librarypath" \
              --prefix LD_AUDIT : "${libcef}/patcher_lib.so" \
              --prefix PATH : "${lib.getBin pkgs.zenity}/bin" \
              ${
                if config.programs.spicetify.wayland != false then
                  "--add-flags '--enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime=true' "
                else
                  "--add-flags '--disable-features=UseOzonePlatform --ozone-platform=x11 --enable-wayland-ime=false' "
              }

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
        beautifulLyrics
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
