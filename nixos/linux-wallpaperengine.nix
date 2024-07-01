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
, unstableGitUpdater
}:

stdenv.mkDerivation {
  pname = "linux-wallpaperengine";
  version = "0-unstable-2024-06-07";

  src = fetchFromGitHub {
    owner = "Almamu";
    repo = "linux-wallpaperengine";
    # upstream lacks versioned releases
    rev = "4bc52050341b8bceb01f2b2f1ccfd6500b7f3b78";
    hash = "sha256-t89L1aZtmZJosjKVFuwmKFfz8cImN7kl5QAdvKDgjeY=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  buildInputs = [
    ffmpeg
    freeglut
    freeimage
    glew
    glfw
    glm
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

  passthru.updateScript = unstableGitUpdater { };

  meta = {
    description = "Wallpaper Engine backgrounds for Linux";
    homepage = "https://github.com/Almamu/linux-wallpaperengine";
    license = lib.licenses.gpl3Only;
    mainProgram = "linux-wallpaperengine";
    maintainers = with lib.maintainers; [ eclairevoyant ];
    platforms = lib.platforms.linux;
  };
}
