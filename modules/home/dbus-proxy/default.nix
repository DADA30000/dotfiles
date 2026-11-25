{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  cfg = config.systemd.user.dbusProxy;
  enabledServices = lib.filterAttrs (_: s: s.enable) cfg.services;
  hmServices = lib.filterAttrs (_: s: s.wire) enabledServices;

  patchedDbusProxy = pkgs.xdg-dbus-proxy.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ../../../stuff/patches/xdg-dbus-proxy-unicast-signals.patch
    ];
  });

  serviceSubmodule = lib.types.submodule {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable filtered session D-Bus proxy for this user service.";
      };
      wire = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether this module should automatically add Requires/After/PartOf/BindPaths/InaccessiblePaths to systemd.user.services.<name> (set false when wired by systemd.user.serviceDropins).";
      };
      own = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "D-Bus names this service may own (--own=).";
      };
      talk = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "D-Bus names this service may talk to (--talk=).";
      };
      see = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "D-Bus names this service may see (--see=).";
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
        description = "Enable xdg-dbus-proxy message logging (--log) for debugging.";
      };
    };
  };

  buildProxyArgs =
    name: s:
    [
      "unix:path=%t/bus"
      "%t/dbus-proxy/${name}.sock"
      "--filter"
    ]
    ++ map (n: "--own=${n}") s.own
    ++ map (n: "--talk=${n}") s.talk
    ++ map (n: "--see=${n}") s.see
    ++ map (r: "--call=${r}") s.call
    ++ map (r: "--broadcast=${r}") s.broadcast
    ++ lib.optional s.sloppyNames "--sloppy-names"
    ++ lib.optional s.log "--log";

  allProxyArgs = lib.concatLists (lib.mapAttrsToList buildProxyArgs enabledServices);

  quoteSystemdArg =
    s:
    ''"${lib.replaceStrings [ "\\" ''"'' ] [ "\\\\" ''\"'' ] s}"'';

  execCommand = lib.concatMapStringsSep " " quoteSystemdArg (
    [
      "${osConfig.scripts."dbus-proxy-launch.c"}/bin/dbus-proxy-launch"
      "${patchedDbusProxy}/bin/xdg-dbus-proxy"
    ]
    ++ allProxyArgs
  );

  makeWiring = name: {
    Unit = {
      Requires = [ "dbus-proxy.service" ];
      After = [ "dbus-proxy.service" ];
      PartOf = [ "dbus-proxy.service" ];
    };
    Service = {
      BindPaths = [ "%t/dbus-proxy/${name}.sock:%t/bus" ];
      InaccessiblePaths = [ "-%t/systemd/private" ];
    };
  };
in
{
  options.systemd.user.dbusProxy.services = lib.mkOption {
    type = lib.types.attrsOf serviceSubmodule;
    default = { };
    description = ''
      User services routed through a single shared session xdg-dbus-proxy daemon.
      Each entry gets its own filtered socket at %t/dbus-proxy/<name>.sock,
      bind-mounted over %t/bus inside the service's mount namespace while hiding
      %t/systemd/private.
    '';
  };

  config = lib.mkIf (enabledServices != { }) {
    systemd.user.services = lib.mkMerge [
      {
        dbus-proxy = {
          Install.WantedBy = [ "default.target" ];
          Unit = {
            Description = "Filtered Session D-Bus Proxy (multi-socket)";
            Requires = [ "dbus.socket" ];
            After = [
              "dbus.socket"
              "dbus-broker.service"
            ];
            PartOf = [ "dbus-broker.service" ];
          };
          Service = {
            Type = "notify";
            KillMode = "mixed";
            ExecStart = execCommand;
            Restart = "on-failure";
            RestartSec = "1s";
            RuntimeDirectory = "dbus-proxy";
            RuntimeDirectoryMode = "0700";
            UMask = "0077";

            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = "read-only";
            PrivateDevices = true;
            DevicePolicy = "closed";
            PrivateNetwork = true;
            PrivateTmp = true;
            PrivateUsers = true;
            ProtectClock = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectControlGroups = true;
            ProtectProc = "invisible";
            ProcSubset = "pid";
            LockPersonality = true;
            MemoryDenyWriteExecute = true;
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            KeyringMode = "private";
            RestrictAddressFamilies = [ "AF_UNIX" ];
            SystemCallArchitectures = "native";
            SystemCallErrorNumber = "EPERM";
            SystemCallFilter = [
              "@system-service"
              "~@privileged"
              "~@resources"
            ];
            ReadWritePaths = [ "%t/dbus-proxy" ];
            BindPaths = [ "%t/bus" ];
            InaccessiblePaths = [
              "%h"
              "-%t/systemd/private"
              "-/run/dbus/system_bus_socket"
            ];
          };
        };
      }

      (lib.mapAttrs (name: _: makeWiring name) hmServices)
    ];
  };
}
