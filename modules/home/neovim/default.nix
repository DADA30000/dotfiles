{
  config,
  inputs,
  lib,
  pkgs,
  kekma,
  listFiles ? (
    paths:
    let
      listSingleDir =
        p:
        if builtins.pathExists p then
          map (name: p + "/${name}") (builtins.attrNames (builtins.readDir p))
        else
          throw "The specified path '${toString p}' does not exist.";
    in
    builtins.concatMap listSingleDir paths
  ),
  ...
}:
with lib;
let
  cfg = config.neovim;
  neovide-config = (pkgs.formats.toml { }).generate "neovide-config" {
    font = {
      normal = [
        "JetBrainsMono NF"
      ];
      size = 12;
    };
  };

  # Dispatcher script using explicit coreutils paths
  smart-neovim-script = pkgs.writeShellScript "smart-nvim" ''
    DIR=$(${pkgs.coreutils}/bin/dirname "$0")

    # Direct pass-through for CLI info/build flags (crucial for Nix build sandboxes)
    for arg in "$@"; do
      case "$arg" in
        --version|--help|--headless|--embed|-v|-u|-i|-c|--cmd|-s|-S|-p|-o|-n|-R|-M)
          exec "$DIR/nvim-raw" "$@"
          ;;
      esac
    done

    # Resolve target Neovim RPC server socket
    TARGET_NVIM=""
    if [[ -n "$SESATT_SESSION" ]]; then
      TARGET_NVIM="$(sesatt --get-nvim "$SESATT_SESSION" 2>/dev/null)"
    fi
    if [[ -z "$TARGET_NVIM" ]]; then
      TARGET_NVIM="$NVIM"
    fi

    # Standalone mode (e.g. running inside Kitty outside Neovide)
    if [[ -z "$TARGET_NVIM" ]]; then
      if [ ! -t 0 ]; then
        exec "$DIR/nvim-raw" -c "lua _G.OpenStandalonePager()"
      else
        exec "$DIR/nvim-raw" "$@"
      fi
    fi

    # Stream stdin into user-isolated tmpfs RAM disk (/run/user/$UID/) with 0600 permissions
    send_stdin_stream_rpc() {
      local mode="$1"
      shift

      local JUMP_BOTTOM="v:false"

      # Check CLI arguments
      for arg in "$@"; do
        case "$arg" in
          +G|+G*|-e|--pager-end)
            JUMP_BOTTOM="v:true"
            ;;
        esac
      done

      # Check $LESS environment variable passed by systemd/journalctl
      if [[ "$LESS" == *"+G"* ]]; then
        JUMP_BOTTOM="v:true"
      fi

      local RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      if [[ ! -d "$RUNTIME_DIR" ]]; then
        RUNTIME_DIR="/tmp"
      fi

      local TMPFILE
      (
        umask 077
        TMPFILE=$(${pkgs.coreutils}/bin/mktemp "$RUNTIME_DIR/nvim-pager.XXXXXX")
        ${pkgs.coreutils}/bin/cat > "$TMPFILE"

        if [[ -s "$TMPFILE" ]]; then
          local func
          if [ "$mode" = "man" ]; then
            func="_G.OpenManPageFile"
          else
            func="_G.OpenAnsiPagerFile"
          fi

          exec "$DIR/nvim-raw" --headless --server "$TARGET_NVIM" --remote-expr \
            "v:lua.$func('$TMPFILE', $JUMP_BOTTOM)" >/dev/null 2>&1
        else
          ${pkgs.coreutils}/bin/rm -f "$TMPFILE"
        fi
      )
      exit 0
    }

    # 1. MANPAGER invocation (`nvim +Man!` or `nvim +Man`)
    if [[ "$1" == "+Man!" || "$1" == "+Man" ]]; then
      shift
      ARG="$1"

      if [ ! -t 0 ]; then
        send_stdin_stream_rpc "man" "$@"
      elif [[ -n "$ARG" ]]; then
        ABS_PATH=$(${pkgs.coreutils}/bin/realpath -s -m "$ARG")
        ABS_PATH_ESC="''${ABS_PATH//\'/\'\'}"
        exec "$DIR/nvim-raw" --headless --server "$TARGET_NVIM" --remote-expr \
          "v:lua._G.OpenManPath('$ABS_PATH_ESC')" >/dev/null 2>&1
      else
        exec "$DIR/nvim-raw" --headless --server "$TARGET_NVIM" --remote-expr \
          "v:lua._G.OpenManPath(\"\")" >/dev/null 2>&1
      fi
    fi

    # 2. Piped Stdin (e.g. `cat file | nvim` or `git diff | nvim` or `journalctl | nvim`)
    if [ ! -t 0 ]; then
      send_stdin_stream_rpc "pager" "$@"
    fi

    # 3. No arguments (`nvim`)
    if [ $# -eq 0 ]; then
      PWD_ESC="''${PWD//\'/\'\'}"
      exec "$DIR/nvim-raw" --headless --server "$TARGET_NVIM" --remote-expr "v:lua._G.OpenNewTab('$PWD_ESC')" >/dev/null 2>&1
    fi

    # 4. File arguments (`nvim file1 file2...`)
    FILES_JSON="["
    FIRST=1
    for arg in "$@"; do
      if [[ "$arg" == -* ]]; then
        exec "$DIR/nvim-raw" "$@"
      fi

      # realpath -s -m resolves relative paths WITHOUT expanding/dereferencing symlinks
      ABS_PATH=$(${pkgs.coreutils}/bin/realpath -s -m "$arg")

      CLEAN_PATH=$(printf '%s' "$ABS_PATH" | sed 's/\\/\\\\/g; s/"/\\"/g')
      if [ $FIRST -eq 1 ]; then
        FILES_JSON="$FILES_JSON\"$CLEAN_PATH\""
        FIRST=0
      else
        FILES_JSON="$FILES_JSON,\"$CLEAN_PATH\""
      fi
    done
    FILES_JSON="''${FILES_JSON}]"

    FILES_JSON_ESC="''${FILES_JSON//\'/\'\'}"

    exec "$DIR/nvim-raw" --headless --server "$TARGET_NVIM" --remote-expr \
      "v:lua._G.OpenFiles('$FILES_JSON_ESC')" >/dev/null 2>&1
  '';

  # Patched neovim-unwrapped built natively with C source changes & smart dispatcher script
  patched-neovim-unwrapped = pkgs.neovim-unwrapped.overrideAttrs (oldAttrs: {
    doCheck = false;
    patches = (oldAttrs.patches or [ ]) ++ [
      ../../../stuff/patches/neovim.patch
    ];
    postInstall = (oldAttrs.postInstall or "") + ''
      mv $out/bin/nvim $out/bin/nvim-raw
      cp ${smart-neovim-script} $out/bin/nvim
      chmod +x $out/bin/nvim
    '';
  });

  python = pkgs.python3.withPackages (
    ps: with ps; [
      debugpy
      pynvim
    ]
  );

  rust-toolchain = pkgs.symlinkJoin {
    name = "nixos-system-toolchain";
    paths = with pkgs; [
      rustc-unwrapped
      rustc
      cargo
      rustfmt
      clippy
      rust-analyzer
    ];
    postBuild = ''
      mkdir -p $out/lib/rustlib/src
      ln -s ${pkgs.rustPlatform.rustLibSrc} $out/lib/rustlib/src/rust
    '';
  };

  rustupInitScript = pkgs.writeShellScript "rustup-init" ''
    export PATH="${
      lib.makeBinPath [
        pkgs.rustup
        pkgs.gnugrep
        pkgs.coreutils
      ]
    }:$PATH"

    TOOLCHAIN_PATH="${config.xdg.dataHome}/nix-system-toolchain"
    RUSTUP_PATH="${config.xdg.dataHome}/rustup"
    mkdir -p "$RUSTUP_PATH/toolchains"
    ln -s "$TOOLCHAIN_PATH" "$RUSTUP_PATH/toolchains/nix-system"
    echo 'version = "12"' > "$RUSTUP_PATH/settings.toml"
    echo 'default_toolchain = "nix-system"' >> "$RUSTUP_PATH/settings.toml"
  '';

  # Injected Nix runtime paths exposed directly to Lua via global _G.NIX table
  nixPreamble = /* lua */ ''
    _G.NIX = {
      python = "${python}/bin/python3",
      gdb = "${pkgs.gdb}/bin/gdb",
      cppdbg = "${pkgs.vscode-extensions.ms-vscode.cpptools}/share/vscode/extensions/ms-vscode.cpptools/debugAdapters/bin/OpenDebugAD7",
      rust_analyzer = "${pkgs.rust-analyzer}/bin/rust-analyzer",
      rust_toolchain = "${rust-toolchain}",
      rust_lib_src = "${pkgs.rustPlatform.rustLibSrc}",
      kekma_home = "${kekma.home}",
      kekma_nix = "${kekma.nix}",
      nixpkgs_flake = "path:${inputs.nixpkgs}?narHash=${inputs.nixpkgs.narHash}",
      system = "${pkgs.stdenv.hostPlatform.system}",
    }
  '';

  # Read all modular .lua files in alphabetical order
  luaDir = ../../../stuff/modules/home/neovim;
  luaFiles =
    lib.pipe
      [ luaDir ]
      [
        listFiles
        (builtins.filter (lib.hasSuffix ".lua"))
        (lib.sort (a: b: toString a < toString b))
      ];
  loadedLua = lib.concatMapStringsSep "\n\n" builtins.readFile luaFiles;
