{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib;
let
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.system};
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
      gcc -Wall -masm=intel -I${pmparser}/include -o patcher_lib.so -shared -fpic -z defs patcher_lib.c -lc -l:libpmparser.a -L${pmparser}/build
    '';
    installPhase = ''
      cp -r ./. $out
    '';
  };
  hazy_orig = inputs.hazy;
  hazy = pkgs.runCommand "patch-theme.js" {} ''
    cp -r ${hazy_orig} $out
    chmod +w $out/theme.js
    echo "setTimeout(() => {
      const htmlElement = document.documentElement;

      const topContainer = document.querySelector('.Root__top-container');

      if (htmlElement) {
          htmlElement.style.backgroundColor = 'transparent';
      }

      if (topContainer) {
          topContainer.style.backgroundColor = 'transparent';
      } else {
          console.log('Element .Root__top-container not found after 2-second delay.');
      }
      }, 2000);" >> $out/theme.js
  '';
  cfg = config.spicetify;
in
{
  options.spicetify = {
    enable = mkEnableOption "Enable spotify with theme";
  };

  imports = [ inputs.spicetify-nix.homeManagerModules.default ];
  config = mkIf cfg.enable {
    home.packages = [ (config.programs.spicetify.spicedSpotify.overrideAttrs {
      fixupPhase = ''
          runHook preFixup

          wrapProgramShell $out/share/spotify/spotify \
            ''${gappsWrapperArgs[@]} \
            --prefix LD_LIBRARY_PATH : "$librarypath" \
            --prefix LD_AUDIT : "${libcef}/patcher_lib.so" \
            --prefix PATH : "${lib.getBin pkgs.zenity}/bin" \
            ${
              if config.programs.spicetify.wayland != false then
                ''--add-flags '--enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime=true' ''
              else
                ''--add-flags '--disable-features=UseOzonePlatform --ozone-platform=x11 --enable-wayland-ime=false' ''
            }

          runHook postFixup
        '';
    }) ];
    programs.spicetify = {
      alwaysEnableDevTools = true;
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
        requiredExtensions = [
          {
            name = "theme.js";
            src = "${hazy}";
          }
        ];
      };
    };
  };
}
