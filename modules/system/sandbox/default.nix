{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.sandboxing;

  sb-flatpak-portal-pkg = pkgs.stdenv.mkDerivation {
    pname = "sb-flatpak-portal";
    version = "1.0.0";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [ pkgs.glib ];
    buildPhase = ''
      $CC -O2 -Wall -Wextra -Werror \
        $(pkg-config --cflags --libs gio-2.0 gio-unix-2.0) \
        ${../../../stuff/system/sandbox/sb-flatpak-portal.c} \
        -o sb-flatpak-portal
    '';
    installPhase = ''
      mkdir -p $out/libexec $out/share/dbus-1/services
      install -m 0755 sb-flatpak-portal $out/libexec/sb-flatpak-portal
      cat > $out/share/dbus-1/services/org.freedesktop.portal.Flatpak.service <<EOF
      [D-BUS Service]
      Name=org.freedesktop.portal.Flatpak
      Exec=$out/libexec/sb-flatpak-portal
      SystemdService=sb-flatpak-portal.service
      EOF
    '';
  };

  wp-mic-portal-pkg = pkgs.stdenv.mkDerivation {
    pname = "wp-mic-portal";
    version = "1.0.0";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [
      pkgs.wireplumber
      pkgs.glib
      pkgs.pipewire
    ];
    buildPhase = ''
      $CC -shared -fPIC -O2 -Wall -Wextra -Werror \
        $(pkg-config --cflags --libs wireplumber-0.5 gio-2.0) \
        ${../../../stuff/system/sandbox/wp-mic-portal.c} \
        -o libwireplumber-module-mic-portal.so
    '';
    installPhase = ''
      mkdir -p $out/lib/wireplumber-0.5 $out/share/wireplumber/scripts/linking
      cp libwireplumber-module-mic-portal.so $out/lib/wireplumber-0.5/
      cp ${../../../stuff/system/sandbox/wp-mic-portal.lua} \
        $out/share/wireplumber/scripts/linking/wp-mic-portal.lua
    '';
  };

  pipewireRestrictedSocketConfig = {
    "module.protocol-native.args".sockets = [
      { name = "pipewire-0"; }
      { name = "pipewire-0-manager"; }
      { name = "pipewire-0-restricted"; }
      { name = "pipewire-0-restricted-nomic"; }
      { name = "pipewire-0-restricted-mic-portal"; }
    ];
    "module.access.args"."access.socket" = {
      "pipewire-0" = "unrestricted";
      "pipewire-0-manager" = "unrestricted";
      "pipewire-0-restricted" = "restricted";
      "pipewire-0-restricted-nomic" = "restricted-nomic";
      "pipewire-0-restricted-mic-portal" = "restricted-mic-portal";
    };
    "context.objects" = [
      {
        factory = "adapter";
        args = {
          "factory.name" = "support.null-audio-sink";
          "media.class" = "Audio/Source/Virtual";
          "node.name" = "sandbox-null-mic";
          "node.description" = "Silent Microphone (Denied)";
          "audio.position" = [
            "FL"
            "FR"
          ];
          "priority.session" = 0;
        };
      }
    ];
  };

  pipewirePulseRestrictedSocketConfig = {
    "pulse.properties"."server.address" = [
      "unix:native"
      {
        address = "unix:restricted";
        "client.access" = "restricted";
      }
      {
        address = "unix:restricted-nomic";
        "client.access" = "restricted-nomic";
      }
      {
        address = "unix:restricted-mic-portal";
        "client.access" = "restricted-mic-portal";
      }
    ];
    "pulse.rules" = [
      {
        matches = [
          { "pipewire.client.access" = "restricted"; }
          { "pipewire.client.access" = "restricted-mic-portal"; }
          { "pipewire.client.access" = "flatpak"; }
        ];
        actions.quirks = [
          "block-source-volume"
          "block-sink-volume"
        ];
      }
      {
        matches = [
          { "pipewire.client.access" = "restricted-nomic"; }
        ];
        actions.quirks = [
          "block-source-volume"
          "block-sink-volume"
          "block-record-stream"
        ];
      }
    ];
  };

  wireplumberRestrictedPermissionsConfig = {
    "access.permission-managers" = [
      {
        name = "sandbox-restricted";
        default_permissions = "rx";
        core_permissions = "rx";
        rules = [
          {
            matches = [
              { "media.class" = "~Video/.*"; }
              { "media.role" = "Camera"; }
              { "device.api" = "v4l2"; }
              { "device.api" = "libcamera"; }
            ];
            actions.set-permissions = "-";
          }
        ];
      }
      {
        name = "sandbox-restricted-nomic";
        default_permissions = "rx";
        core_permissions = "rx";
        rules = [
          {
            matches = [
              { "media.class" = "~Video/.*"; }
              { "media.role" = "Camera"; }
              { "device.api" = "v4l2"; }
              { "device.api" = "libcamera"; }
              { "media.class" = "~Audio/Source.*"; }
            ];
            actions.set-permissions = "-";
          }
        ];
      }
    ];
    "access.rules" = [
      {
        matches = [
          { "pipewire.access" = "restricted"; }
          { "pipewire.access" = "restricted-mic-portal"; }
          { "pipewire.access" = "flatpak"; }
          { "pipewire.sec.socket" = "pipewire-0-restricted"; }
          { "pipewire.sec.socket" = "pipewire-0-restricted-mic-portal"; }
        ];
        actions.update-props.permission_manager_name = "sandbox-restricted";
      }
      {
        matches = [
          { "pipewire.access" = "restricted-nomic"; }
          { "pipewire.sec.socket" = "pipewire-0-restricted-nomic"; }
        ];
        actions.update-props.permission_manager_name = "sandbox-restricted-nomic";
      }
    ];
  };

  wireplumberRestrictedPermissionsText = ''
    access.permission-managers = ${
      builtins.toJSON wireplumberRestrictedPermissionsConfig."access.permission-managers"
    }
    access.rules = ${builtins.toJSON wireplumberRestrictedPermissionsConfig."access.rules"}
    wireplumber.components = [
      {
        name = libwireplumber-module-mic-portal
        type = module
        provides = api.mic-portal
        requires = [ support.dbus ]
      }
      {
        name = linking/wp-mic-portal.lua
        type = script/lua
        provides = hooks.linking.mic-portal
        requires = [ api.mic-portal ]
      }
    ]
    wireplumber.profiles = {
      main = {
        hooks.linking.mic-portal = required
      }
    }
  '';

  wireplumberRestrictedPermissionsPkg = pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/99-restricted-permissions.conf" wireplumberRestrictedPermissionsText;
in
{
  options.sandboxing.enable = lib.mkEnableOption "app sandboxing (PipeWire & WirePlumber audio portals)";

  config = lib.mkIf cfg.enable {
    services = {
      dbus.packages = [ sb-flatpak-portal-pkg ];
      pipewire = {
        package = pkgs.pipewire.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            ../../../stuff/patches/pipewire-quirk-block-mute.patch
            ../../../stuff/patches/pipewire-pulse-socket-access.patch
          ];
        });
        wireplumber = {
          package = pkgs.wireplumber.overrideAttrs (old: {
            postInstall = (old.postInstall or "") + ''
              ln -s ${wp-mic-portal-pkg}/lib/wireplumber-0.5/libwireplumber-module-mic-portal.so \
                $out/lib/wireplumber-0.5/libwireplumber-module-mic-portal.so
              mkdir -p $out/share/wireplumber/scripts/linking
              ln -s ${wp-mic-portal-pkg}/share/wireplumber/scripts/linking/wp-mic-portal.lua \
                $out/share/wireplumber/scripts/linking/wp-mic-portal.lua
            '';
          });
          configPackages = [ wireplumberRestrictedPermissionsPkg ];
        };
        extraConfig = {
          pipewire."99-restricted-socket" = pipewireRestrictedSocketConfig;
          pipewire-pulse."99-restricted-socket" = pipewirePulseRestrictedSocketConfig;
        };
      };
    };

    systemd.user.services.sb-flatpak-portal = {
      description = "sb-run Flatpak Portal Relay";
      partOf = [ "graphical-session.target" ];
      requires = [ "dbus.service" ];
      after = [ "dbus.service" ];
      serviceConfig = {
        Type = "dbus";
        BusName = "org.freedesktop.portal.Flatpak";
        ExecStart = "${sb-flatpak-portal-pkg}/libexec/sb-flatpak-portal";
        Restart = "on-failure";
        RestartSec = "1s";

        # Keep in the host user namespace (no PrivateTmp/Protect* mount isolation)
        # so reading /proc/<pid>/root/.sb-sandbox of sibling user processes is permitted.
        NoNewPrivileges = true;
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
        UMask = "0077";
      };
    };
  };
}
