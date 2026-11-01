{
  pkgs,
  inputs,
}:

let
  boringssl = pkgs.stdenv.mkDerivation {
    pname = "fptn-boringssl";
    version = "working-russia-tls-handshake";
    src = inputs.fptn-boringssl-src;
    nativeBuildInputs = with pkgs; [
      cmake
      ninja
      go
      perl
    ];
    NIX_CFLAGS_COMPILE = [ "-Wno-error" ];
    cmakeFlags = [ "-DBUILD_TESTING=OFF" ];
    postInstall = ''
      cat >> $out/include/openssl/opensslv.h << 'EOF'
#define OPENSSL_VERSION_STR "3.0.0"
#define OPENSSL_VERSION_MAJOR 3
#define OPENSSL_VERSION_MINOR 0
#define OPENSSL_VERSION_PATCH 0
EOF
    '';
    installPhase = ''
      mkdir -p $out/include $out/lib
      cp -r ../include/* $out/include/
      cp libssl.a libcrypto.a $out/lib/
      runHook postInstall
    '';
  };

  yaff = pkgs.stdenv.mkDerivation {
    pname = "fptn-yaff";
    version = "main";
    src = inputs.fptn-yaff-src;
    nativeBuildInputs = with pkgs; [
      cmake
      ninja
      protobuf
    ];
    buildInputs = with pkgs; [
      protobuf
      abseil-cpp
    ];
    cmakeFlags = [
      "-DYAFF_BUILD_TESTS=OFF"
      "-DYAFF_BUILD_BENCHMARKS=OFF"
      "-DYAFF_BUILD_EXAMPLES=OFF"
    ];
  };

in
pkgs.stdenv.mkDerivation {
  pname = "fptn-client-cli";
  version = "0.4.6";
  src = inputs.fptn-src;

  patches = [ ./fptn.patch ];

  nativeBuildInputs = with pkgs; [
    cmake
    ninja
    protobuf
    pkg-config
  ];

  buildInputs = with pkgs; [
    boringssl
    yaff
    boost186
    zlib
    re2
    spdlog
    fmt
    libidn2
    nlohmann_json
    httplib
    brotli
    argparse
    protobuf
    abseil-cpp
    gtest
  ];

  cmakeFlags = [
    "-DFPTN_VERSION=0.4.6"
    "-DOPENSSL_ROOT_DIR=${boringssl}"
    "-DOPENSSL_INCLUDE_DIR=${boringssl}/include"
    "-DOPENSSL_CRYPTO_LIBRARY=${boringssl}/lib/libcrypto.a"
    "-DOPENSSL_SSL_LIBRARY=${boringssl}/lib/libssl.a"
    "-DYaFF_DIR=${yaff}/lib/cmake/YaFF"
    "-DFETCHCONTENT_SOURCE_DIR_BASE64=${inputs.fptn-base64-src}"
    "-DFETCHCONTENT_SOURCE_DIR_LIBTUNTAP=${inputs.fptn-libtuntap-src}"
    "-DFETCHCONTENT_SOURCE_DIR_CAMOUFLAGETLS=${inputs.fptn-camouflagetls-src}"
    "-DFETCHCONTENT_SOURCE_DIR_NTP_CLIENT=${inputs.fptn-ntpclient-src}"
  ];

  installPhase = ''
    install -Dm755 src/fptn-client/fptn-client-cli $out/bin/fptn-client-cli
  '';
}
