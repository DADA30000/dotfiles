{
  config,
  inputs,
  lib,
  pkgs,
  kekma,
  ...
}:
with lib;
let
  cfg = config.neovim;
  python = pkgs.python3.withPackages (
    ps: with ps; [
      tkinter
      debugpy
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
  };
  rustupInitScript = pkgs.writeShellScript "rustup-init" ''
    export PATH="${lib.makeBinPath [ pkgs.rustup pkgs.gnugrep pkgs.coreutils ]}:$PATH"
    
    TOOLCHAIN_PATH="${config.xdg.dataHome}/nix-system-toolchain"
    
    if ! rustup toolchain list | grep -q "nix-system"; then
      rustup toolchain link nix-system "$TOOLCHAIN_PATH"
    fi

    if ! rustup show active-toolchain >/dev/null 2>&1; then
      rustup default nix-system
    fi
  '';
  nix-path =
    pkgs.runCommand "kekma"
      {
        src = ../../../stuff/nixpkgs.tar.zst;
      }
      ''
        PATH=$PATH:${pkgs.zstd}/bin
        mkdir $out
        tar --strip-components=1 -xvf $src -C $out
      '';
  coc_cfg = ''
    -- https://raw.githubusercontent.com/neoclide/coc.nvim/master/doc/coc-example-config.lua

    -- Some servers have issues with backup files, see #649
    vim.opt.backup = false
    vim.opt.writebackup = false

    -- Having longer updatetime (default is 4000 ms = 4s) leads to noticeable
    -- delays and poor user experience
    vim.opt.updatetime = 100

    -- Always show the signcolumn, otherwise it would shift the text each time
    -- diagnostics appeared/became resolved
    vim.opt.signcolumn = "yes"

    local keyset = vim.keymap.set
    -- Autocomplete
    function _G.check_back_space()
        local col = vim.fn.col('.') - 1
        return col == 0 or vim.fn.getline('.'):sub(col, col):match('%s') ~= nil
    end

    -- Use Tab for trigger completion with characters ahead and navigate
    -- NOTE: There's always a completion item selected by default, you may want to enable
    -- no select by setting `"suggest.noselect": true` in your configuration file
    -- NOTE: Use command ':verbose imap <tab>' to make sure Tab is not mapped by
    -- other plugins before putting this into your config
    local opts = {silent = true, noremap = true, expr = true, replace_keycodes = false}
    keyset("i", "<TAB>", 'coc#pum#visible() ? coc#pum#next(1) : v:lua.check_back_space() ? "<TAB>" : coc#refresh()', opts)
    keyset("i", "<S-TAB>", [[coc#pum#visible() ? coc#pum#prev(1) : "\<C-h>"]], opts)

    -- Make <CR> to accept selected completion item or notify coc.nvim to format
    -- <C-g>u breaks current undo, please make your own choice
    keyset("i", "<cr>", [[coc#pum#visible() ? coc#pum#confirm() : "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"]], opts)

    -- Use <c-j> to trigger snippets
    keyset("i", "<c-j>", "<Plug>(coc-snippets-expand-jump)")
    -- Use <c-space> to trigger completion
    keyset("i", "<c-space>", "coc#refresh()", {silent = true, expr = true})

    -- Use `[g` and `]g` to navigate diagnostics
    -- Use `:CocDiagnostics` to get all diagnostics of current buffer in location list
    keyset("n", "[g", "<Plug>(coc-diagnostic-prev)", {silent = true})
    keyset("n", "]g", "<Plug>(coc-diagnostic-next)", {silent = true})

    -- GoTo code navigation
    keyset("n", "gd", "<Plug>(coc-definition)", {silent = true})
    keyset("n", "gy", "<Plug>(coc-type-definition)", {silent = true})
    keyset("n", "gi", "<Plug>(coc-implementation)", {silent = true})
    keyset("n", "gr", "<Plug>(coc-references)", {silent = true})


    -- Use K to show documentation in preview window
    function _G.show_docs()
        local cw = vim.fn.expand('<cword>')
        if vim.fn.index({'vim', 'help'}, vim.bo.filetype) >= 0 then
            vim.api.nvim_command('h ' .. cw)
        elseif vim.api.nvim_eval('coc#rpc#ready()') then
            vim.fn.CocActionAsync('doHover')
        else
            vim.api.nvim_command('!' .. vim.o.keywordprg .. ' ' .. cw)
        end
    end
    keyset("n", "K", '<CMD>lua _G.show_docs()<CR>', {silent = true})


    -- Highlight the symbol and its references on a CursorHold event(cursor is idle)
    vim.api.nvim_create_augroup("CocGroup", {})
    vim.api.nvim_create_autocmd("CursorHold", {
        group = "CocGroup",
        command = "silent call CocActionAsync('highlight')",
        desc = "Highlight symbol under cursor on CursorHold"
    })


    -- Symbol renaming
    keyset("n", "<leader>rn", "<Plug>(coc-rename)", {silent = true})


    -- Formatting selected code
    keyset("x", "<leader>f", "<Plug>(coc-format-selected)", {silent = true})
    keyset("n", "<leader>f", "<Plug>(coc-format-selected)", {silent = true})


    -- Setup formatexpr specified filetype(s)
    vim.api.nvim_create_autocmd("FileType", {
        group = "CocGroup",
        pattern = "typescript,json",
        command = "setl formatexpr=CocAction('formatSelected')",
        desc = "Setup formatexpr specified filetype(s)."
    })

    -- Apply codeAction to the selected region
    -- Example: `<leader>aap` for current paragraph
    local opts = {silent = true, nowait = true}
    keyset("x", "<leader>a", "<Plug>(coc-codeaction-selected)", opts)
    keyset("n", "<leader>a", "<Plug>(coc-codeaction-selected)", opts)

    -- Remap keys for apply code actions at the cursor position.
    keyset("n", "<leader>ac", "<Plug>(coc-codeaction-cursor)", opts)
    -- Remap keys for apply source code actions for current file.
    keyset("n", "<leader>as", "<Plug>(coc-codeaction-source)", opts)
    -- Apply the most preferred quickfix action on the current line.
    keyset("n", "<leader>qf", "<Plug>(coc-fix-current)", opts)

    -- Remap keys for apply refactor code actions.
    keyset("n", "<leader>re", "<Plug>(coc-codeaction-refactor)", { silent = true })
    keyset("x", "<leader>r", "<Plug>(coc-codeaction-refactor-selected)", { silent = true })
    keyset("n", "<leader>r", "<Plug>(coc-codeaction-refactor-selected)", { silent = true })

    -- Run the Code Lens actions on the current line
    keyset("n", "<leader>cl", "<Plug>(coc-codelens-action)", opts)


    -- Map function and class text objects
    -- NOTE: Requires 'textDocument.documentSymbol' support from the language server
    keyset("x", "if", "<Plug>(coc-funcobj-i)", opts)
    keyset("o", "if", "<Plug>(coc-funcobj-i)", opts)
    keyset("x", "af", "<Plug>(coc-funcobj-a)", opts)
    keyset("o", "af", "<Plug>(coc-funcobj-a)", opts)
    keyset("x", "ic", "<Plug>(coc-classobj-i)", opts)
    keyset("o", "ic", "<Plug>(coc-classobj-i)", opts)
    keyset("x", "ac", "<Plug>(coc-classobj-a)", opts)
    keyset("o", "ac", "<Plug>(coc-classobj-a)", opts)


    -- Remap <C-f> and <C-b> to scroll float windows/popups
    ---@diagnostic disable-next-line: redefined-local
    local opts = {silent = true, nowait = true, expr = true}
    keyset("n", "<C-f>", 'coc#float#has_scroll() ? coc#float#scroll(1) : "<C-f>"', opts)
    keyset("n", "<C-b>", 'coc#float#has_scroll() ? coc#float#scroll(0) : "<C-b>"', opts)
    keyset("i", "<C-f>",
           'coc#float#has_scroll() ? "<c-r>=coc#float#scroll(1)<cr>" : "<Right>"', opts)
    keyset("i", "<C-b>",
           'coc#float#has_scroll() ? "<c-r>=coc#float#scroll(0)<cr>" : "<Left>"', opts)
    keyset("v", "<C-f>", 'coc#float#has_scroll() ? coc#float#scroll(1) : "<C-f>"', opts)
    keyset("v", "<C-b>", 'coc#float#has_scroll() ? coc#float#scroll(0) : "<C-b>"', opts)


    -- Use CTRL-S for selections ranges
    -- Requires 'textDocument/selectionRange' support of language server
    keyset("n", "<C-s>", "<Plug>(coc-range-select)", {silent = true})
    keyset("x", "<C-s>", "<Plug>(coc-range-select)", {silent = true})


    -- Add `:Format` command to format current buffer
    vim.api.nvim_create_user_command("Format", "call CocAction('format')", {})

    -- " Add `:Fold` command to fold current buffer
    vim.api.nvim_create_user_command("Fold", "call CocAction('fold', <f-args>)", {nargs = '?'})

    -- Add `:OR` command for organize imports of the current buffer
    vim.api.nvim_create_user_command("OR", "call CocActionAsync('runCommand', 'editor.action.organizeImport')", {})

    -- Add (Neo)Vim's native statusline support
    -- NOTE: Please see `:h coc-status` for integrations with external plugins that
    -- provide custom statusline: lightline.vim, vim-airline
    vim.opt.statusline:prepend("%{coc#status()}%{get(b:,'coc_current_function',\'\')}")

    -- Mappings for CoCList
    -- code actions and coc stuff
    ---@diagnostic disable-next-line: redefined-local
    local opts = {silent = true, nowait = true}
    -- Show all diagnostics
    keyset("n", "<space>a", ":<C-u>CocList diagnostics<cr>", opts)
    -- Manage extensions
    keyset("n", "<space>e", ":<C-u>CocList extensions<cr>", opts)
    -- Show commands
    keyset("n", "<space>c", ":<C-u>CocList commands<cr>", opts)
    -- Find symbol of current document
    keyset("n", "<space>o", ":<C-u>CocList outline<cr>", opts)
    -- Search workspace symbols
    keyset("n", "<space>s", ":<C-u>CocList -I symbols<cr>", opts)
    -- Do default action for next item
    keyset("n", "<space>j", ":<C-u>CocNext<cr>", opts)
    -- Do default action for previous item
    keyset("n", "<space>k", ":<C-u>CocPrev<cr>", opts)
    -- Resume latest coc list
    keyset("n", "<space>p", ":<C-u>CocListResume<cr>", opts)
  '';
in
{
  options.neovim = {
    enable = mkEnableOption "Enable neovim, console based text editor";
  };

  config = mkIf cfg.enable {
    xdg = {
      configFile."ruff/ruff.toml".source = (pkgs.formats.toml { }).generate "ruff.toml" {
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
      dataFile.nix-system-toolchain.source = rust-toolchain;
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
    home.packages = with pkgs; [
      delve
      rustup
      vscode-extensions.vadimcn.vscode-lldb
      hexpatch
      tinyxxd
      bash-language-server
      shellcheck
      gcc
      shfmt
      asm-lsp
      tmux
      tree-sitter
      ripgrep
      ruff
      basedpyright
      python
    ];
    programs.neovim = {
      coc.enable = true;
      enable = true;
      viAlias = true;
      defaultEditor = true;
      vimAlias = true;
      vimdiffAlias = true;
      plugins = with pkgs.vimPlugins; [
        nvim-dap
        nvim-dap-ui
        nvim-dap-virtual-text
        nvim-nio
        nvim-dap-go
        nvim-dap-python
        indent-blankline-nvim
        nvim-web-devicons
        nvim-treesitter.withAllGrammars
        (pkgs.callPackage ./cord-nvim.nix { })
        coc-snippets
        vim-snippets
        coc-json
        coc-sh
        coc-css
        coc-html
        coc-prettier
        coc-tsserver
        onedark-nvim
        coc-rust-analyzer
        auto-save-nvim
      ];
      coc.settings = {
        diagnostic = {
          enable = true;
          virtualText = true;
          virtualTextCurrentLineOnly = true;
        };
        rust-analyzer = {
          serverPath = "rust-analyzer";
          check = {
            command = "clippy";
            extraArgs = [ "--" "-W" "clippy::all" "-W" "clippy::pedantic" ];
          };
        };
        languageserver = {
          basedpyright = {
            command = "basedpyright-langserver";
            args = [ "--stdio" ];
            filetypes = [ "python" ];
            rootPatterns = [
              "pyproject.toml"
              "setup.py"
              ".git"
              ".venv"
            ];
            settings = {
              basedpyright.analysis = {
                typeCheckingMode = "standard";
                autoImportCompletions = true;
              };
            };
          };
          ruff = {
            command = "ruff";
            args = [ "server" ];
            filetypes = [ "python" ];
            rootPatterns = [
              "pyproject.toml"
              "ruff.toml"
              ".git"
            ];
            settings.logLevel = "debug";
          };
          asm = {
            command = "asm-lsp";
            filetypes = [
              "asm"
              "s"
              "S"
            ];
          };
          qml = {
            command = "qmlls";
            filetypes = [ "qml" ];
            args = [ "-E" ];
          };
          ccls = {
            command = "ccls";
            filetypes = [
              "c"
              "cc"
              "cpp"
              "c++"
              "objc"
              "objcpp"
            ];
            rootPatterns = [
              ".ccls"
              "compile_commands.json"
              ".git/"
              ".hg/"
            ];
            initializationOptions = {
              cache = {
                directory = "/tmp/ccls";
              };
            };
          };
          nixd = {
            command = "nixd";
            rootPatterns = [ ".nixd.json" ];
            filetypes = [ "nix" ];
            settings = {
              nixd = {
                nixpkgs = {
                  expr = "import (builtins.getFlake \"git+file://${nix-path}?rev=${inputs.nixpkgs.rev}&shallow=1\") { system = \"${pkgs.stdenv.hostPlatform.system}\"; config.allowUnfree = true; }";
                };
                formatting = {
                  command = [ "nixfmt" ];
                };
                options = {
                  nixos = {
                    expr = "(builtins.getFlake \"/etc/nixos\").nixosConfigurations.nixos.options";
                  };
                  home_manager = {
                    expr = "(builtins.getFlake \"/etc/nixos\").nixosConfigurations.nixos.options.home-manager.users.type.getSubOptions []";
                  };
                };
              };
            };
          };
        };
      };
      extraLuaConfig = ''
        local dap = require("dap")
        local dapui = require("dapui")
        dapui.setup()
        require("nvim-dap-virtual-text").setup()
        dap.listeners.before.attach.dapui_config = function() dapui.open() end
        dap.listeners.before.launch.dapui_config = function() dapui.open() end
        dap.listeners.before.event_terminated.dapui_config = function() dapui.close() end
        dap.listeners.before.event_exited.dapui_config = function() dapui.close() end
        require('dap-go').setup()
        require('dap-python').setup('${python}/bin/python3')
        dap.adapters.codelldb = {
          type = 'server',
          port = "${"\${port}"}",
          executable = {
            -- POINT THIS TO THE NIX PATH
            -- This path finds the adapter inside the VSCode extension
            command = '${pkgs.vscode-extensions.vadimcn.vscode-lldb}/share/vscode/extensions/vadimcn.vscode-lldb/adapter/codelldb',
            args = {"--port", "${"\${port}"}"},
          }
        }

        dap.configurations.rust = {
          {
            name = "Debug Launch",
            type = "codelldb",
            request = "launch",
            program = function()
              -- This asks you to select the executable to debug from /target/debug
              return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/target/debug/', 'file')
            end,
            cwd = '${"\${workspaceFolder}"}',
            stopOnEntry = false,
          },
        }

        -- === KEYMAPS ===
        vim.keymap.set('n', '<F5>', function() dap.continue() end, { desc = "Debug: Start" })
        vim.keymap.set('n', '<F10>', function() dap.step_over() end, { desc = "Debug: Step Over" })
        vim.keymap.set('n', '<F11>', function() dap.step_into() end, { desc = "Debug: Step Into" })
        vim.keymap.set('n', '<F12>', function() dap.step_out() end, { desc = "Debug: Step Out" })
        vim.keymap.set('n', '<leader>b', function() dap.toggle_breakpoint() end, { desc = "Debug: Breakpoint" })
        require'nvim-treesitter.configs'.setup {
          highlight = {
            enable = true,
          },
        }
        vim.cmd([[
          autocmd TermClose * execute 'bdelete! ' . expand('<abuf>')
          let g:onedark_config = { 'style': 'deep', }
          let g:netrw_keepdir = 0
          colorscheme onedark
          highlight Normal guifg=#bbddff
          map! <S-Insert> <C-R>+
          map !aa :tabnew $NEOVIDE_MOUNT_POINT<cr>
          map !hh :silent! tabnew +Man! ${kekma.home}<cr>
          map !nn :silent! tabnew +Man! ${kekma.nix}<cr>
          nnoremap <silent> <C-h> :CocCommand document.toggleInlayHint<CR>
          set number
          highlight EndOfBuffer ctermbg=none guibg=none
          highlight SignColumn ctermbg=none guibg=none
          highlight Normal guibg=none
          highlight NonText guibg=none
          highlight Normal ctermbg=none
          highlight NonText ctermbg=none
          highlight StatusLine guibg=none
          set tabstop=2
          set softtabstop=2
          set shiftwidth=2
          set expandtab
          set autoindent
          set smartindent
        ]])
        require("ibl").setup {
          indent = { char = "│" },  -- Vertical indentation line
          scope = { enabled = true, show_start = true, show_end = true }, -- Enable scope guides
        }
        if vim.g.neovide == true then
          -- Copy to system clipboard (Normal/Visual mode)
          vim.keymap.set({"n", "x"}, "<C-S-c>", '"+y', {desc = "Copy system clipboard"})
          
          -- Paste from system clipboard (Normal/Visual mode)
          vim.keymap.set({"n", "x"}, "<C-S-v>", '"+p', {desc = "Paste system clipboard"})
          
          -- Paste from system clipboard (Insert mode)
          vim.keymap.set("i", "<C-S-v>", '<C-r><C-o>+', {desc = "Paste system clipboard"})
        end

        local function open_nos_terminal()
          vim.cmd("tab term tmux new-session -s my-tui 'tmux set-option status off; nos; tmux kill-session -t my-tui'")
          vim.b.auto_terminal_mode = true
          vim.cmd('startinsert')
        end

        vim.api.nvim_create_user_command('Hh', open_nos_terminal, {
          desc = 'Open `nos` in a smart terminal',
        })

        vim.keymap.set('n', '!nos', ':Hh<CR>', { desc = 'Open nos terminal', noremap = true, silent = true })

        vim.api.nvim_create_autocmd("BufEnter", {
          pattern = "*",
          callback = function()
            if vim.bo.buftype == "terminal" and vim.b.auto_terminal_mode == true then
              vim.cmd("startinsert")
            end
          end,
        })

        vim.keymap.set('t', '<C-PageDown>', '<C-\\><C-n>:tabnext<CR>', { desc = 'Next Tab', noremap = true, silent = true })
        vim.keymap.set('t', '<C-PageUp>',   '<C-\\><C-n>:tabprevious<CR>', { desc = 'Previous Tab', noremap = true, silent = true })
        vim.opt.undofile = true
        local undodir = vim.fn.expand('~/.config/nvim/undodir')
        vim.opt.undodir = undodir
        require("cord").setup({})
        require("auto-save").setup({})
      ''
      + coc_cfg;
      extraConfig = ''
        if exists("g:neovide")
            let g:neovide_padding_top = 15
            let g:neovide_opacity = 0.2
        endif
        augroup statusline
          autocmd User CocStatusChange redrawstatus
        augroup END
      '';
    };
  };
}
