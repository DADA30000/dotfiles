{
  pkgs,
  lib,
  inputs,
  osConfig,
  config,
  mkSandbox,
  staticBwrap,
  ...
}:
let
  fixPrism =
    pkg:
    pkgs.symlinkJoin {
      inherit (pkg) name;
      paths = [ pkg ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        rm $out/bin/prismlauncher
        makeWrapper ${pkg}/bin/prismlauncher $out/bin/prismlauncher \
          --run '
            CONF_DIR="$XDG_DATA_HOME/PrismLauncher"
            CONF="$CONF_DIR/prismlauncher.cfg"
            GEOM="\"AdnQywADAAAAAAAAAAAAAAAABDYAAAO/AAAAAAAAAAD////+/////gAAAAACAAAABkAAAAAAAAAAAAAABDYAAAO/\""
            mkdir -p "$CONF_DIR"
            if [ ! -f "$CONF" ]; then
              echo "MainWindowGeometry=$GEOM" > "$CONF"
            else
              sed -i "s|^MainWindowGeometry=.*|MainWindowGeometry=$GEOM|" "$CONF"
            fi
          '
      '';
    };

  fhsSeccompAllow = [
    "@10:unshare"
    "@10:setns"
    "@10:clone"
    "capset"
    "mount"
    "umount"
    "umount2"
    "pivot_root"
    "chroot"
    "open_tree"
    "move_mount"
    "fsopen"
    "fsconfig"
    "fsmount"
    "fspick"
    "mount_setattr"
  ];

  # ---------------------------------------------------------------------------
  # Sandboxed Applications
  # ---------------------------------------------------------------------------
  aistudio2apiSandbox = mkSandbox rec {
    appId = "io.github.mag1cfall.aistudio2api";
    package = aistudio2apiPkg;
    network = "sandboxed";
    gpu = true;
    wayland = "sandboxed";
    seccomp.allow = fhsSeccompAllow;
    additional_outside_commands = ''
      rust-bridge -r listen --address 127.0.0.1:2048 -s "$SANDBOXED_RUNTIME_DIR/aistudio" &
      rust-bridge -r pass --address 127.0.0.1:2080 -s "$SANDBOXED_RUNTIME_DIR/aistudio_proxy" &
      SANDBOX_HOME="$HOME/.nixpak/${appId}/home"
      SANDBOX_CFG_REL="''${XDG_CONFIG_HOME#"$HOME/"}"
      SANDBOX_CACHE_REL="''${XDG_CACHE_HOME#"$HOME/"}"
      SANDBOX_CFG="$SANDBOX_HOME/$SANDBOX_CFG_REL/AIStudio2API"
      SANDBOX_CACHE="$SANDBOX_HOME/$SANDBOX_CACHE_REL/AIStudio2API"
      mkdir -p "$SANDBOX_HOME/$SANDBOX_CFG_REL" "$SANDBOX_HOME/$SANDBOX_CACHE_REL" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
      if [ -d "$XDG_CONFIG_HOME/AIStudio2API" ] && [ ! -L "$XDG_CONFIG_HOME/AIStudio2API" ]; then
        if [ ! -e "$SANDBOX_CFG" ]; then
          mv "$XDG_CONFIG_HOME/AIStudio2API" "$SANDBOX_CFG"
        else
          rm -rf "$XDG_CONFIG_HOME/AIStudio2API.pre-sandbox"
          mv "$XDG_CONFIG_HOME/AIStudio2API" "$XDG_CONFIG_HOME/AIStudio2API.pre-sandbox"
        fi
      fi
      if [ -d "$XDG_CACHE_HOME/AIStudio2API" ] && [ ! -L "$XDG_CACHE_HOME/AIStudio2API" ]; then
        rm -rf "$XDG_CACHE_HOME/AIStudio2API.pre-sandbox"
        mv "$XDG_CACHE_HOME/AIStudio2API" "$XDG_CACHE_HOME/AIStudio2API.pre-sandbox"
      fi
      mkdir -p "$SANDBOX_CFG" "$SANDBOX_CACHE"
      rm -f "$SANDBOX_CFG/webkit2gtk-4.1"
      ln -sfn "$SANDBOX_CFG" "$XDG_CONFIG_HOME/AIStudio2API"
      ln -sfn "$SANDBOX_CACHE" "$XDG_CACHE_HOME/AIStudio2API"
    '';
    additional_inside_commands = ''
      rust-bridge -r pass --address 127.0.0.1:2048 -s "$XDG_RUNTIME_DIR/aistudio" -d
      rust-bridge -r listen --address 127.0.0.1:2080 -s "$XDG_RUNTIME_DIR/aistudio_proxy" -d
    '';
  };

  geminiWeb2ApiSandbox = mkSandbox rec {
    appId = "com.mag1cfall.geminiweb2api";
    package = geminiWeb2ApiPkg;
    network = "sandboxed";
    gpu = true;
    wayland = "sandboxed";
    x11 = "sandboxed";
    seccomp.allow = fhsSeccompAllow;
    dbus.owns = [ "com.mag1cfall.gemini-web2api.*" ];
    additional_outside_commands = ''
      rust-bridge -r listen --address 127.0.0.1:8007 -s "$SANDBOXED_RUNTIME_DIR/gemini-web2api" &
      rust-bridge -r pass --address 127.0.0.1:2080 -s "$SANDBOXED_RUNTIME_DIR/aistudio_proxy" &
      SANDBOX_HOME="$HOME/.nixpak/${appId}/home"
      SANDBOX_CFG_REL="''${XDG_CONFIG_HOME#"$HOME/"}"
      SANDBOX_CFG="$SANDBOX_HOME/$SANDBOX_CFG_REL/Gemini-Web2API"
      mkdir -p "$SANDBOX_HOME/$SANDBOX_CFG_REL" "$XDG_CONFIG_HOME"
      if [ -d "$XDG_CONFIG_HOME/Gemini-Web2API" ] && [ ! -L "$XDG_CONFIG_HOME/Gemini-Web2API" ]; then
        if [ ! -e "$SANDBOX_CFG" ]; then
          mv "$XDG_CONFIG_HOME/Gemini-Web2API" "$SANDBOX_CFG"
        else
          rm -rf "$XDG_CONFIG_HOME/Gemini-Web2API.pre-sandbox"
          mv "$XDG_CONFIG_HOME/Gemini-Web2API" "$XDG_CONFIG_HOME/Gemini-Web2API.pre-sandbox"
        fi
      fi
      mkdir -p "$SANDBOX_CFG"
      ln -sfn "$SANDBOX_CFG" "$XDG_CONFIG_HOME/Gemini-Web2API"
    '';
    additional_inside_commands = ''
      rust-bridge -r pass --address 127.0.0.1:8007 -s "$XDG_RUNTIME_DIR/gemini-web2api" -d
      rust-bridge -r listen --address 127.0.0.1:2080 -s "$XDG_RUNTIME_DIR/aistudio_proxy" -d
    '';
  };

  antigravity2apiSandbox = mkSandbox rec {
    appId = "com.mag1cfall.antigravity2api";
    package = antigravity2apiPkg;
    network = "sandboxed";
    gpu = true;
    wayland = "sandboxed";
    x11 = "sandboxed";
    seccomp.allow = fhsSeccompAllow;
    additional_outside_commands = ''
      rust-bridge -r listen --address 127.0.0.1:8017 -s "$SANDBOXED_RUNTIME_DIR/antigravity2api" &
      rust-bridge -r pass --address 127.0.0.1:2080 -s "$SANDBOXED_RUNTIME_DIR/aistudio_proxy" &
      SANDBOX_HOME="$HOME/.nixpak/${appId}/home"
      SANDBOX_CFG_REL="''${XDG_CONFIG_HOME#"$HOME/"}"
      SANDBOX_CFG="$SANDBOX_HOME/$SANDBOX_CFG_REL/Antigravity2API"
      mkdir -p "$SANDBOX_HOME/$SANDBOX_CFG_REL" "$XDG_CONFIG_HOME"
      if [ -d "$XDG_CONFIG_HOME/Antigravity2API" ] && [ ! -L "$XDG_CONFIG_HOME/Antigravity2API" ]; then
        if [ ! -e "$SANDBOX_CFG" ]; then
          mv "$XDG_CONFIG_HOME/Antigravity2API" "$SANDBOX_CFG"
        else
          rm -rf "$XDG_CONFIG_HOME/Antigravity2API.pre-sandbox"
          mv "$XDG_CONFIG_HOME/Antigravity2API" "$XDG_CONFIG_HOME/Antigravity2API.pre-sandbox"
        fi
      fi
      mkdir -p "$SANDBOX_CFG"
      ln -sfn "$SANDBOX_CFG" "$XDG_CONFIG_HOME/Antigravity2API"
    '';
    additional_inside_commands = ''
      rust-bridge -r pass --address 127.0.0.1:8017 -s "$XDG_RUNTIME_DIR/antigravity2api" -d
      rust-bridge -r listen --address 127.0.0.1:2080 -s "$XDG_RUNTIME_DIR/aistudio_proxy" -d
    '';
  };

  prismLauncherSandbox = mkSandbox rec {
    appId = "org.prismlauncher.PrismLauncher";
    network = "singbox";
    pulse = "sandboxed";
    wayland = "sandboxed";
    x11 = "sandboxed";
    gpu = true;
    dbus.talks = [ "com.feralinteractive.GameMode" ];
    seccomp.deny.log.eperm = [ "fchown" ];
    binds = {
      mkdir = [
        "$XDG_CONFIG_HOME/openvr"
        "$XDG_CONFIG_HOME/openxr"
        "$XDG_RUNTIME_DIR/wivrn"
      ];
      ro = [
        "$XDG_CONFIG_HOME/openvr"
        "$XDG_CONFIG_HOME/openxr"
        "$XDG_RUNTIME_DIR/wivrn"
      ];
    };
    additional_outside_commands = ''
      ln -sf "$HOME/.nixpak/${appId}/home/''${XDG_DATA_HOME#"$HOME/"}/PrismLauncher" "$XDG_DATA_HOME/PrismLauncher"
    '';
    package = fixPrism (
      pkgs.prismlauncher.override {
        prismlauncher-unwrapped = pkgs.prismlauncher-unwrapped.overrideAttrs (prev: {
          patches = prev.patches or [ ] ++ [ ../../../stuff/patches/prismlauncher.patch ];
        });
      }
    );
  };

  discordSandbox = mkSandbox rec {
    appId = "com.discordapp.Discord";
    network = "singbox";
    pulse = "sandboxed";
    microphone = "portal";
    wayland = "sandboxed";
    gpu = true;
    webcam = "portal";
    share_pid = true;
    seccomp.allow = fhsSeccompAllow;
    binds.rw = [ "$XDG_CONFIG_HOME/Vencord" ];
    additional_outside_commands = ''
      ln -sf "$HOME/.nixpak/${appId}/home/''${XDG_CONFIG_HOME#"$HOME/"}/discord" "$XDG_CONFIG_HOME/discord"
      ln -sf "$XDG_RUNTIME_DIR/.nixpak/${appId}/runtime/discord-ipc-0" "$XDG_RUNTIME_DIR/discord-ipc-0"
    '';
    package = pkgs.discord.override {
      withVencord = true;
    };
  };

  sounduxSandbox = mkSandbox {
    appId = "io.github.Soundux";
    network = "sandboxed";
    pulse = "passthrough";
    pipewire = "passthrough";
    wayland = "sandboxed";
    gpu = true;
    package = sounduxPkg;
    binds = {
      mkdir = [ "$HOME/Music/Soundux" ];
      rw = [ "$HOME/Music/Soundux" ];
    };
  };

  ayugramDesktopSandbox = mkSandbox rec {
    appId = "com.ayugram.desktop";
    network = "singbox";
    pulse = "sandboxed";
    microphone = "portal";
    wayland = "sandboxed";
    gpu = true;
    webcam = "portal";
    dbus.owns = [
      "com.ayugram.desktop"
      "com.ayugram.desktop.*"
    ];
    additional_outside_commands = ''
      ln -sf "$HOME/.nixpak/${appId}/home/''${XDG_DATA_HOME#"$HOME/"}/AyuGramDesktop" "$XDG_DATA_HOME/AyuGramDesktop"
    '';
    package = pkgs.symlinkJoin {
      name = "ayugram-desktop-patched";
      paths = [ pkgs.ayugram-desktop ];
      postBuild = ''
        rm -f $out/share/applications/com.ayugram.desktop.desktop
        cp ${pkgs.ayugram-desktop}/share/applications/com.ayugram.desktop.desktop $out/share/applications/com.ayugram.desktop.desktop
        chmod u+w $out/share/applications/com.ayugram.desktop.desktop
        substituteInPlace $out/share/applications/com.ayugram.desktop.desktop \
          --replace-fail "DBusActivatable=true" "DBusActivatable=false"
      '';
    };
  };

  enteAuthSandbox = mkSandbox {
    appId = "io.ente.auth";
    network = "sandboxed";
    wayland = "sandboxed";
    gpu = true;
    dbus.owns = [ "io.ente.auth" ];
    package = pkgs.ente-auth;
  };

  steamExtraPackages = with pkgs; [
    libgdiplus
    fontconfig
    attr
    libXcursor
    libXinerama
    libXScrnSaver
    libXi
    nss
    nspr
    atk
    at-spi2-atk
    libdrm
    libGL
    libXcomposite
    libXdamage
    libXrandr
    libXext
    libXfixes
    mesa
    libva
    protontricks
  ];

  steamExtraLibraries = [
    "/mnt/data-nvme/${config.home.username}/SteamLibrary"
    "/mnt/data-hdd/${config.home.username}/SteamLibrary"
  ];

  steamSandbox =
    let
      overriddenSteam = pkgs.steam.override {
        privateTmp = false;
        extraPkgs = _: steamExtraPackages;
      };

      sandboxed = mkSandbox rec {
        appId = "com.valvesoftware.Steam";
        network = "sandboxed";
        pulse = "sandboxed";
        gpu = true;
        wayland = "sandboxed";
        landlock = false;
        tmp = "passthrough";
        shm = "passthrough";
        share_pid = true;
        seccomp.allow = fhsSeccompAllow ++ [
          "@10:ptrace"
          "process_vm_readv"
          "process_vm_writev"
          "modify_ldt"
          "personality"
          "userfaultfd"
          "socketcall"
        ];
        dbus = {
          owns = [ "com.steampowered.*" ];
          talks = [ "com.feralinteractive.GameMode" ];
        };
        binds = {
          dev = [ "/dev" ];
          mkdir = [
            "$XDG_CONFIG_HOME/openvr"
            "$XDG_CONFIG_HOME/openxr"
            "$XDG_RUNTIME_DIR/wivrn"
          ];
          ro = [
            "$XDG_CONFIG_HOME/openvr"
            "$XDG_CONFIG_HOME/openxr"
            "$XDG_RUNTIME_DIR/wivrn"
          ];
          rw = steamExtraLibraries ++ [
            "/tmp"
            "/sys/class"
            "/sys/bus"
            "/sys/dev"
            "/sys/devices"
            "/sys/block"
            "/run/udev"
          ];
        };
        additional_outside_commands = ''
          rust-bridge -r listen --address 127.0.0.1:[57343,27060] -s "$SANDBOXED_RUNTIME_DIR/steam" &
          mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_DATA_HOME/vulkan"
          SANDBOXED_XDG_DATA_HOME="$HOME/.nixpak/${appId}/home''${XDG_DATA_HOME#"/home/$USER"}"
          ln -sf "$HOME/.nixpak/${appId}/home/.steam" "$HOME/.steam"
          ln -sf "$SANDBOXED_XDG_DATA_HOME/Steam" "$XDG_DATA_HOME/Steam"
          ln -sf "$SANDBOXED_XDG_DATA_HOME/vulkan/implicit_layer.d" "$XDG_DATA_HOME/vulkan/implicit_layer.d"
          ${pkgs.python3}/bin/python3 ${../../../stuff/home/steam/sync-steam-libraries.py} ${lib.escapeShellArgs steamExtraLibraries}
        '';
        additional_inside_commands = ''
          rust-bridge -r pass --address 127.0.0.1:[57343,27060] -s "$XDG_RUNTIME_DIR/steam" -d
        '';
        package = overriddenSteam;
      };
    in
    sandboxed
    // {
      override = attrs: (sandboxed.override attrs) // { inherit (overriddenSteam) run; };
      inherit (overriddenSteam) run;
    };

  # ---------------------------------------------------------------------------
  # Custom Derivations & Overrides
  # ---------------------------------------------------------------------------
  aistudio2apiPkg =
    let
      src = inputs.aistudio2api;
      version = src.shortRev or "unstable";
      spidermonkeyVersion =
        let
          m = builtins.match ".*SPIDERMONKEY:[[:space:]]*([^[:space:]\r\n]+).*" (
            builtins.readFile "${src}/.github/actions/static-libraries/action.yml"
          );
        in
        if m != null then
          builtins.head m
        else
          throw "Failed to parse SPIDERMONKEY version from .github/actions/static-libraries/action.yml";
      targetArch = pkgs.stdenv.hostPlatform.go.GOARCH;

      spidermonkey = pkgs.fetchzip {
        name = "spidermonkey-${spidermonkeyVersion}-linux-${targetArch}-gnu";
        url = "https://github.com/Mag1cFall/firefox/releases/download/${spidermonkeyVersion}/spidermonkey-${spidermonkeyVersion}-linux-${targetArch}-gnu.tar.gz";
        hash = "sha256-bxQhqD3+REqItpPT5tvYDiyfj1D7Tn9VVH2X3ul8vts=";
        stripRoot = false;
      };

      webDist = pkgs.buildNpmPackage {
        pname = "aistudio2api-web";
        inherit version src;

        npmDeps = pkgs.importNpmLock {
          npmRoot = "${src}/web";
          package = removeAttrs (lib.importJSON "${src}/web/package.json") [ "overrides" ];
          packageLock = lib.importJSON "${src}/web/package-lock.json";
        };
        npmConfigHook = pkgs.importNpmLock.npmConfigHook;
        npmFlags = [ "--legacy-peer-deps" ];

        postPatch = ''
          cd web
        '';

        preBuild = ''
          for dart in node_modules/sass-embedded-*/dart-sass/src/dart; do
            if [ -f "$dart" ]; then
              chmod +w "$dart"
              patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" "$dart"
            fi
          done
        '';

        nodejs = pkgs.nodejs_22;

        installPhase = ''
          runHook preInstall
          mkdir -p $out
          cp -r ../internal/webui/dist/* $out/
          runHook postInstall
        '';
      };

      aistudio2apiBin = pkgs.buildGoModule {
        pname = "aistudio2api";
        inherit version src;

        vendorHash = "sha256-+s01NxdjtDDY7adYIe86XwXqNaHlugXeo6128swjuaw=";
        overrideModAttrs = _: {
          name = "aistudio2api-go-modules-${
            builtins.substring 0 12 (builtins.hashFile "sha256" "${src}/go.mod")
          }-${builtins.substring 0 12 (builtins.hashFile "sha256" "${src}/go.sum")}";
        };

        subPackages = [ "cmd/aistudio2api" ];
        tags = [
          "desktop"
          "production"
          "gtk3"
        ];
        ldflags = [
          "-s"
          "-w"
          "-X github.com/Mag1cFall/AIStudio2API/internal/app.version=${version}"
          "-X github.com/Mag1cFall/AIStudio2API/internal/app.managedBy=Nix"
        ];
        doCheck = false;

        nativeBuildInputs = [
          pkgs.pkg-config
          pkgs.wrapGAppsHook3
        ];

        buildInputs = [
          pkgs.gtk3
          pkgs.webkitgtk_4_1
          pkgs.pkgsStatic.libwebp
        ];

        env = {
          CGO_ENABLED = "1";
          CGO_CPPFLAGS = "-I${spidermonkey}/include";
          CGO_LDFLAGS = "-L${spidermonkey}/lib";
        };

        postConfigure = ''
          rm -rf internal/webui/dist
          cp -r ${webDist} internal/webui/dist
        '';

        postInstall = ''
          install -Dm644 build/linux/aistudio2api.desktop $out/share/applications/aistudio2api.desktop
          install -Dm644 build/appicon.png $out/share/icons/hicolor/256x256/apps/aistudio2api.png
        '';
      };

      # FHS runner so runtime-downloaded Camoufox (isolated login / camoufox backend) executes without patchelf
      aistudio2apiFhs = pkgs.buildFHSEnv {
        name = "aistudio2api";
        targetPkgs = pkgs: [
          pkgs.cacert
          pkgs.gtk3
          pkgs.glib
          pkgs.pango
          pkgs.cairo
          pkgs.gdk-pixbuf
          pkgs.atk
          pkgs.at-spi2-atk
          pkgs.alsa-lib
          pkgs.libxkbcommon
          pkgs.libx11
          pkgs.libxcomposite
          pkgs.libxdamage
          pkgs.libxext
          pkgs.libxfixes
          pkgs.libxrandr
          pkgs.libxrender
          pkgs.libxtst
          pkgs.libxcb
          pkgs.libxt
          pkgs.nspr
          pkgs.nss
          pkgs.dbus
          pkgs.libglvnd
          pkgs.libgbm
          pkgs.mesa
          pkgs.ffmpeg
          pkgs.cups
          pkgs.libdrm
          pkgs.udev
          pkgs.fontconfig
          pkgs.freetype
          pkgs.zlib
          pkgs.libgpg-error
          pkgs.stdenv.cc.cc.lib
        ];
        runScript = "${aistudio2apiBin}/bin/aistudio2api";
      };

      aistudio2apiAssets = pkgs.runCommand "aistudio2api-assets" { } ''
        mkdir -p $out/share
        cp -r ${aistudio2apiBin}/share/* $out/share/
      '';
    in
    pkgs.symlinkJoin {
      name = "aistudio2api-${version}";
      paths = [
        aistudio2apiFhs
        aistudio2apiAssets
      ];
    };

  geminiWeb2ApiPkg =
    let
      src = inputs.gemini-web2api;
      version = src.shortRev or "unstable";

      webDist = pkgs.stdenv.mkDerivation {
        pname = "gemini-web2api-web";
        inherit version src;

        pnpmRoot = "web";

        nativeBuildInputs = [
          pkgs.nodejs_22
          pkgs.pnpmConfigHook
          pkgs.pnpm_11
        ];

        pnpmDeps = pkgs.fetchPnpmDeps {
          pname = "gemini-web2api-web-${
            builtins.substring 0 12 (builtins.hashFile "sha256" "${src}/web/pnpm-lock.yaml")
          }";
          inherit version;
          src = "${src}/web";
          pnpm = pkgs.pnpm_11;
          fetcherVersion = 5;
          hash = "sha256-rVhlRT1OAlJy+exu8NR/meb5S81p10R1D0dy0ldL6ro=";
        };

        buildPhase = ''
          runHook preBuild
          pnpm --dir web run build
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          cp -r internal/webui/dist $out
          runHook postInstall
        '';
      };
      geminiWeb2ApiBin = pkgs.buildGoModule {
        pname = "gemini-web2api";
        inherit version src;

        patches = [ ../../../stuff/patches/gemini-web2api-chunk-long-prompt.patch ];

        vendorHash = "sha256-9qH33RD7DnIBoh5Cg9/c2jvl1X8nhSE+8n2H9RCbdwQ=";
        overrideModAttrs = _: {
          name = "gemini-web2api-go-modules-${
            builtins.substring 0 12 (builtins.hashFile "sha256" "${src}/go.mod")
          }-${builtins.substring 0 12 (builtins.hashFile "sha256" "${src}/go.sum")}";
        };

        subPackages = [ "cmd/gemini-web2api" ];
        tags = [
          "desktop"
          "production"
          "gtk3"
          "nomsgpack"
        ];
        ldflags = [
          "-s"
          "-w"
          "-X github.com/Mag1cFall/Gemini-Web2API/internal/app.version=${version}"
        ];
        doCheck = false;

        nativeBuildInputs = [
          pkgs.pkg-config
          pkgs.wrapGAppsHook3
        ];

        buildInputs = [
          pkgs.gtk3
          pkgs.webkitgtk_4_1
        ];

        postConfigure = ''
          rm -rf internal/webui/dist
          cp -r ${webDist} internal/webui/dist
        '';

        postInstall = ''
          install -Dm644 internal/desktop/icon.png $out/share/icons/hicolor/256x256/apps/gemini-web2api.png
          mkdir -p $out/share/applications
          cat << 'DESKTOP' > $out/share/applications/gemini-web2api.desktop
          [Desktop Entry]
          Version=1.0
          Name=Gemini-Web2API
          Comment=Gemini Web to OpenAI, Anthropic and Gemini compatible API
          Exec=gemini-web2api
          Terminal=false
          Type=Application
          Icon=gemini-web2api
          Categories=Network;Development;
          StartupWMClass=gemini-web2api
          DESKTOP
        '';
      };

      geminiFhs = pkgs.buildFHSEnv {
        name = "gemini-web2api";
        targetPkgs = pkgs: [
          pkgs.cacert
          pkgs.gtk3
          pkgs.glib
          pkgs.pango
          pkgs.cairo
          pkgs.gdk-pixbuf
          pkgs.atk
          pkgs.at-spi2-atk
          pkgs.alsa-lib
          pkgs.libxkbcommon
          pkgs.libx11
          pkgs.libxcomposite
          pkgs.libxdamage
          pkgs.libxext
          pkgs.libxfixes
          pkgs.libxrandr
          pkgs.libxrender
          pkgs.libxtst
          pkgs.libxcb
          pkgs.libxt
          pkgs.nspr
          pkgs.nss
          pkgs.dbus
          pkgs.libglvnd
          pkgs.libgbm
          pkgs.mesa
          pkgs.ffmpeg
          pkgs.cups
          pkgs.libdrm
          pkgs.udev
          pkgs.fontconfig
          pkgs.freetype
          pkgs.zlib
          pkgs.libgpg-error
          pkgs.stdenv.cc.cc.lib
        ];
        runScript = "${geminiWeb2ApiBin}/bin/gemini-web2api";
      };

      geminiAssets = pkgs.runCommand "gemini-web2api-assets" { } ''
        mkdir -p $out/share
        cp -r ${geminiWeb2ApiBin}/share/* $out/share/
      '';
    in
    pkgs.symlinkJoin {
      name = "gemini-web2api-${version}";
      paths = [
        geminiFhs
        geminiAssets
      ];
    };

  antigravity2apiPkg =
    let
      src = inputs.antigravity2api;
      version = src.shortRev or "unstable";

      webDist = pkgs.stdenv.mkDerivation {
        pname = "antigravity2api-web";
        inherit version src;

        pnpmRoot = "web";

        nativeBuildInputs = [
          pkgs.nodejs_22
          pkgs.pnpmConfigHook
          pkgs.pnpm_11
        ];

        pnpmDeps = pkgs.fetchPnpmDeps {
          pname = "antigravity2api-web-${
            builtins.substring 0 12 (builtins.hashFile "sha256" "${src}/web/pnpm-lock.yaml")
          }";
          inherit version;
          src = "${src}/web";
          pnpm = pkgs.pnpm_11;
          fetcherVersion = 5;
          hash = "sha256-9AwX6scQJLubFOfPXfYdsbuKMtyK2YAqeWd8ZAwWwi8=";
        };

        buildPhase = ''
          runHook preBuild
          pnpm --dir web run build
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          cp -r internal/webui/dist $out
          runHook postInstall
        '';
      };

      antigravity2apiBin = pkgs.buildGoModule {
        pname = "antigravity2api";
        inherit version src;

        proxyVendor = true;
        vendorHash = "sha256-buOyNNsLaCSYC4Jy4/PPlTT0mf9RGAggsc7jrWkcPG8=";

        overrideModAttrs = _: {
          name = "antigravity2api-go-modules-${
            builtins.substring 0 12 (builtins.hashFile "sha256" "${src}/go.mod")
          }-${builtins.substring 0 12 (builtins.hashFile "sha256" "${src}/go.sum")}";
        };

        subPackages = [ "cmd/antigravity2api" ];
        tags = [
          "desktop"
          "production"
          "gtk3"
        ];
        ldflags = [
          "-s"
          "-w"
        ];
        doCheck = false;

        nativeBuildInputs = [
          pkgs.pkg-config
          pkgs.wrapGAppsHook3
        ];

        buildInputs = [
          pkgs.gtk3
          pkgs.webkitgtk_4_1
        ];

        postConfigure = ''
          rm -rf internal/webui/dist
          cp -r ${webDist} internal/webui/dist
        '';

        postInstall = ''
                    install -Dm644 internal/desktop/icon.png $out/share/icons/hicolor/256x256/apps/antigravity2api.png
                    mkdir -p $out/share/applications
                    cat << 'DESKTOP' > $out/share/applications/antigravity2api.desktop
          [Desktop Entry]
          Version=1.0
          Name=Antigravity2API
          Comment=Antigravity to OpenAI, Anthropic and Gemini compatible API
          Exec=antigravity2api
          Terminal=false
          Type=Application
          Icon=antigravity2api
          Categories=Network;Development;
          StartupWMClass=antigravity2api
          DESKTOP
        '';
      };

      antigravityFhs = pkgs.buildFHSEnv {
        name = "antigravity2api";
        targetPkgs = pkgs: [
          pkgs.cacert
          pkgs.gtk3
          pkgs.glib
          pkgs.pango
          pkgs.cairo
          pkgs.gdk-pixbuf
          pkgs.atk
          pkgs.at-spi2-atk
          pkgs.alsa-lib
          pkgs.libxkbcommon
          pkgs.libx11
          pkgs.libxcomposite
          pkgs.libxdamage
          pkgs.libxext
          pkgs.libxfixes
          pkgs.libxrandr
          pkgs.libxrender
          pkgs.libxtst
          pkgs.libxcb
          pkgs.libxt
          pkgs.nspr
          pkgs.nss
          pkgs.dbus
          pkgs.libglvnd
          pkgs.libgbm
          pkgs.mesa
          pkgs.ffmpeg
          pkgs.cups
          pkgs.libdrm
          pkgs.udev
          pkgs.fontconfig
          pkgs.freetype
          pkgs.zlib
          pkgs.libgpg-error
          pkgs.stdenv.cc.cc.lib
        ];
        runScript = "${antigravity2apiBin}/bin/antigravity2api";
      };

      antigravityAssets = pkgs.runCommand "antigravity2api-assets" { } ''
        mkdir -p $out/share
        cp -r ${antigravity2apiBin}/share/* $out/share/
      '';
    in
    pkgs.symlinkJoin {
      name = "antigravity2api-${version}";
      paths = [
        antigravityFhs
        antigravityAssets
      ];
    };

  sounduxPkg = pkgs.stdenv.mkDerivation {
    pname = "soundux";
    version = "0.2.8-unstable";

    src = pkgs.fetchgit {
      url = "https://github.com/Soundux/Soundux.git";
      rev = "e02845233221aff3261865afb7ea158d4a51bd52";
      fetchSubmodules = true;
      deepClone = false;
      hash = "sha256-Dc+6EqH/2TriT2zUYsF+Xe3O3+7DBTdbXqIEHu053Ik=";
    };

    nativeBuildInputs = with pkgs; [
      cmake
      pkg-config
      wrapGAppsHook3
    ];

    buildInputs = with pkgs; [
      pipewire
      libpulseaudio
      libx11
      libxi
      libxtst
      libwnck
      gtk3
      webkitgtk_4_1
      libappindicator-gtk3
      tl-expected
      openssl
      glib
      gst_all_1.gstreamer
      gst_all_1.gst-plugins-base
      gst_all_1.gst-plugins-good
    ];

    cmakeFlags = [ "-DCMAKE_POLICY_VERSION_MINIMUM=3.5" ];

    postPatch = ''
      substituteInPlace src/ui/impl/webview/lib/webviewpp/CMakeLists.txt \
        --replace-fail "webkit2gtk-4.0" "webkit2gtk-4.1"
      substituteInPlace CMakeLists.txt \
        --replace-fail 'set(CMAKE_INSTALL_PREFIX "/opt/soundux" CACHE PATH "Install path prefix, prepended onto install directories." FORCE)' "" \
        --replace-fail 'install(TARGETS soundux DESTINATION .)' 'install(TARGETS soundux DESTINATION bin)' \
        --replace-fail 'install(DIRECTORY "''${CMAKE_SOURCE_DIR}/build/dist" DESTINATION .)' 'install(DIRECTORY "''${CMAKE_SOURCE_DIR}/build/dist" DESTINATION bin)' \
        --replace-fail 'DESTINATION /usr/share/' 'DESTINATION share/'
      substituteInPlace lib/guardpp/CMakeLists.txt \
        --replace-fail 'include(FetchContent)' 'find_package(tl-expected REQUIRED)' \
        --replace-fail 'FetchContent_Declare(expected GIT_REPOSITORY "https://github.com/TartanLlama/expected")' "" \
        --replace-fail 'FetchContent_MakeAvailable(expected)' ""
      substituteInPlace deployment/soundux.desktop \
        --replace-fail "/opt/soundux/soundux" "soundux"
      substituteInPlace src/ui/impl/webview/webview.cpp \
        --replace-fail '"/usr/share/pixmaps/soundux.png"' "\"$out/share/pixmaps/soundux.png\""
      substituteInPlace src/helper/audio/linux/pipewire/forward.cpp \
        --replace-fail '"libpipewire-0.3.so.0"' '"${pkgs.pipewire}/lib/libpipewire-0.3.so.0"'
      substituteInPlace src/helper/audio/linux/pulseaudio/forward.cpp \
        --replace-fail '"libpulse.so.0"' '"${pkgs.libpulseaudio}/lib/libpulse.so.0"'
      substituteInPlace src/helper/icons/forward.cpp \
        --replace-fail '"libwnck-3.so.0"' '"${pkgs.libwnck}/lib/libwnck-3.so.0"'
      substituteInPlace src/helper/ytdl/youtube-dl.cpp \
        --replace-fail '"youtube-dl ' '"yt-dlp '
    '';

    preFixup = ''
      gappsWrapperArgs+=(
        --prefix PATH : ${
          pkgs.lib.makeBinPath (
            with pkgs;
            [
              ffmpeg
              yt-dlp
            ]
          )
        }
        --prefix LD_LIBRARY_PATH : ${
          pkgs.lib.makeLibraryPath (
            with pkgs;
            [
              pipewire
              libpulseaudio
              libwnck
            ]
          )
        }
      )
    '';
  };

  gtkshutdownPkg =
    (pkgs.callPackage (inputs.gtkshutdown + "/nix") {
      inputs = inputs.gtkshutdown.inputs;
      toolchain = pkgs.symlinkJoin {
        name = "rust-toolchain";
        paths = [
          pkgs.rustc
          pkgs.cargo
        ];
      };
    }).overrideAttrs
      (oldAttrs: {
        patches = (oldAttrs.patches or [ ]) ++ [
          ../../../stuff/patches/gtkshutdown.patch
        ];
      });

  rustHelpersPkg = inputs.rust-helpers.packages.${pkgs.stdenv.hostPlatform.system}.default;
  json2xPkg = pkgs.callPackage "${inputs.nixpkgs}/pkgs/pkgs-lib/formats/json2x/package.nix" { };
  app2unitPkg = pkgs.app2unit.overrideAttrs (oldAttrs: {
    postPatch = (oldAttrs.postPatch or "") + ''
      echo "app2unit(1)" > app2unit.1.scd
    '';
  });

  pythonPkg = pkgs.python3.withPackages (
    ps: with ps; [
      tkinter
      debugpy
      pynvim
    ]
  );

  nhPkg = pkgs.nh.overrideAttrs (prev: {
    postPatch = (prev.postPatch or "") + ''
      rom_vendor="$(find "$cargoDepsCopy" -maxdepth 2 -type d -name 'rom-*' -print -quit)"
      test -n "$rom_vendor"
      rm -rf "$rom_vendor/src"
      cp -r "${inputs.rom}/rom/src" "$rom_vendor/src"
      chmod -R u+w "$rom_vendor/src"
    '';
  });

  romSandbox = pkgs.runCommand "rom-sandboxed" { } ''
    mkdir -p "$out/bin" "$out/libexec"
    cp -L "${inputs.rom.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/rom" "$out/libexec/rom"

    substitute "${pkgs.writeShellScript "rom-bwrap-runner" ''
      STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/rom"
      CONFIG_DIR="''${XDG_CONFIG_HOME:-$HOME/.config}/rom"
      mkdir -p "$STATE_DIR" 2>/dev/null || true
      exec ${staticBwrap}/bin/bwrap \
        --unshare-all \
        --ro-bind /nix/store /nix/store \
        --dev /dev \
        --tmpfs /tmp \
        --bind "$STATE_DIR" "$STATE_DIR" \
        --ro-bind-try "$CONFIG_DIR" "$CONFIG_DIR" \
        --ro-bind-try /sys/fs/cgroup /sys/fs/cgroup \
        --chdir /tmp \
        @ROM_BIN@ "$@"
    ''}" "$out/bin/rom" \
      --replace-fail "@ROM_BIN@" "$out/libexec/rom"

    chmod +x "$out/bin/rom"
  '';

  nixSearchPkg = inputs.nix-search.packages.${pkgs.stdenv.hostPlatform.system}.default;
  heliumPkg = inputs.helium.packages.${pkgs.stdenv.hostPlatform.system}.default;

  translateZapretNixosPkg = pkgs.writeShellScriptBin "translate-zapret-nixos" (
    builtins.readFile ../../../stuff/system/packages/translate-zapret-nixos.sh
  );

  qt6ctPkg = pkgs.kdePackages.qt6ct.overrideAttrs (prev: {
    patches = prev.patches or [ ] ++ [ ../../../stuff/patches/qt6ct-shenanigans.patch ];
    buildInputs = prev.buildInputs or [ ] ++ [
      pkgs.kdePackages.kconfig
      pkgs.kdePackages.kcolorscheme
      pkgs.kdePackages.kiconthemes
      pkgs.kdePackages.qqc2-desktop-style
    ];
  });

  aria2Pkg = pkgs.aria2.overrideAttrs (prev: {
    patches = prev.patches or [ ] ++ [ ../../../stuff/patches/max-connection-to-unlimited.patch ];
  });

  anicliRuPkg =
    let
      workspace = inputs.uv2nix.lib.workspace.loadWorkspace {
        workspaceRoot = inputs.anicli-ru;
      };
      overlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };
      pythonSet =
        (pkgs.callPackage inputs.pyproject-nix.build.packages { python = pkgs.python312; }).overrideScope
          (
            lib.composeManyExtensions [
              inputs.pyproject-build-systems.overlays.default
              overlay
            ]
          );
      anicliPkg = pythonSet.anicli-ru;
      venv = pythonSet.mkVirtualEnv "anicli-ru-env" (
        workspace.deps.default // { anicli-ru = [ "all" ]; }
      );
    in
    pkgs.runCommand "anicli-ru-${anicliPkg.version or "latest"}"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
      }
      ''
        mkdir -p $out/bin
        makeWrapper ${venv}/bin/anicli-ru $out/bin/anicli-ru \
          --prefix PATH : ${lib.makeBinPath [ pkgs.mpv ]}
      '';

  diskoPkg = inputs.disko.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
    path = inputs.nixpkgs;
  };

  ventoyFullGtkPkg = pkgs.ventoy-full-gtk.overrideAttrs (
    _: prevAttrs: {
      postInstall = (prevAttrs.postInstall or "") + ''
        GUI_BIN="$(echo "$out"/share/ventoy/tool/*/Ventoy2Disk.gtk3)"
        cat << EOF > "$out/bin/ventoy-gui"
        #!${pkgs.bash}/bin/bash
        set -euo pipefail
        VENTOY_PATH="$out/share/ventoy"
        GUI_BIN="$GUI_BIN"
        if [ "\''${EUID}" -ne 0 ]; then
          exec pkexec env \
            PATH="\$PATH" \
            XDG_DATA_HOME="\$XDG_DATA_HOME" \
            WAYLAND_DISPLAY="\$XDG_RUNTIME_DIR/\$WAYLAND_DISPLAY" \
            DISPLAY="\$DISPLAY" \
            GTK_THEME="\$GTK_THEME" \
            "\$0" "\$@"
        fi
        cd "\$VENTOY_PATH"
        exec "\$GUI_BIN" "\$@"
        EOF
        chmod +x "$out/bin/ventoy-gui"
        wrapProgram "$out/bin/ventoy-gui" \
          --prefix PATH : "${pkgs.lib.makeBinPath prevAttrs.buildInputs}"
      '';
    }
  );

  aero-control-center = pkgs.stdenv.mkDerivation {
    pname = "aero-control-center";
    version = "0.1.0";
    src = inputs.aero-control-center;

    nativeBuildInputs = with pkgs; [
      cmake
      pkg-config
      qt6.wrapQtAppsHook
    ];

    buildInputs = with pkgs; [
      qt6.qtbase
      libusb1
    ];

    postInstall = ''
      if [ ! -d $out/bin ]; then
        mkdir -p $out/bin
        mv $out/AeroControlCenter $out/bin/ || true
      fi
      mkdir -p $out/lib/udev/rules.d
      if [ -f ../70-keyboard.rules ]; then
        cp ../70-keyboard.rules $out/lib/udev/rules.d/70-keyboard.rules
      fi
    '';
  };

  valentPkg = pkgs.valent.overrideAttrs (oldAttrs: {
    buildInputs = (oldAttrs.buildInputs or [ ]) ++ [ pkgs.wayland ];
    patches = (oldAttrs.patches or [ ]) ++ [
      ../../../stuff/patches/valent-wayland-clipboard.patch
    ];
  });

  run0editPkg = pkgs.stdenv.mkDerivation rec {
    pname = "run0edit";
    version = "0.7.2";
    src = inputs.run0edit;

    patches = [
      ../../../stuff/patches/run0edit.patch
    ];

    nativeBuildInputs = [ pkgs.python3 ];
    buildInputs = [ pkgs.python3 ];

    postPatch = ''
      substituteInPlace run0edit_main.py \
        --replace-fail '@VERSION@' '${version}' \
        --replace-fail '@LIBEXECDIR@' "$out/libexec" \
        --replace-fail '@SYSCONFDIR@' "/etc"
    '';

    installPhase = ''
      mkdir -p $out/bin $out/libexec/run0edit $out/share/run0edit
      install -m 0755 run0edit_main.py $out/bin/run0edit
      install -m 0644 run0edit_inner.py $out/libexec/run0edit/run0edit_inner.py
      install -m 0644 data/editor.conf $out/share/run0edit/editor.conf
      patchShebangs $out/bin/run0edit $out/libexec/run0edit/run0edit_inner.py
    '';
  };

  myHomePackages = [
    pkgs.mokutil
    pkgs.clang
    pkgs.gnutar
    pkgs.procps
    pkgs.seahorse
    pkgs.vista-fonts
    pkgs.corefonts
    pkgs.noto-fonts
    pkgs.noto-fonts-monochrome-emoji
    pkgs.liberation_ttf
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.usbguard-notifier
    pkgs.dnsutils
    pkgs.nmap
    pkgs.podman-compose
    pkgs.cmatrix
    pkgs.dpkg
    pkgs.libinput
    pkgs.nftables
    pkgs.wev
    pkgs.binwalk
    pkgs.iperf3
    pkgs.wireshark
    pkgs.gh
    pkgs.git-repo
    pkgs.gpu-screen-recorder-gtk
    pkgs.qdiskinfo
    pkgs.blender
    pkgs.krita
    pkgs.mindustry
    pkgs.dash
    pkgs.openrgb-with-all-plugins
    pkgs.stress-ng
    pkgs.furmark
    pkgs.xrdb
    pkgs.nix-tree
    pkgs.n-m3u8dl-re
    pkgs.yt-dlp
    pkgs.pi-coding-agent
    pkgs.gcc
    pkgs.libcap-text-verifier
    pkgs.curl
    pkgs.libxkbcommon
    pkgs.sbsigntool
    pkgs.slurp
    pkgs.w3m-nographics
    pkgs.testdisk
    pkgs.ms-sys
    pkgs.efivar
    pkgs.parted
    pkgs.gptfdisk
    pkgs.ccrypt
    pkgs.cryptsetup
    pkgs.fuse
    pkgs.fuse3
    pkgs.sshfs-fuse
    pkgs.screen
    pkgs.tcpdump
    pkgs.sdparm
    pkgs.hdparm
    pkgs.pciutils
    pkgs.innoextract
    pkgs.btrfs-progs
    pkgs.unzip
    pkgs.dosfstools
    pkgs.gum
    pkgs.tpm2-tools
    pkgs.uefi-firmware-parser
    pkgs.uefitool
    pkgs.flashrom
    pkgs.acpica-tools
    pkgs.lolcat
    pkgs.openssl
    pkgs.gparted
    pkgs.neovim-remote
    pkgs.stylua
    pkgs.rustup
    pkgs.vscode-extensions.ms-vscode.cpptools
    pkgs.hexpatch
    pkgs.tinyxxd
    pkgs.bash-language-server
    pkgs.vscode-langservers-extracted
    pkgs.jdt-language-server
    pkgs.lua-language-server
    pkgs.taplo
    pkgs.yaml-language-server
    pkgs.shellcheck
    pkgs.shfmt
    pkgs.tmux
    pkgs.tree-sitter
    pkgs.ripgrep
    pkgs.ruff
    pkgs.basedpyright
    pkgs.cmake-lint
    pkgs.clang-tools
    pkgs.cmake-language-server
    pkgs.flatpak
    pkgs.duperemove
    pkgs.psmisc
    pkgs.woeusb-ng
    pkgs.wimlib
    pkgs.lsof
    pkgs.ddrescue
    pkgs.smartmontools
    pkgs.uv
    pkgs.bindfs
    pkgs.imagemagick
    pkgs.tonelib-gfx
    pkgs.sbctl
    pkgs.virt-manager
    pkgs.jq
    pkgs.wayvr
    pkgs.xhost
    pkgs.dante
    pkgs.patchelf
    pkgs.file
    pkgs.gnome-boxes
    pkgs.lsd
    pkgs.e2fsprogs
    pkgs.efitools
    pkgs.efibootmgr
    pkgs.kdiskmark
    pkgs.nixfmt
    pkgs.sshfs
    pkgs.gdu
    pkgs.nixd
    pkgs.go
    pkgs.gopls
    pkgs.delve
    pkgs.gotools
    pkgs.wget
    pkgs.zenity
    pkgs.linuxConsoleTools
    pkgs.evtest
    pkgs.bat
    pkgs.nvme-cli
    pkgs.ethtool
    pkgs.killall
    pkgs.unrar
    pkgs.zip
    pkgs.dmidecode
    pkgs.usbutils
    pkgs.adwaita-icon-theme
    pkgs.vmpk
    pkgs.socat
    pkgs.neovide
    pkgs._7zz-rar
    pkgs.crudini
    pkgs.lndir
    pkgs.texinfoInteractive
    pkgs.xkbcomp
    pkgs.nvtopPackages.full
    pkgs.xkeyboard-config
    pkgs.libX11
    pkgs.scanmem
    pkgs.comma
    pkgs.remmina
    pkgs.mangohud
    pkgs.jdk25
    pkgs.moonlight-qt
    pkgs.osu-lazer-bin
    pkgs.xonotic
    pkgs.supertux
    pkgs.supertuxkart
    pkgs.pavucontrol
    pkgs.qalculate-gtk
    pkgs.distrobox
    pkgs.qbittorrent
    pkgs.gdb
    pkgs.wiggle
    pkgs.nodejs
    pkgs.libreoffice
    pkgs.protonplus
    pkgs.gimp3-with-plugins
    pkgs.gamescope
    pkgs.android-tools
    pkgs.compsize
    pkgs.erofs-utils
    pkgs.gsettings-desktop-schemas
    pkgs.resources
    pkgs.quickshell
    pkgs.hunspell
    pkgs.hunspellDicts.en_US-large
    pkgs.hunspellDicts.ru_RU
    pkgs.libsForQt5.qt5ct
    pkgs.libsForQt5.qtstyleplugin-kvantum
    pkgs.kdePackages.qtstyleplugin-kvantum
    pkgs.kdePackages.qtdeclarative
    pkgs.kdePackages.kdenlive
    pkgs.yad
    pkgs.rsync
    pkgs.strace
    pkgs.nix-diff
    pkgs.migrate-to-uv
    pkgs.ssdeep
    pkgs.gtk3
    pkgs.kdePackages.kservice
    pkgs.libsForQt5.qtsvg
    pkgs.kdePackages.qtsvg
    pkgs.kdePackages.dolphin
    pkgs.kdePackages.ark
    pkgs.pulseaudio
    pkgs.nautilus
    pkgs.file-roller
    pkgs.libnotify
    pkgs.brightnessctl
    pkgs.qimgv
    pkgs.myxer
    pkgs.ffmpeg-full
    pkgs.ffmpegthumbnailer
    pkgs.hyprpicker
    pkgs.wttrbar
    pkgs.makeWrapper
    pkgs.makeBinaryWrapper
    pkgs.dieHook
    pkgs.shellcheck.doc
    pkgs.python3Packages.xmltodict

    valentPkg
    aero-control-center
    rustHelpersPkg
    json2xPkg
    diskoPkg
    ventoyFullGtkPkg
    translateZapretNixosPkg
    nhPkg
    app2unitPkg
    run0editPkg
    pythonPkg
    nixSearchPkg
    heliumPkg
    qt6ctPkg
    aria2Pkg
    gtkshutdownPkg
    anicliRuPkg

    aistudio2apiSandbox
    geminiWeb2ApiSandbox
    antigravity2apiSandbox
    romSandbox
    sounduxSandbox
    prismLauncherSandbox
    discordSandbox
    ayugramDesktopSandbox
    enteAuthSandbox
  ];

  #steamExcludedPackages = [
  #  osConfig.boot.kernelPackages.ryzen-smu
  #  pkgs.kmod
  #  pkgs.libreoffice
  #  pkgs.obs-studio
  #  pkgs.obs-studio-plugins.obs-vaapi
  #  pkgs.jdk25
  #  pkgs.jdt-language-server
  #];

  #isExcludedFromSteam =
  #  p:
  #  let
  #    pName = p.pname or (p.name or (lib.getName p));
  #  in
  #  lib.any (
  #    ex:
  #    let
  #      exName = ex.pname or (ex.name or (lib.getName ex));
  #    in
  #    ex == p || exName == pName || lib.hasInfix exName pName
  #  ) steamExcludedPackages;

  #allSteamExtraPackages = lib.filter (p: !isExcludedFromSteam p) (
  #  lib.unique (myHomePackages ++ steamExtraPackages ++ (osConfig.environment.systemPackages or [ ]))
  #);

  collectPairedPackages =
    pkg:
    if pkg ? passthru.pairedPackages then
      pkg.passthru.pairedPackages
    else
      lib.unique ([ pkg ] ++ (map (outName: pkg.${outName} or pkg) (pkg.outputs or [ ])));

  processMergedPackage =
    entry:
    let
      winner = builtins.elemAt entry 0;
      loser = builtins.elemAt entry 1;
      name1 = winner.pname or (lib.getName winner);
      name2 = loser.pname or (lib.getName loser);
      name =
        if builtins.length entry > 2 && builtins.elemAt entry 2 != null then
          builtins.elemAt entry 2
        else
          "${name1}-${name2}-merged";
      prio =
        if builtins.length entry > 3 && builtins.elemAt entry 3 != null then
          builtins.elemAt entry 3
        else
          lib.meta.defaultPriority;
      pairedPackages = lib.unique (collectPairedPackages winner ++ collectPairedPackages loser);
      merged = pkgs.buildEnv {
        inherit name;
        paths = [
          (lib.hiPrio winner)
          (lib.lowPrio loser)
        ];
        extraOutputsToInstall = osConfig.environment.extraOutputsToInstall or [ ] ++ [ "lib" ];
      };
    in
    (lib.setPrio prio merged)
    // {
      passthru = (merged.passthru or { }) // {
        inherit pairedPackages;
      };
    };

  mergedPackages = [
    [
      pkgs.clang
      pkgs.gcc
    ]
    [
      pkgs.dconf
      osConfig.services.gvfs.package
    ]
    [
      pkgs.tinyxxd
      pkgs.neovim
    ]
    [
      pkgs.gnutar
      pkgs.cpio
    ]
    [
      osConfig.scripts."pkexec.rs"
      pkgs.polkit
    ]
    [
      osConfig.scripts."run0.rs"
      (processMergedPackage [
        pkgs.systemd
        pkgs.openresolv
      ])
    ]
    [
      pkgs.procps
      (processMergedPackage [
        (processMergedPackage [
          pkgs.shadow
          pkgs.util-linux
        ])
        pkgs.coreutils-full
      ])
      "core-unix-tools-merged"
    ]
  ];

  mergedPairs = map processMergedPackage mergedPackages;

  allPairedPackages = lib.unique (lib.concatMap (m: m.passthru.pairedPackages) mergedPairs);

  isPaired =
    p:
    let
      pName = p.pname or (lib.getName p);
    in
    lib.any (
      paired:
      let
        pairedName = paired.pname or (lib.getName paired);
      in
      p == paired
      || (p ? outPath && paired ? outPath && p.outPath == paired.outPath)
      || pName == pairedName
    ) allPairedPackages;

  allHomePackages = lib.unique (
    (lib.filter (p: !isPaired p) myHomePackages)
    ++ (lib.filter (p: !isPaired p) (osConfig.environment.systemPackages or [ ]))
    ++ steamExtraPackages
    ++ mergedPairs
    ++ [
      steamSandbox
      steamSandbox.run
    ]
  );

  strictHomeEnv = pkgs.buildEnv {
    name = "strict-home-env";
    paths = map (lib.setPrio lib.meta.defaultPriority) allHomePackages;
    inherit (config.home) extraOutputsToInstall;
    ignoreCollisions = false;
    checkCollisionContents = true;
  };

