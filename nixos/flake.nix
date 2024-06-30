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
    spicetify-nix.url = "github:the-argus/spicetify-nix";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    kwin-effects-forceblur = {
      url = "github:taj-ny/kwin-effects-forceblur";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland-plugins = {
        url = "github:hyprwm/hyprland-plugins";
        inputs.hyprland.follows = "hyprland"; # IMPORTANT
    };
    pollymc.url = "github:fn2006/PollyMC";
    pipewire-screenaudio.url = "github:IceDBorn/pipewire-screenaudio";
    ags.url = "github:Aylur/ags";
  };

  outputs = {self, nixpkgs, home-manager, ...} @ inputs: let user = "l0lk3k"; hostname = "nixos"; in { # DON'T FORGET TO CHANGE USERNAME AND HOSTNAME HERE <<<<<<<<<<
    nixosConfigurations."${hostname}" = nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs user hostname; };
      modules = [
        ./configuration.nix
	home-manager.nixosModules.home-manager
          {
            home-manager = {
	      extraSpecialArgs = { inherit inputs; }; 
              useGlobalPkgs = true;
              users."${user}" = import ./home.nix;
              useUserPackages = true;
            };
          }
      ];
    };
  };
}
