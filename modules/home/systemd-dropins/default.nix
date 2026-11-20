{
  config,
  lib,
  ...
}:
let
  cfg = config.systemd.user.serviceDropins;

  primitiveType =
    with lib.types;
    oneOf [
      str
      int
      float
      bool
    ];

  valueType = lib.types.oneOf [
    primitiveType
    (lib.types.listOf primitiveType)
  ];

  formatValue =
    v:
    if builtins.isBool v then
      (if v then "yes" else "no")
    else
      toString v;

  formatKey =
    key: value:
    if builtins.isList value then
      lib.concatMapStringsSep "\n" (item: "${key}=${formatValue item}") value
    else
      "${key}=${formatValue value}";

  formatSection =
    sectionName: attrs:
    let
      body = lib.concatStringsSep "\n" (lib.mapAttrsToList formatKey attrs);
    in
    lib.optionalString (attrs != { }) "[${sectionName}]\n${body}\n";

  renderDropin =
    sections:
    lib.concatStringsSep "\n" (
      lib.filter (s: s != "") (lib.mapAttrsToList formatSection sections)
    );
in
{
  options.systemd.user.serviceDropins = lib.mkOption {
    type = lib.types.attrsOf (lib.types.attrsOf (lib.types.attrsOf valueType));
    default = { };
    example = {
      dconf.Service = {
        ProtectSystem = "strict";
        NoNewPrivileges = true;
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
        ];
      };
    };
    description = ''
      Drop-in overrides for systemd user services, written to
      ~/.config/systemd/user/<name>.service.d/~~~override.conf.
      Allows extending or overriding upstream/NixOS-provided user units without
      shadowing the base .service file, with maximum persistent drop-in
      priority in systemd (user XDG config dir + ~ / ASCII 0x7E sort order).
    '';
  };

  config = lib.mkIf (cfg != { }) {
    xdg.configFile = lib.mapAttrs' (
      name: sections:
      lib.nameValuePair "systemd/user/${name}.service.d/~~~override.conf" {
        text = renderDropin sections;
      }
    ) cfg;
  };
}
