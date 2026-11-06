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
		if not (ev.buf and vim.api.nvim_buf_is_valid(ev.buf)) then
			return
		end
		local ok, is_pager = pcall(function()
			return vim.b[ev.buf].is_pager
		end)
		if ok and is_pager then
			return
		end
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

-- Track last mode & preserve scroll position when leaving terminal window/tab
vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave", "TabLeave" }, {
	pattern = "*",
	callback = function(ev)
		local win = vim.api.nvim_get_current_win()
		if not vim.api.nvim_win_is_valid(win) then
			return
		end
		local buf = ev.buf or vim.api.nvim_win_get_buf(win)
		if not (buf and vim.api.nvim_buf_is_valid(buf)) then
			return
		end
		if not (vim.bo[buf].buftype == "terminal" or vim.b[buf].is_pager) then
			return
		end
		local m = vim.fn.mode()
		pcall(function()
			vim.b[buf].last_mode = m
		end)

		if m == "t" then
			vim.w[win].saved_term_view = nil
			return
		end

		local win_info = vim.fn.getwininfo(win)[1]
		if win_info then
			local max_bottom = vim.api.nvim_buf_line_count(buf)
			if vim.b[buf].is_pager or win_info.botline < max_bottom then
				local lnum = math.min(win_info.botline, math.max(win_info.topline, vim.api.nvim_win_get_cursor(win)[1]))
				vim.w[win].saved_term_view = {
					topline = win_info.topline,
					lnum = lnum,
					col = 0,
				}
			else
				vim.w[win].saved_term_view = nil
			end
		end
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
vim.api.nvim_create_autocmd({ "TabClosed", "WinClosed" }, {
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

-- Native run0 execution for suda.vim with immediate unit notification
_G.SudaRun0Exec = function(cmd_args, input_data)
	local stdout_lines = {}
	local stderr_lines = {}
	local full_cmd = { "run0", "--background=" }
	for _, arg in ipairs(cmd_args) do
		table.insert(full_cmd, arg)
	end

	local job_id = vim.fn.jobstart(full_cmd, {
		stdout_buffered = true,
		stderr_buffered = false,
		on_stderr = function(_, data)
			for _, line in ipairs(data) do
				if line and line ~= "" then
					table.insert(stderr_lines, line)
					if line:match("^run0:") then
						vim.api.nvim_echo({ { "[" .. line .. "]", "Title" } }, false, {})
						vim.cmd("redraw")
					end
				end
			end
		end,
		on_stdout = function(_, data)
			if data then
				for _, line in ipairs(data) do
					table.insert(stdout_lines, line)
				end
			end
		end,
	})

	if job_id <= 0 then
		return { code = -1, stdout = {}, stderr = { "Failed to spawn run0" } }
	end

	if input_data and input_data ~= "" then
		vim.api.nvim_chan_send(job_id, input_data)
	end

	local code = vim.fn.jobwait({ job_id })[1]
	if #stdout_lines > 0 and stdout_lines[#stdout_lines] == "" then
		table.remove(stdout_lines, #stdout_lines)
	end

	return { code = code, stdout = stdout_lines, stderr = stderr_lines }
end

-- Smart Netrw directory browsing (supports suda:// and root-edited files)
local function get_clean_buffer_dir()
	local name = vim.api.nvim_buf_get_name(0)
	if name == "" then
		return nil
	end
	local clean_path = name:gsub("^suda://", "")
	local dir = vim.fs.dirname(clean_path)
	if dir and vim.fn.isdirectory(dir) == 1 then
		return dir
	end
	return nil
end

local netrw_cmd_configs = {
	Ex = { dosplit = 0, style = 0 },
	Explore = { dosplit = 0, style = 0 },
	Sexplore = { dosplit = 1, style = 0 },
	Hexplore = { dosplit = 1, style = 2 },
	Vexplore = { dosplit = 1, style = 4 },
	Texplore = { dosplit = 0, style = 6 },
}

for cmd_name, cfg in pairs(netrw_cmd_configs) do
	vim.api.nvim_create_user_command(cmd_name, function(opts)
		if _G.CloseAllFloatingPreviews then
			_G.CloseAllFloatingPreviews()
		end
		local target_dir = opts.args
		if not target_dir or target_dir == "" then
			target_dir = get_clean_buffer_dir() or ""
		end
		local bang_val = opts.bang and 1 or 0
		local style = (cfg.style == 6) and 6 or (cfg.style + bang_val)
		vim.fn["netrw#Explore"](opts.count or 0, cfg.dosplit, style, target_dir)
	end, { bang = true, nargs = "*", count = 0, complete = "dir" })
end
