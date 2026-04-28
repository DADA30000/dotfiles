{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-flatpak.url = "github:gmodena/nix-flatpak/latest";
    # determinate = {
    #   url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    #   inputs = {
    #     nixpkgs.follows = "nixpkgs";
    #     nix.inputs = {
    #       # nixpkgs.follows = "nixpkgs";
    #       nixpkgs-23-11.follows = "nixpkgs";
    #       nixpkgs-regression.follows = "nixpkgs";
    #     };
    #   };
    # };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs = {
        pyproject-nix.follows = "pyproject-nix";
        uv2nix.follows = "uv2nix";
        nixpkgs.follows = "nixpkgs";
      };
    };
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        hyprland.follows = "hyprland";
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
      url = "github:CosmoCreeper/Sine";
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
  };

  outputs =
    {
      self,
      ...
    }@inputs:
    let
      # Needed for offline installation, so that I could access config.system.build.toplevel without causing infinite recursion
      iso-wrapper = (
        prev_system:
        let
          system = prev_system // {
            specialArgs = (prev_system.specialArgs or {}) // {
              user-hash = null;
              user = user_iso;
              inherit
                inputs
                self
                umport
                system-modules
                home-modules
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

      umport = (import ./modules/umport.nix { inherit (inputs.nixpkgs) lib; }).umport;

      system-modules = umport {
        paths = [ ./modules/system ];
        recursive = false;
      };

      home-modules =
        umport {
          paths = [ ./modules/home ];
          recursive = false;
        }
        ++ [
          inputs.nix-index-database.homeModules.nix-index
          inputs.zen-browser.homeModules.twilight
        ];

      modules-list = [
        # inputs.determinate.nixosModules.default
        inputs.impermanence.nixosModules.impermanence
        inputs.lanzaboote.nixosModules.lanzaboote
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager = {
            extraSpecialArgs = {
              inherit
                inputs
                self
                umport
                home-modules
                ;
            };
            backupFileExtension = "backup";
            overwriteBackup = true;
            useGlobalPkgs = true;
            useUserPackages = true;
            users.${user} = { imports = home-modules; };
            users.root = import ./modules/home/shared/home-root.nix;
          };
        }
      ]
      ++ system-modules;

      user = "l0lk3k";
      user-hash = "$y$j9T$4Q2h.L51xcYILK8eRbquT1$rtuCEsO2kdtTLjUL3pOwvraDy9M773cr4hsNaKcSIs1";
      user_iso = "nixos";
    in
    {
      nixosConfigurations = {
        nixos = inputs.nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit
              inputs
              user
              user-hash
              self
              umport
              system-modules
              home-modules
              ;
          };
          modules = modules-list ++ [
            ./machines/nixos/configuration.nix
            ./machines/nixos/hardware-configuration.nix
          ];
        };
        laptop = inputs.nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit
              inputs
              user
              user-hash
              self
              umport
              system-modules
              home-modules
              ;
          };
          modules = modules-list ++ [
            ./machines/laptop/configuration.nix
            ./machines/laptop/hardware-configuration.nix
          ];
        };
        iso = iso-wrapper { modules = modules-list ++ [ ./machines/iso/configuration.nix ]; };
      };
    };
}
