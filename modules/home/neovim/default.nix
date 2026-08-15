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
  neovide-term = pkgs.writeShellScriptBin "neovide-term" ''
    TITLE=""
    APP_ID=""
    WORKDIR=""
    HOLD=""

    while [ $# -gt 0 ]; do
      case "$1" in
        -T|--title)
          TITLE="$2"
          shift 2
          ;;
        --class|--app-id)
          APP_ID="$2"
          shift 2
          ;;
        --working-directory)
          WORKDIR="$2"
          shift 2
          ;;
        --hold)
          HOLD="1"
          shift
          ;;
        -e|--)
          shift
          break
          ;;
        *)
          break
          ;;
      esac
    done

    CMD=""
    for arg in "$@"; do
      escaped="''${arg//\'/\'\\\'\'}"
      if [ -z "$CMD" ]; then
        CMD="'$escaped'"
      else
        CMD="$CMD '$escaped'"
      fi
    done

    # Construct Neovide CLI arguments array safely
    set -- --frame none --mouse-cursor-icon i-beam

    if [ -n "$APP_ID" ]; then
      set -- "$@" --app-id "$APP_ID"
    fi

    if [ -n "$TITLE" ]; then
      set -- "$@" --title "$TITLE"
    fi

    if [ -n "$WORKDIR" ]; then
      set -- "$@" "+cd $WORKDIR"
    fi

    if [ -n "$CMD" ]; then
      if [ -n "$HOLD" ]; then
        set -- "$@" "+term $CMD; \$SHELL"
      else
        set -- "$@" "+term $CMD"
      fi
    else
      set -- "$@" "+term"
    fi

    set -- "$@" +startinsert \
      '+set laststatus=0' \
      '+set cmdheight=0' \
      '+nnoremap <C-S-t> :tabnew +term<CR>' \
      '+inoremap <C-S-t> <C-o>:tabnew +term<CR>' \
      '+tnoremap <C-S-t> <C-\><C-n>:tabnew +term<CR>' \
      '+xnoremap <C-S-t> <Esc>:tabnew +term<CR>' \
      '+snoremap <C-S-t> <Esc>:tabnew +term<CR>'

    exec neovide "$@"
  '';
  nvr-remote-editor = pkgs.writeShellScriptBin "nvr-remote-editor" ''
    exec ${pkgs.neovim-remote}/bin/nvr --servername "$NVIM" --remote-tab-wait +"setlocal bufhidden=wipe" "$@"
  '';

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

    -- Auto-create missing parent directories on save (:w)
    vim.api.nvim_create_autocmd("BufWritePre", {
      group = vim.api.nvim_create_augroup("AutoCreateParentDirs", { clear = true }),
      callback = function(event)
        if event.match:match("^%w%w+:[\\/][\\/]") then return end
        local dir = vim.fn.fnamemodify(event.match, ":p:h")
        if vim.fn.isdirectory(dir) == 0 then
          vim.fn.mkdir(dir, "p")
        end
      end,
    })

    -- === DISABLE FOLDING GLOBALLY ===
    vim.opt.foldenable = false
    vim.opt.foldlevel = 99

    -- Enable line wrapping globally & disable horizontal mouse scroll wheel
    vim.opt.wrap = true
    vim.keymap.set({ "n", "v", "i", "t" }, "<ScrollWheelLeft>", "<Nop>", { silent = true })
    vim.keymap.set({ "n", "v", "i", "t" }, "<ScrollWheelRight>", "<Nop>", { silent = true })

    -- Disable mode display to prevent command line popups in cmdheight=0
    vim.opt.showmode = false

    -- === AUTO-CLOSE TERMINALS ON SUCCESSFUL EXIT (Removes [Process exited 0] tabs) ===
    vim.api.nvim_create_autocmd("TermClose", {
      group = vim.api.nvim_create_augroup("AutoCloseTermOnSuccess", { clear = true }),
      callback = function(ev)
        local status = vim.v.event.status
        if status == 0 then
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(ev.buf) then
              pcall(vim.api.nvim_buf_delete, ev.buf, { force = true })
            end
          end)
        end
      end,
    })

    -- === MODE-SAFE RPC HELPER FUNCTIONS ===
    _G.OpenNewTab = function(dir)
      vim.cmd("tabnew")
      if dir and dir ~= "" then
        pcall(vim.cmd, "lcd " .. vim.fn.fnameescape(dir))
      end
    end

    _G.OpenManPath = function(path_or_arg)
      pcall(vim.cmd, "runtime ftplugin/man.vim")
      vim.cmd("tabnew")
      if path_or_arg and path_or_arg ~= "" then
        vim.cmd("silent! Man " .. vim.fn.fnameescape(path_or_arg))
      else
        vim.cmd("silent! Man")
      end
    end

    _G.OpenFiles = function(files_json)
      local ok, files = pcall(vim.json.decode, files_json)
      if ok and files and #files > 0 then
        vim.cmd("tabnew " .. vim.fn.fnameescape(files[1]))
        for i = 2, #files do
          vim.cmd("tabedit " .. vim.fn.fnameescape(files[i]))
        end
      else
        vim.cmd("tabnew")
      end
    end

    -- === CLAMPED PAGER SCROLLING HELPER (HARD STOP AT LAST LINE + GPU ANIMATION) ===
    local function setup_pager_scroll(buf, win)
      local function scroll_down(amount)
        if not (vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(win)) then return end
        local line_c = vim.api.nvim_buf_line_count(buf)
        local win_h = vim.api.nvim_win_get_height(win)
        local max_top = math.max(1, line_c - win_h + 1)
        local win_info = vim.fn.getwininfo(win)[1]
        local cur_top = win_info and win_info.topline or 1
        local can_scroll = max_top - cur_top
        if can_scroll > 0 then
          local to_scroll = math.min(amount, can_scroll)
          vim.cmd("normal! " .. to_scroll .. "\x05") -- Ctrl-E (Smooth GPU scroll down)
          local cur_cursor = vim.api.nvim_win_get_cursor(win)[1]
          local new_top = cur_top + to_scroll
          if cur_cursor < new_top then
            pcall(vim.api.nvim_win_set_cursor, win, { new_top, 0 })
          elseif cur_cursor > new_top + win_h - 1 then
            pcall(vim.api.nvim_win_set_cursor, win, { math.min(line_c, new_top + win_h - 1), 0 })
          end
        else
          pcall(vim.api.nvim_win_set_cursor, win, { line_c, 0 })
        end
      end

      local function scroll_up(amount)
        if not (vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(win)) then return end
        local win_h = vim.api.nvim_win_get_height(win)
        local win_info = vim.fn.getwininfo(win)[1]
        local cur_top = win_info and win_info.topline or 1
        local can_scroll = cur_top - 1
        if can_scroll > 0 then
          local to_scroll = math.min(amount, can_scroll)
          vim.cmd("normal! " .. to_scroll .. "\x19") -- Ctrl-Y (Smooth GPU scroll up)
          local cur_cursor = vim.api.nvim_win_get_cursor(win)[1]
          local new_top = cur_top - to_scroll
          if cur_cursor < new_top then
            pcall(vim.api.nvim_win_set_cursor, win, { new_top, 0 })
          elseif cur_cursor > new_top + win_h - 1 then
            pcall(vim.api.nvim_win_set_cursor, win, { math.min(vim.api.nvim_buf_line_count(buf), new_top + win_h - 1), 0 })
          end
        else
          pcall(vim.api.nvim_win_set_cursor, win, { 1, 0 })
        end
      end

      -- Bind Mouse Wheel
      vim.keymap.set("n", "<ScrollWheelDown>", function() scroll_down(3) end, { buffer = buf, silent = true, nowait = true })
      vim.keymap.set("n", "<ScrollWheelUp>", function() scroll_up(3) end, { buffer = buf, silent = true, nowait = true })

      -- Bind Page Keys & Ctrl-F / Ctrl-B / Ctrl-D / Ctrl-U
      vim.keymap.set("n", "<PageDown>", function() scroll_down(math.max(1, vim.api.nvim_win_get_height(win) - 2)) end, { buffer = buf, silent = true, nowait = true })
      vim.keymap.set("n", "<PageUp>", function() scroll_up(math.max(1, vim.api.nvim_win_get_height(win) - 2)) end, { buffer = buf, silent = true, nowait = true })
      vim.keymap.set("n", "<C-f>", function() scroll_down(math.max(1, vim.api.nvim_win_get_height(win) - 2)) end, { buffer = buf, silent = true, nowait = true })
      vim.keymap.set("n", "<C-b>", function() scroll_up(math.max(1, vim.api.nvim_win_get_height(win) - 2)) end, { buffer = buf, silent = true, nowait = true })
      vim.keymap.set("n", "<C-d>", function() scroll_down(math.floor(vim.api.nvim_win_get_height(win) / 2)) end, { buffer = buf, silent = true, nowait = true })
      vim.keymap.set("n", "<C-u>", function() scroll_up(math.floor(vim.api.nvim_win_get_height(win) / 2)) end, { buffer = buf, silent = true, nowait = true })

      -- Bind j / k / Down / Up
      vim.keymap.set("n", "j", function() scroll_down(1) end, { buffer = buf, silent = true, nowait = true })
      vim.keymap.set("n", "<Down>", function() scroll_down(1) end, { buffer = buf, silent = true, nowait = true })
      vim.keymap.set("n", "k", function() scroll_up(1) end, { buffer = buf, silent = true, nowait = true })
      vim.keymap.set("n", "<Up>", function() scroll_up(1) end, { buffer = buf, silent = true, nowait = true })
    end

    -- === USER-ISOLATED TMPFS ANSI PAGER & MAN PAGER ===
    _G.OpenAnsiPagerFile = function(filepath, jump_bottom)
      local f = io.open(filepath, "rb")
      local raw = ""
      if f then
        raw = f:read("*a") or ""
        f:close()
      end
      pcall(os.remove, filepath)

      raw = raw:gsub("\r?\n", "\r\n")

      vim.cmd("tabnew")
      local buf = vim.api.nvim_get_current_buf()
      local win = vim.api.nvim_get_current_win()

      pcall(vim.api.nvim_buf_set_name, buf, "[Pager " .. buf .. "]")
      vim.bo[buf].bufhidden = "wipe"
      vim.b[buf].is_pager = true
      vim.wo[win].wrap = true

      -- Map 'q', 'Q' and '<Esc>' FIRST so they are 100% guaranteed to exist
      vim.keymap.set("n", "q", "<Cmd>tabclose<CR>", { buffer = buf, silent = true, nowait = true })
      vim.keymap.set("n", "Q", "<Cmd>tabclose<CR>", { buffer = buf, silent = true, nowait = true })
      vim.keymap.set("n", "<Esc>", "<Cmd>tabclose<CR>", { buffer = buf, silent = true, nowait = true })

      -- Open C libvterm terminal channel (100% robust VT100 / ANSI rendering)
      local chan = vim.api.nvim_open_term(buf, {})
      vim.api.nvim_chan_send(chan, raw)

      -- Flush libvterm lines synchronously
      vim.cmd("redraw")

      -- Attach clamped scrolling helper (hard stop at bottom line)
      setup_pager_scroll(buf, win)

      vim.cmd("stopinsert")
      local line_count = vim.api.nvim_buf_line_count(buf)
      local win_h = vim.api.nvim_win_get_height(win)
      if jump_bottom then
        local max_top = math.max(1, line_count - win_h + 1)
        vim.cmd("normal! " .. max_top .. "zt")
        pcall(vim.api.nvim_win_set_cursor, win, { line_count, 0 })
      else
        pcall(vim.api.nvim_win_set_cursor, win, { 1, 0 })
        vim.cmd("normal! zt")
      end
    end

    _G.OpenManPageFile = function(filepath, jump_bottom)
      pcall(vim.cmd, "runtime ftplugin/man.vim")

      local f = io.open(filepath, "rb")
      local content = ""
      if f then
        content = f:read("*a") or ""
        f:close()
      end
      pcall(os.remove, filepath)

      local lines = vim.split(content, "\n", { plain = true })

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      vim.cmd("tabnew | buffer " .. buf)
      vim.cmd("silent! Man!")

      local cur_buf = vim.api.nvim_get_current_buf()
      local win = vim.api.nvim_get_current_win()
      vim.bo[cur_buf].bufhidden = "wipe"
      vim.b[cur_buf].is_pager = true
      vim.wo[win].wrap = true

      -- Map q, Q and Esc on the man buffer
      vim.keymap.set("n", "q", "<Cmd>tabclose<CR>", { buffer = cur_buf, silent = true, nowait = true })
      vim.keymap.set("n", "Q", "<Cmd>tabclose<CR>", { buffer = cur_buf, silent = true, nowait = true })
      vim.keymap.set("n", "<Esc>", "<Cmd>tabclose<CR>", { buffer = cur_buf, silent = true, nowait = true })

      setup_pager_scroll(cur_buf, win)

      vim.cmd("stopinsert")
      local line_count = vim.api.nvim_buf_line_count(cur_buf)
      local win_h = vim.api.nvim_win_get_height(win)
      if jump_bottom then
        local max_top = math.max(1, line_count - win_h + 1)
        vim.cmd("normal! " .. max_top .. "zt")
        pcall(vim.api.nvim_win_set_cursor, win, { line_count, 0 })
      else
        pcall(vim.api.nvim_win_set_cursor, win, { 1, 0 })
        vim.cmd("normal! zt")
      end
    end

    _G.OpenStandalonePager = function()
      local buf = vim.api.nvim_get_current_buf()
      local win = vim.api.nvim_get_current_win()

      vim.bo[buf].bufhidden = "wipe"
      vim.b[buf].is_pager = true
      vim.wo[win].wrap = true

      vim.keymap.set("n", "q", "<Cmd>qa!<CR>", { buffer = buf, silent = true, nowait = true })
      vim.keymap.set("n", "Q", "<Cmd>qa!<CR>", { buffer = buf, silent = true, nowait = true })
      vim.keymap.set("n", "<Esc>", "<Cmd>qa!<CR>", { buffer = buf, silent = true, nowait = true })

      setup_pager_scroll(buf, win)

      local content = io.stdin:read("*a") or ""
      content = content:gsub("\r?\n", "\r\n")

      local chan = vim.api.nvim_open_term(buf, {})
      vim.api.nvim_chan_send(chan, content)

      vim.cmd("redraw")
      pcall(vim.fn.chanclose, chan)
      vim.bo[buf].buftype = "nofile"

      vim.cmd("stopinsert")
      pcall(vim.api.nvim_win_set_cursor, win, { 1, 0 })
      vim.cmd("normal! 1zt")
    end

    -- === SLIDING TABLINE WITH OVERFLOW FOLLOWING ===
    _G.MyTabLine = function()
      local total_tabs = vim.fn.tabpagenr("$")
      local current_tab = vim.fn.tabpagenr()
      local max_width = vim.o.columns

      -- 1. Pre-calculate tab titles and display widths
      local tabs = {}
      for i = 1, total_tabs do
        local buflist = vim.fn.tabpagebuflist(i)
        local winnr = vim.fn.tabpagewinnr(i)
        local bufnr = buflist and buflist[winnr]
        local bufname = bufnr and vim.api.nvim_buf_get_name(bufnr) or ""

        local tabname = ""
        if bufnr and vim.b[bufnr].is_pager then
          tabname = "Pager"
        elseif bufnr and vim.bo[bufnr].buftype == "terminal" then
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

        local label = " " .. i .. ": " .. tabname .. " "
        table.insert(tabs, {
          index = i,
          label = label,
          width = vim.fn.strdisplaywidth(label),
        })
      end

      -- 2. Expand visible window outwards around current_tab
      local start_tab = current_tab
      local end_tab = current_tab
      local used_width = tabs[current_tab].width

      while true do
        local expanded = false
        if start_tab > 1 then
          local left_w = tabs[start_tab - 1].width
          if used_width + left_w + 6 <= max_width then
            start_tab = start_tab - 1
            used_width = used_width + left_w
            expanded = true
          end
        end
        if end_tab < total_tabs then
          local right_w = tabs[end_tab + 1].width
          if used_width + right_w + 6 <= max_width then
            end_tab = end_tab + 1
            used_width = used_width + right_w
            expanded = true
          end
        end
        if not expanded then break end
      end

      -- 3. Construct tabline string
      local s = ""
      if start_tab > 1 then
        s = s .. "%#TabLine# < "
      end

      for i = start_tab, end_tab do
        if i == current_tab then
          s = s .. "%#TabLineSel#"
        else
          s = s .. "%#TabLine#"
        end
        s = s .. "%" .. i .. "T" .. tabs[i].label
      end

      s = s .. "%#TabLineFill#%T"

      if end_tab < total_tabs then
        s = s .. "%#TabLine# > "
      end

      return s
    end

    -- === CLEAN KITTY-STYLE WINDOW TITLE ===
    vim.opt.title = true

    _G.GetWindowTitle = function()
      local bufnr = vim.api.nvim_get_current_buf()
      local bufname = vim.api.nvim_buf_get_name(bufnr)

      if vim.b[bufnr].is_pager then
        return "Pager"
      elseif vim.bo[bufnr].buftype == "terminal" then
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
      set wrap
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
    if vim.g.neovide then
      vim.keymap.set({"n", "x"}, "<C-S-c>", '"+y', {desc = "Copy system clipboard"})
      vim.keymap.set({"n", "x"}, "<C-S-v>", '"+p', {desc = "Paste system clipboard"})
      vim.keymap.set("i", "<C-S-v>", '<C-r><C-o>+', {desc = "Paste system clipboard"})
      vim.g.neovide_no_vsync = true
      vim.g.neovide_idle_timer = 0
      vim.g.neovide_scroll_animation_length = 0.15
      vim.g.neovide_cursor_animation_length = 0.05
      vim.g.neovide_cursor_trail_size = 0.2
      vim.g.neovide_padding_top = 20
      vim.g.neovide_padding_left = 20
      vim.g.neovide_padding_right = 20
      vim.g.neovide_opacity = 0.2
      vim.g.neovide_floating_shadow = false
      vim.g.neovide_floating_blur_amount_x = 8.0
      vim.g.neovide_floating_blur_amount_y = 8.0
    end

    local function open_nos_terminal()
      vim.cmd("tab term tmux new-session -s my-tui 'tmux set-option status off; nos; tmux kill-session -t my-tui'")
      vim.b.auto_terminal_mode = true
      vim.cmd('startinsert')
    end

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

    -- === TERMINAL, MAN PAGE & PAGER VS FILE LAYOUT AUTO-TOGGLE ===
    vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "TermOpen", "FileType" }, {
      pattern = "*",
      callback = function()
        if vim.bo.buftype == "terminal" or vim.bo.filetype == "man" or vim.b.is_pager then
          vim.o.laststatus = 0
          vim.o.cmdheight = 0

          if vim.bo.buftype == "terminal" and not vim.b.is_pager and (vim.b.last_mode == nil or vim.b.last_mode == "t") then
            vim.cmd("startinsert")
          end
        else
          vim.o.laststatus = 2
          vim.o.cmdheight = 1
        end
      end,
    })

    vim.opt.guicursor:append("t:ver25")
    vim.opt.selection = "inclusive"

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

    local function set_terminal_cursor_hidden(hide)
      local current = vim.o.guicursor
      local cleaned = current:gsub(",?n%-v:HiddenCursor", "")
                             :gsub(",?n:HiddenCursor", "")
                             :gsub(",?v:ver25%-HiddenCursor", "")
                             :gsub(",?v:HiddenCursor", "")
      if hide then
        -- n:HiddenCursor hides normal cursor; v:ver25-HiddenCursor hides visual cursor while keeping full highlight on last char
        vim.o.guicursor = cleaned .. ",n:HiddenCursor,v:ver25-HiddenCursor"
      else
        vim.o.guicursor = cleaned
      end
    end

    -- Hide cursor during Normal (nt) AND Visual (v/V) scrolling in terminals, restore in Insert (t)
    vim.api.nvim_create_autocmd("ModeChanged", {
      pattern = "*",
      callback = function()
        if vim.bo.buftype == "terminal" then
          local mode = vim.api.nvim_get_mode().mode
          if mode == "nt" or mode == "v" or mode == "V" or mode == "\22" then
            set_terminal_cursor_hidden(true)
          else
            set_terminal_cursor_hidden(false)
          end
        end
      end,
    })

    vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
      pattern = "term://*",
      callback = function()
        set_terminal_cursor_hidden(false)
      end
    })

    -- === SYNCHRONOUS TERMINAL SCROLLING & BOUNDARY PROTECTION ===
    local function term_scroll_down()
      if vim.fn.line("w$") + 3 >= vim.fn.line("$") then
        return "3\x05i" -- auto-enter insert mode in 1 tick when reaching bottom
      else
        return "3\x05"   -- scroll down 3 lines
      end
    end

    local function term_visual_scroll_down()
      local max_bottom = vim.fn.line("$")
      local current_bottom = vim.fn.line("w$")
      local can_scroll = max_bottom - current_bottom
      if can_scroll > 0 then
        local to_scroll = math.min(3, can_scroll)
        return to_scroll .. "\x05"
      else
        return "" -- hard stop at bottom line, never overscroll
      end
    end

    vim.keymap.set("n", "<ScrollWheelDown>", function()
      if vim.bo.buftype == "terminal" then
        return term_scroll_down()
      end
      return "<ScrollWheelDown>"
    end, { expr = true, silent = true, desc = "Scroll down in terminal, enter insert at bottom" })

    vim.keymap.set("n", "<ScrollWheelUp>", function()
      if vim.bo.buftype == "terminal" then
        return "3\x19" -- 3<C-y>
      end
      return "<ScrollWheelUp>"
    end, { expr = true, silent = true, desc = "Scroll up in terminal" })

    vim.keymap.set("x", "<ScrollWheelDown>", function()
      if vim.bo.buftype == "terminal" then
        return term_visual_scroll_down()
      end
      return "<ScrollWheelDown>"
    end, { expr = true, silent = true })

    vim.keymap.set("x", "<ScrollWheelUp>", function()
      if vim.bo.buftype == "terminal" then
        return "3\x19"
      end
      return "<ScrollWheelUp>"
    end, { expr = true, silent = true })

    vim.api.nvim_create_autocmd("TermOpen", {
      pattern = "term://*",
      callback = function(args)
        local bufnr = args.buf

        if not vim.b[bufnr].is_pager then
          vim.cmd("startinsert")
        end

        -- 1st scroll up: immediately exit to normal mode, hide cursor, and scroll up 3 lines
        vim.keymap.set("t", "<ScrollWheelUp>", function()
          return vim.api.nvim_replace_termcodes("<C-\\><C-n>3<C-y>", true, false, true)
        end, { buffer = bufnr, expr = true, silent = true })

        -- Scroll down at bottom prompt: hard stop (do nothing)
        vim.keymap.set("t", "<ScrollWheelDown>", function()
          return ""
        end, { buffer = bufnr, expr = true, silent = true })

        -- Buffer-local handlers
        vim.keymap.set("n", "<ScrollWheelDown>", function()
          return term_scroll_down()
        end, { buffer = bufnr, expr = true, silent = true })

        vim.keymap.set("n", "<ScrollWheelUp>", function()
          return "3\x19"
        end, { buffer = bufnr, expr = true, silent = true })

        vim.keymap.set("x", "<ScrollWheelDown>", function()
          return term_visual_scroll_down()
        end, { buffer = bufnr, expr = true, silent = true })

        vim.keymap.set("x", "<ScrollWheelUp>", function()
          return "3\x19"
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
        end

        local ctrl_keys = { "a", "b", "c", "d", "e", "f", "g", "h", "k", "l", "p", "r", "u", "z" }
        for _, key in ipairs(ctrl_keys) do
          local keycode = "<C-" .. key .. ">"
          vim.keymap.set("n", keycode, "i" .. keycode, { buffer = bufnr, nowait = true, silent = true })
          vim.keymap.set("v", keycode, function()
            exit_visual_and_type(vim.api.nvim_replace_termcodes(keycode, true, false, true))
          end, { buffer = bufnr, nowait = true, silent = true })
        end

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
      cmd_env = {
        PATH = "${rust-toolchain}/bin:" .. (os.getenv("PATH") or ""),
        RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}",
      },
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
          cargo = {
            sysroot = "${rust-toolchain}",
            sysrootSrc = "${pkgs.rustPlatform.rustLibSrc}",
          },
          check = {
            command = "clippy",
            extraArgs = { "--", "-W", "clippy::all", "-W", "clippy::pedantic" }
          },
          procMacro = {
            enable = true,
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
      initLua = config_lua + lsp_cmp_cfg;
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
