{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-flatpak.url = "github:gmodena/nix-flatpak/latest";
    llama-cpp = {
      url = "github:ikawrakow/ik_llama.cpp";
      flake = false;
    };
    nix-amd-ai = {
      url = "github:noamsto/nix-amd-ai";
      flake = false;
    };
    way-secure = {
      url = "sourcehut:~whynothugo/way-secure";
      flake = false;
    };
    zapret-flowseal = {
      url = "github:Flowseal/zapret-discord-youtube";
      flake = false;
    };
    vencord-src = {
      url = "github:Vendicated/Vencord";
      flake = false;
    };
    my-internet = {
      url = "github:sameerasw/my-internet";
      flake = false;
    };
    nos = {
      url = "github:madsbv/nix-options-search";
      flake = false;
    };
    hazy = {
      url = "github:Astromations/Hazy";
      flake = false;
    };
    pmparser = {
      url = "github:ouadev/proc_maps_parser";
      flake = false;
    };
    libcef-transparency-linux = {
      url = "github:fixpointer/libcef-transparency-linux";
      flake = false;
    };
    cape = {
      url = "github:kevoreilly/CAPEv2";
      flake = false;
    };
    xrizer = {
      url = "github:Supreeeme/xrizer";
      flake = false;
    };
    sine = {
      url = "github:CosmoCreeper/Sine/v2.3.3";
      flake = false;
    };
    sine-bootloader = {
      url = "github:sineorg/bootloader";
      flake = false;
    };
    nebula-zen = {
      url = "github:JustAdumbPrsn/Zen-Nebula";
      flake = false;
    };
    susfs4ksu = {
      url = "gitlab:simonpunk/susfs4ksu/gki-android16-6.12";
      flake = false;
    };
    android-kernel-src = {
      url = "git+https://android.googlesource.com/kernel/common?ref=refs/heads/android16-6.12-2025-12&shallow=1";
      flake = false;
    };
    ksu-next = {
      url = "git+https://github.com/pershoot/KernelSU-Next?ref=dev-susfs";
      flake = false;
    };
    monado = {
      url = "gitlab:xytovl/monado/shared-fences?host=gitlab.freedesktop.org";
      flake = false;
    };
    gigabyte-laptop-wmi = {
      url = "github:tangalbert919/gigabyte-laptop-wmi";
      flake = false;
    };
    waywallen = {
      url = "github:waywallen/waywallen/v0.2.0";
      flake = false;
    };
    open-wallpaper-engine = {
      url = "github:waywallen/open-wallpaper-engine/v0.1.6";
      flake = false;
    };
    rstd = {
      url = "github:hypengw/rstd/629bda81eb98856ca023f0f87f57dde8d22b4823";
      flake = false;
    };
    ncrequest = {
      url = "github:hypengw/ncrequest/404868aa2aa4481e262f25d8f7d053f42b61b7b8";
      flake = false;
    };
    wavsen = {
      url = "github:hypengw/wavsen/c714a4fc59a689a80b3b537ee8ef501c363a841f";
      flake = false;
    };
    qmlmaterial = {
      url = "github:hypengw/QmlMaterial/c36528593c70d67c8bac8fc7dea579702a7e8aff";
      flake = false;
    };
    qextra = {
      url = "github:hypengw/QExtra/26e4b4134a05d35676f02f8b0e82a6130d877695";
      flake = false;
    };
    spirv-reflect = {
      url = "github:KhronosGroup/SPIRV-Reflect/vulkan-sdk-1.4.321.0";
      flake = false;
    };
    btop = {
      url = "github:aristocratos/btop";
      flake = false;
    };
    fluent-gtk-theme = {
      url = "github:vinceliuice/Fluent-gtk-theme";
      flake = false;
    };
    bibata-modern-hyprcursor = {
      url = "github:LOSEARDES77/Bibata-Cursor-hyprcursor";
      flake = false;
    };
    helium = {
      url = "github:schembriaiden/helium-browser-nix-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    wivrn = {
      url = "github:WiVRn/WiVRn";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    android-nixpkgs = {
      url = "github:tadfisher/android-nixpkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpak = {
      url = "github:DADA30000/nixpak";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-cachyos-kernel = {
      url = "github:xddxdd/nix-cachyos-kernel/release";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    split-monitor-workspaces = {
      url = "github:zjeffer/split-monitor-workspaces";
      inputs.hyprland.follows = "hyprland";
    };
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs-xr = {
      url = "github:nix-community/nixpkgs-xr";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    quickshell = {
      url = "github:quickshell-mirror/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland = {
      url = "github:hyprwm/Hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pipewire-screenaudio = {
      url = "github:IceDBorn/pipewire-screenaudio";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-search = {
      url = "github:diamondburned/nix-search";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    chaotic = {
      url = "github:chaotic-cx/nyx";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };
    nix-mineral = {
      url = "github:cynicsketch/nix-mineral";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        ndg.inputs.nixpkgs.follows = "nixpkgs";
      };
    };
    nix-alien = {
      url = "github:thiagokokada/nix-alien";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nix-index-database.follows = "nix-index-database";
      };
    };
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        pyproject-nix.follows = "pyproject-nix";
      };
    };
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        hyprland.follows = "hyprland";
      };
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs = {
        pyproject-nix.follows = "pyproject-nix";
        uv2nix.follows = "uv2nix";
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs =
    {
      ...
    }@inputs:
    let
      # Needed for offline installation, so that I could access config.system.build.toplevel without causing infinite recursion
      iso-wrapper = (
        prev_system:
        let
          system = prev_system // {
            specialArgs = (prev_system.specialArgs or { }) // {
              user-hash = null;
              user = user_iso;
              inherit
                inputs
                system-modules
                home-modules
                listFiles
                ;
            };
          };
          orig_system = inputs.nixpkgs.lib.nixosSystem (
            system
            // {
              specialArgs = system.specialArgs // {
                wrapped = false;
                orig = { };
              };
            }
          );
        in
        inputs.nixpkgs.lib.nixosSystem (
          system
          // {
            specialArgs = system.specialArgs // {
              wrapped = true;
              orig = orig_system;
            };
            modules = system.modules ++ [
              "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            ];
          }
        )
      );

      listFiles =
        paths:
        let
          listSingleDir =
            p:
            if builtins.pathExists p then
              map (name: p + "/${name}") (builtins.attrNames (builtins.readDir p))
            else
              throw "The specified path '${toString p}' does not exist.";
        in
        builtins.concatMap listSingleDir paths;

      system-modules = listFiles [
        ./modules/system
        ./modules/universal
      ];

      home-modules =
        listFiles [
          ./modules/home
          ./modules/universal
        ]
        ++ [
          inputs.nix-index-database.homeModules.nix-index
          inputs.zen-browser.homeModules.twilight
        ];

      modules-list = [
        inputs.nix-mineral.nixosModules.nix-mineral
        inputs.impermanence.nixosModules.impermanence
        inputs.lanzaboote.nixosModules.lanzaboote
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager = {
            extraSpecialArgs = {
              inherit
                inputs
                home-modules
                listFiles
                ;
            };
            backupFileExtension = "backup";
            overwriteBackup = true;
            useGlobalPkgs = true;
            useUserPackages = true;
            users.root = import ./modules/home/shared/home-root.nix;
            sharedModules = [
              { home.stateVersion = "26.05"; }
            ]
            ++ home-modules;
          };
        }
      ]
      ++ system-modules;

      mkMachine =
        hostname:
        inputs.nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit
              inputs
              user
              user-hash
              system-modules
              home-modules
              listFiles
              ;
          };
          modules = modules-list ++ [
            ./machines/${hostname}/configuration.nix
            ./machines/${hostname}/hardware-configuration.nix
            { networking.hostName = hostname; }
          ];
        };

      user = "l0lk3k";
      user-hash = "$y$j9T$4Q2h.L51xcYILK8eRbquT1$rtuCEsO2kdtTLjUL3pOwvraDy9M773cr4hsNaKcSIs1";
      user_iso = "nixos";
    in
    {
      nixosConfigurations = {
        nixos = mkMachine "nixos";
        laptop = mkMachine "laptop";
        iso = iso-wrapper { modules = modules-list ++ [ ./machines/iso/configuration.nix ]; };
      };
    };
}
