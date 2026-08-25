-- === TERMINAL CURSOR VISIBILITY ===
vim.api.nvim_set_hl(0, "HiddenCursor", { blend = 100, nocombine = true })

local function set_terminal_cursor_hidden(hide)
	local current = vim.o.guicursor
	local cleaned = current
		:gsub(",?n%-v:HiddenCursor", "")
		:gsub(",?n:HiddenCursor", "")
		:gsub(",?v:ver25%-HiddenCursor", "")
		:gsub(",?v:HiddenCursor", "")
	if hide then
		vim.o.guicursor = cleaned .. ",n:HiddenCursor,v:ver25-HiddenCursor"
	else
		vim.o.guicursor = cleaned
	end
end

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
	end,
})

-- === SYNCHRONOUS TERMINAL SCROLLING & STRICT BOUNDARY CLAMPING ===
local function term_scroll_down(buf)
	local bufnr = buf or vim.api.nvim_get_current_buf()
	if vim.b[bufnr].terminal_altscreen then
		return "i<ScrollWheelDown>"
	end

	local max_bottom = vim.fn.line("$")
	local current_bottom = vim.fn.line("w$")
	local can_scroll = max_bottom - current_bottom
	local step = _G.OPTS.scroll.step

	if can_scroll > 0 then
		local to_scroll = math.min(step, can_scroll)
		if can_scroll <= step then
			return to_scroll .. "\x05i"
		else
			return to_scroll .. "\x05"
		end
	else
		return "i"
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
			return "i<ScrollWheelUp>"
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
				return "i<ScrollWheelUp>"
			end
			return _G.OPTS.scroll.step .. "\x19"
		end, { buffer = bufnr, expr = true, silent = true })

		vim.keymap.set("x", "<ScrollWheelDown>", function()
			return term_visual_scroll_down(bufnr)
		end, { buffer = bufnr, expr = true, silent = true })

		vim.keymap.set("x", "<ScrollWheelUp>", function()
			return _G.OPTS.scroll.step .. "\x19"
		end, { buffer = bufnr, expr = true, silent = true })

		local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-=~!@#$%^&*()_+[]{}|;:',./<>?"
		local cyrillic =
			"абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"
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
		if line_count > _G.OPTS.terminal.prune_threshold then
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

			vim.opt_local.scrollback = _G.OPTS.terminal.pruned_history

			vim.defer_fn(function()
				if vim.api.nvim_buf_is_valid(bufnr) then
					vim.opt_local.scrollback = _G.OPTS.terminal.max_scrollback
				end
			end, _G.OPTS.terminal.prune_restore_delay_ms)
		end
	end,
})
