{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.document-portal;

  patchedXdp = pkgs.xdg-desktop-portal.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ../../../stuff/patches/xdg-document-portal-premount-fd.patch
    ];
  });

  launcher = pkgs.stdenv.mkDerivation {
    pname = "xdp-document-portal-launch";
    version = "1.0";
    dontUnpack = true;
    buildPhase = ''
      $CC -O2 -Wall -Wextra -Werror ${../../../stuff/system/document-portal/xdp-document-portal-launch.c} -o xdp-document-portal-launch
    '';
    installPhase = ''
      mkdir -p $out/bin
      install -m 0755 xdp-document-portal-launch $out/bin/xdp-document-portal-launch
    '';
  };
in
{
  options.document-portal.enable = lib.mkEnableOption "multi-user premounted-FUSE xdg-document-portal without SUID fusermount3";

  config = lib.mkIf cfg.enable {
    # Per-user system template: mounts /run/user/%i/doc as FUSE, then drops all
    # privileges & capabilities (PR_SET_NO_NEW_PRIVS) before exec'ing xdg-document-portal.
    # Runs in the host mount/user namespace so /run/user/%i/doc propagates to host & sb-run
    # and /proc/<pid>/root portal identity checks succeed.
    systemd.services."xdg-document-portal@" = {
      description = "Premounted FUSE Document Portal for UID %i";
      after = [ "user@%i.service" ];
      bindsTo = [ "user@%i.service" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${launcher}/bin/xdp-document-portal-launch %i ${patchedXdp}/libexec/xdg-document-portal";
        ExecStopPost = "${launcher}/bin/xdp-document-portal-launch -u %i";
        Restart = "on-failure";
        RestartSec = "2s";

        NoNewPrivileges = true;
        CapabilityBoundingSet = [
          "CAP_SYS_ADMIN"
          "CAP_SETUID"
          "CAP_SETGID"
          "CAP_DAC_OVERRIDE"
          "CAP_CHOWN"
        ];
        # Avoid PrivateNetwork/PrivateIPC/mount-ns directives so the FUSE mount
        # stays in PID 1's mount namespace and propagates to the host.
        IPAddressDeny = "any";
        LockPersonality = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        KeyringMode = "private";
        RestrictAddressFamilies = [ "AF_UNIX" ];
        SystemCallArchitectures = "native";
        SystemCallErrorNumber = "EPERM";
        SystemCallFilter = [
          "@system-service"
          "@mount"
          "~@module"
          "~@raw-io"
          "~@reboot"
          "~@swap"
          "~@clock"
          "~@debug"
          "~@obsolete"
          "~@cpu-emulation"
        ];
        UMask = "0077";
      };
    };

    # Global user unit bridge (applies to every user automatically) so D-Bus
    # activation of org.freedesktop.portal.Documents starts xdg-document-portal@%U.service.
    systemd.user.services.xdg-document-portal = {
      description = "Flatpak Document Portal User Bridge";
      partOf = [ "graphical-session.target" ];
      requires = [ "dbus.service" ];
      after = [ "dbus.service" ];
      serviceConfig = {
        Type = lib.mkForce "dbus";
        BusName = lib.mkForce "org.freedesktop.portal.Documents";
        ExecStart = lib.mkForce "${pkgs.systemd}/bin/systemctl start --wait xdg-document-portal@%U.service";
        ExecStop = lib.mkForce "${pkgs.systemd}/bin/systemctl stop xdg-document-portal@%U.service";
        Slice = "session.slice";

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateTmp = true;
        PrivateDevices = true;
        DevicePolicy = "closed";
        PrivateNetwork = true;
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
        ReadWritePaths = [ "%t" ];
        InaccessiblePaths = [
          "-%t/bus"
          "-%t/systemd/private"
          "-/run/systemd/private"
        ];
        RestrictAddressFamilies = [ "AF_UNIX" ];
        SystemCallArchitectures = "native";
        SystemCallErrorNumber = "EPERM";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        UMask = "0077";
      };
    };

    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units") {
          var unit = action.lookup("unit");
          if (unit === "xdg-document-portal@" + subject.uid + ".service") {
            return polkit.Result.YES;
          }
        }
      });
    '';
  };
}
