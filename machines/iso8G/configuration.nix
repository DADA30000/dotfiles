{
  lib,
  inputs,
  pkgs,
  user,
  ...
}:
{
  imports = [ ../iso/configuration.nix ];
  environment.systemPackages = lib.mkForce (
    lib.filter (
      x: x != inputs.zen-browser.packages.${pkgs.system}.twilight
    ) inputs.self.outputs.nixosConfigurations.nixos.config.environment.systemPackages
  );
  home-manager.users."${user}" = import ./home.nix;
  obs.enable = lib.mkForce false;
  specialisation = lib.mkForce {};
  virtualisation.libvirtd.enable = lib.mkForce false;
}
