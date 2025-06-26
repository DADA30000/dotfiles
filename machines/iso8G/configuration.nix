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
      x: x != inputs.zen-browser.packages.${pkgs.system}.twilight && x != pkgs.qemu && x != pkgs.rustc && x != pkgs.cargo && x != pkgs.ccls && x != pkgs.rust-analyzer && x != pkgs.speechd && x != pkgs.speechd-minimal
    ) inputs.self.outputs.nixosConfigurations.iso.config.environment.systemPackages
  );
  home-manager.users."${user}" = import ./home.nix;
  obs.enable = lib.mkForce false;
  specialisation = lib.mkForce {};
  virtualisation.libvirtd.enable = lib.mkForce false;
}
