{
  pkgs,
  inputs,
  config,
  lib,
  ...
}:
{

  xdg.configFile = {
    "openxr/1/active_runtime.i686.json".source =
      config.lib.file.mkOutOfStoreSymlink "/etc/xdg/openxr/1/active_runtime.i686.json";
    "bookmarks.html".source = ../../../stuff/bookmarks.html;
    "uwsm/env".source = "${config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh";
  };

  android.enable = false;

  systemd.user.services.easyeffects.Service.TimeoutStopSec = lib.mkForce 1;

  manual.manpages.enable = false;

  sandboxing.enable = true;

  umu.enable = true;

  thunderbird.enable = true;

  zen.enable = true;

  spicetify.enable = true;

  home.file.".config/mpv".source = ../../../stuff/mpv;

  neovim.enable = true;

  theming.enable = true;

  cava.enable = true;

  swaync.enable = true;

  kitty.enable = true;

  zsh.enable = true;

  file-associations.enable = true;

  waybar.enable = true;

  btop.enable = true;

  programs = {

    opencode = {
      enable = true;
      enableMcpIntegration = true;
      package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode;
      settings = {
        autoshare = false;
        autoupdate = true;

        compaction = {
          auto = true;
          prune = true;
          threshold = 0.85;
        };

        lsp = {
          cpp = {
            command = [
              "${pkgs.clang-tools}/bin/clangd"
              "--background-index"
              "--clang-tidy"
              "--header-insertion=iwyu"
              "--completion-style=detailed"
              "-j=4"
            ];
            extensions = [
              ".cpp"
              ".hpp"
              ".h"
              ".cc"
              ".cxx"
            ];
          };
          c = {
            command = [
              "${pkgs.clang-tools}/bin/clangd"
              "--background-index"
              "--clang-tidy"
              "-j=4"
            ];
            extensions = [
              ".c"
              ".h"
            ];
          };
        };

        provider = {
          "llama.cpp" = {
            npm = "@ai-sdk/openai-compatible";
            name = "Local llama-server";
            options = {
              baseURL = "http://127.0.0.1:8080/v1";
            };
            models = {
              qwen-local = {
                name = "/var/lib/llama-cpp/models/Qwen3.6-35B-A3B-abliterated-Q4_K_M.gguf";
                limit = {
                  context = 98304;
                  output = 16384;
                };
              };
            };
          };
        };

        model = "llama.cpp/qwen-local";

        mcp = {
          searxng = {
            type = "local";
            command = [
              "${pkgs.nodejs}/bin/npx"
              "-y"
              "mcp-searxng"
            ];
            env = {
              SEARXNG_URL = "http://127.0.0.1:8000";
            };
          };
        };
      };
    };

    mcp = {
      enable = true;
      servers.context7 = {
        url = "https://mcp.context7.com/mcp";
        headers = {
          CONTEXT7_API_KEY = "{env:CONTEXT7_API_KEY}";
        };
      };
    };

  };

  services = {

    easyeffects.enable = true;

    kdeconnect = {
      enable = true;
      indicator = true;
    };

  };

  mpd = {

    enable = false;

    ncmpcpp = false;

  };

  flatpak = {

    enable = false;

    packages = [
      "io.github.Soundux"
    ];

  };

  hyprland = {

    enable = true;

    from-unstable = false;

    stable = false;

    enable-plugins = true;

    mpvpaper = false;

    wallpaper = true;

    wlogout = true;

    hyprlock = true;

    rofi = true;

  };

  fastfetch = {

    enable = true;

    zsh-start = true;

    logo-path = ../../../stuff/logo.png;

  };
}
