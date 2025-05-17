{
  lib,
  inputs,
  user,
  user_iso,
  ...
}:
{
  imports = [ ../../machines/nixos/configuration.nix ];
  users.users."${user}" = lib.mkForce {};
  users.users."${user_iso}" = lib.mkMerge [
    inputs.self.outputs.nixosConfigurations.nixos.config.users.users."${user}"
    { hashedPassword = lib.mkForce null; initialPassword = "1234"; }
  ];
}
