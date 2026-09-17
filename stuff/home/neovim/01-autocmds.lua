-- Auto bufhidden=wipe for git and temp edit files
vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
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
		if event.match:match("^%w%w+:[\\/][\\/]") then
			return
		end
		local dir = vim.fn.fnamemodify(event.match, ":p:h")
		if vim.fn.isdirectory(dir) == 0 then
			vim.fn.mkdir(dir, "p")
		end
	end,
})

-- Auto-close terminals on successful exit (Removes [Process exited 0] tabs)
vim.api.nvim_create_autocmd("TermClose", {
	group = vim.api.nvim_create_augroup("AutoCloseTermOnSuccess", { clear = true }),
	callback = function(ev)
		if vim.v.event.status == 0 then
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(ev.buf) then
					pcall(vim.api.nvim_buf_delete, ev.buf, { force = true })
				end
			end)
		end
	end,
})

-- Auto-start Treesitter
vim.api.nvim_create_autocmd("FileType", {
	pattern = "*",
	callback = function()
		local lang = vim.treesitter.language.get_lang(vim.bo.filetype)
		if lang then
			pcall(vim.treesitter.start)
		end
	end,
})

-- Track last mode when leaving terminal
vim.api.nvim_create_autocmd("BufLeave", {
	pattern = "term://*",
	callback = function()
		vim.b.last_mode = vim.fn.mode()
	end,
})

-- Auto-stop LSP when its last buffer is closed (0.11/0.12 client:stop & client:is_stopped)
local stopping_clients = {}
vim.api.nvim_create_autocmd("LspDetach", {
	group = vim.api.nvim_create_augroup("LspAutoStopOnClose", { clear = true }),
	callback = function(ev)
		local client_id = ev.data.client_id
		if not client_id or stopping_clients[client_id] then
			return
		end

		vim.schedule(function()
			if stopping_clients[client_id] then
				return
			end
			local client = vim.lsp.get_client_by_id(client_id)
			if not client or client:is_stopped() then
				return
			end

			local has_attached = false
			for bufnr, is_attached in pairs(client.attached_buffers or {}) do
				if is_attached and bufnr ~= ev.buf and vim.api.nvim_buf_is_valid(bufnr) then
					has_attached = true
					break
				end
			end

			if not has_attached then
				stopping_clients[client_id] = true
				pcall(function()
					client:stop(true)
				end)
			end
		end)
	end,
})

-- Auto-wipe unused file buffers when tab/window is closed
vim.api.nvim_create_autocmd({ "BufHidden", "TabClosed" }, {
	group = vim.api.nvim_create_augroup("AutoWipeHiddenBuffers", { clear = true }),
	callback = function(ev)
		vim.schedule(function()
			local buf = ev.buf
			if not vim.api.nvim_buf_is_valid(buf) then
				return
			end
			if vim.bo[buf].modified or vim.bo[buf].buftype ~= "" then
				return
			end

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

-- Tab origin tracker (Return to origin tab on close)
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
