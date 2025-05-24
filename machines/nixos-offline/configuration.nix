{
  lib,
  inputs,
  user,
  user_iso,
  ...
}:
let
  orig = inputs.self.outputs.nixosConfigurations.nixos.config.users.users;
  users_without = lib.removeAttrs orig [ user ];
  imported = inputs.self.outputs.nixosConfigurations.nixos.config.users.users."${user}";
  changed = lib.mkMerge [ imported { hashedPassword = lib.mkForce null; initialPassword = lib.mkForce "1234"; }];
in
{
  imports = [ ../../machines/nixos/configuration.nix ];
  users.users = lib.mkForce (
    users_without // { "${user_iso}" = changed; }
  );
}