in
{
  options.neovim = {
    enable = mkEnableOption "neovim, console based text editor";
  };

  config = mkIf cfg.enable {
    xdg = {
      configFile = {
        "neovide/config.toml".source = neovide-config;
        "ruff/ruff.toml".source = (pkgs.formats.toml { }).generate "ruff.toml" {
          line-length = 79;
          lint = {
            select = [
              "E"
              "W"
              "F"
              "C90"
            ];
            preview = true;
            ignore = [ ];
            mccabe.max-complexity = 10;
          };
        };
      };
      dataFile.nix-system-toolchain.source = rust-toolchain;

      # Create desktop entry for neovide-term
      desktopEntries.neovide-term = {
        name = "neovide-term";
        genericName = "Terminal emulator";
        comment = "Fast, feature-rich, GPU based terminal inside Neovide";
        exec = "neovide-term";
        icon = "neovide";
        categories = [
          "System"
          "TerminalEmulator"
        ];
        startupNotify = true;
        settings = {
          X-TerminalArgExec = "-e";
          X-TerminalArgTitle = "--title";
          X-TerminalArgAppId = "--app-id";
          X-TerminalArgDir = "--working-directory";
          X-TerminalArgHold = "--hold";
        };
      };
    };
    systemd.user.services.rustup-init = {
      Unit = {
        Description = "Initialize rustup with system toolchain";
        After = [ "network.target" ];
      };

      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${rustupInitScript}";
      };

      Install = {
        WantedBy = [ "default.target" ];
      };
    };
    programs.neovim = {
      package = patched-neovim-unwrapped;
      withPython3 = true;
      withRuby = true;
      withPerl = true;
      withNodeJs = true;
      enable = true;
      viAlias = true;
      defaultEditor = true;
      vimAlias = true;
      vimdiffAlias = true;
      initLua = nixPreamble + "\n" + loadedLua;
      extraPython3Packages =
        ps: with ps; [
          pynvim
        ];
      plugins = with pkgs.vimPlugins; [
        conform-nvim
        auto-save-nvim
        netrw-nvim
        nvim-dap
        nvim-dap-ui
        nvim-dap-virtual-text
        nvim-nio
        nvim-dap-go
        nvim-dap-python
        indent-blankline-nvim
        nvim-web-devicons
        nvim-treesitter.withAllGrammars
        cord-nvim
        nvim-lspconfig
        nvim-cmp
        cmp-nvim-lsp
        cmp-buffer
        cmp-path
        luasnip
        cmp_luasnip
        friendly-snippets
        fidget-nvim
        onedark-nvim
      ];
    };
  };
}
