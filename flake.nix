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
    #hyprland.url = "github:hyprwm/Hyprland/v0.46.2";
    hyprland.url = "github:hyprwm/Hyprland";
    #chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    pipewire-screenaudio.url = "github:IceDBorn/pipewire-screenaudio";
    nix-alien.url = "github:thiagokokada/nix-alien";
    nix-flatpak.url = "github:gmodena/nix-flatpak";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-search.url = "github:diamondburned/nix-search";
  };

  outputs =
    { nixpkgs, home-manager, ... }@inputs:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations = {
        nixos = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs system;
          };
          modules = [
            ./machines/nixos/configuration.nix
            inputs.nix-index-database.nixosModules.nix-index
            #inputs.chaotic.nixosModules.default
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
            #inputs.chaotic.nixosModules.default
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                extraSpecialArgs = {
                  inherit inputs system;
                };
                backupFileExtension = "backup";
                useGlobalPkgs = true;
                users.nixos = import ./machines/iso/home.nix;
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
