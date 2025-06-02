{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.neovim;
in
{
  options.neovim = {
    enable = mkEnableOption "Enable neovim, console based text editor";
  };

  config = mkIf cfg.enable {
    programs.neovim = {
      coc.enable = true;
      enable = true;
      viAlias = true;
      defaultEditor = true;
      vimAlias = true;
      vimdiffAlias = true;
      plugins = with pkgs.vimPlugins; [
        onedark-nvim
        indent-blankline-nvim
        nvim-web-devicons
        nvim-treesitter-parsers.cpp
        nvim-treesitter-parsers.nix
        nvim-treesitter-parsers.javascript
        nvim-treesitter
        coc-ultisnips
        coc-snippets
        vim-snippets
        coc-json
        presence-nvim
        coc-basedpyright
        coc-css
        coc-html
        coc-tsserver
        coc-rust-analyzer
      ];
      coc.settings = {
        languageserver = {
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
                  expr = "import <nixpkgs> { }";
                };
                formatting = {
                  command = [ "nixfmt" ];
                };
                options = {
                  nixos = {
                    expr = "(builtins.getFlake \"/etc/nixos\").nixosConfigurations.nixos.options";
                  };
                  home_manager = {
                    expr = "(builtins.getFlake \"/etc/nixos\").homeConfigurations.\"${config.home.username}\".options";
                  };
                };
              };
            };
          };
        };
      };
      extraLuaConfig = ''
        require'nvim-treesitter.configs'.setup {
          highlight = {
            enable = true,
          },
          vim.cmd([[
            let g:onedark_config = { 'style': 'deep', }
            colorscheme onedark
            highlight Normal guifg=#bbddff
            map! <S-Insert> <C-R>+
            map !aa :tabnew +Ex /etc/nixos<cr>
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
        }
        require("ibl").setup {
          indent = { char = "│" },  -- Vertical indentation line
          scope = { enabled = true, show_start = true, show_end = true }, -- Enable scope guides
        }
        -- https://raw.githubusercontent.com/neoclide/coc.nvim/master/doc/coc-example-config.lua

        -- Some servers have issues with backup files, see #649
        vim.opt.backup = false
        vim.opt.writebackup = false

        -- Having longer updatetime (default is 4000 ms = 4s) leads to noticeable
        -- delays and poor user experience
        vim.opt.updatetime = 300

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

        -- Update signature help on jump placeholder
        vim.api.nvim_create_autocmd("User", {
            group = "CocGroup",
            pattern = "CocJumpPlaceholder",
            command = "call CocActionAsync('showSignatureHelp')",
            desc = "Update signature help on jump placeholder"
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
        vim.opt.statusline:prepend("%{coc#status()}%{get(b:,'coc_current_function','${''''}')}")

        ---@diagnostic disable-next-line: redefined-local
        local opts = {silent = true, nowait = true}
        keyset("n", "<space>a", ":<C-u>CocList diagnostics<cr>", opts)
        keyset("n", "<space>e", ":<C-u>CocList extensions<cr>", opts)
        keyset("n", "<space>c", ":<C-u>CocList commands<cr>", opts)
        keyset("n", "<space>o", ":<C-u>CocList outline<cr>", opts)
        keyset("n", "<space>s", ":<C-u>CocList -I symbols<cr>", opts)
        keyset("n", "<space>j", ":<C-u>CocNext<cr>", opts)
        keyset("n", "<space>k", ":<C-u>CocPrev<cr>", opts)
        keyset("n", "<space>p", ":<C-u>CocListResume<cr>", opts)
        require("presence").setup({
          -- General options
          auto_update         = true,                       -- Update activity based on autocmd events (if `false`, map or manually execute `:lua package.loaded.presence:update()`)
          neovim_image_text   = "The One True Text Editor", -- Text displayed when hovered over the Neovim image
          main_image          = "neovim",                   -- Main image display (either "neovim" or "file")
          client_id           = "793271441293967371",       -- Use your own Discord application client id (not recommended)
          log_level           = nil,                        -- Log messages at or above this level (one of the following: "debug", "info", "warn", "error")
          debounce_timeout    = 10,                         -- Number of seconds to debounce events (or calls to `:lua package.loaded.presence:update(<filename>, true)`)
          enable_line_number  = false,                      -- Displays the current line number instead of the current project
          blacklist           = {},                         -- A list of strings or Lua patterns that disable Rich Presence if the current file name, path, or workspace matches
          buttons             = true,                       -- Configure Rich Presence button(s), either a boolean to enable/disable, a static table (`{{ label = "<label>", url = "<url>" }, ...}`, or a function(buffer: string, repo_url: string|nil): table)
          file_assets         = {},                         -- Custom file asset definitions keyed by file names and extensions (see default config at `lua/presence/file_assets.lua` for reference)
          show_time           = true,                       -- Show the timer

          -- Rich Presence text options
          editing_text        = "Editing %s",               -- Format string rendered when an editable file is loaded in the buffer (either string or function(filename: string): string)
          file_explorer_text  = "Browsing %s",              -- Format string rendered when browsing a file explorer (either string or function(file_explorer_name: string): string)
          git_commit_text     = "Committing changes",       -- Format string rendered when committing changes in git (either string or function(filename: string): string)
          plugin_manager_text = "Managing plugins",         -- Format string rendered when managing plugins (either string or function(plugin_manager_name: string): string)
          reading_text        = "Reading %s",               -- Format string rendered when a read-only or unmodifiable file is loaded in the buffer (either string or function(filename: string): string)
          workspace_text      = "Working on %s",            -- Format string rendered when in a git repository (either string or function(project_name: string|nil, filename: string): string)
          line_number_text    = "Line %s out of %s",        -- Format string rendered when `enable_line_number` is set to true (either string or function(line_number: number, line_count: number): string)
        })
      if vim.g.neovide == true then
        -- Copy to system clipboard (Normal/Visual mode)
        vim.keymap.set({"n", "x"}, "<C-S-c>", '"+y', {desc = "Copy system clipboard"})
        
        -- Paste from system clipboard (Normal/Visual mode)
        vim.keymap.set({"n", "x"}, "<C-S-v>", '"+p', {desc = "Paste system clipboard"})
        
        -- Paste from system clipboard (Insert mode)
        vim.keymap.set("i", "<C-S-v>", '<C-r><C-o>+', {desc = "Paste system clipboard"})
      end
      '';
      extraConfig = ''
        if exists("g:neovide")
            let g:neovide_padding_top = 15
            let g:neovide_opacity = 0.2
        endif
        augroup autosave
          autocmd!
          autocmd TextChanged,TextChangedI * if &modifiable && !&readonly | silent! write | endif
        augroup END
      '';
    };
  };
}
