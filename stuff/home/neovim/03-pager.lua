-- === MODE-SAFE RPC HELPER FUNCTIONS ===
local setup_pager_scroll
_G.OpenNewTab = function(dir)
	vim.cmd("tabnew")
	if dir and dir ~= "" then
		pcall(vim.cmd, "lcd " .. vim.fn.fnameescape(dir))
	end
end

_G.OpenManPath = function(path_or_arg)
	pcall(vim.cmd, "runtime ftplugin/man.vim")
	if path_or_arg and path_or_arg ~= "" and vim.fn.filereadable(path_or_arg) == 1 then
		vim.cmd("tabnew " .. vim.fn.fnameescape(path_or_arg))
		local buf = vim.api.nvim_get_current_buf()
		local win = vim.api.nvim_get_current_win()
		vim.bo[buf].bufhidden = "wipe"
		vim.b[buf].is_pager = true
		vim.wo[win].wrap = true
		vim.keymap.set("n", "q", "<Cmd>tabclose<CR>", { buffer = buf, silent = true, nowait = true })
		vim.keymap.set("n", "Q", "<Cmd>tabclose<CR>", { buffer = buf, silent = true, nowait = true })
		vim.keymap.set("n", "<Esc>", "<Cmd>tabclose<CR>", { buffer = buf, silent = true, nowait = true })
		vim.cmd("silent! Man!")
		setup_pager_scroll(buf, win)
	else
		vim.cmd("tabnew")
		local buf = vim.api.nvim_get_current_buf()
		local win = vim.api.nvim_get_current_win()
		vim.bo[buf].bufhidden = "wipe"
		vim.b[buf].is_pager = true
		vim.wo[win].wrap = true
		vim.keymap.set("n", "q", "<Cmd>tabclose<CR>", { buffer = buf, silent = true, nowait = true })
		vim.keymap.set("n", "Q", "<Cmd>tabclose<CR>", { buffer = buf, silent = true, nowait = true })
		vim.keymap.set("n", "<Esc>", "<Cmd>tabclose<CR>", { buffer = buf, silent = true, nowait = true })
		if path_or_arg and path_or_arg ~= "" then
			vim.cmd("silent! Man " .. vim.fn.fnameescape(path_or_arg))
		else
			vim.cmd("silent! Man")
		end
		setup_pager_scroll(buf, win)
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

-- === OVERTAKE TERMINAL TAB WHEN NVIM IS INVOKED FROM WITHIN IT ===
_G.OvertakeTerminal = function(term_buf, files_json, fifo_path)
	term_buf = tonumber(term_buf)
	local win = vim.fn.bufwinid(term_buf)
	if win == -1 then
		for _, w in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_buf(w) == term_buf then
				win = w
				break
			end
		end
	end
	if win == -1 or not vim.api.nvim_win_is_valid(win) then
		win = vim.api.nvim_get_current_win()
	end

	local target_tab = vim.api.nvim_win_get_tabpage(win)
	if target_tab ~= vim.api.nvim_get_current_tabpage() then
		vim.api.nvim_set_current_tabpage(target_tab)
	end
	vim.api.nvim_set_current_win(win)

	local ok, files = pcall(vim.json.decode, files_json)
	local target_buf
	if ok and files and #files > 0 then
		vim.cmd("edit " .. vim.fn.fnameescape(files[1]))
		target_buf = vim.api.nvim_get_current_buf()
		for i = 2, #files do
			vim.cmd("badd " .. vim.fn.fnameescape(files[i]))
		end
	else
		vim.cmd("enew")
		target_buf = vim.api.nvim_get_current_buf()
	end

	local restored = false
	local function signal_fifo()
		if fifo_path and fifo_path ~= "" then
			local uv = vim.uv or vim.loop
			local flags = uv.constants.O_WRONLY
			if uv.constants.O_NONBLOCK then
				flags = bit.bor(flags, uv.constants.O_NONBLOCK)
			end
			local fd = uv.fs_open(fifo_path, flags, 438)
			if fd then
				uv.fs_write(fd, "done\n", -1, function()
					uv.fs_close(fd)
				end)
			end
		end
	end

	local function restore_terminal()
		if restored then
			return
		end
		restored = true

		if vim.api.nvim_buf_is_valid(term_buf) then
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_set_buf(win, term_buf)
			else
				-- Window/tab was closed (:q! or :wq on modified) —
				-- show terminal in current window
				vim.api.nvim_set_current_buf(term_buf)
			end
			vim.cmd("startinsert")
		end

		vim.schedule(signal_fifo)
	end

	-- QuitPre: before :q/:q!/:wq/:x closes the window, open a split
	-- with the terminal buffer so the tab survives the window close.
	-- The user sees exactly what they type (:q, :q!, :wq, :x).
	vim.api.nvim_create_autocmd("QuitPre", {
		buffer = target_buf,
		nested = true,
		callback = function()
			if restored then
				return
			end
			if not vim.api.nvim_buf_is_valid(term_buf) then
				return
			end

			local file_win = vim.api.nvim_get_current_win()

			-- Create a minimal split with the terminal to keep the tab alive
			vim.cmd("1split")
			local term_win = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_buf(term_win, term_buf)
			vim.api.nvim_set_current_win(file_win)

			vim.schedule(function()
				restored = true
				if vim.api.nvim_win_is_valid(term_win) then
					vim.api.nvim_set_current_win(term_win)
					pcall(vim.cmd, "only")
					vim.cmd("startinsert")
				end
				signal_fifo()
			end)
		end,
	})

	vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
		buffer = target_buf,
		once = true,
		callback = function()
			restore_terminal()
		end,
	})
