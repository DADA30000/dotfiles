{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.rust-helpers;

  protonVersionModule = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Display name of the Proton version.";
      };
      default = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether this Proton version is the fallback default.";
      };
    };
  };

  bridgePresetModule = lib.types.submodule {
    options = {
      label = lib.mkOption {
        type = lib.types.str;
        description = "Quick-add button label.";
      };
      rule = lib.mkOption {
        type = lib.types.str;
        description = "Bridge specification string (direction:addr:ports).";
      };
    };
  };

  rustHelpersConfigModule = {
    options = {
      paths = lib.mkOption {
        type = lib.types.submodule {
          options = {
            umu_dir_rel = lib.mkOption {
              type = lib.types.str;
              default = ".umu";
              description = "Relative directory under HOME for UMU prefixes.";
            };
            icon_cache_rel = lib.mkOption {
              type = lib.types.str;
              default = ".cache/umu/icons";
              description = "Relative directory under HOME for cached shortcut icons.";
            };
            icon_dest_rel = lib.mkOption {
              type = lib.types.str;
              default = "icons/umu";
              description = "Relative directory under XDG_DATA_HOME for persisted shortcut icons.";
            };
            desktop_dir_rel = lib.mkOption {
              type = lib.types.str;
              default = "applications";
              description = "Relative directory under XDG_DATA_HOME for .desktop files.";
            };
            proton_versions_file = lib.mkOption {
              type = lib.types.str;
              default = "$XDG_DATA_HOME/umu-ui/proton_versions.json";
              description = "Path to the Proton versions JSON file.";
            };
            games_appid_file = lib.mkOption {
              type = lib.types.str;
              default = "$XDG_DATA_HOME/umu-ui/games_appid.json";
              description = "Path to the Steam AppID database JSON file.";
            };
            ignored_prefix_dirs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [
                "steamrt3"
                "umu"
              ];
              description = "Subdirectories under the UMU prefix root ignored by prefix management.";
            };
          };
        };
        default = { };
        description = "Filesystem paths configuration for rust-helpers.";
      };

      bins = lib.mkOption {
        type = lib.types.submodule {
          options = {
            umu_run_wrapper = lib.mkOption {
              type = lib.types.str;
              default = "umu-run-wrapper";
              description = "Command used to launch UMU targets and shortcuts.";
            };
            scan_umu_for_lnk = lib.mkOption {
              type = lib.types.str;
              default = "scan-umu-for-lnk";
              description = "Command run after launching an executable to index new .lnk files.";
            };
            run_exe = lib.mkOption {
              type = lib.types.str;
              default = "run-exe";
              description = "Launcher command for creating a new UMU shortcut.";
            };
            sb_run = lib.mkOption {
              type = lib.types.str;
              default = "sb-run";
              description = "Sandbox runner binary invoked by sb-gui.";
            };
            notify_send = lib.mkOption {
              type = lib.types.str;
              default = "${pkgs.libnotify}/bin/notify-send";
              description = "Notification binary.";
            };
            xdg_open = lib.mkOption {
              type = lib.types.str;
              default = "${pkgs.xdg-utils}/bin/xdg-open";
              description = "XDG URI/folder opener binary.";
            };
            exiftool = lib.mkOption {
              type = lib.types.str;
              default = "${pkgs.exiftool}/bin/exiftool";
              description = "ExifTool binary for inspecting .lnk shortcuts.";
            };
            wrestool = lib.mkOption {
              type = lib.types.str;
              default = "${pkgs.icoutils}/bin/wrestool";
              description = "wrestool binary for extracting Windows icon resources.";
            };
            magick = lib.mkOption {
              type = lib.types.str;
              default = "${pkgs.imagemagick}/bin/magick";
              description = "ImageMagick binary for icon conversion.";
            };
            systemctl = lib.mkOption {
              type = lib.types.str;
              default = "${pkgs.systemd}/bin/systemctl";
              description = "systemctl binary for checking/stopping prefix scopes.";
            };
            mountpoint = lib.mkOption {
              type = lib.types.str;
              default = "${pkgs.util-linux}/bin/mountpoint";
              description = "mountpoint binary for verifying overlay mounts.";
            };
            umount = lib.mkOption {
              type = lib.types.str;
              default = "${pkgs.util-linux}/bin/umount";
              description = "umount binary for cleaning up mounted prefixes.";
            };
          };
        };
        default = { };
        description = "Helper binary commands and paths.";
      };

      steam = lib.mkOption {
        type = lib.types.submodule {
          options = {
            info_api_url = lib.mkOption {
              type = lib.types.str;
              default = "https://api.steamcmd.net/v1/info/{appid}";
              description = "Steam app info URL template.";
            };
            icon_cdn_url = lib.mkOption {
              type = lib.types.str;
              default = "https://cdn.cloudflare.steamstatic.com/steamcommunity/public/images/apps/{appid}/{hash}.ico";
              description = "Steam client icon CDN URL template.";
            };
            info_timeout_secs = lib.mkOption {
              type = lib.types.int;
              default = 3;
              description = "HTTP timeout in seconds for Steam app info requests.";
            };
            icon_timeout_secs = lib.mkOption {
              type = lib.types.int;
              default = 5;
              description = "HTTP timeout in seconds for Steam icon downloads.";
            };
            search_max_results = lib.mkOption {
              type = lib.types.int;
              default = 80;
              description = "Maximum search results shown in Steam search.";
            };
          };
        };
        default = { };
        description = "Steam search and icon fetching settings.";
      };

      systemd = lib.mkOption {
        type = lib.types.submodule {
          options = {
            prefix_scope_template = lib.mkOption {
              type = lib.types.str;
              default = "umu-pfx-{prefix}.scope";
              description = "Systemd user unit template for active UMU prefix scopes.";
            };
            prefix_mount_rel = lib.mkOption {
              type = lib.types.str;
              default = "umu-pfx/{prefix}";
              description = "Relative runtime mount path template for active prefixes.";
            };
          };
        };
        default = { };
        description = "Systemd prefix lifecycle configuration.";
      };

      shortcut_defaults = lib.mkOption {
        type = lib.types.submodule {
          options = {
            prefix = lib.mkOption {
              type = lib.types.str;
              default = "default";
              description = "Default UMU prefix name.";
            };
            icon = lib.mkOption {
              type = lib.types.str;
              default = "wine";
              description = "Default fallback icon name.";
            };
            gpu = lib.mkOption {
              type = lib.types.str;
              default = "Автоматически";
              description = "Default GPU selection entry.";
            };
            gpu_options = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [
                "Автоматически"
                "AMD"
                "Intel"
                "Nvidia"
              ];
              description = "Available GPU selector choices.";
            };
            default_proton = lib.mkOption {
              type = lib.types.str;
              default = "Proton UMU 10";
              description = "Fallback default Proton display name.";
            };
            proton_versions = lib.mkOption {
              type = lib.types.listOf protonVersionModule;
              default = [
                { name = "Proton GE (Latest)"; }
                { name = "Proton GE 10"; }
                {
                  name = "Proton UMU 10";
                  default = true;
                }
                { name = "Proton UMU 9"; }
                { name = "Proton UMU 8"; }
              ];
              description = "Fallback Proton versions list.";
            };
            gamemode = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Default GameMode toggle state.";
            };
            mangohud = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Default MangoHud toggle state.";
            };
            wayland = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Default Wayland toggle state.";
            };
            x11 = lib.mkOption {
              type = lib.types.str;
              default = "passthrough";
              description = "Default X11 mode for new shortcuts.";
            };
            steam_integration = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Default Steam integration toggle state.";
            };
            steam_overlay = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Default Steam overlay toggle state.";
            };
            vpn = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Default VPN toggle state.";
            };
            sandbox = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Default sandbox toggle state.";
            };
            gamepad = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Default gamepad toggle state.";
            };
            network = lib.mkOption {
              type = lib.types.str;
              default = "sandboxed";
              description = "Default network isolation mode for shortcuts.";
            };
            categories = lib.mkOption {
              type = lib.types.str;
              default = "Game;";
              description = "Desktop entry Categories value.";
            };
            args_placeholder = lib.mkOption {
              type = lib.types.str;
              default = "VAR=1 %command% --dx11";
              description = "Placeholder text for arguments/env entry.";
            };
            gameid_placeholder = lib.mkOption {
              type = lib.types.str;
              default = "Например: 292030 (AppID)";
              description = "Placeholder text for Steam App ID entry.";
            };
          };
        };
        default = { };
        description = "Default shortcut creation/editor values.";
      };

      sandbox_ui = lib.mkOption {
        type = lib.types.submodule {
          options = {
            tmp_id_prefix = lib.mkOption {
              type = lib.types.str;
              default = "tmp-";
              description = "Prefix for auto-generated sandbox IDs in sb-gui.";
            };
            sb_gui_width = lib.mkOption {
              type = lib.types.int;
              default = 640;
              description = "Default window width for sb-gui.";
            };
            sb_gui_height = lib.mkOption {
              type = lib.types.int;
              default = 740;
              description = "Default window height for sb-gui.";
            };
            seccomp_dialog_width = lib.mkOption {
              type = lib.types.int;
              default = 600;
              description = "Seccomp settings dialog width.";
            };
            seccomp_dialog_height = lib.mkOption {
              type = lib.types.int;
              default = 580;
              description = "Seccomp settings dialog height.";
            };
            umu_width_collapsed = lib.mkOption {
              type = lib.types.int;
              default = 560;
              description = "UMU launcher/editor width without sandbox panel.";
            };
            umu_width_expanded = lib.mkOption {
              type = lib.types.int;
              default = 980;
              description = "UMU launcher/editor width with sandbox panel.";
            };
            bridge_default_address = lib.mkOption {
              type = lib.types.str;
              default = "127.0.0.1";
              description = "Default IP address pre-filled in the bridges editor.";
            };
            bridge_ports_placeholder = lib.mkOption {
              type = lib.types.str;
              default = "57343,27060";
              description = "Placeholder text for bridge ports input.";
            };
            bridge_presets = lib.mkOption {
              type = lib.types.listOf bridgePresetModule;
              default = [
                {
                  label = "+ Steam";
                  rule = "from:127.0.0.1:57343,27060";
                }
              ];
              description = "Quick-add bridge preset buttons.";
            };
            umu_defaults = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  x11 = lib.mkOption {
                    type = lib.types.str;
                    default = "passthrough";
                    description = "Default X11 mode in UMU sandbox preset.";
                  };
                  gpu = lib.mkOption {
                    type = lib.types.bool;
                    default = true;
                    description = "Default GPU toggle in UMU sandbox preset.";
                  };
                  landlock = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                    description = "Default Landlock toggle in UMU sandbox preset.";
                  };
                  tmpfs = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                    description = "Default tmpfs toggle in UMU sandbox preset.";
                  };
                  flatpak_portal = lib.mkOption {
                    type = lib.types.bool;
                    default = true;
                    description = "Default org.freedesktop.portal.Flatpak toggle in UMU sandbox preset.";
                  };
                  seccomp_allow = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [
                      "@10:ptrace"
                      "process_vm_readv"
                      "process_vm_writev"
                      "modify_ldt"
                      "personality"
                      "userfaultfd"
                    ];
                    description = "Extra seccomp allow rules added for UMU sandbox presets.";
                  };
                };
              };
              default = { };
              description = "Default sandbox overrides for UMU shortcuts.";
            };
          };
        };
        default = { };
        description = "Sandbox UI defaults and presets.";
      };
    };
  };
in
{
  options.rust-helpers = {
    enable = lib.mkEnableOption "rust-helpers configuration";
    settings = lib.mkOption {
      type = lib.types.submodule rustHelpersConfigModule;
      default = { };
      description = "Declarative runtime settings for rust-helpers binaries.";
    };
  };

  config = lib.mkIf cfg.enable {
    xdg.dataFile."rust-helpers/config.json".source =
      (pkgs.formats.json { }).generate "rust-helpers-config.json"
        (
          removeAttrs
            (lib.evalModules {
              modules = [
                rustHelpersConfigModule
                cfg.settings
              ];
            }).config
            [ "_module" ]
        );
  };
}
