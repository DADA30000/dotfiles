{
  config,
  inputs,
  lib,
  pkgs,
  kekma,
  evalAndSubstitute,
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
  smart-neovim-script = pkgs.writeShellScript "smart-nvim" (evalAndSubstitute {
    string = builtins.readFile ../../../stuff/home/neovim/smart-nvim.sh;
  });

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

  rust-analyzer-unwrapped = pkgs.rust-analyzer-unwrapped.overrideAttrs (prev: {
    patches = (prev.patches or [ ]) ++ [ ../../../stuff/patches/rust-analyzer.patch ];
    doCheck = false;
  });

  rust-analyzer = pkgs.rust-analyzer.override {
    inherit rust-analyzer-unwrapped;
  };

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

  rustupInitScript = pkgs.writeShellScript "rustup-init" (evalAndSubstitute {
    string = builtins.readFile ../../../stuff/home/neovim/rustup-init.sh;
    scope = { inherit config; };
  });

  # Injected Nix runtime paths exposed directly to Lua via global _G.NIX table
  nixPreamble = /* lua */ ''
    _G.NIX = {
      python = "${python}/bin/python3",
      gdb = "${pkgs.gdb}/bin/gdb",
      cppdbg = "${pkgs.vscode-extensions.ms-vscode.cpptools}/share/vscode/extensions/ms-vscode.cpptools/debugAdapters/bin/OpenDebugAD7",
      rust_analyzer = "${rust-analyzer}/bin/rust-analyzer",
      rust_toolchain = "${rust-toolchain}",
      rust_lib_src = "${pkgs.rustPlatform.rustLibSrc}",
      kekma_home = "${kekma.home}",
      kekma_nix = "${kekma.nix}",
      nixpkgs_flake = "path:${inputs.nixpkgs}?narHash=${inputs.nixpkgs.narHash}",
      system = "${pkgs.stdenv.hostPlatform.system}",
    }
  '';

  # Read all modular .lua files in alphabetical order
  luaDir = ../../../stuff/home/neovim;
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
    enable = lib.mkEnableOption "neovim, console based text editor";
  };

  config = lib.mkIf cfg.enable {
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
      extraPython3Packages = ps: [
        ps.pynvim
      ];
      plugins = [
        pkgs.vimPlugins.vim-suda
        pkgs.vimPlugins.conform-nvim
        pkgs.vimPlugins.auto-save-nvim
        pkgs.vimPlugins.netrw-nvim
        pkgs.vimPlugins.nvim-dap
        pkgs.vimPlugins.nvim-dap-ui
        pkgs.vimPlugins.nvim-dap-virtual-text
        pkgs.vimPlugins.nvim-nio
        pkgs.vimPlugins.nvim-dap-go
        pkgs.vimPlugins.nvim-dap-python
        pkgs.vimPlugins.indent-blankline-nvim
        pkgs.vimPlugins.nvim-web-devicons
        pkgs.vimPlugins.nvim-treesitter.withAllGrammars
        pkgs.vimPlugins.cord-nvim
        pkgs.vimPlugins.nvim-lspconfig
        pkgs.vimPlugins.nvim-cmp
        pkgs.vimPlugins.cmp-nvim-lsp
        pkgs.vimPlugins.cmp-buffer
        pkgs.vimPlugins.cmp-path
        pkgs.vimPlugins.luasnip
        pkgs.vimPlugins.cmp_luasnip
        pkgs.vimPlugins.friendly-snippets
        pkgs.vimPlugins.fidget-nvim
        pkgs.vimPlugins.onedark-nvim
      ];
    };
  };
}
