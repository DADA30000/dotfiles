{
  config,
  lib,
  pkgs,
  kekma,
  ...
}:
with lib;
let
  cfg = config.neovim;
  neovide-config = (pkgs.formats.toml { }).generate "neovide-config" {
    font = {
      normal = [
        "JetBrainsMono NF"
        "Noto Emoji"
        "Maple Mono NF CN"
      ];
      size = 12;
    };
  };
  neovide-term = pkgs.writers.writeDashBin "neovide-term" ''
    exec neovide --frame none --no-idle --mouse-cursor-icon i-beam "+term''${1:+ $*}" +startinsert \
      '+set laststatus=0' \
      '+set cmdheight=0' \
      '+nnoremap <C-S-t> :tabnew +term<CR>' \
      '+inoremap <C-S-t> <C-o>:tabnew +term<CR>' \
      '+tnoremap <C-S-t> <C-\><C-n>:tabnew +term<CR>'
  '';
  python = pkgs.python3.withPackages (
    ps: with ps; [
      tkinter
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

    if ! rustup toolchain list | grep -q "nix-system"; then
      rustup toolchain link nix-system "$TOOLCHAIN_PATH"
    fi

    if ! rustup show active-toolchain >/dev/null 2>&1; then
      rustup default nix-system
    fi
  '';
  config_lua = /* lua */ ''
    vim.api.nvim_create_autocmd('FileType', {
      pattern = '*',
      callback = function()
        local lang = vim.treesitter.language.get_lang(vim.bo.filetype)
        if lang then
          pcall(vim.treesitter.start)
        end
      end,
    })

    local dap = require("dap")
    local dapui = require("dapui")
    dapui.setup()
    require("nvim-dap-virtual-text").setup()
    dap.listeners.before.attach.dapui_config = function() dapui.open() end
    dap.listeners.before.launch.dapui_config = function() dapui.open() end
    dap.listeners.before.event_terminated.dapui_config = function() dapui.close() end
    dap.listeners.before.event_exited.dapui_config = function() dapui.close() end
    dap.defaults.fallback.switch_into_active_window = true
    require('dap-go').setup()
    require('dap-python').setup('${python}/bin/python3')
    local function pick_binary(path)
      return coroutine.create(function(dap_run)
        local files = vim.fn.glob(path .. '*', 0, 1)
        local executables = vim.tbl_filter(function(f)
          return vim.fn.executable(f) == 1 and vim.fn.isdirectory(f) == 0
                 and not f:match("%.cpp$") and not f:match("%.c$") and not f:match("%.rs$")
        end, files)

        if #executables == 0 then
          print("No executables found in " .. path)
          coroutine.resume(dap_run, vim.fn.input('Path to executable: ', path, 'file'))
        else
          vim.ui.select(executables, {
            prompt = 'Select executable to debug:',
            format_item = function(item) return vim.fn.fnamemodify(item, ":t") end,
          }, function(choice)
            coroutine.resume(dap_run, choice)
          end)
        end
      end)
    end

    dap.adapters.cppdbg = {
      id = 'cppdbg',
      type = 'executable',
      command = '${pkgs.vscode-extensions.ms-vscode.cpptools}/share/vscode/extensions/ms-vscode.cpptools/debugAdapters/bin/OpenDebugAD7',
    }

    dap.configurations.cpp = {
      {
        name = "Launch file",
        type = "cppdbg",
        request = "launch",
        program = function() return pick_binary(vim.fn.getcwd() .. '/') end,
        cwd = "''${workspaceFolder}",
        stopAtEntry = false,
        setupCommands = {
          {
            text = 'settings set target.process.thread.step-in-avoid-nodebug true',
            description = 'ignore runtime code',
            ignoreFailures = true
          },
          {
            text = '-enable-pretty-printing',
            description = 'enable pretty printing',
            ignoreFailures = false
          },
          {
            text = 'handle SIGSTOP noprint nostop pass',
            description = 'ignore SIGSTOP',
            ignoreFailures = true
          },
        },
        logging = {
          engineLogging = false,
        },
        externalConsole = false,
        MIMode = 'gdb',
        miDebuggerPath = '${pkgs.gdb}/bin/gdb',
      },
    }

    dap.configurations.c = dap.configurations.cpp
    dap.configurations.rust = {
      vim.tbl_extend("force", dap.configurations.cpp[1], {
        name = "Launch Rust (target/debug)",
        program = function()
          return pick_binary(vim.fn.getcwd() .. '/target/debug/')
        end,
      })
    }

    -- === KEYMAPS ===
    vim.keymap.set('n', '<F5>', function() dap.continue() end, { desc = "Debug: Start" })
    vim.keymap.set('n', '<F10>', function() dap.step_over() end, { desc = "Debug: Step Over" })
    vim.keymap.set('n', '<F11>', function() dap.step_into() end, { desc = "Debug: Step Into" })
    vim.keymap.set('n', '<F12>', function() dap.step_out() end, { desc = "Debug: Step Out" })
    vim.keymap.set('n', '<leader>b', function() dap.toggle_breakpoint() end, { desc = "Debug: Breakpoint" })
    vim.cmd([[
      autocmd TermClose * if expand("<abuf>") == bufnr() | silent! quit! | endif
      let g:onedark_config = { 'style': 'deep', }
      let g:netrw_keepdir = 0
      colorscheme onedark
      highlight Visual guibg=#4e5a6b guifg=#ffffff
      highlight Normal guifg=#bbddff
      map! <S-Insert> <C-R>+
      map !aa :tabnew $NEOVIDE_MOUNT_POINT<cr>
      map !hh :silent! tabnew +Man! ${kekma.home}<cr>
      map !nn :silent! tabnew +Man! ${kekma.nix}<cr>
      set number
      set signcolumn=yes
      highlight EndOfBuffer ctermbg=none guibg=none
      highlight SignColumn ctermbg=none guibg=none
      highlight Normal guibg=none
      highlight NonText guibg=none
      highlight Normal ctermbg=none
      highlight NonText ctermbg=none
      highlight StatusLine guibg=none
      set report=99999
      set tabstop=2
      set softtabstop=2
      set shiftwidth=2
      set expandtab
      set autoindent
      set smartindent
    ]])
    require("ibl").setup {
      indent = { char = "│" },  
      scope = { enabled = true, show_start = true, show_end = true }, 
    }
    if vim.g.neovide == true then
      vim.keymap.set({"n", "x"}, "<C-S-c>", '"+y', {desc = "Copy system clipboard"})
      vim.keymap.set({"n", "x"}, "<C-S-v>", '"+p', {desc = "Paste system clipboard"})
      vim.keymap.set("i", "<C-S-v>", '<C-r><C-o>+', {desc = "Paste system clipboard"})
    end

    local function open_nos_terminal()
      vim.cmd("tab term tmux new-session -s my-tui 'tmux set-option status off; nos; tmux kill-session -t my-tui'")
      vim.b.auto_terminal_mode = true
      vim.cmd('startinsert')
    end

    -- Define a custom, beautiful tablined
    _G.MyTabLine = function()
      local s = ""
      for i = 1, vim.fn.tabpagenr("$") do
        -- Highlight the active tab differently from inactive tabs
        if i == vim.fn.tabpagenr() then
          s = s .. "%#TabLineSel#"
        else
          s = s .. "%#TabLine#"
        end

        -- Map the click target to this tab number (for mouse support)
        s = s .. "%" .. i .. "T"

        -- Find the active buffer in this tab
        local buflist = vim.fn.tabpagebuflist(i)
        local winnr = vim.fn.tabpagewinnr(i)
        local bufnr = buflist and buflist[winnr]
        local bufname = bufnr and vim.api.nvim_buf_get_name(bufnr) or ""

        local tabname = ""
        if bufnr and vim.bo[bufnr].buftype == "terminal" then
          -- Fetch the dynamic process title set by your shell/program
          local term_title = vim.b[bufnr].term_title
          if term_title and term_title ~= "" then
            -- Clean up any paths (e.g., "/bin/zsh" -> "zsh")
            local cmd = term_title:match("([^/]+)$") or term_title
            -- Strip trailing flags or arguments (e.g., "htop -d 10" -> "htop")
            cmd = cmd:match("^([^%s]+)") or cmd
            tabname = " " .. cmd
          else
            tabname = " term"
          end
        elseif bufname == "" then
          tabname = "[No Name]"
        else
          local filename = vim.fn.fnamemodify(bufname, ":t")
          if filename == "default.nix" then
            -- "my-module"
            tabname = vim.fn.fnamemodify(bufname, ":h:t")
            -- "my-module/default.nix"
            -- tabname = vim.fn.fnamemodify(bufname, ":h:t") .. "/" .. filename
          else
            tabname = filename
          end
        end

        -- Add clean padding and the tab index
        s = s .. " " .. i .. ": " .. tabname .. " "
      end

      -- Fill the rest of the bar and reset highlight
      s = s .. "%#TabLineFill#%T"
      return s
    end

    -- === HORIZONTAL TRACKPAD SCROLLING IN TERMINALS ===
    -- Translates horizontal trackpad swipes to Left/Right arrow keys in terminal mode
    vim.keymap.set('t', '<ScrollWheelLeft>', '<Left>', { silent = true, desc = "Scroll left in terminal" })
    vim.keymap.set('t', '<ScrollWheelRight>', '<Right>', { silent = true, desc = "Scroll right in terminal" })

    -- Set the tabline to use our Lua function
    vim.o.tabline = "%!v:lua.MyTabLine()"

    vim.api.nvim_create_user_command('Hh', open_nos_terminal, {
      desc = 'Open `nos` in a smart terminal',
    })

    vim.keymap.set('n', '!nos', ':Hh<CR>', { desc = 'Open nos terminal', noremap = true, silent = true })

    -- Remember the last active mode of each terminal buffer and restore it when entering
    vim.api.nvim_create_autocmd("BufLeave", {
      pattern = "term://*",
      callback = function()
        vim.b.last_mode = vim.fn.mode()
      end,
    })

    -- === SILENT MANUAL SAVING ===
    -- Prevents the file status, line count, and byte count from printing on save.
    -- Using 'silent' suppresses standard output while still displaying write errors if they occur.
    local silent_commands = {
      w = "silent w",
      wq = "silent wq",
      x = "silent x",
      wa = "silent wa",
      wqa = "silent wqa",
      xa = "silent xa",
    }
    for abbrev, replacement in pairs(silent_commands) do
      vim.cmd(string.format(
        "cnoreabbrev <expr> %s (getcmdtype() == ':' && getcmdline() ==# '%s') ? '%s' : '%s'",
        abbrev, abbrev, replacement, abbrev
      ))
    end

    -- === TERMINAL VS FILE LAYOUT AUTO-TOGGLE ===
    vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "TermOpen" }, {
      pattern = "*",
      callback = function()
        if vim.bo.buftype == "terminal" then
          -- Hide UI elements for terminal buffers
          vim.o.laststatus = 0
          vim.o.cmdheight = 0

          -- If new tab (nil) or left in Insert mode (t), restore Insert mode automatically!
          if vim.b.last_mode == nil or vim.b.last_mode == "t" then
            vim.cmd("startinsert")
          end
        else
          -- Restore UI elements for standard files
          vim.o.laststatus = 2 -- Use 3 if you prefer Neovim's global statusline
          vim.o.cmdheight = 1
        end
      end,
    })

    -- Make the cursor a vertical line in Terminal-Insert mode
    vim.opt.guicursor:append("t:ver25")

    -- Global Tab-Switching Wrapper
    -- Temporarily mutes ALL animations (scroll, cursor, and position) only during the tab switch,
    -- preventing any visual delay or sluggish "catching up" when switching buffers.
    _G.InstantTabSwitch = function(cmd)
      -- Save all active animation lengths
      local old_scroll = vim.g.neovide_scroll_animation_length or 0.3
      local old_cursor = vim.g.neovide_cursor_animation_length or 0.13
      local old_pos = vim.g.neovide_position_animation_length or 0.15
      
      -- 1. Mute all animations *before* Neovim switches states
      vim.g.neovide_scroll_animation_length = 0
      vim.g.neovide_cursor_animation_length = 0
      vim.g.neovide_position_animation_length = 0
      
      -- 2. Switch the tab
      vim.cmd(cmd)
      
      -- 3. Instantly restore your smooth animations on the next event loop tick
      vim.schedule(function()
        vim.g.neovide_scroll_animation_length = old_scroll
        vim.g.neovide_cursor_animation_length = old_cursor
        vim.g.neovide_position_animation_length = old_pos
      end)
    end

    -- Map your tab controls to use the InstantTabSwitch wrapper
    for _, mode in ipairs({ "n", "i", "t" }) do
      vim.keymap.set(mode, "<C-S-Right>", "<Cmd>lua InstantTabSwitch('tabnext')<CR>", { desc = "Next Tab", silent = true })
      vim.keymap.set(mode, "<C-S-Left>", "<Cmd>lua InstantTabSwitch('tabprevious')<CR>", { desc = "Previous Tab", silent = true })
      vim.keymap.set(mode, "<C-S-w>", "<Cmd>lua InstantTabSwitch('tabclose')<CR>", { desc = "Close Tab", silent = true })
    end

    -- Define a hidden cursor style (100% transparent)
    vim.api.nvim_set_hl(0, "HiddenCursor", { blend = 100, nocombine = true })

    -- Hide cursor during Normal (nt) / Visual (v/V) scrolling in terminals, restore in Insert (t)
    vim.api.nvim_create_autocmd("ModeChanged", {
      pattern = "*",
      callback = function()
        if vim.bo.buftype == "terminal" then
          local mode = vim.api.nvim_get_mode().mode
          if mode == "nt" or mode == "v" or mode == "V" then
            vim.opt.guicursor:append("n-v:HiddenCursor")
          else
            vim.opt.guicursor:remove("n-v:HiddenCursor")
          end
        end
      end,
    })
    vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
      pattern = "term://*",
      callback = function()
        vim.opt.guicursor:remove("n-v:HiddenCursor")
      end
    })

    -- 1. Hard physical stop for Touchpad/Mouse scrolling (prevents bouncy rubber-banding)
    -- (Checks if prompt is at the bottom, and completely discards any further scroll-down inputs)
    vim.keymap.set({ "n", "x" }, "<ScrollWheelDown>", function()
      if vim.bo.buftype == "terminal" then
        local bufnr = vim.api.nvim_get_current_buf()
        local last_line = vim.api.nvim_buf_line_count(bufnr)
        local win_height = vim.fn.winheight(0)
        
        local win_info = vim.fn.getwininfo(vim.fn.win_getid())[1]
        local topline = win_info and win_info.topline
        
        if topline and win_height and last_line then
          local max_topline = last_line - win_height + 1
          if max_topline < 1 then max_topline = 1 end
          
          -- Return an empty string "" to execute a silent, error-free No-Op
          -- (This avoids "<Nop>" which contains "N", triggering the "search previous" error)
          if topline >= max_topline then
            return ""
          end
        end
      end
      -- Pass standard scroll wheel down natively (Neovim translates this automatically)
      return "<ScrollWheelDown>"
    end, { expr = true, silent = true, desc = "Hard stop scroll down" })

    -- 2. Autocommand fallback safety (handles keyboard-based overscrolls like PageDown)
    vim.api.nvim_create_autocmd({ "WinScrolled", "CursorMoved" }, {
      pattern = "term://*",
      callback = function()
        local bufnr = vim.api.nvim_get_current_buf()
        local last_line = vim.api.nvim_buf_line_count(bufnr)
        local win_height = vim.fn.winheight(0)
        
        local win_info = vim.fn.getwininfo(vim.fn.win_getid())[1]
        local topline = win_info and win_info.topline
        
        if topline and win_height and last_line then
          local max_topline = last_line - win_height + 1
          if max_topline < 1 then max_topline = 1 end
          
          -- Fallback view lock (silent and non-recursive)
          if topline > max_topline then
            vim.cmd("noautocmd call winrestview({'topline': " .. max_topline .. "})")
          end
        end
      end,
    })

    -- Auto-snap to terminal prompt when you start typing, pasting, or using shortcuts while scrolled up
    vim.api.nvim_create_autocmd("TermOpen", {
      pattern = "term://*",
      callback = function(args)
        local bufnr = args.buf

        -- Instantly start insert mode and scroll to the bottom ONLY when spawned
        vim.cmd("startinsert")

        -- Absolutely all printable ASCII characters
        local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-=~!@#$%^&*()_+[]{}|;:',./<>?"

        -- Complete Russian alphabet (safe to map completely since Vim commands use ASCII)
        local cyrillic = "абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"

        -- Split cleanly into UTF-8 characters
        local char_list = vim.fn.split(chars .. cyrillic, [[\zs]])
        
        -- Programmatic transition function for Visual/Select modes (v)
        -- Prevents Neovim from flushing or discarding keys during mode switches
        local function exit_visual_and_type(char)
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
          vim.schedule(function()
            vim.cmd("startinsert")
            vim.schedule(function()
              vim.api.nvim_feedkeys(char, "m", true)
            end)
          end)
        end

        -- Register typing mappings for both Normal mode (n) and Visual/Select modes (v)
        -- (This captures absolutely every key, including 'y' and 'Y')
        for _, mode in ipairs({ "n", "v" }) do
          local prefix = (mode == "v" and "<Esc>i" or "i")
          for _, char in ipairs(char_list) do
            vim.keymap.set(mode, char, prefix .. char, { buffer = bufnr, nowait = true, silent = true })
          end
          -- Map Space, Enter, Backspace, and Arrow keys to also jump back
          vim.keymap.set(mode, "<Space>", prefix .. " ", { buffer = bufnr, nowait = true, silent = true })
          vim.keymap.set(mode, "<CR>", prefix .. "<CR>", { buffer = bufnr, nowait = true, silent = true })
          vim.keymap.set(mode, "<BS>", prefix .. "<BS>", { buffer = bufnr, nowait = true, silent = true })
          vim.keymap.set(mode, "<Up>", prefix .. "<Up>", { buffer = bufnr, nowait = true, silent = true })
          vim.keymap.set(mode, "<Down>", prefix .. "<Down>", { buffer = bufnr, nowait = true, silent = true })
          vim.keymap.set(mode, "<Left>", prefix .. "<Left>", { buffer = bufnr, nowait = true, silent = true })
          vim.keymap.set(mode, "<Right>", prefix .. "<Right>", { buffer = bufnr, nowait = true, silent = true })

          -- === ADD: Horizontal scroll mappings for Normal (n) and Visual/Select (v) ===
          vim.keymap.set(mode, "<ScrollWheelLeft>", prefix .. "<Left>", { buffer = bufnr, nowait = true, silent = true })
          vim.keymap.set(mode, "<ScrollWheelRight>", prefix .. "<Right>", { buffer = bufnr, nowait = true, silent = true })
        end

        -- 3. Common terminal control shortcuts (safely passing Ctrl+C, Ctrl+D, Ctrl+L, etc.)
        local ctrl_keys = { "a", "b", "c", "d", "e", "f", "g", "h", "k", "l", "p", "r", "u", "z" }
        for _, key in ipairs(ctrl_keys) do
          local keycode = "<C-" .. key .. ">"
          vim.keymap.set("n", keycode, "i" .. keycode, { buffer = bufnr, nowait = true, silent = true })
          vim.keymap.set("v", keycode, function()
            exit_visual_and_type(vim.api.nvim_replace_termcodes(keycode, true, false, true))
          end, { buffer = bufnr, nowait = true, silent = true })
        end

        -- === ADD: Horizontal scroll mappings for Terminal mode (t) ===
        vim.keymap.set("t", "<ScrollWheelLeft>", "<Left>", { buffer = bufnr, silent = true })
        vim.keymap.set("t", "<ScrollWheelRight>", "<Right>", { buffer = bufnr, silent = true })

        -- Native clipboard paste mapping for Terminal mode (t) - prevents printing ^V
        vim.keymap.set("t", "<C-S-v>", function()
          vim.api.nvim_paste(vim.fn.getreg("+"), true, -1)
        end, { buffer = bufnr, silent = true })

        -- Paste mappings for Normal (n) and Visual/Select (v) modes that automatically enter insert mode first
        vim.keymap.set("n", "<C-S-v>", function()
          vim.cmd("startinsert")
          vim.schedule(function()
            vim.api.nvim_paste(vim.fn.getreg("+"), true, -1)
          end)
        end, { buffer = bufnr, silent = true })

        vim.keymap.set("v", "<C-S-v>", function()
          vim.cmd([[normal! \<Esc>]])
          vim.cmd("startinsert")
          vim.schedule(function()
            vim.api.nvim_paste(vim.fn.getreg("+"), true, -1)
          end)
        end, { buffer = bufnr, silent = true })
      end,
    })

    -- General copy/paste configuration (works in standard Neovim and GUI)
    -- (Configured with 'v' so you can use Ctrl+Shift+C inside both Visual and Select modes!)
    vim.keymap.set({"n", "v"}, "<C-S-c>", "\"+y", { desc = "Copy system clipboard" })
    vim.keymap.set({"n", "v"}, "<C-S-v>", "\"+p", { desc = "Paste system clipboard" })
    vim.keymap.set("i", "<C-S-v>", "<C-r><C-o>+", { desc = "Paste system clipboard" })

    vim.opt.updatetime = 100
    vim.opt.undofile = true
    local undodir = vim.fn.expand('~/.config/nvim/undodir')
    vim.opt.undodir = undodir

    vim.keymap.set({'n', 'v'}, 'd', '"_d')
    vim.keymap.set('n', 'dd', '"_dd')
    vim.keymap.set({'n', 'v'}, 'x', '"_x')
    vim.opt.clipboard = "unnamedplus"

    require("cord").setup({})

    -- === AUTO-SAVE SETUP ===
    require("auto-save").setup({
      enabled = true,
      trigger_events = {
        immediate_save = { "FocusLost", "BufLeave" },
        defer_save = { "InsertLeave" }, 
        cancel_deferred_save = { "InsertEnter" },
      },
      noautocmd = true,
      debounce_delay = 1000,
    })
  '';
  lsp_cmp_cfg = /* lua */ ''
    require("fidget").setup({
      notification = {
        window = {
          winblend = 100,
        },
      },
    })

    local lspconfig = require("lspconfig")

    local luasnip = require("luasnip")
    require("luasnip.loaders.from_vscode").lazy_load()

    local cmp = require("cmp")

    -- Autocomplete
    function _G.check_back_space()
      local col = vim.fn.col('.') - 1
      return col == 0 or vim.fn.getline('.'):sub(col, col):match('%s') ~= nil
    end

    cmp.setup({
      snippet = {
        expand = function(args)
          luasnip.lsp_expand(args.body)
        end,
      },
      mapping = cmp.mapping.preset.insert({
        ['<C-b>'] = cmp.mapping.scroll_docs(-4),
        ['<C-f>'] = cmp.mapping.scroll_docs(4),
        ['<C-Space>'] = cmp.mapping.complete(),
        ['<C-e>'] = cmp.mapping.abort(),
        ['<S-CR>'] = cmp.mapping.confirm({ select = true }),
        ['<CR>'] = cmp.mapping.confirm({ select = false }), 
        ['<Tab>'] = cmp.mapping(function(fallback)
          if cmp.visible() then
            cmp.select_next_item()
          elseif luasnip.expand_or_jumpable() then
            luasnip.expand_or_jump()
          elseif not _G.check_back_space() then
            cmp.complete()
          else
            fallback()
          end
        end, { "i", "s" }),
        ['<S-Tab>'] = cmp.mapping(function(fallback)
          if cmp.visible() then
            cmp.select_prev_item()
          elseif luasnip.jumpable(-1) then
            luasnip.jump(-1)
          else
            fallback()
          end
        end, { "i", "s" }),
      }),
      sources = cmp.config.sources({
        { name = "nvim_lsp" },
        { name = "luasnip" },
      }, {
        { name = "buffer" },
        { name = "path" }
      })
    })

    -- === CONFORM FORMATTING SETUP ===
    local conform = require("conform")
    conform.setup({
      formatters_by_ft = {
        lua = { "stylua" },
        python = { "ruff_format" },
        rust = { "rustfmt" },
        nix = { "nixfmt" }, 
      },
      default_format_opts = {
        lsp_format = "fallback",
      },
      format_on_save = {
        lsp_format = "fallback",
        timeout_ms = 10000, 
      },
    })

    vim.api.nvim_create_user_command("Format", function()
      conform.format({ async = false, lsp_format = "fallback" })
    end, {})

    -- === ASYNC AUTO-FORMAT ON AUTO-SAVE (WITH STATE LOCK) ===
    local is_formatting = false
    vim.api.nvim_create_autocmd("User", {
      pattern = "AutoSaveWritePost",
      group = vim.api.nvim_create_augroup("AutoSaveAsyncFormat", { clear = true }),
      callback = function()
        if is_formatting then return end
        if not vim.bo.modifiable then return end

        is_formatting = true
        conform.format({
          async = true,
          lsp_format = "fallback",
          callback = function()
            is_formatting = false
            -- Write changes to disk silently without triggering standard autocmds
            if vim.bo.modified then
              vim.cmd("silent! noautocmd write")
            end
          end,
        })
      end,
    })

    -- Configure Diagnostics
    vim.diagnostic.config({
      virtual_text = true,
      float = {
        focusable = false,
        style = "minimal",
        border = "rounded",
        source = "always",
        header = "",
        prefix = "",
      },
    })

    vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
      callback = function()
        vim.diagnostic.open_float(nil, { focusable = false, scope = "cursor" })
      end
    })

    vim.keymap.set('n', '[g', vim.diagnostic.goto_prev, { desc = "Previous Diagnostic" })
    vim.keymap.set('n', ']g', vim.diagnostic.goto_next, { desc = "Next Diagnostic" })
    vim.keymap.set('n', '<space>a', vim.diagnostic.setqflist, { desc = "Workspace Diagnostics" })

    vim.api.nvim_create_autocmd('LspAttach', {
      group = vim.api.nvim_create_augroup('UserLspConfig', {}),
      callback = function(ev)
        local opts = { buffer = ev.buf, silent = true }
        local bind = vim.keymap.set

        bind('n', 'gd', vim.lsp.buf.definition, opts)
        bind('n', 'gy', vim.lsp.buf.type_definition, opts)
        bind('n', 'gi', vim.lsp.buf.implementation, opts)
        bind('n', 'gr', vim.lsp.buf.references, opts)
        bind('n', 'K', vim.lsp.buf.hover, opts)
        bind('n', '<leader>rn', vim.lsp.buf.rename, opts)
        bind({'n', 'x'}, '<leader>f', function() conform.format({ async = false, lsp_format = "fallback" }) end, opts)
        bind({'n', 'x'}, '<leader>a', vim.lsp.buf.code_action, opts)
        bind('n', '<leader>ac', vim.lsp.buf.code_action, opts)
        bind('n', '<leader>cl', vim.lsp.codelens.run, opts)
      end,
    })

    vim.keymap.set('n', '<C-h>', function()
      if vim.lsp.inlay_hint then
        vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
      end
    end, { desc = "Toggle Inlay Hints", silent = true })

    local capabilities = require('cmp_nvim_lsp').default_capabilities()

    -- Compliant Neovim 0.11+ configuration style via vim.lsp.config.
    vim.lsp.config('rust_analyzer', {
      capabilities = capabilities,
      root_dir = function(bufnr, cb)
        local fname = vim.api.nvim_buf_get_name(bufnr)
        if fname == "" then
          return
        end
        local root = vim.fs.root(fname, { 'Cargo.toml', 'rust-project.json' })
        cb(root) -- Pass nil if we are not inside a Cargo workspace
      end,
      before_init = function(params, config)
        -- 1. Ensure settings['rust-analyzer'] is properly loaded into initializationOptions.
        -- Overriding before_init replaces the default handler, so we must merge this manually.
        if config.settings and config.settings['rust-analyzer'] then
          params.initializationOptions = vim.tbl_deep_extend(
            "force",
            params.initializationOptions or {},
            config.settings['rust-analyzer']
          )
        end

        -- 2. Configure detached/single-file mode if not in a workspace
        local fname = vim.api.nvim_buf_get_name(0)
        if fname ~= "" then
          local root = vim.fs.root(fname, { 'Cargo.toml', 'rust-project.json' })
          if not root then
            -- Force-nullify workspace paths using vim.NIL to prevent fallback to the editor's cwd
            params.rootPath = vim.NIL
            params.rootUri = vim.NIL
            params.workspaceFolders = vim.NIL

            -- Configure the detached files directly in initializationOptions
            params.initializationOptions = params.initializationOptions or {}
            params.initializationOptions.detachedFiles = { fname }
          end
        end
      end,
      settings = {
        ["rust-analyzer"] = {
          check = {
            command = "clippy",
            extraArgs = { "--", "-W", "clippy::all", "-W", "clippy::pedantic" }
          }
        }
      }
    })
    vim.lsp.enable('rust_analyzer')

    vim.lsp.config('basedpyright', {
      capabilities = capabilities,
      settings = {
        basedpyright = {
          analysis = {
            typeCheckingMode = "standard",
            autoImportCompletions = true,
          }
        }
      }
    })
    vim.lsp.enable('basedpyright')

    vim.lsp.config('ruff', {
      capabilities = capabilities,
      init_options = {
        settings = { logLevel = "debug" }
      }
    })
    vim.lsp.enable('ruff')

    vim.lsp.config('asm_lsp', {
      capabilities = capabilities,
      filetypes = { "asm", "s", "S" }
    })
    vim.lsp.enable('asm_lsp')

    vim.lsp.config('qmlls', {
      capabilities = capabilities,
      cmd = { "qmlls", "-E" }
    })
    vim.lsp.enable('qmlls')

    vim.lsp.config('cmake', {
      capabilities = capabilities,
      init_options = { buildDirectory = "build" }
    })
    vim.lsp.enable('cmake')

    vim.lsp.config('clangd', { capabilities = capabilities })
    vim.lsp.enable('clangd')

    vim.lsp.config('nixd', {
      capabilities = capabilities,
      settings = {
        nixd = {
          nixpkgs = {
            expr = 'import (builtins.getFlake "git+file://${config.offline-path}?rev=${config.offline-rev}").inputs.nixpkgs { system = "${pkgs.stdenv.hostPlatform.system}"; config.allowUnfree = true; }'
          },
          formatting = {
            command = { "nixfmt" }
          },
          options = {
            nixos = {
              expr = '(builtins.getFlake "/etc/nixos").nixosConfigurations.nixos.options'
            },
            home_manager = {
              expr = '(builtins.getFlake "/etc/nixos").nixosConfigurations.nixos.options.home-manager.users.type.getSubOptions []'
            }
          }
        }
      }
    })
    vim.lsp.enable('nixd')

    vim.lsp.config('lua_ls', {
      capabilities = capabilities,
      settings = {
        Lua = {
          diagnostics = {
            globals = { 'vim' }
          }
        }
      }
    })
    vim.lsp.enable('lua_ls')

    local standard_lsps = { 'bashls', 'html', 'cssls', 'jsonls', 'jdtls', 'taplo', 'yamlls' }
    for _, lsp in ipairs(standard_lsps) do
      vim.lsp.config(lsp, { capabilities = capabilities })
      vim.lsp.enable(lsp)
    end
  '';
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
        exec = "${neovide-term}/bin/neovide-term";
        icon = "neovide";
        categories = [
          "System"
          "TerminalEmulator"
        ];
        startupNotify = true;
        settings = {
          X-TerminalArgExec = "--";
          X-TerminalArgTitle = "--title";
          X-TerminalArgAppId = "--class";
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
    home.packages = with pkgs; [
      neovide-term
      stylua
      delve
      rustup
      vscode-extensions.ms-vscode.cpptools
      hexpatch
      tinyxxd
      bash-language-server

      # Patches ESM main files to prepend Node's createRequire helper
      (
        (vscode-langservers-extracted.override {
          buildNpmPackage = buildNpmPackage.override { nodejs = nodejs_22; };
        }).overrideAttrs
        (oldAttrs: {
          postInstall = (oldAttrs.postInstall or "") + ''
            for f in $(find $out -name "*ServerMain.js"); do
              echo 'import { createRequire } from "module"; const require = createRequire(import.meta.url);' > temp.js
              cat "$f" >> temp.js
              mv temp.js "$f"
            done
          '';
        })
      )

      jdt-language-server
      lua-language-server
      taplo
      yaml-language-server
      shellcheck
      shfmt
      asm-lsp
      tmux
      tree-sitter
      ripgrep
      ruff
      basedpyright
      python
      cmake-lint
      clang-tools
      clang
      cmake-language-server
    ];
    programs.neovim = {
      withPython3 = true;
      withRuby = true;
      withPerl = true;
      withNodeJs = true;
      enable = true;
      viAlias = true;
      defaultEditor = true;
      vimAlias = true;
      vimdiffAlias = true;
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
      initLua = config_lua + lsp_cmp_cfg;
      extraConfig = ''
        if exists("g:neovide")
          let g:neovide_scroll_animation_length = 0.15
          let g:neovide_cursor_animation_length = 0.05
          let g:neovide_cursor_trail_size = 0.2
          let g:neovide_refresh_rate_idle = 165
          let g:neovide_padding_top = 20
          let g:neovide_padding_left = 20
          let g:neovide_padding_right = 20
          let g:neovide_opacity = 0.2
          let g:neovide_floating_shadow = v:false
          let g:neovide_floating_blur_amount_x = 8.0
          let g:neovide_floating_blur_amount_y = 8.0
        endif
      '';
    };
  };
}
