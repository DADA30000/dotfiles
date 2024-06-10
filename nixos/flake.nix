{
  inputs = {
    hyprland = {
      type = "git";
      url = "https://github.com/hyprwm/Hyprland";
      submodules = true;
    };
    spicetify-nix.url = "github:the-argus/spicetify-nix";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-fast-build.url = "github:Mic92/nix-fast-build";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland-plugins = {
        url = "github:hyprwm/hyprland-plugins";
        inputs.hyprland.follows = "hyprland"; # IMPORTANT
    };
    pollymc.url = "github:fn2006/PollyMC";
    nps.url = "github:OleMussmann/Nix-Package-Search";
    pipewire-screenaudio.url = "github:IceDBorn/pipewire-screenaudio";
  };

  outputs = {self, nixpkgs, home-manager, ...} @ inputs: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs; }; # this is the important part
      modules = [
        ./configuration.nix
	home-manager.nixosModules.home-manager
          {
            home-manager = {
	      extraSpecialArgs = { inherit inputs; }; 
              useGlobalPkgs = true;
              users.l0lk3k = import ./home.nix; # DON'T FORGET TO CHANGE USERNAME HERE <<<<<<<<<<<<<<<<
              useUserPackages = true;
            };
          }
      ];
    };
  };
}
