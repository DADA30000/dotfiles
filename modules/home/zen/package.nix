{
  buildMozillaMach,
  fetchFromGitHub,
  lib,
  fetchurl,
  stdenvNoCC,
}:

let
  firefoxVersion = "147.0.2";

  zenBrowserSource = fetchFromGitHub {
    owner = "DADA30000";
    repo = "desktop";
    rev = "ffef4e43c7e54f662470f3fc9934c78b66077dee";
    hash = "sha256-iLTNu0wLaiZtneqdEd/LnDZX1SgBZ5nonl4WtkLeQOc=";
  };

  patchedSrc = stdenvNoCC.mkDerivation {
    pname = "firefox-browser-src-patched";
    version = firefoxVersion;

    src = fetchurl {
      url = "https://archive.mozilla.org/pub/firefox/releases/${firefoxVersion}/source/firefox-${firefoxVersion}.source.tar.xz";
      hash = "sha256-aJ09NMMbMXURoJ1uVoJQxnNhOO4JLvkSnJiDbRHZQtk=";
    };

    patches = [
      "${zenBrowserSource}/**/**/*.patch" # We need to fetch all zen-browser patches dymanically.
    ];

  };

in
(buildMozillaMach {
  pname = "zen-browser";
  packageVersion = "1.18.3b";
  version = firefoxVersion;
  applicationName = "zen";
  branding = "browser/branding/release";
  requireSigning = false;
  allowAddonSideload = true;

  src = patchedSrc;

  extraConfigureFlags = [
    "--with-app-basename=Zen"
  ];

  meta = {
    description = "Firefox based browser with a focus on privacy and customization";
    homepage = "https://zen-browser.app/";
    downloadPage = "https://zen-browser.app/download/";
    changelog = "https://zen-browser.app/release-notes/#1.18.3b";
    maintainers = with lib.maintainers; [
      matthewpi
      titaniumtown
      eveeifyeve
    ];
    platforms = lib.platforms.unix;
    broken = false; # Broken for now because major issue with getting rid of surfer.
    # since Firefox 60, build on 32-bit platforms fails with "out of memory".
    # not in `badPlatforms` because cross-compilation on 64-bit machine might work.
    maxSilent = 14400; # 4h, double the default of 7200s (c.f. #129212, #129115)
    license = lib.licenses.mpl20;
  };
}).override
  {
    pgoSupport = true;
    crashreporterSupport = false;
    enableOfficialBranding = false;
  }
