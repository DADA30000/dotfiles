{
  inputs = {
    hyprland = {
      type = "git";
      url = "https://github.com/hyprwm/Hyprland";
      submodules = true;
    };
    nvidia-patch = {
      url = "github:icewind1991/nvidia-patch-nixos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland-plugins = {
        url = "github:hyprwm/hyprland-plugins";
        inputs.hyprland.follows = "hyprland";
    };
    minegrub-world-sel-theme = {
      url = "github:Lxtharia/minegrub-world-sel-theme";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pollymc.url = "github:fn2006/PollyMC";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=v0.4.1";
    pipewire-screenaudio.url = "github:IceDBorn/pipewire-screenaudio";
    ags.url = "github:Aylur/ags";
  };

  outputs = {self, nixpkgs, home-manager, ...} @ inputs: 
  let
    var = {
      user = "l0lk3k"; # DON'T FORGET TO CHANGE STUFF HERE <<<<<<<<<<
      hostname = "nixos"; # DON'T FORGET TO CHANGE STUFF HERE <<<<<<<<<<
      user-hash = "$y$j9T$4Q2h.L51xcYILK8eRbquT1$rtuCEsO2kdtTLjUL3pOwvraDy9M773cr4hsNaKcSIs1"; # DON'T FORGET TO CHANGE STUFF HERE <<<<<<<<<< # change to null if you don't need this
    };
  in { 
    nixosConfigurations = {
      "${var.hostname}" = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs var; };
        modules = [
          ./nixos/configuration.nix
	  inputs.spicetify-nix.nixosModules.default
          inputs.nix-flatpak.nixosModules.nix-flatpak
          inputs.minegrub-world-sel-theme.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              extraSpecialArgs = { inherit inputs; }; 
              useGlobalPkgs = true;
              users."${var.user}" = import ./nixos/home.nix;
              useUserPackages = true;
            };
          }
        ];
      };
      iso = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs var; };
	modules = [
	  ./iso/configuration.nix
	  inputs.minegrub-world-sel-theme.nixosModules.default
	];
      };
    };
  };
}
