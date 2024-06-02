{
  inputs = {
    #hyprland.url = "github:hyprwm/Hyprland";
    #hyprland.url = "git+https://github.com/hyprwm/Hyprland/?submodules=1";
    #tempest.url = "github:lavafroth/tempest";
    #ags.url = "github:Aylur/ags";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    #nix-gaming.url = "github:fufexan/nix-gaming";
    hyprlock.url = "github:hyprwm/Hyprlock";
    ulauncher.url = "github:Ulauncher/Ulauncher";
    pollymc.url = "github:fn2006/PollyMC";
    nps.url = "github:OleMussmann/Nix-Package-Search";
    pipewire-screenaudio.url = "github:IceDBorn/pipewire-screenaudio";
    #hyprland-plugins = {
    #  url = "github:hyprwm/hyprland-plugins";
    #  inputs.hyprland.follows = "hyprland";
    #};
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