in
{
  home.extraOutputsToInstall = osConfig.environment.extraOutputsToInstall ++ [ "lib" ];

  home.packages = allHomePackages;

  home.sessionVariables = {
    NIX_LD_LIBRARY_PATH = "${strictHomeEnv}/lib";
  };

  xdg.dataFile."home-env".source = strictHomeEnv;

  systemd.user.services.valent = {
    Install.WantedBy = [ "graphical-session.target" ];

    Unit = {
      Description = "Valent KDE Connect Service";
      PartOf = [ "graphical-session.target" ];
      Requires = [ "ssh-agent.service" ];
      After = [
        "graphical-session.target"
        "ssh-agent.service"
      ];
    };

    Service = {
      Type = "dbus";
      BusName = "ca.andyholmes.Valent";
      ExecStart = "${valentPkg}/bin/valent --gapplication-service";
      Environment = "SSH_AUTH_SOCK=%t/ssh-agent";
      Restart = "on-failure";
      RestartSec = 3;

      # Uses xdg-desktop-portal -> stays in host userns (no mount/UTS/net ns)
      NoNewPrivileges = true;
      LockPersonality = true;
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      KeyringMode = "private";
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
        "AF_NETLINK"
        "AF_BLUETOOTH"
      ];
      SystemCallArchitectures = "native";
      SystemCallErrorNumber = "EPERM";
      SystemCallFilter = [
        "@system-service"
        "~@mount"
        "~@module"
        "~@raw-io"
        "~@reboot"
        "~@swap"
        "~@clock"
        "~@debug"
        "~@obsolete"
        "~@cpu-emulation"
      ];
    };
  };
}
