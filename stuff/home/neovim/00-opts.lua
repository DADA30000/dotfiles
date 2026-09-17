-- ============================================================================
-- CENTRAL CONFIGURATION OPTIONS
-- ============================================================================
_G.OPTS = {
	-- Terminal & Pager Scrolling
	scroll = {
		step = 3, -- Number of lines to scroll per mouse wheel tick
		drag_scroll_interval_ms = 12, -- Auto-scroll interval during mouse selection drag (ms)
	},

	-- Terminal Buffer & History Management
	terminal = {
		prune_threshold = 3000, -- Buffer line count threshold to trigger pruning
		pruned_history = 1000, -- Scrollback limit applied during pruning
		max_scrollback = 100000, -- Full scrollback capacity restored after pruning
		prune_restore_delay_ms = 50, -- Delay before restoring max scrollback (ms)
	},

	-- Neovide GPU GUI Settings
	neovide = {
		scroll_animation_length = 0.15,
		cursor_animation_length = 0.05,
		position_animation_length = 0.15,
		cursor_trail_size = 0.2,
		padding = { top = 20, left = 20, right = 20 },
		opacity = 0.2,
		floating_blur = 8.0,
		floating_shadow = false,
		no_vsync = true,
		idle_timer = 0,
	},

	-- General Editor & Indentation Options
	editor = {
		tabstop = 2,
		shiftwidth = 2,
		updatetime = 100,
		undodir = vim.fn.expand("~/.config/nvim/undodir"),
		indent_char = "│",
		colorscheme = "onedark",
		onedark_style = "deep",
		auto_save_debounce_ms = 1000,
		format_timeout_ms = 10000,
	},
}

-- === CORE EDITOR OPTIONS ===
vim.opt.foldenable = false
vim.opt.foldlevel = 99
vim.opt.wrap = true
vim.opt.showmode = false
vim.opt.number = true
vim.opt.signcolumn = "yes"
vim.opt.expandtab = true
vim.opt.autoindent = true
vim.opt.smartindent = true
vim.opt.tabstop = _G.OPTS.editor.tabstop
vim.opt.softtabstop = _G.OPTS.editor.tabstop
vim.opt.shiftwidth = _G.OPTS.editor.shiftwidth
vim.opt.updatetime = _G.OPTS.editor.updatetime
vim.opt.undofile = true
vim.opt.undodir = _G.OPTS.editor.undodir
vim.opt.clipboard = "unnamedplus"
vim.opt.selection = "inclusive"
vim.opt.tabclose = "uselast"
vim.opt.guicursor:append("t:ver25")
vim.g.suda_smart_edit = 1
vim.cmd("set report=99999")
