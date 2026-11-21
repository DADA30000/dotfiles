{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.systemd.dbusProxy;
  enabledServices = lib.filterAttrs (_: s: s.enable) cfg.services;

  patchedDbusProxy = pkgs.xdg-dbus-proxy.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ../../../stuff/patches/xdg-dbus-proxy-unicast-signals.patch
    ];
  });

  dbusProxyLaunch = pkgs.stdenv.mkDerivation {
    pname = "dbus-proxy-launch";
    version = "1.0";
    dontUnpack = true;
    buildPhase = ''
      $CC -O2 -Wall -Wextra -Werror ${../../../stuff/system/packages/dbus-proxy-launch.c} -o dbus-proxy-launch
    '';
    installPhase = ''
      mkdir -p $out/bin
      install -m 0755 dbus-proxy-launch $out/bin/dbus-proxy-launch
    '';
  };

  serviceSubmodule = lib.types.submodule {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable filtered system D-Bus proxy for this service.";
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
      "unix:path=/run/dbus/system_bus_socket"
      "/run/dbus-proxy/${name}.sock"
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
      "${dbusProxyLaunch}/bin/dbus-proxy-launch"
      "${patchedDbusProxy}/bin/xdg-dbus-proxy"
    ]
    ++ allProxyArgs
  );
in
{
  options.systemd.dbusProxy.services = lib.mkOption {
    type = lib.types.attrsOf serviceSubmodule;
    default = { };
    description = ''
      System services routed through a single shared xdg-dbus-proxy daemon.
      Each entry gets its own filtered socket at /run/dbus-proxy/<name>.sock,
      bind-mounted over /run/dbus/system_bus_socket inside the service's mount
      namespace while hiding /run/systemd/private.
    '';
  };

  config = lib.mkIf (enabledServices != { }) {
    systemd.services = lib.mkMerge [
      {
        dbus-proxy = {
          description = "Filtered System D-Bus Proxy (multi-socket)";
          wantedBy = [ "multi-user.target" ];
          requires = [ "dbus.socket" ];
          after = [
            "dbus.socket"
            "dbus-broker.service"
          ];
          partOf = [ "dbus-broker.service" ];
          serviceConfig = {
            Type = "notify";
            KillMode = "mixed";
            ExecStart = execCommand;
            Restart = "on-failure";
            RestartSec = "1s";
            RuntimeDirectory = "dbus-proxy";
            RuntimeDirectoryMode = "0700";
            UMask = "0077";

            NoNewPrivileges = true;
            CapabilityBoundingSet = "";
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateDevices = true;
            DevicePolicy = "closed";
            PrivateNetwork = true;
            IPAddressDeny = "any";
            PrivateTmp = true;
            PrivateIPC = true;
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
            InaccessiblePaths = [ "-/run/systemd/private" ];
          };
        };
      }

      (lib.mapAttrs (name: _: {
        requires = [ "dbus-proxy.service" ];
        after = [ "dbus-proxy.service" ];
        partOf = [ "dbus-proxy.service" ];
        serviceConfig = {
          BindPaths = [ "/run/dbus-proxy/${name}.sock:/run/dbus/system_bus_socket" ];
          InaccessiblePaths = [ "-/run/systemd/private" ];
        };
      }) enabledServices)
    ];
  };
}
