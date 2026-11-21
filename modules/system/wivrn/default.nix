{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.wivrn;
  pkg_xrizer =
    inputs.nixpkgs-xr.packages.${pkgs.stdenv.hostPlatform.system}.xrizer.overrideAttrs
      (prev: {
        patches = (prev.patches or [ ]) ++ [ ../../../stuff/patches/xrizer-getposesforframe.patch ];
      });
  pkg_opencomposite = inputs.nixpkgs-xr.packages.${pkgs.stdenv.hostPlatform.system}.opencomposite;
  xrizer_multilib = pkgs.symlinkJoin {
    name = "xrizer-multilib";
    paths = [
      pkg_xrizer
      (pkgs.pkgsi686Linux.callPackage pkg_xrizer.override { })
    ];
  };
  opencomposite_multilib = pkgs.symlinkJoin {
    name = "opencomposite-multilib";
    paths = [
      pkg_opencomposite
      (pkgs.pkgsi686Linux.callPackage pkg_opencomposite.override { })
    ];
  };
  pkg_wivrn = pkgs.wivrn.override {
    cudaSupport = if config.graphics.nvidia.enable then true else false;
    xrizer = xrizer_multilib;
    opencomposite = opencomposite_multilib;
  };
  wivrn_i686 = pkgs.pkgsi686Linux.callPackage pkg_wivrn.override {
    clientLibOnly = true;
    git = (pkgs.pkgsi686Linux.git.override { withManual = false; }).overrideAttrs {
      doCheck = false;
      doInstallCheck = false;
    };
    android-tools = pkgs.android-tools.overrideAttrs (old: {
      cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DOPENSSL_NO_ASM=ON" ];
    });
  };

  wivrnEnvForward = pkgs.writeShellScript "wivrn-env-forward" ''
    echo "export WAYLAND_DISPLAY=''${WAYLAND_DISPLAY:-wayland-1}" > "$XDG_RUNTIME_DIR/wivrn.env"
    echo "export DBUS_SESSION_BUS_ADDRESS=''${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}" >> "$XDG_RUNTIME_DIR/wivrn.env"
    if [ -n "''${DISPLAY:-}" ]; then
      echo "export DISPLAY=$DISPLAY" >> "$XDG_RUNTIME_DIR/wivrn.env"
    fi
  '';

  wivrnSystemRunner = pkgs.writeShellScript "wivrn-system-runner" ''
    USER_NAME="$1"
    USER_UID="$(${pkgs.coreutils}/bin/id -u "$USER_NAME")"
    export XDG_RUNTIME_DIR="/run/user/$USER_UID"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
    if [ -f "$XDG_RUNTIME_DIR/wivrn.env" ]; then
      set -a
      # shellcheck disable=SC1090
      . "$XDG_RUNTIME_DIR/wivrn.env"
      set +a
    fi
    export WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-wayland-1}"
    exec ${pkg_wivrn}/bin/wivrn-server
  '';
in
with lib;
{
  options.wivrn = {
    enable = mkEnableOption "WiVRn";
  };
  config = mkIf cfg.enable {
    hardware.graphics.extraPackages = with pkgs; [
      monado-vulkan-layers
    ];
    services.wivrn = {
      enable = true;
      openFirewall = true;
      autoStart = false;
      steam.importOXRRuntimes = true;
      highPriority = false; # Eliminates /run/wrappers/bin/wivrn-server; CAP_SYS_NICE granted via wivrn@.service
      package = pkg_wivrn;
    };
    environment.etc."xdg/openxr/1/active_runtime.i686.json".source =
      "${wivrn_i686}/share/openxr/1/openxr_wivrn.i686.json";
    environment.sessionVariables.OXR_RECENTER_STAGE = 1;

    # Lightweight user bridge forwarding session env -> hardened wivrn@%u.service
    systemd.user.services.wivrn = {
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        Type = mkForce "simple";
        ExecStartPre = mkForce "${wivrnEnvForward}";
        ExecStart = mkForce "${pkgs.systemd}/bin/systemctl start --wait wivrn@%u.service";
        ExecStop = mkForce "${pkgs.systemd}/bin/systemctl stop wivrn@%u.service";
        Restart = mkForce "on-failure";
        RestartSec = mkForce "3s";

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

    systemd.services."wivrn@" = {
      description = "WiVRn XR Runtime Server for %i (CAP_SYS_NICE shim)";
      after = [
        "graphical.target"
        "network.target"
        "user@%U.service"
      ];
      bindsTo = [ "user@%U.service" ];
      environment.PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES = "1";
      serviceConfig = {
        Type = "simple";
        User = "%i";
        Group = "users";
        SupplementaryGroups = [
          "video"
          "render"
        ];
        ExecStart = "${wivrnSystemRunner} %i";
        Restart = "on-failure";
        RestartSec = "3s";

        # Systemd-scoped CAP_SYS_NICE replaces /run/wrappers/bin/wivrn-server
        AmbientCapabilities = [ "CAP_SYS_NICE" ];
        CapabilityBoundingSet = [ "CAP_SYS_NICE" ];
        NoNewPrivileges = true;

        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [
          "-/home/%i/.config/wivrn"
          "-/home/%i/.config/openxr"
          "-/home/%i/.local/share/wivrn"
          "-/home/%i/.cache/wivrn"
          "-/home/%i/.cache/nvidia"
          "/run/user/%U"
        ];
        InaccessiblePaths = [
          "-/run/systemd/private"
          "-/run/user/%U/systemd/private"
        ];
        PrivateTmp = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        ProtectProc = "invisible";
        LockPersonality = true;
        RestrictNamespaces = true;
        RestrictSUIDSGID = true;
        KeyringMode = "private";
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
          "AF_NETLINK"
        ];
        SystemCallArchitectures = "native";
        SystemCallErrorNumber = "EPERM";
        SystemCallFilter = [
          "@system-service"
          "~@clock"
          "~@cpu-emulation"
          "~@debug"
          "~@module"
          "~@mount"
          "~@obsolete"
          "~@raw-io"
          "~@reboot"
          "~@swap"
        ];
        UMask = "0077";
      };
    };

    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units") {
          var unit = action.lookup("unit");
          if (unit === "wivrn@" + subject.user + ".service") {
            return polkit.Result.YES;
          }
        }
      });
    '';
  };
}
