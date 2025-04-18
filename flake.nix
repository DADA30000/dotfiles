{
  inputs = {
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hypr-dynamic-cursors = {
      url = "github:VirtCode/hypr-dynamic-cursors";
      inputs.hyprland.follows = "hyprland";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpak = {
      url = "github:nixpak/nixpak";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fabric = {
      url = "github:Fabric-Development/fabric";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fabric-gray = {
      url = "github:Fabric-Development/gray";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fabric-cli = {
      url = "github:HeyImKyu/fabric-cli";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    #hyprland.url = "github:hyprwm/Hyprland/v0.46.2";
    hyprland.url = "github:hyprwm/Hyprland";
    #chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    pipewire-screenaudio.url = "github:IceDBorn/pipewire-screenaudio";
    nix-alien.url = "github:thiagokokada/nix-alien";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    nix-flatpak.url = "github:gmodena/nix-flatpak";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    impermanence.url = "github:nix-community/impermanence";
    nix-search.url = "github:diamondburned/nix-search";
  };

  outputs =
    { nixpkgs, home-manager, ... }@inputs:
    let
      system = "x86_64-linux";
      overlays = [ 
        (final: prev: {fabric-run-widget = inputs.fabric.packages.${system}.run-widget;})
        (final: prev: {fabric = inputs.fabric.packages.${system}.default;})
        (final: prev: {fabric-cli = inputs.fabric-cli.packages.${system}.default;})
        (final: prev: {fabric-gray = inputs.fabric-gray.packages.${system}.default;})
        inputs.fabric.overlays.${system}.default
      ];
    in
    {
      nixosConfigurations = {
        nixos = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs system;
            pkgs = import nixpkgs {
              system = system;
              overlays = overlays;
              config.allowUnfree = true;
            };
          };
          
          modules = [
            ./machines/nixos/configuration.nix
            inputs.nix-index-database.nixosModules.nix-index
            #inputs.chaotic.nixosModules.default
            inputs.impermanence.nixosModules.impermanence
            home-manager.nixosModules.home-manager 
            {
              home-manager = {
                extraSpecialArgs = {
                  inherit inputs system;
                };
                backupFileExtension = "backup";
                useGlobalPkgs = true;
                users.l0lk3k = import ./machines/nixos/home.nix;
                useUserPackages = true;
              };
              nixpkgs.overlays = [
                overlays
              ];
            }
          ];
        };
        iso = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs system;
          };
          modules = [
            ./machines/iso/configuration.nix
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            inputs.nix-index-database.nixosModules.nix-index
            inputs.impermanence.nixosModules.impermanence
            #inputs.chaotic.nixosModules.default
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                extraSpecialArgs = {
                  inherit inputs system;
                };
                backupFileExtension = "backup";
                useGlobalPkgs = true;
                users.nixos = import ./machines/nixos/home.nix;
                useUserPackages = true;
              };
            }
          ];
        };
      };
      homeConfigurations = {
        l0lk3k = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [
            ./machines/nixos/home-options.nix
          ];
          extraSpecialArgs = {
            inherit inputs system;
          };
        };
      };
    };
}
