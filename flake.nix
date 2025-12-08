{
  inputs = {
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    quickshell = {
      url = "github:quickshell-mirror/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
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
    nos = {
      url = "github:madsbv/nix-options-search";
      flake = false;
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    cape = {
      url = "github:kevoreilly/CAPEv2";
      flake = false;
    };
    xrizer = {
      url = "github:Supreeeme/xrizer";
      flake = false;
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    anicli-ru = {
      url = "github:vypivshiy/ani-cli-ru";
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
    hazy = {
      url = "github:Astromations/Hazy";
      flake = false;
    };
    pmparser = {
      # This is for Spicetify
      url = "github:ouadev/proc_maps_parser";
      flake = false;
    };
    libcef-transparency-linux = {
      # This is for Spicetify
      url = "github:fixpointer/libcef-transparency-linux";
      flake = false;
    };
    nix-alien = {
      url = "github:thiagokokada/nix-alien";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };
    fx-autoconfig = {
      url = "github:MrOtherGuy/fx-autoconfig";
      flake = false;
    };
    sine = {
      url = "github:CosmoCreeper/Sine";
      flake = false;
    };
    nebula-zen = {
      url = "github:JustAdumbPrsn/Zen-Nebula";
      flake = false;
    };
    nix-search = {
      url = "github:diamondburned/nix-search";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-flatpak.url = "github:gmodena/nix-flatpak/latest";
    impermanence.url = "github:nix-community/impermanence";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      ...
    }@inputs:
    let
      # Needed for offline installation, so that I could access config.system.build.toplevel without causing infinite recursion
      iso-wrapper = (
        prev_system:
        let
          system = prev_system // {
            specialArgs = prev_system.specialArgs // {
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
          orig_system = nixpkgs.lib.nixosSystem (
            system
            // {
              specialArgs = system.specialArgs // {
                wrapped = false;
                orig = { };
              };
            }
          );
        in
        nixpkgs.lib.nixosSystem (
          system
          // {
            specialArgs = system.specialArgs // {
              wrapped = true;
              orig = orig_system;
            };
            modules = system.modules ++ [
              "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            ];
          }
        )
      );

      umport = (import ./modules/umport.nix { inherit (nixpkgs) lib; }).umport;

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
        inputs.impermanence.nixosModules.impermanence
        home-manager.nixosModules.home-manager
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
            users.root = import ./machines/nixos/home-root.nix;
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
        nixos = nixpkgs.lib.nixosSystem {
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
            min-flag = false;
            avg-flag = false;
          };
          modules = modules-list ++ [
            ./machines/nixos/configuration.nix
            ./machines/nixos/hardware-configuration.nix
          ];
        };
        iso = iso-wrapper {
          specialArgs = {
            min-flag = false;
            avg-flag = false;
          };
          modules = modules-list ++ [ ./machines/iso/configuration.nix ];
        };
        iso8G = iso-wrapper {
          specialArgs = {
            min-flag = false;
            avg-flag = true;
          };
          modules = modules-list ++ [ ./machines/iso8G/configuration.nix ];
        };
        isoMIN = iso-wrapper {
          specialArgs = {
            min-flag = true;
            avg-flag = false;
          };
          modules = modules-list ++ [ ./machines/isoMIN/configuration.nix ];
        };
      };
    };
}
