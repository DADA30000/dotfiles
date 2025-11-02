{
  inputs = {
    determinate = {
      url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
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
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nur = {
      url = "github:nix-community/NUR";
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
    #hypr-dynamic-cursors = {
    #  url = "github:VirtCode/hypr-dynamic-cursors";
    #  inputs.hyprland.follows = "hyprland";
    #  inputs.nixpkgs.follows = "nixpkgs";
    #};
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    #nixpak = {
    #  url = "github:nixpak/nixpak";
    #  inputs.nixpkgs.follows = "nixpkgs";
    #};
    #fabric = {
    #  url = "github:Fabric-Development/fabric";
    #  inputs.nixpkgs.follows = "nixpkgs";
    #};
    #fabric-gray = {
    #  url = "github:Fabric-Development/gray";
    #  inputs.nixpkgs.follows = "nixpkgs";
    #};
    #fabric-cli = {
    #  url = "github:HeyImKyu/fabric-cli";
    #  inputs.nixpkgs.follows = "nixpkgs";
    #};
    #hyprpanel = {
    #  url = "github:DADA30000/HyprPanel/json";
    #  inputs.nixpkgs.follows = "nixpkgs";
    #};
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
      inputs.nixpkgs.follows = "nixpkgs";
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
      #iso-wrapper = (orig_name: system: 
      #  builtins.listToAttrs [
      #    { name = orig_name; value = nixpkgs.lib.nixosSystem (system // { specialArgs = system.specialArgs // { recursion-breaker = true; }; }); }
      #    { name = "${orig_name}_orig"; value = nixpkgs.lib.nixosSystem (system // { specialArgs = system.specialArgs // { recursion-breaker = false; }; }); }
      #  ]
      #);
      # Needed for offline installation, so that I could access config.system.build.toplevel without causing infinite recursion
      iso-wrapper = (system: 
        let
          orig_system = nixpkgs.lib.nixosSystem (system // { specialArgs = system.specialArgs // { wrapped = false; orig = {}; }; });
        in
          nixpkgs.lib.nixosSystem (system // { specialArgs = system.specialArgs // { wrapped = true; orig = orig_system; }; })
      );
      umport = (import ./modules/umport.nix {inherit (nixpkgs) lib;}).umport;
      modules-list = [
        inputs.impermanence.nixosModules.impermanence
        home-manager.nixosModules.home-manager
        # inputs.determinate.nixosModules.default
        {
          home-manager = {
            extraSpecialArgs = {
              inherit inputs self umport;
            };
            backupFileExtension = "backup";
            useGlobalPkgs = true;
            useUserPackages = true;
            users.root = import ./machines/nixos/home-root.nix;
          };
        }
      ];
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
              ;
            min-flag = false;
            avg-flag = false;
          };
          modules = modules-list ++ [
            ./machines/nixos/configuration.nix
            { home-manager.extraSpecialArgs = { avg-flag = false; min-flag = false; }; }
            { home-manager.users."${user}" = import ./machines/nixos/home.nix; }
          ];
        };
        iso = iso-wrapper {
          specialArgs = {
            user = user_iso;
            user-hash = null;
            min-flag = false;
            avg-flag = false;
            inherit inputs self umport;
          };
          modules = modules-list ++ [
            { home-manager.extraSpecialArgs = { avg-flag = false; min-flag = false; }; }
            ./machines/iso/configuration.nix
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          ];
        };
        iso8G = iso-wrapper {
          specialArgs = {
            user = user_iso;
            user-hash = null;
            min-flag = false;
            avg-flag = true;
            inherit inputs self umport;
          };
          modules = modules-list ++ [
            { home-manager.extraSpecialArgs = { avg-flag = true; min-flag = false; }; }
            ./machines/iso8G/configuration.nix
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          ];
        };
        isoMIN = iso-wrapper {
          specialArgs = {
            user = user_iso;
            user-hash = null;
            min-flag = true;
            avg-flag = false;
            inherit inputs self umport;
          };
          modules = modules-list ++ [
            { home-manager.extraSpecialArgs = { avg-flag = false; min-flag = true; }; }
            ./machines/isoMIN/configuration.nix
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          ];
        };
      };
    };
}
