{
  lib,
  inputs,
  pkgs,
  ...
}:
{
  imports = [ ../iso/configuration.nix ];
  environment.systemPackages = lib.mkForce (
    lib.filter (
      x: x != inputs.zen-browser.packages.${pkgs.system}.twilight
    ) inputs.self.outputs.nixosConfigurations.nixos.config.environment.systemPackages
  );

  specialisation = lib.mkForce {};
  virtualisation.libvirtd.enable = lib.mkForce false;
}
