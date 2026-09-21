-- === UNMAP NEOVIM DEFAULT EDITING MAPPINGS IN TERMINALS ===
-- Ensures <C-L>, Y, and & are not intercepted by Neovim and pass to terminal
pcall(vim.keymap.del, "n", "<C-L>")
pcall(vim.keymap.del, "n", "&")
pcall(vim.keymap.del, "n", "Y")

-- === CURSOR VISIBILITY FOR TERMINALS, MANPAGES & PAGERS ===
vim.api.nvim_set_hl(0, "HiddenCursor", { blend = 100, nocombine = true })

local function set_terminal_cursor_hidden(hide)
	pcall(function()
		local current = vim.o.guicursor
		local cleaned = current
			:gsub(",?n%-v:HiddenCursor", "")
			:gsub(",?n:HiddenCursor", "")
			:gsub(",?v:ver25%-HiddenCursor", "")
			:gsub(",?v:HiddenCursor", "")
		cleaned = cleaned:gsub("^,", ""):gsub(",$", ""):gsub(",,", ",")
		if hide then
			vim.o.guicursor = cleaned .. ",n:HiddenCursor,v:ver25-HiddenCursor"
		else
			vim.o.guicursor = cleaned
		end
	end)
end

-- Auto hide cursor on entering manpages, pagers, or normal-mode terminals
vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "FileType" }, {
	group = vim.api.nvim_create_augroup("HideCursorInPagers", { clear = true }),
	pattern = "*",
	callback = function(ev)
		local buf = ev.buf
		if not (buf and vim.api.nvim_buf_is_valid(buf)) then
			return
		end
		if vim.bo[buf].filetype == "man" or vim.b[buf].is_pager then
			set_terminal_cursor_hidden(true)
		elseif vim.bo[buf].buftype == "terminal" then
			local mode = vim.api.nvim_get_mode().mode
			if mode == "t" then
				set_terminal_cursor_hidden(false)
			else
				set_terminal_cursor_hidden(true)
			end
		else
			set_terminal_cursor_hidden(false)
		end
	end,
})

vim.api.nvim_create_autocmd("ModeChanged", {
	pattern = "*",
	callback = function()
		if vim.bo.filetype == "man" or vim.b.is_pager then
			set_terminal_cursor_hidden(true)
		elseif vim.bo.buftype == "terminal" then
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
	pattern = "*",
	callback = function()
		set_terminal_cursor_hidden(false)
	end,
})

-- === SYNCHRONOUS TERMINAL SCROLLING & STRICT BOUNDARY CLAMPING ===
local function term_scroll_down(buf)
	local bufnr = buf or vim.api.nvim_get_current_buf()
	if vim.b[bufnr].terminal_altscreen then
		return "<ScrollWheelDown>"
	end

	local max_bottom = vim.fn.line("$")
	local current_bottom = vim.fn.line("w$")
	local can_scroll = max_bottom - current_bottom
	local step = _G.OPTS.scroll.step

	if can_scroll > 0 then
		local to_scroll = math.min(step, can_scroll)
		if can_scroll <= to_scroll then
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buftype == "terminal" then
					vim.cmd("startinsert")
				end
			end)
		end
		return to_scroll .. "\x05"
	else
		vim.cmd("startinsert")
		return ""
	end
end

local function term_visual_scroll_down(buf)
	local bufnr = buf or vim.api.nvim_get_current_buf()
	if vim.b[bufnr].terminal_altscreen then
		return "<ScrollWheelDown>"
	end

	local max_bottom = vim.fn.line("$")
	local current_bottom = vim.fn.line("w$")
	local can_scroll = max_bottom - current_bottom
	local step = _G.OPTS.scroll.step

	if can_scroll > 0 then
		local to_scroll = math.min(step, can_scroll)
		return to_scroll .. "\x05"
	else
		return ""
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
		if vim.b.terminal_altscreen then
			return "<ScrollWheelUp>"
		end
		return _G.OPTS.scroll.step .. "\x19"
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
		return _G.OPTS.scroll.step .. "\x19"
	end
	return "<ScrollWheelUp>"
end, { expr = true, silent = true })

-- === MOUSE DRAG AUTO-SCROLL SELECTION ===
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
	if drag_timer then
		return
	end

	drag_timer = vim.uv.new_timer()
	drag_timer:start(
		0,
		_G.OPTS.scroll.drag_scroll_interval_ms,
		vim.schedule_wrap(function()
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
		end)
	)
end

vim.keymap.set({ "n", "v", "x", "s" }, "<LeftDrag>", function()
	start_drag_scroll()
	return "<LeftDrag>"
end, { expr = true, silent = true, desc = "Auto-scroll on mouse drag" })

vim.keymap.set({ "n", "v", "x", "s" }, "<LeftRelease>", function()
	stop_drag_scroll()
	return "<LeftRelease>"
end, { expr = true, silent = true, desc = "Stop auto-scroll on release" })

