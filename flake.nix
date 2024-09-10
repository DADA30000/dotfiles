{
  inputs = {
    hyprland = {
      type = "git";
      url = "https://github.com/hyprwm/Hyprland";
      submodules = true;
    };
    home-manager = {
      url = "github:nix-community/home-manager";
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
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=v0.4.1";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs, home-manager, ...} @ inputs: { 
    nixosConfigurations = {
      nixos = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          ./machines/nixos/configuration.nix
          home-manager.nixosModules.home-manager
	  { home-manager = {
              extraSpecialArgs = { inherit inputs; }; 
              useGlobalPkgs = true;
              users.l0lk3k = import ./machines/nixos/home.nix;
              useUserPackages = true;
          }; }
        ];
      };
      iso = nixpkgs.lib.nixosSystem {
	modules = [
	  ./machines/iso/configuration.nix
	];
      };
    };
  };
}