end

-- === CLAMPED PAGER SCROLLING HELPER (HARD STOP AT LAST LINE + GPU ANIMATION) ===
setup_pager_scroll = function(buf, win)
	local function scroll_down(amount)
		if not (vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(win)) then
			return
		end
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
		if not (vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(win)) then
			return
		end
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
				pcall(
					vim.api.nvim_win_set_cursor,
					win,
					{ math.min(vim.api.nvim_buf_line_count(buf), new_top + win_h - 1), 0 }
				)
			end
		else
			pcall(vim.api.nvim_win_set_cursor, win, { 1, 0 })
		end
	end

	-- Bind Mouse Wheel
	vim.keymap.set("n", "<ScrollWheelDown>", function()
		scroll_down(_G.OPTS.scroll.step)
	end, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "<ScrollWheelUp>", function()
		scroll_up(_G.OPTS.scroll.step)
	end, { buffer = buf, silent = true, nowait = true })

	-- Bind Page Keys & Ctrl-F / Ctrl-B / Ctrl-D / Ctrl-U
	vim.keymap.set("n", "<PageDown>", function()
		scroll_down(math.max(1, vim.api.nvim_win_get_height(win) - 2))
	end, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "<PageUp>", function()
		scroll_up(math.max(1, vim.api.nvim_win_get_height(win) - 2))
	end, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "<C-f>", function()
		scroll_down(math.max(1, vim.api.nvim_win_get_height(win) - 2))
	end, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "<C-b>", function()
		scroll_up(math.max(1, vim.api.nvim_win_get_height(win) - 2))
	end, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "<C-d>", function()
		scroll_down(math.floor(vim.api.nvim_win_get_height(win) / 2))
	end, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "<C-u>", function()
		scroll_up(math.floor(vim.api.nvim_win_get_height(win) / 2))
	end, { buffer = buf, silent = true, nowait = true })

	-- Bind j / k / Down / Up
	vim.keymap.set("n", "j", function()
		scroll_down(1)
	end, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "<Down>", function()
		scroll_down(1)
	end, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "k", function()
		scroll_up(1)
	end, { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "<Up>", function()
		scroll_up(1)
	end, { buffer = buf, silent = true, nowait = true })
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

	vim.keymap.set("n", "q", "<Cmd>tabclose<CR>", { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "Q", "<Cmd>tabclose<CR>", { buffer = buf, silent = true, nowait = true })
	vim.keymap.set("n", "<Esc>", "<Cmd>tabclose<CR>", { buffer = buf, silent = true, nowait = true })

	setup_pager_scroll(buf, win)

	local function reset_view()
		if not (vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(win)) then
			return
		end
		pcall(vim.cmd, "stopinsert")

		local line_count = vim.api.nvim_buf_line_count(buf)
		local win_h = vim.api.nvim_win_get_height(win)

		if jump_bottom then
			local max_top = math.max(1, line_count - win_h + 1)
			pcall(vim.api.nvim_win_set_cursor, win, { line_count, 0 })
			pcall(vim.fn.winrestview, { topline = max_top, lnum = line_count, col = 0 })
		else
			pcall(vim.api.nvim_win_set_cursor, win, { 1, 0 })
			pcall(vim.fn.winrestview, { topline = 1, lnum = 1, col = 0 })
		end
	end

	local detached = false
	local detach_autocmd = vim.api.nvim_create_autocmd({ "CursorMoved", "WinScrolled" }, {
		buffer = buf,
		once = true,
		callback = function()
			detached = true
		end,
	})

	vim.api.nvim_buf_attach(buf, false, {
		on_lines = function()
			if detached then
				pcall(vim.api.nvim_del_autocmd, detach_autocmd)
				return true
			end
			vim.schedule(reset_view)
		end,
	})

	local chan = vim.api.nvim_open_term(buf, {})
	vim.api.nvim_chan_send(chan, raw)
	vim.cmd("redraw")
	vim.cmd("stopinsert")
	reset_view()
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
