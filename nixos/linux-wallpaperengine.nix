{ lib
, stdenv
, fetchFromGitHub
, cmake
, ffmpeg
, freeglut
, freeimage
, glew
, glfw
, glm
, libGL
, libpulseaudio
, libX11
, libXau
, libXdmcp
, libXext
, libXpm
, libXrandr
, libXxf86vm
, lz4
, mpv
, pkg-config
, SDL2
, SDL2_mixer
, zlib
}:

stdenv.mkDerivation {
  pname = "linux-wallpaperengine";
  version = "unstable-2023-09-23";

  src = fetchFromGitHub {
    owner = "Almamu";
    repo = "linux-wallpaperengine";
    # upstream lacks versioned releases
    rev = "6c27d9411585d75187042ce6918ddefe3a6e2656";
    hash = "sha256-bZlMHlNKSydh9eGm5cFSEtv/RV9sA5ABs99uurblBZY=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  buildInputs = [
    ffmpeg
    freeglut
    glew
    glfw
    glm
    freeimage
    libGL
    libpulseaudio
    libX11
    libXau
    libXdmcp
    libXext
    libXrandr
    libXpm
    libXxf86vm
    mpv
    lz4
    SDL2
    SDL2_mixer.all
    zlib
  ];

  meta = {
    description = "Wallpaper Engine backgrounds for Linux";
    homepage = "https://github.com/Almamu/linux-wallpaperengine";
    license = lib.licenses.gpl3Only;
    mainProgram = "linux-wallpaperengine";
    maintainers = with lib.maintainers; [ eclairevoyant ];
    platforms = lib.platforms.linux;
  };
}
