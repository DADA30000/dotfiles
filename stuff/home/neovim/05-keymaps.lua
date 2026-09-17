-- Shift-Insert paste from clipboard
vim.keymap.set({ "i", "c" }, "<S-Insert>", "<C-R>+", { silent = true })

-- Custom shortcuts
vim.keymap.set("n", "!aa", ":tabnew $NEOVIDE_MOUNT_POINT<cr>", { silent = true })
vim.keymap.set("n", "!hh", ":silent! tabnew +Man! " .. _G.NIX.kekma_home .. "<cr>", { silent = true })
vim.keymap.set("n", "!nn", ":silent! tabnew +Man! " .. _G.NIX.kekma_nix .. "<cr>", { silent = true })

-- Tab switching keymaps
for _, mode in ipairs({ "n", "i", "t", "v", "x", "s" }) do
	local prefix = (mode:match("[vxs]") and "<Esc>" or "")
	vim.keymap.set(
		mode,
		"<C-S-Right>",
		prefix .. "<Cmd>lua InstantTabSwitch('tabnext')<CR>",
		{ desc = "Next Tab", silent = true }
	)
	vim.keymap.set(
		mode,
		"<C-S-Left>",
		prefix .. "<Cmd>lua InstantTabSwitch('tabprevious')<CR>",
		{ desc = "Previous Tab", silent = true }
	)
	vim.keymap.set(
		mode,
		"<C-S-w>",
		prefix .. "<Cmd>lua InstantTabSwitch('tabclose')<CR>",
		{ desc = "Close Tab", silent = true }
	)
	vim.keymap.set(mode, "<C-S-t>", prefix .. "<Cmd>tabnew +term<CR>", { desc = "New Terminal Tab", silent = true })
end

-- Clipboard operations
vim.keymap.set({ "n", "x" }, "<C-S-c>", '"+y', { desc = "Copy system clipboard" })
vim.keymap.set({ "n", "x" }, "<C-S-v>", '"+p', { desc = "Paste system clipboard" })
vim.keymap.set("s", "<C-S-c>", '<C-g>"+y', { silent = true, desc = "Copy selection in Select mode" })
vim.keymap.set("s", "<C-S-v>", '<C-g>"+p', { silent = true, desc = "Paste/Replace in Select mode" })

-- Horizontal scroll wheel no-ops
vim.keymap.set({ "n", "v", "i" }, "<ScrollWheelLeft>", "<Nop>", { silent = true })
vim.keymap.set({ "n", "v", "i" }, "<ScrollWheelRight>", "<Nop>", { silent = true })
vim.keymap.set("t", "<ScrollWheelLeft>", function()
	if vim.b.terminal_altscreen then
		return "<ScrollWheelLeft>"
	end
	return "<Nop>"
end, { expr = true, silent = true })
vim.keymap.set("t", "<ScrollWheelRight>", function()
	if vim.b.terminal_altscreen then
		return "<ScrollWheelRight>"
	end
	return "<Nop>"
end, { expr = true, silent = true })

-- Black hole register for delete operations
vim.keymap.set({ "n", "v" }, "d", '"_d')
vim.keymap.set("n", "dd", '"_dd')
vim.keymap.set({ "n", "v" }, "x", '"_x')

-- Silent manual save abbreviations
local silent_commands = {
	wq = "silent wq",
	x = "silent x",
	wqa = "silent wqa",
	xa = "silent xa",
}
for abbrev, replacement in pairs(silent_commands) do
	vim.cmd(
		string.format(
			"cnoreabbrev <expr> %s (getcmdtype() == ':' && getcmdline() ==# '%s') ? '%s' : '%s'",
			abbrev,
			abbrev,
			replacement,
			abbrev
		)
	)
end

-- Auto-Save plugin configuration
require("auto-save").setup({
	enabled = true,
	trigger_events = {
		immediate_save = { "FocusLost", "BufLeave" },
		defer_save = { "InsertLeave" },
		cancel_deferred_save = { "InsertEnter" },
	},
	noautocmd = true,
	debounce_delay = _G.OPTS.editor.auto_save_debounce_ms,
})
