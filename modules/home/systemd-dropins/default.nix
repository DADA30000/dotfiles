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

  valueType = lib.mkOptionType {
    name = "systemdDropinValue";
    description = "scalar systemd value or list of scalar values (lists concatenate on merge)";
    check =
      v:
      primitiveType.check v || (builtins.isList v && builtins.all primitiveType.check v);
    merge =
      loc: defs:
      if builtins.all (d: builtins.isList d.value) defs then
        builtins.concatLists (map (d: d.value) defs)
      else
        lib.mergeEqualOption loc defs;
  };

  dbusHasProxy =
    d:
    d.filter
    || d.own != [ ]
    || d.talk != [ ]
    || d.see != [ ]
    || d.call != [ ]
    || d.broadcast != [ ]
    || d.sloppyNames;

  dropinSubmodule = lib.types.submodule {
    freeformType = lib.types.attrsOf (lib.types.attrsOf valueType);

    options.dbus = {
      block = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Hide %t/bus and %t/systemd/private without creating a D-Bus proxy socket.";
      };
      blockSystemBus = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Also hide /run/dbus/system_bus_socket in InaccessiblePaths.";
      };
      filter = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Route session D-Bus through shared dbus-proxy.service even when policy lists are empty.";
      };
      own = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Session D-Bus names this service may own (--own=).";
      };
      talk = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Session D-Bus names this service may talk to (--talk=).";
      };
      see = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Session D-Bus names this service may see (--see=).";
      };
      call = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Fine-grained call rules (--call=NAME=RULE).";
      };
      broadcast = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Fine-grained broadcast rules (--broadcast=NAME=RULE).";
      };
      sloppyNames = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Pass --sloppy-names for this proxy socket.";
      };
      log = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable xdg-dbus-proxy message logging (--log).";
      };
    };
  };

  toList = v: if builtins.isList v then v else [ v ];

  mergeSectionAttrs =
    base: extra:
    lib.foldl' (
      acc: key:
      let
        addVals = extra.${key};
      in
      if acc ? ${key} then
        acc // { ${key} = lib.unique ((toList acc.${key}) ++ (toList addVals)); }
      else
        acc // { ${key} = addVals; }
    ) base (builtins.attrNames extra);

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
    name: sections:
    let
      d = sections.dbus;
      useProxy = dbusHasProxy d;
      iniSections = builtins.removeAttrs sections [ "dbus" ];

      extraUnit = lib.optionalAttrs useProxy {
        Requires = [ "dbus-proxy.service" ];
        After = [ "dbus-proxy.service" ];
        PartOf = [ "dbus-proxy.service" ];
      };

      inaccessible =
        lib.optionals useProxy [ "-%t/systemd/private" ]
        ++ lib.optionals d.block [
          "-%t/bus"
          "-%t/systemd/private"
        ]
        ++ lib.optional d.blockSystemBus "-/run/dbus/system_bus_socket";

      extraService =
        lib.optionalAttrs useProxy {
          BindPaths = [ "%t/dbus-proxy/${name}.sock:%t/bus" ];
        }
        // lib.optionalAttrs (inaccessible != [ ]) {
          InaccessiblePaths = inaccessible;
        };

      mergedSections =
        iniSections
        // lib.optionalAttrs (extraUnit != { }) {
          Unit = mergeSectionAttrs (iniSections.Unit or { }) extraUnit;
        }
        // lib.optionalAttrs (extraService != { }) {
          Service = mergeSectionAttrs (iniSections.Service or { }) extraService;
        };
    in
    lib.concatStringsSep "\n" (
      lib.filter (s: s != "") (lib.mapAttrsToList formatSection mergedSections)
    );

  proxiedDropins = lib.filterAttrs (_: s: dbusHasProxy s.dbus) cfg;
in
{
  options.systemd.user.serviceDropins = lib.mkOption {
    type = lib.types.attrsOf dropinSubmodule;
    default = { };
    example = {
      dconf = {
        dbus.own = [ "ca.desrt.dconf" ];
        Service = {
          ProtectSystem = "strict";
          NoNewPrivileges = true;
          SystemCallFilter = [
            "@system-service"
            "~@privileged"
          ];
        };
      };
    };
    description = ''
      Drop-in overrides for systemd user services, written to
      ~/.config/systemd/user/<name>.service.d/~~~override.conf.
      Supports arbitrary systemd INI sections plus a `dbus` hardening helper
      that registers filtered sockets with `systemd.user.dbusProxy` or blocks
      bus access via `InaccessiblePaths`.
    '';
  };

  config = lib.mkIf (cfg != { }) {
    assertions = lib.mapAttrsToList (name: s: {
      assertion = !(s.dbus.block && dbusHasProxy s.dbus);
      message = "systemd.user.serviceDropins.${name}: dbus.block cannot be combined with dbus proxy rules";
    }) cfg;

    xdg.configFile = lib.mapAttrs' (
      name: sections:
      lib.nameValuePair "systemd/user/${name}.service.d/~~~override.conf" {
        text = renderDropin name sections;
      }
    ) cfg;

    systemd.user.dbusProxy.services = lib.mapAttrs (
      _: s: {
        wire = false;
        inherit (s.dbus)
          own
          talk
          see
          call
          broadcast
          sloppyNames
          log
          ;
      }
    ) proxiedDropins;
  };
}