-- === TERM OPEN HANDLERS ===
vim.api.nvim_create_autocmd("TermOpen", {
	pattern = "term://*",
	callback = function(args)
		local bufnr = args.buf

		if not vim.b[bufnr].is_pager then
			vim.cmd("startinsert")
		end

		vim.keymap.set("t", "<ScrollWheelUp>", function()
			if vim.b[bufnr].terminal_altscreen then
				return "<ScrollWheelUp>"
			end
			return vim.api.nvim_replace_termcodes("<C-\\><C-n>" .. _G.OPTS.scroll.step .. "<C-y>", true, false, true)
		end, { buffer = bufnr, expr = true, silent = true })

		vim.keymap.set("t", "<ScrollWheelDown>", function()
			if vim.b[bufnr].terminal_altscreen then
				return "<ScrollWheelDown>"
			end
			return ""
		end, { buffer = bufnr, expr = true, silent = true })

		vim.keymap.set("n", "<ScrollWheelDown>", function()
			return term_scroll_down(bufnr)
		end, { buffer = bufnr, expr = true, silent = true })

		vim.keymap.set("n", "<ScrollWheelUp>", function()
			if vim.b[bufnr].terminal_altscreen then
				return "<ScrollWheelUp>"
			end
			return _G.OPTS.scroll.step .. "\x19"
		end, { buffer = bufnr, expr = true, silent = true })

		vim.keymap.set("x", "<ScrollWheelDown>", function()
			return term_visual_scroll_down(bufnr)
		end, { buffer = bufnr, expr = true, silent = true })

		vim.keymap.set("x", "<ScrollWheelUp>", function()
			return _G.OPTS.scroll.step .. "\x19"
		end, { buffer = bufnr, expr = true, silent = true })

		vim.keymap.set("x", "y", '"+y', { buffer = bufnr, silent = true, desc = "Copy selection to clipboard" })
		vim.keymap.set("x", "Y", '"+y', { buffer = bufnr, silent = true, desc = "Copy selection to clipboard" })
		vim.keymap.set("x", "<C-S-c>", '"+y', { buffer = bufnr, silent = true, desc = "Copy selection to clipboard" })
		vim.keymap.set("x", "<Esc>", "<Esc>", { buffer = bufnr, silent = true, desc = "Cancel selection" })

		local function term_paste()
			local job_id = vim.b[bufnr].terminal_job_id
			local text = vim.fn.getreg("+")
			if job_id and text ~= "" then
				vim.api.nvim_chan_send(job_id, text)
				vim.cmd("startinsert")
			end
		end

		vim.keymap.set({ "t", "n", "v" }, "<C-S-v>", term_paste, { buffer = bufnr, silent = true })

		local mouse_events = {
			"<C-LeftMouse>",
			"<C-S-LeftMouse>",
			"<C-LeftDrag>",
			"<C-S-LeftDrag>",
			"<C-LeftRelease>",
			"<C-S-LeftRelease>",
		}
		local standard_events = {
			"<LeftMouse>",
			"<LeftMouse>",
			"<LeftDrag>",
			"<LeftDrag>",
			"<LeftRelease>",
			"<LeftRelease>",
		}
		for i, event in ipairs(mouse_events) do
			vim.keymap.set({ "n", "v", "t" }, event, standard_events[i], { buffer = bufnr, silent = true })
		end

		vim.keymap.set("n", "!nos", ":Hh<CR>", { buffer = bufnr, desc = "Open nos terminal", noremap = true, silent = true })
	end,
})

-- === OPEN NOS TERMINAL COMMAND ===
local function open_nos_terminal()
	vim.cmd("tab term tmux new-session -s my-tui 'tmux set-option status off; nos; tmux kill-session -t my-tui'")
	vim.b.auto_terminal_mode = true
	vim.cmd("startinsert")
end

vim.api.nvim_create_user_command("Hh", open_nos_terminal, { desc = "Open `nos` in a smart terminal" })
vim.keymap.set("n", "!nos", ":Hh<CR>", { desc = "Open nos terminal", noremap = true, silent = true })

-- === TERMINAL AUTOMATIC SCROLLBACK PRUNING ===
vim.api.nvim_create_autocmd({ "TextChangedT", "TextChanged" }, {
	pattern = "term://*",
	callback = function(args)
		local bufnr = args.buf
		if not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end

		local line_count = vim.api.nvim_buf_line_count(bufnr)
		if _G.OPTS and _G.OPTS.terminal and _G.OPTS.terminal.prune_threshold and line_count > _G.OPTS.terminal.prune_threshold then
			local win_id = vim.fn.bufwinid(bufnr)
			if win_id == -1 then
				return
			end

			local win_info = vim.fn.getwininfo(win_id)[1]
			local topline = win_info and win_info.topline
			local win_height = vim.fn.winheight(win_id)
			local max_topline = line_count - win_height + 1

			if topline and topline < max_topline - 5 then
				return
			end

			vim.bo[bufnr].scrollback = _G.OPTS.terminal.pruned_history

			vim.defer_fn(function()
				if vim.api.nvim_buf_is_valid(bufnr) then
					vim.bo[bufnr].scrollback = _G.OPTS.terminal.max_scrollback
				end
			end, _G.OPTS.terminal.prune_restore_delay_ms)
		end
	end,
})
