{
  inputs = {
    home-manager = {
      url = "git+https://github.com/nix-community/home-manager?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland-plugins = {
      url = "git+https://github.com/hyprwm/hyprland-plugins?shallow=1";
      inputs.hyprland.follows = "hyprland";
    };
    nur = {
      url = "git+https://github.com/nix-community/NUR?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    spicetify-nix = {
      url = "git+https://github.com/Gerg-L/spicetify-nix?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hypr-dynamic-cursors = {
      url = "git+https://github.com/VirtCode/hypr-dynamic-cursors?shallow=1";
      inputs.hyprland.follows = "hyprland";
    };
    nix-index-database = {
      url = "git+https://github.com/nix-community/nix-index-database?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpak = {
      url = "git+https://github.com/nixpak/nixpak?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fabric = {
      url = "git+https://github.com/Fabric-Development/fabric?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fabric-gray = {
      url = "git+https://github.com/Fabric-Development/gray?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fabric-cli = {
      url = "git+https://github.com/HeyImKyu/fabric-cli?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    singbox = {
      url = "github:SagerNet/sing-box/dev-next";
      flake = false;
    };
    hyprpanel.url = "github:DADA30000/HyprPanel/json";
    anicli-ru.url = "github:vypivshiy/ani-cli-ru";
    nixpkgs.url = "git+https://github.com/NixOS/nixpkgs?shallow=1&ref=nixos-unstable";
    hyprland.url = "git+https://github.com/hyprwm/Hyprland?shallow=1";
    #chaotic.url = "git+https://github.com/chaotic-cx/nyx/nyxpkgs-unstable";
    pipewire-screenaudio.url = "git+https://github.com/IceDBorn/pipewire-screenaudio?shallow=1";
    #determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    nix-alien.url = "git+https://github.com/thiagokokada/nix-alien?shallow=1";
    zen-browser.url = "git+https://github.com/0xc000022070/zen-browser-flake?shallow=1";
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";
    impermanence.url = "git+https://github.com/nix-community/impermanence?shallow=1";
    nix-search.url = "git+https://github.com/diamondburned/nix-search?shallow=1";
  };

  outputs =
    { nixpkgs, home-manager, ... }@inputs:
    let
      system = "x86_64-linux";
      modules-list = [
        inputs.impermanence.nixosModules.impermanence
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            extraSpecialArgs = {
              inherit inputs;
            };
            backupFileExtension = "backup";
            useGlobalPkgs = true;
            useUserPackages = true;
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
            inherit inputs user user-hash;
          };
          modules = modules-list ++ [
            ./machines/nixos/configuration.nix
            { home-manager.users."${user}" = import ./machines/nixos/home.nix; }
          ];
        };
        nixos-offline = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit
              inputs
              user
              user_iso
              user-hash
              ;
          };
          modules = modules-list ++ [
            ./machines/nixos-offline/configuration.nix
            { home-manager.users."${user_iso}" = import ./machines/nixos/home.nix; }
          ];
        };
        iso = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs user user_iso;
          };
          modules = modules-list ++ [
            ./machines/iso/configuration.nix
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
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
            inherit inputs system user;
          };
        };
      };
    };
}
