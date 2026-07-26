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
    exec neovide --frame none --mouse-cursor-icon i-beam "+term''${1:+ $*}" +startinsert \
      '+set laststatus=0' \
      '+set cmdheight=0' \
      '+nnoremap <C-S-t> :tabnew +term<CR>' \
      '+inoremap <C-S-t> <C-o>:tabnew +term<CR>' \
      '+tnoremap <C-S-t> <C-\><C-n>:tabnew +term<CR>' \
      '+xnoremap <C-S-t> <Esc>:tabnew +term<CR>' \
      '+snoremap <C-S-t> <Esc>:tabnew +term<CR>'
  '';
  nvr-remote-editor = pkgs.writeShellScriptBin "nvr-remote-editor" ''
    exec ${pkgs.neovim-remote}/bin/nvr --servername "$NVIM" --remote-tab-wait +"setlocal bufhidden=wipe" "$@"
  '';

  # Dispatcher script using explicit coreutils paths
  smart-neovim-script = pkgs.writeShellScript "smart-nvim" ''
    DIR=$(${pkgs.coreutils}/bin/dirname "$0")

    # Direct pass-through for CLI info flags
    for arg in "$@"; do
      case "$arg" in
        --version|--help|--headless|--embed|-v)
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

    # If not running inside a Neovim terminal session, execute real neovim-raw
    if [[ -z "$TARGET_NVIM" ]]; then
      exec "$DIR/nvim-raw" "$@"
    fi

    # 1. Piped Stdin (e.g. `cat file | nvim` or `git diff | nvim`)
    if [ ! -t 0 ]; then
      TMPFILE=$(${pkgs.coreutils}/bin/mktemp /tmp/nvim-pipe.XXXXXX)
      ${pkgs.coreutils}/bin/cat > "$TMPFILE"
      exec "$DIR/nvim-raw" --headless --server "$TARGET_NVIM" --remote-send \
        "<Cmd>tabnew $TMPFILE | setlocal buftype=nofile bufhidden=wipe nomodifiable | file [Pager]<CR>"
    fi

    # 2. MANPAGER invocation (`nvim +Man!` or `nvim +Man`)
    if [[ "$1" == "+Man!" || "$1" == "+Man" ]]; then
      shift
      ARG="$1"
      if [[ -n "$ARG" ]]; then
        if [[ -e "$ARG" ]]; then
          ABS_PATH=$(${pkgs.coreutils}/bin/readlink -f "$ARG")
          exec "$DIR/nvim-raw" --headless --server "$TARGET_NVIM" --remote-send \
            "<Cmd>tabnew | silent! Man $ABS_PATH<CR>"
        else
          exec "$DIR/nvim-raw" --headless --server "$TARGET_NVIM" --remote-send \
            "<Cmd>tabnew | silent! Man $ARG<CR>"
        fi
      else
        exec "$DIR/nvim-raw" --headless --server "$TARGET_NVIM" --remote-send \
          "<Cmd>tabnew | silent! Man<CR>"
      fi
    fi

    # 3. No arguments (`nvim`)
    if [ $# -eq 0 ]; then
      exec "$DIR/nvim-raw" --headless --server "$TARGET_NVIM" --remote-send "<Cmd>tabnew<CR>"
    fi

    # 4. File arguments (`nvim file1 file2...`)
    CMD_STR="<Cmd>tabnew"
    FIRST=1
    for arg in "$@"; do
      if [[ "$arg" == -* ]]; then
        exec "$DIR/nvim-raw" "$@"
      fi
      if [[ -e "$arg" ]]; then
        ABS_PATH=$(${pkgs.coreutils}/bin/readlink -f "$arg")
      else
        ABS_PATH="$arg"
      fi

      if [ $FIRST -eq 1 ]; then
        CMD_STR="''${CMD_STR} | edit ''${ABS_PATH}"
        FIRST=0
      else
        CMD_STR="''${CMD_STR} | tabedit ''${ABS_PATH}"
      fi
    done
    CMD_STR="''${CMD_STR}<CR>"

    exec "$DIR/nvim-raw" --headless --server "$TARGET_NVIM" --remote-send "$CMD_STR"
  '';

  # Patched neovim-unwrapped built natively with C source changes & smart dispatcher script
  patched-neovim-unwrapped = pkgs.neovim-unwrapped.overrideAttrs (oldAttrs: {
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

    if ! rustup toolchain list | grep -q "nix-system"; then
      rustup toolchain link nix-system "$TOOLCHAIN_PATH"
    fi

    if ! rustup show active-toolchain >/dev/null 2>&1; then
      rustup default nix-system
    fi
  '';
  config_lua = /* lua */ ''
    -- Auto bufhidden=wipe for git and temp edit files so nvr unblocks git/sudoedit immediately on close
    vim.api.nvim_create_autocmd({"BufReadPost", "BufNewFile"}, {
      group = vim.api.nvim_create_augroup("AutoWipeGitAndTemp", { clear = true }),
      pattern = {
        "/tmp/*",
        "/var/tmp/*",
        "*/.git/COMMIT_EDITMSG",
        "*/.git/git-rebase-todo",
        "*/.git/MERGE_MSG",
        "*/.git/SQUASH_MSG",
      },
      callback = function()
        vim.bo.bufhidden = "wipe"
      end,
    })

    -- === DISABLE FOLDING GLOBALLY ===
    vim.opt.foldenable = false
    vim.opt.foldlevel = 99

    -- Disable mode display to prevent command line popups in cmdheight=0
    vim.opt.showmode = false

    -- === AUTO-STOP LSP WHEN ITS LAST BUFFER IS CLOSED ===
    local stopping_clients = {}
    vim.api.nvim_create_autocmd("LspDetach", {
      group = vim.api.nvim_create_augroup("LspAutoStopOnClose", { clear = true }),
      callback = function(ev)
        local client_id = ev.data.client_id
        if not client_id or stopping_clients[client_id] then return end

        vim.schedule(function()
          if stopping_clients[client_id] then return end
          local client = vim.lsp.get_client_by_id(client_id)
          if not client or (client.is_stopped and client.is_stopped()) then return end

          local has_attached = false
          for bufnr, is_attached in pairs(client.attached_buffers or {}) do
            if is_attached and bufnr ~= ev.buf and vim.api.nvim_buf_is_valid(bufnr) then
              has_attached = true
              break
            end
          end

          if not has_attached then
            stopping_clients[client_id] = true
            pcall(vim.lsp.stop_client, client_id, true)
          end
        end)
      end,
    })

    -- === AUTO-WIPE UNUSED FILE BUFFERS WHEN TAB/WINDOW IS CLOSED ===
    vim.api.nvim_create_autocmd({ "BufHidden", "TabClosed" }, {
      group = vim.api.nvim_create_augroup("AutoWipeHiddenBuffers", { clear = true }),
      callback = function(ev)
        vim.schedule(function()
          local buf = ev.buf
          if not vim.api.nvim_buf_is_valid(buf) then return end
          if vim.bo[buf].modified or vim.bo[buf].buftype ~= "" then return end

          local is_visible = false
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
              is_visible = true
              break
            end
          end

          if not is_visible then
            pcall(vim.api.nvim_buf_delete, buf, { force = false })
          end
        end)
      end,
    })

    -- === TAB ORIGIN TRACKER (RETURN TO ORIGIN TAB ON CLOSE) ===
    vim.opt.tabclose = "uselast"
    local tab_origins = {}
    local last_tabpage = vim.api.nvim_get_current_tabpage()

    vim.api.nvim_create_autocmd("TabLeave", {
      group = vim.api.nvim_create_augroup("TabOriginLeave", { clear = true }),
      callback = function()
        last_tabpage = vim.api.nvim_get_current_tabpage()
      end,
    })

    vim.api.nvim_create_autocmd("TabNew", {
      group = vim.api.nvim_create_augroup("TabOriginNew", { clear = true }),
      callback = function()
        local new_tab = vim.api.nvim_get_current_tabpage()
        if last_tabpage and vim.api.nvim_tabpage_is_valid(last_tabpage) and last_tabpage ~= new_tab then
          tab_origins[new_tab] = last_tabpage
        end
      end,
    })

    vim.api.nvim_create_autocmd("TabClosedPre", {
      group = vim.api.nvim_create_augroup("TabOriginClose", { clear = true }),
      callback = function()
        local closing_tab = vim.api.nvim_get_current_tabpage()
        local origin = tab_origins[closing_tab]
        tab_origins[closing_tab] = nil
        if origin and vim.api.nvim_tabpage_is_valid(origin) then
          vim.schedule(function()
            if vim.api.nvim_tabpage_is_valid(origin) then
              vim.api.nvim_set_current_tabpage(origin)
            end
          end)
        end
      end,
    })

    -- === CLEAN KITTY-STYLE WINDOW TITLE ===
    vim.opt.title = true

    _G.GetWindowTitle = function()
      local bufnr = vim.api.nvim_get_current_buf()
      local bufname = vim.api.nvim_buf_get_name(bufnr)

      if vim.bo[bufnr].buftype == "terminal" then
        local term_title = vim.b[bufnr].term_title
        if term_title and term_title ~= "" then
          local cmd = term_title:match("([^/]+)$") or term_title
          return cmd:match("^([^%s]+)") or cmd
        end
        return "term"
      elseif bufname == "" then
        return "[No Name]"
      else
        local filename = vim.fn.fnamemodify(bufname, ":t")
        if filename == "default.nix" then
          return vim.fn.fnamemodify(bufname, ":h:t") .. "/default.nix"
        end
        return filename
      end
    end

    vim.o.titlestring = "%{v:lua.GetWindowTitle()}"

    -- === BROWSER / KITTY-STYLE MOUSE DRAG AUTO-SCROLL SELECTION ===
    local drag_timer = nil

    local function stop_drag_scroll()
      if drag_timer then
        pcall(function()
          drag_timer:stop()
          if not drag_timer:is_closing() then
            drag_timer:close()
          end
        end)
        drag_timer = nil
      end
    end

    local function start_drag_scroll()
      if drag_timer then return end

      drag_timer = vim.uv.new_timer()
      drag_timer:start(0, 12, vim.schedule_wrap(function()
        local mode = vim.api.nvim_get_mode().mode
        if not (mode:match("[vV\22sS\19]") or mode == "n") then
          stop_drag_scroll()
          return
        end

        local mouse = vim.fn.getmousepos()
        local winid = vim.api.nvim_get_current_win()
        local win_height = vim.api.nvim_win_get_height(winid)
        local winrow = mouse.winrow

        if winrow <= 1 or (mouse.winid ~= winid and mouse.winid ~= 0) then
          if winrow <= 1 then
            vim.cmd("normal! gk")
          else
            vim.cmd("normal! gj")
          end
        elseif winrow >= win_height then
          vim.cmd("normal! gj")
        else
          stop_drag_scroll()
        end
      end))
    end

    vim.keymap.set({ "n", "v", "x", "s" }, "<LeftDrag>", function()
      start_drag_scroll()
      return "<LeftDrag>"
    end, { expr = true, silent = true, desc = "Auto-scroll on mouse drag" })

    vim.keymap.set({ "n", "v", "x", "s" }, "<LeftRelease>", function()
      stop_drag_scroll()
      return "<LeftRelease>"
    end, { expr = true, silent = true, desc = "Stop auto-scroll on release" })

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
      highlight TabLineSel guifg=#ffffff gui=bold ctermfg=white cterm=bold
      map! <S-Insert> <C-R>+
      map !aa :tabnew $NEOVIDE_MOUNT_POINT<cr>
      map !hh :silent! tabnew +Man! ${kekma.home}<cr>
      map !nn :silent! tabnew +Man! ${kekma.nix}<cr>
      set number
      set nofoldenable
      set foldlevel=99
      set noshowmode
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

    -- Define a custom, beautiful tabline
    _G.MyTabLine = function()
      local s = ""
      for i = 1, vim.fn.tabpagenr("$") do
        if i == vim.fn.tabpagenr() then
          s = s .. "%#TabLineSel#"
        else
          s = s .. "%#TabLine#"
        end

        s = s .. "%" .. i .. "T"

        local buflist = vim.fn.tabpagebuflist(i)
        local winnr = vim.fn.tabpagewinnr(i)
        local bufnr = buflist and buflist[winnr]
        local bufname = bufnr and vim.api.nvim_buf_get_name(bufnr) or ""

        local tabname = ""
        if bufnr and vim.bo[bufnr].buftype == "terminal" then
          local term_title = vim.b[bufnr].term_title
          if term_title and term_title ~= "" then
            local cmd = term_title:match("([^/]+)$") or term_title
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
            tabname = vim.fn.fnamemodify(bufname, ":h:t")
          else
            tabname = filename
          end
        end

        s = s .. " " .. i .. ": " .. tabname .. " "
      end

      s = s .. "%#TabLineFill#%T"
      return s
    end

    -- === HORIZONTAL TRACKPAD SCROLLING IN TERMINALS ===
    vim.keymap.set('t', '<ScrollWheelLeft>', '<Left>', { silent = true, desc = "Scroll left in terminal" })
    vim.keymap.set('t', '<ScrollWheelRight>', '<Right>', { silent = true, desc = "Scroll right in terminal" })

    vim.o.tabline = "%!v:lua.MyTabLine()"

    vim.api.nvim_create_user_command('Hh', open_nos_terminal, {
      desc = 'Open `nos` in a smart terminal',
    })

    vim.keymap.set('n', '!nos', ':Hh<CR>', { desc = 'Open nos terminal', noremap = true, silent = true })

    vim.api.nvim_create_autocmd("BufLeave", {
      pattern = "term://*",
      callback = function()
        vim.b.last_mode = vim.fn.mode()
      end,
    })

    -- === SILENT MANUAL SAVING ===
    local silent_commands = {
      wq = "silent wq",
      x = "silent x",
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
          vim.o.laststatus = 0
          vim.o.cmdheight = 0

          if vim.b.last_mode == nil or vim.b.last_mode == "t" then
            vim.cmd("startinsert")
          end
        else
          vim.o.laststatus = 2
          vim.o.cmdheight = 1
        end
      end,
    })

    vim.opt.guicursor:append("t:ver25")

    -- Global Tab-Switching Wrapper
    _G.InstantTabSwitch = function(cmd)
      local old_scroll = vim.g.neovide_scroll_animation_length or 0.3
      local old_cursor = vim.g.neovide_cursor_animation_length or 0.13
      local old_pos = vim.g.neovide_position_animation_length or 0.15
      
      vim.g.neovide_scroll_animation_length = 0
      vim.g.neovide_cursor_animation_length = 0
      vim.g.neovide_position_animation_length = 0
      
      vim.cmd(cmd)
      
      vim.schedule(function()
        vim.g.neovide_scroll_animation_length = old_scroll
        vim.g.neovide_cursor_animation_length = old_cursor
        vim.g.neovide_position_animation_length = old_pos
      end)
    end

    for _, mode in ipairs({ "n", "i", "t", "v", "x", "s" }) do
      local prefix = (mode:match("[vxs]") and "<Esc>" or "")
      vim.keymap.set(mode, "<C-S-Right>", prefix .. "<Cmd>lua InstantTabSwitch('tabnext')<CR>", { desc = "Next Tab", silent = true })
      vim.keymap.set(mode, "<C-S-Left>", prefix .. "<Cmd>lua InstantTabSwitch('tabprevious')<CR>", { desc = "Previous Tab", silent = true })
      vim.keymap.set(mode, "<C-S-w>", prefix .. "<Cmd>lua InstantTabSwitch('tabclose')<CR>", { desc = "Close Tab", silent = true })
      vim.keymap.set(mode, "<C-S-t>", prefix .. "<Cmd>tabnew +term<CR>", { desc = "New Terminal Tab", silent = true })
    end

    -- Define a hidden cursor style (100% transparent)
    vim.api.nvim_set_hl(0, "HiddenCursor", { blend = 100, nocombine = true })

    local function set_hidden_cursor(hide)
      local current = vim.o.guicursor
      local cleaned = current:gsub(",?n%-v:HiddenCursor", "")
      if hide then
        vim.o.guicursor = cleaned .. ",n-v:HiddenCursor"
      else
        vim.o.guicursor = cleaned
      end
    end

    -- Hide cursor during Normal (nt) / Visual (v/V) scrolling in terminals, restore in Insert (t)
    vim.api.nvim_create_autocmd("ModeChanged", {
      pattern = "*",
      callback = function()
        if vim.bo.buftype == "terminal" then
          local mode = vim.api.nvim_get_mode().mode
          if mode == "nt" or mode == "v" or mode == "V" then
            set_hidden_cursor(true)
          else
            set_hidden_cursor(false)
          end
        end
      end,
    })

    vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
      pattern = "term://*",
      callback = function()
        set_hidden_cursor(false)
      end
    })

    -- Helper to feed raw unmapped scroll wheel key events to C engine
    local function feed_raw_scroll(key)
      local termcode = vim.api.nvim_replace_termcodes(key, true, false, true)
      vim.api.nvim_feedkeys(termcode, "n", false)
    end

    -- === SYNCHRONOUS TERMINAL SCROLLING & BOUNDARY PROTECTION ===
    -- 1) Normal/Visual mode: Hard stop at bottom line and instantly switch to insert mode via native "i"
    vim.keymap.set({ "n", "x" }, "<ScrollWheelDown>", function()
      if vim.bo.buftype == "terminal" then
        if vim.b.terminal_altscreen then
          feed_raw_scroll("<ScrollWheelDown>")
          return ""
        end
        if vim.fn.line("w$") >= vim.fn.line("$") then
          -- Return native "i" command to enter Insert mode without triggering Ex command line bar in cmdheight=0
          return "i"
        else
          feed_raw_scroll("<ScrollWheelDown>")
          return ""
        end
      end
      return "<ScrollWheelDown>"
    end, { expr = true, silent = true, desc = "Hard stop scroll down at terminal bottom" })

    vim.api.nvim_create_autocmd({ "TermRequest", "TermResponse" }, {
      pattern = "*",
      callback = function()
        vim.cmd("redrawtabline")
      end,
    })

    vim.api.nvim_create_autocmd("TermOpen", {
      pattern = "term://*",
      callback = function(args)
        local bufnr = args.buf

        vim.cmd("startinsert")

        -- 2) Terminal-Insert mode scroll handlers
        -- Scroll down at prompt: pass through to C in altscreen; swallow at bottom prompt to prevent exiting insert mode
        vim.keymap.set("t", "<ScrollWheelDown>", function()
          if vim.b[bufnr].terminal_altscreen then
            feed_raw_scroll("<ScrollWheelDown>")
            return ""
          end
          if vim.fn.line("w$") >= vim.fn.line("$") then
            return ""
          end
          feed_raw_scroll("<ScrollWheelDown>")
          return ""
        end, { buffer = bufnr, expr = true, silent = true })

        -- Scroll up at prompt: pass through to C in altscreen; exit to Normal mode and scroll up if at prompt
        vim.keymap.set("t", "<ScrollWheelUp>", function()
          if vim.b[bufnr].terminal_altscreen then
            feed_raw_scroll("<ScrollWheelUp>")
            return ""
          end
          vim.cmd("stopinsert")
          feed_raw_scroll("<ScrollWheelUp>")
          return ""
        end, { buffer = bufnr, expr = true, silent = true })

        local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-=~!@#$%^&*()_+[]{}|;:',./<>?"
        local cyrillic = "абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"

        local char_list = vim.fn.split(chars .. cyrillic, [[\zs]])
        
        local function exit_visual_and_type(char)
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
          vim.schedule(function()
            vim.cmd("startinsert")
            vim.schedule(function()
              vim.api.nvim_feedkeys(char, "m", true)
            end)
          end)
        end

        for _, mode in ipairs({ "n", "v" }) do
          local prefix = (mode == "v" and "<Esc>i" or "i")
          for _, char in ipairs(char_list) do
            vim.keymap.set(mode, char, prefix .. char, { buffer = bufnr, nowait = true, silent = true })
          end
          vim.keymap.set(mode, "<Space>", prefix .. " ", { buffer = bufnr, nowait = true, silent = true })
          vim.keymap.set(mode, "<CR>", prefix .. "<CR>", { buffer = bufnr, nowait = true, silent = true })
          vim.keymap.set(mode, "<BS>", prefix .. "<BS>", { buffer = bufnr, nowait = true, silent = true })
          vim.keymap.set(mode, "<Up>", prefix .. "<Up>", { buffer = bufnr, nowait = true, silent = true })
          vim.keymap.set(mode, "<Down>", prefix .. "<Down>", { buffer = bufnr, nowait = true, silent = true })
          vim.keymap.set(mode, "<Left>", prefix .. "<Left>", { buffer = bufnr, nowait = true, silent = true })
          vim.keymap.set(mode, "<Right>", prefix .. "<Right>", { buffer = bufnr, nowait = true, silent = true })

          vim.keymap.set(mode, "<ScrollWheelLeft>", prefix .. "<Left>", { buffer = bufnr, nowait = true, silent = true })
          vim.keymap.set(mode, "<ScrollWheelRight>", prefix .. "<Right>", { buffer = bufnr, nowait = true, silent = true })
        end

        local ctrl_keys = { "a", "b", "c", "d", "e", "f", "g", "h", "k", "l", "p", "r", "u", "z" }
        for _, key in ipairs(ctrl_keys) do
          local keycode = "<C-" .. key .. ">"
          vim.keymap.set("n", keycode, "i" .. keycode, { buffer = bufnr, nowait = true, silent = true })
          vim.keymap.set("v", keycode, function()
            exit_visual_and_type(vim.api.nvim_replace_termcodes(keycode, true, false, true))
          end, { buffer = bufnr, nowait = true, silent = true })
        end

        vim.keymap.set("t", "<ScrollWheelLeft>", "<Left>", { buffer = bufnr, silent = true })
        vim.keymap.set("t", "<ScrollWheelRight>", "<Right>", { buffer = bufnr, silent = true })

        vim.keymap.set("t", "<C-S-v>", function()
          vim.api.nvim_paste(vim.fn.getreg("+"), true, -1)
        end, { buffer = bufnr, silent = true })

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

        local mouse_events = { 
          "<C-LeftMouse>", "<C-S-LeftMouse>", 
          "<C-LeftDrag>", "<C-S-LeftDrag>", 
          "<C-LeftRelease>", "<C-S-LeftRelease>" 
        }
        local standard_events = { 
          "<LeftMouse>", "<LeftMouse>", 
          "<LeftDrag>", "<LeftDrag>", 
          "<LeftRelease>", "<LeftRelease>" 
        }
        for i, event in ipairs(mouse_events) do
          vim.keymap.set({ "n", "v", "t" }, event, standard_events[i], { buffer = bufnr, silent = true })
        end
      end,
    })

    vim.keymap.set({"n", "x"}, "<C-S-c>", "\"+y", { desc = "Copy system clipboard" })
    vim.keymap.set({"n", "x"}, "<C-S-v>", "\"+p", { desc = "Paste system clipboard" })

    vim.keymap.set("s", "<C-S-c>", "<C-g>\"+y", { silent = true, desc = "Copy selection in Select mode" })
    vim.keymap.set("s", "<C-S-v>", "<C-g>\"+p", { silent = true, desc = "Paste/Replace in Select mode" })

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

    -- === TERMINAL AUTOMATIC SCROLLBACK PRUNING ===
    vim.api.nvim_create_autocmd({ "TextChangedT", "TextChanged" }, {
      pattern = "term://*",
      callback = function(args)
        local bufnr = args.buf
        if not vim.api.nvim_buf_is_valid(bufnr) then return end

        local line_count = vim.api.nvim_buf_line_count(bufnr)
        if line_count > 3000 then
          local win_id = vim.fn.bufwinid(bufnr)
          if win_id == -1 then return end
          
          local win_info = vim.fn.getwininfo(win_id)[1]
          local topline = win_info and win_info.topline
          local win_height = vim.fn.winheight(win_id)
          local max_topline = line_count - win_height + 1
          
          if topline and topline < max_topline - 5 then
            return
          end

          vim.opt_local.scrollback = 1000
          
          vim.defer_fn(function()
            if vim.api.nvim_buf_is_valid(bufnr) then
              vim.opt_local.scrollback = 100000
            end
          end, 50)
        end
      end,
    })

    -- === ASYNC AUTO-FORMAT ON AUTO-SAVE ===
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
      cmd = { "${pkgs.rust-analyzer}/bin/rust-analyzer" },
      root_dir = function(bufnr_or_fname, cb)
        local fname = type(bufnr_or_fname) == "number" and vim.api.nvim_buf_get_name(bufnr_or_fname) or bufnr_or_fname
        if not fname or fname == "" then
          if cb then cb(nil) end
          return nil
        end

        local cargo_root = vim.fs.root(fname, { 'Cargo.toml', 'rust-project.json' })
        if cargo_root then
          if cb then cb(cargo_root) end
          return cargo_root
        end

        -- Standalone file fallback: generate an ephemeral rust-project.json with source.include_dirs
        local hash = vim.fn.sha256(fname):sub(1, 8)
        local standalone_dir = "/tmp/ra_standalone_" .. hash
        vim.fn.mkdir(standalone_dir, "p")
        
        local project_json = standalone_dir .. "/rust-project.json"
        local f = io.open(project_json, "w")
        if f then
          local content = vim.json.encode({
            sysroot = "${rust-toolchain}",
            sysroot_src = "${pkgs.rustPlatform.rustLibSrc}",
            crates = {
              {
                root_module = fname,
                edition = "2021",
                deps = {},
                cfg = { "unix", "debug_assertions" },
                is_workspace_member = true,
                source = {
                  include_dirs = { standalone_dir },
                  exclude_dirs = {}
                }
              }
            }
          })
          f:write(content)
          f:close()
        end

        if cb then cb(standalone_dir) end
        return standalone_dir
      end,
      settings = {
        ["rust-analyzer"] = {
          check = {
            command = "clippy",
            extraArgs = { "--", "-W", "clippy::all", "-W", "clippy::pedantic" }
          },
          files = {
            watcher = "client",
          },
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
    home.packages = [
      nvr-remote-editor
      neovide-term
    ];
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
