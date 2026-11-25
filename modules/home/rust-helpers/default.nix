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
      # Display name shown in the Proton version selector.
      name = lib.mkOption {
        type = lib.types.str;
        description = "Display name of the Proton version.";
      };
      # Whether this Proton version is selected by default for new shortcuts.
      default = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether this Proton version is the fallback default.";
      };
    };
  };

  bridgePresetModule = lib.types.submodule {
    options = {
      # Button label in the Bridges UI quick-add bar.
      label = lib.mkOption {
        type = lib.types.str;
        description = "Quick-add button label.";
      };
      # Bridge rule string passed to sb-run (--bridge).
      rule = lib.mkOption {
        type = lib.types.str;
        description = "Bridge specification string (direction:addr:ports).";
      };
    };
  };

  rustHelpersConfigModule = {
    options = {
      # Relative and XDG file paths used by UMU and icon helpers.
      paths = lib.mkOption {
        type = lib.types.submodule {
          options = {
            # Subdirectory under $HOME holding UMU overlay prefixes.
            umu_dir_rel = lib.mkOption {
              type = lib.types.str;
              default = ".umu";
              description = "Relative directory under HOME for UMU prefixes.";
            };
            # Subdirectory under $HOME used to cache extracted icons.
            icon_cache_rel = lib.mkOption {
              type = lib.types.str;
              default = ".cache/umu/icons";
              description = "Relative directory under HOME for cached shortcut icons.";
            };
            # Subdirectory under $XDG_DATA_HOME for persisted shortcut icons.
            icon_dest_rel = lib.mkOption {
              type = lib.types.str;
              default = "icons/umu";
              description = "Relative directory under XDG_DATA_HOME for persisted shortcut icons.";
            };
            # Subdirectory under $XDG_DATA_HOME for .desktop shortcuts.
            desktop_dir_rel = lib.mkOption {
              type = lib.types.str;
              default = "applications";
              description = "Relative directory under XDG_DATA_HOME for .desktop files.";
            };
            # JSON file listing available Proton versions.
            proton_versions_file = lib.mkOption {
              type = lib.types.str;
              default = "$XDG_DATA_HOME/umu-ui/proton_versions.json";
              description = "Path to the Proton versions JSON file.";
            };
            # JSON file containing Steam AppID lookup entries.
            games_appid_file = lib.mkOption {
              type = lib.types.str;
              default = "$XDG_DATA_HOME/umu-ui/games_appid.json";
              description = "Path to the Steam AppID database JSON file.";
            };
            # Directory names inside umu_dir_rel ignored by the prefix manager.
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

      # External helper executable names or paths invoked by rust-helpers.
      bins = lib.mkOption {
        type = lib.types.submodule {
          options = {
            # UMU runner wrapper command.
            umu_run_wrapper = lib.mkOption {
              type = lib.types.str;
              default = "umu-run-wrapper";
              description = "Command used to launch UMU targets and shortcuts.";
            };
            # Post-run .lnk shortcut scanner command.
            scan_umu_for_lnk = lib.mkOption {
              type = lib.types.str;
              default = "scan-umu-for-lnk";
              description = "Command run after launching an executable to index new .lnk files.";
            };
            # Windows executable GUI launcher binary.
            run_exe = lib.mkOption {
              type = lib.types.str;
              default = "run-exe";
              description = "Launcher command for creating a new UMU shortcut.";
            };
            # Sandbox runner CLI binary.
            sb_run = lib.mkOption {
              type = lib.types.str;
              default = "sb-run";
              description = "Sandbox runner binary invoked by sb-gui.";
            };
            # Desktop notification sender command.
            notify_send = lib.mkOption {
              type = lib.types.str;
              default = "${pkgs.libnotify}/bin/notify-send";
              description = "Notification binary.";
            };
            # File/directory opener command.
            xdg_open = lib.mkOption {
              type = lib.types.str;
              default = "${pkgs.xdg-utils}/bin/xdg-open";
              description = "XDG URI/folder opener binary.";
            };
            # ExifTool binary used to inspect Windows .lnk files.
            exiftool = lib.mkOption {
              type = lib.types.str;
              default = "${pkgs.exiftool}/bin/exiftool";
              description = "ExifTool binary for inspecting .lnk shortcuts.";
            };
            # icoutils wrestool binary used to extract .exe icon resources.
            wrestool = lib.mkOption {
              type = lib.types.str;
              default = "${pkgs.icoutils}/bin/wrestool";
              description = "wrestool binary for extracting Windows icon resources.";
            };
            # ImageMagick convert/magick binary for converting .ico to .png.
            magick = lib.mkOption {
              type = lib.types.str;
              default = "${pkgs.imagemagick}/bin/magick";
              description = "ImageMagick binary for icon conversion.";
            };
            # systemd control binary.
            systemctl = lib.mkOption {
              type = lib.types.str;
              default = "${pkgs.systemd}/bin/systemctl";
              description = "systemctl binary for checking/stopping prefix scopes.";
            };
            # mountpoint check binary.
            mountpoint = lib.mkOption {
              type = lib.types.str;
              default = "${pkgs.util-linux}/bin/mountpoint";
              description = "mountpoint binary for verifying overlay mounts.";
            };
            # umount binary for lazy overlay cleanup fallback.
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

      # Steam metadata & icon lookup configuration.
      steam = lib.mkOption {
        type = lib.types.submodule {
          options = {
            # SteamCMD app info API URL template ({appid} placeholder).
            info_api_url = lib.mkOption {
              type = lib.types.str;
              default = "https://api.steamcmd.net/v1/info/{appid}";
              description = "Steam app info URL template.";
            };
            # Steam icon CDN URL template ({appid} and {hash} placeholders).
            icon_cdn_url = lib.mkOption {
              type = lib.types.str;
              default = "https://cdn.cloudflare.steamstatic.com/steamcommunity/public/images/apps/{appid}/{hash}.ico";
              description = "Steam client icon CDN URL template.";
            };
            # Request timeout in seconds for Steam app info lookup.
            info_timeout_secs = lib.mkOption {
              type = lib.types.int;
              default = 3;
              description = "HTTP timeout in seconds for Steam app info requests.";
            };
            # Request timeout in seconds for Steam icon downloads.
            icon_timeout_secs = lib.mkOption {
              type = lib.types.int;
              default = 5;
              description = "HTTP timeout in seconds for Steam icon downloads.";
            };
            # Maximum number of matches displayed in the Steam search dialog.
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

      # Systemd user scope and overlay mount settings for running-prefix management.
      systemd = lib.mkOption {
        type = lib.types.submodule {
          options = {
            # Systemd user scope template for running UMU prefixes ({prefix} placeholder).
            prefix_scope_template = lib.mkOption {
              type = lib.types.str;
              default = "umu-pfx-{prefix}.scope";
              description = "Systemd user unit template for active UMU prefix scopes.";
            };
            # Relative path inside XDG_RUNTIME_DIR for overlay-mounted prefixes ({prefix} placeholder).
            prefix_mount_rel = lib.mkOption {
              type = lib.types.str;
              default = "umu-pfx/{prefix}";
              description = "Relative runtime mount path template for active prefixes.";
            };
            # Maximum wait in milliseconds when stopping a running prefix scope.
            stop_timeout_ms = lib.mkOption {
              type = lib.types.int;
              default = 3000;
              description = "Maximum milliseconds to wait for a stopped prefix unit.";
            };
            # Polling interval in milliseconds while waiting for a stopped prefix unit.
            stop_poll_ms = lib.mkOption {
              type = lib.types.int;
              default = 100;
              description = "Poll interval in milliseconds when waiting on prefix shutdown.";
            };
          };
        };
        default = { };
        description = "Systemd prefix lifecycle configuration.";
      };

      # Default settings for newly created or loaded UMU shortcuts.
      shortcut_defaults = lib.mkOption {
        type = lib.types.submodule {
          options = {
            # Default UMU prefix name.
            prefix = lib.mkOption {
              type = lib.types.str;
              default = "default";
              description = "Default UMU prefix name.";
            };
            # Default fallback icon name.
            icon = lib.mkOption {
              type = lib.types.str;
              default = "wine";
              description = "Default fallback icon name.";
            };
            # Default GPU selector value.
            gpu = lib.mkOption {
              type = lib.types.str;
              default = "Автоматически";
              description = "Default GPU selection entry.";
            };
            # Available GPU options shown in the combo box.
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
            # Fallback Proton name when no version has default=true.
            default_proton = lib.mkOption {
              type = lib.types.str;
              default = "Proton UMU 10";
              description = "Fallback default Proton display name.";
            };
            # Fallback Proton versions list if proton_versions_file is unreadable.
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
            # Default GameMode toggle state.
            gamemode = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Default GameMode toggle state.";
            };
            # Default MangoHud toggle state.
            mangohud = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Default MangoHud toggle state.";
            };
            # Default Wayland toggle state.
            wayland = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Default Wayland toggle state.";
            };
            # Default X11/XWayland mode.
            x11 = lib.mkOption {
              type = lib.types.str;
              default = "passthrough";
              description = "Default X11 mode for new shortcuts.";
            };
            # Default Steam integration toggle state.
            steam_integration = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Default Steam integration toggle state.";
            };
            # Default Steam overlay toggle state.
            steam_overlay = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Default Steam overlay toggle state.";
            };
            # Default VPN toggle state.
            vpn = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Default VPN toggle state.";
            };
            # Default sandbox toggle state.
            sandbox = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Default sandbox toggle state.";
            };
            # Default gamepad toggle state.
            gamepad = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Default gamepad toggle state.";
            };
            # Default network mode for new UMU shortcuts.
            network = lib.mkOption {
              type = lib.types.str;
              default = "sandboxed";
              description = "Default network isolation mode for shortcuts.";
            };
            # Categories field written to generated .desktop shortcuts.
            categories = lib.mkOption {
              type = lib.types.str;
              default = "Game;";
              description = "Desktop entry Categories value.";
            };
            # Placeholder shown in the launch arguments entry.
            args_placeholder = lib.mkOption {
              type = lib.types.str;
              default = "VAR=1 %command% --dx11";
              description = "Placeholder text for arguments/env entry.";
            };
            # Placeholder shown in the Game ID / App ID entry.
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

      # Sandbox UI and UMU sandbox preset configuration.
      sandbox_ui = lib.mkOption {
        type = lib.types.submodule {
          options = {
            # Prefix used for auto-generated temporary sandbox IDs in sb-gui.
            tmp_id_prefix = lib.mkOption {
              type = lib.types.str;
              default = "tmp-";
              description = "Prefix for auto-generated sandbox IDs in sb-gui.";
            };
            # Default sb-gui window width in pixels.
            sb_gui_width = lib.mkOption {
              type = lib.types.int;
              default = 640;
              description = "Default window width for sb-gui.";
            };
            # Default sb-gui window height in pixels.
            sb_gui_height = lib.mkOption {
              type = lib.types.int;
              default = 740;
              description = "Default window height for sb-gui.";
            };
            # Seccomp editor dialog width in pixels.
            seccomp_dialog_width = lib.mkOption {
              type = lib.types.int;
              default = 600;
              description = "Seccomp settings dialog width.";
            };
            # Seccomp editor dialog height in pixels.
            seccomp_dialog_height = lib.mkOption {
              type = lib.types.int;
              default = 580;
              description = "Seccomp settings dialog height.";
            };
            # UMU editor window width when sandbox panel is collapsed.
            umu_width_collapsed = lib.mkOption {
              type = lib.types.int;
              default = 560;
              description = "UMU launcher/editor width without sandbox panel.";
            };
            # UMU editor window width when sandbox panel is expanded.
            umu_width_expanded = lib.mkOption {
              type = lib.types.int;
              default = 980;
              description = "UMU launcher/editor width with sandbox panel.";
            };
            # Default bind address shown in the Bridges widget.
            bridge_default_address = lib.mkOption {
              type = lib.types.str;
              default = "127.0.0.1";
              description = "Default IP address pre-filled in the bridges editor.";
            };
            # Placeholder ports shown in the Bridges widget.
            bridge_ports_placeholder = lib.mkOption {
              type = lib.types.str;
              default = "57343,27060";
              description = "Placeholder text for bridge ports input.";
            };
            # Quick-add bridge presets displayed next to "+ Добавить".
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
            # Sandbox overrides applied by default when SandboxUiMode::Umu initializes.
            umu_defaults = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  # Default X11 mode for sandboxed UMU prefixes.
                  x11 = lib.mkOption {
                    type = lib.types.str;
                    default = "passthrough";
                    description = "Default X11 mode in UMU sandbox preset.";
                  };
                  # Enable GPU passthrough by default in UMU sandbox preset.
                  gpu = lib.mkOption {
                    type = lib.types.bool;
                    default = true;
                    description = "Default GPU toggle in UMU sandbox preset.";
                  };
                  # Landlock toggle default in UMU sandbox preset.
                  landlock = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                    description = "Default Landlock toggle in UMU sandbox preset.";
                  };
                  # Ephemeral tmpfs home default in UMU sandbox preset.
                  tmpfs = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                    description = "Default tmpfs toggle in UMU sandbox preset.";
                  };
                  # Extra seccomp allow rules added on top of sb-run defaults for UMU/pressure-vessel.
                  seccomp_allow = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [
                      "@10:unshare"
                      "@10:setns"
                      "@10:clone"
                      "capset"
                      "mount"
                      "umount"
                      "umount2"
                      "pivot_root"
                      "chroot"
                      "open_tree"
                      "move_mount"
                      "fsopen"
                      "fsconfig"
                      "fsmount"
                      "fspick"
                      "mount_setattr"
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
