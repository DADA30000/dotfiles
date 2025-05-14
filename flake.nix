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
    #hyprland.url = "git+https://github.com/hyprwm/Hyprland/v0.46.2";
    hyprland.url = "git+https://github.com/hyprwm/Hyprland?shallow=1";
    #chaotic.url = "git+https://github.com/chaotic-cx/nyx/nyxpkgs-unstable";
    pipewire-screenaudio.url = "git+https://github.com/IceDBorn/pipewire-screenaudio?shallow=1";
    nix-alien.url = "git+https://github.com/thiagokokada/nix-alien?shallow=1";
    zen-browser.url = "git+https://github.com/0xc000022070/zen-browser-flake?shallow=1";
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";
    nixpkgs.url = "git+https://github.com/NixOS/nixpkgs?shallow=1&ref=nixpkgs-unstable";
    impermanence.url = "git+https://github.com/nix-community/impermanence?shallow=1";
    nix-search.url = "git+https://github.com/diamondburned/nix-search?shallow=1";
  };

  outputs =
    { nixpkgs, home-manager, ... }@inputs:
    let
      system = "x86_64-linux";
      overlays = [
        (final: prev: { fabric-run-widget = inputs.fabric.packages.${system}.run-widget; })
        (final: prev: { fabric = inputs.fabric.packages.${system}.default; })
        (final: prev: { fabric-cli = inputs.fabric-cli.packages.${system}.default; })
        (final: prev: { fabric-gray = inputs.fabric-gray.packages.${system}.default; })
        (final: prev: {
          python313Packages.deal-solver = prev.python313Packages.deal-solver.overrideAttrs {
            disabledTests = [
              "test_expr_asserts_ok"
              "test_fuzz_math_floats"
              "test_timeout"
            ];
          };
        })
        inputs.fabric.overlays.${system}.default
      ];
      modules-list = [
        ./machines/nixos/configuration.nix
        inputs.nix-index-database.nixosModules.nix-index
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
        }
      ];
    in
    {
      nixosConfigurations = {
        nixos = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs system overlays;
          };
          modules = modules-list;
        };
        iso = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs system overlays;
          };
          modules = modules-list ++ [ "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix" ];
        };
      };
      homeConfigurations = {
        l0lk3k = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [
            ./machines/nixos/home-options.nix
          ];
          extraSpecialArgs = {
            inherit inputs system overlays;
          };
        };
      };
    };
}
