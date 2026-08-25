-- === THEME & NATIVE HIGHLIGHTS ===
vim.g.onedark_config = { style = _G.OPTS.editor.onedark_style }
vim.g.netrw_keepdir = 0
vim.cmd("colorscheme " .. _G.OPTS.editor.colorscheme)

-- Pure Lua highlights replacing legacy vimscript highlight commands
vim.api.nvim_set_hl(0, "Visual", { bg = "#4e5a6b", fg = "#ffffff" })
vim.api.nvim_set_hl(0, "Normal", { fg = "#bbddff", bg = "none", ctermbg = "none" })
vim.api.nvim_set_hl(0, "TabLineSel", { fg = "#ffffff", bold = true, ctermfg = 15, cterm = { bold = true } })
vim.api.nvim_set_hl(0, "EndOfBuffer", { bg = "none", ctermbg = "none" })
vim.api.nvim_set_hl(0, "SignColumn", { bg = "none", ctermbg = "none" })
vim.api.nvim_set_hl(0, "NonText", { bg = "none", ctermbg = "none" })
vim.api.nvim_set_hl(0, "StatusLine", { bg = "none" })

require("ibl").setup({
	indent = { char = _G.OPTS.editor.indent_char },
	scope = { enabled = true, show_start = true, show_end = true },
})

require("cord").setup({})

require("fidget").setup({
	notification = {
		window = {
			winblend = 100,
		},
	},
})

-- === WINDOW TITLE ===
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

-- === SLIDING TABLINE WITH OVERFLOW FOLLOWING ===
_G.MyTabLine = function()
	local total_tabs = vim.fn.tabpagenr("$")
	local current_tab = vim.fn.tabpagenr()
	local max_width = vim.o.columns

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
		if not expanded then
			break
		end
	end

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

vim.o.tabline = "%!v:lua.MyTabLine()"

-- === TERMINAL, MAN PAGE & PAGER VS FILE LAYOUT AUTO-TOGGLE ===
vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "TermOpen", "FileType" }, {
	pattern = "*",
	callback = function()
		if vim.bo.buftype == "terminal" or vim.bo.filetype == "man" or vim.b.is_pager then
			vim.o.laststatus = 0
			vim.o.cmdheight = 0

			if
				vim.bo.buftype == "terminal"
				and not vim.b.is_pager
				and (vim.b.last_mode == nil or vim.b.last_mode == "t")
			then
				vim.cmd("startinsert")
			end
		else
			vim.o.laststatus = 2
			vim.o.cmdheight = 1
		end
	end,
})

-- === NEOVIDE SETTINGS & INSTANT TAB SWITCH ===
if vim.g.neovide then
	vim.keymap.set({ "n", "x" }, "<C-S-c>", '"+y', { desc = "Copy system clipboard" })
	vim.keymap.set({ "n", "x" }, "<C-S-v>", '"+p', { desc = "Paste system clipboard" })
	vim.keymap.set("i", "<C-S-v>", "<C-r><C-o>+", { desc = "Paste system clipboard" })
	vim.g.neovide_no_vsync = _G.OPTS.neovide.no_vsync
	vim.g.neovide_idle_timer = _G.OPTS.neovide.idle_timer
	vim.g.neovide_scroll_animation_length = _G.OPTS.neovide.scroll_animation_length
	vim.g.neovide_cursor_animation_length = _G.OPTS.neovide.cursor_animation_length
	vim.g.neovide_cursor_trail_size = _G.OPTS.neovide.cursor_trail_size
	vim.g.neovide_padding_top = _G.OPTS.neovide.padding.top
	vim.g.neovide_padding_left = _G.OPTS.neovide.padding.left
	vim.g.neovide_padding_right = _G.OPTS.neovide.padding.right
	vim.g.neovide_opacity = _G.OPTS.neovide.opacity
	vim.g.neovide_floating_shadow = _G.OPTS.neovide.floating_shadow
	vim.g.neovide_floating_blur_amount_x = _G.OPTS.neovide.floating_blur
	vim.g.neovide_floating_blur_amount_y = _G.OPTS.neovide.floating_blur
end

_G.InstantTabSwitch = function(cmd)
	local old_scroll = vim.g.neovide_scroll_animation_length or _G.OPTS.neovide.scroll_animation_length
	local old_cursor = vim.g.neovide_cursor_animation_length or _G.OPTS.neovide.cursor_animation_length
	local old_pos = vim.g.neovide_position_animation_length or _G.OPTS.neovide.position_animation_length

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
