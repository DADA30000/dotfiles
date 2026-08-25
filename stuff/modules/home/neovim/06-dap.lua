local dap = require("dap")
local dapui = require("dapui")

dapui.setup()
require("nvim-dap-virtual-text").setup()

dap.listeners.before.attach.dapui_config = function()
	dapui.open()
end
dap.listeners.before.launch.dapui_config = function()
	dapui.open()
end
dap.listeners.before.event_terminated.dapui_config = function()
	dapui.close()
end
dap.listeners.before.event_exited.dapui_config = function()
	dapui.close()
end
dap.defaults.fallback.switch_into_active_window = true

require("dap-go").setup()
require("dap-python").setup(_G.NIX.python)

local function pick_binary(path)
	return coroutine.create(function(dap_run)
		local files = vim.fn.glob(path .. "*", 0, 1)

		-- Modern 0.11/0.12 vim.iter() replacing deprecated vim.tbl_filter()
		local executables = vim.iter(files)
			:filter(function(f)
				return vim.fn.executable(f) == 1
					and vim.fn.isdirectory(f) == 0
					and not f:match("%.cpp$")
					and not f:match("%.c$")
					and not f:match("%.rs$")
			end)
			:totable()

		if #executables == 0 then
			print("No executables found in " .. path)
			coroutine.resume(dap_run, vim.fn.input("Path to executable: ", path, "file"))
		else
			vim.ui.select(executables, {
				prompt = "Select executable to debug:",
				format_item = function(item)
					return vim.fn.fnamemodify(item, ":t")
				end,
			}, function(choice)
				coroutine.resume(dap_run, choice)
			end)
		end
	end)
end

dap.adapters.cppdbg = {
	id = "cppdbg",
	type = "executable",
	command = _G.NIX.cppdbg,
}

dap.configurations.cpp = {
	{
		name = "Launch file",
		type = "cppdbg",
		request = "launch",
		program = function()
			return pick_binary(vim.fn.getcwd() .. "/")
		end,
		cwd = "${workspaceFolder}",
		stopAtEntry = false,
		setupCommands = {
			{
				text = "settings set target.process.thread.step-in-avoid-nodebug true",
				description = "ignore runtime code",
				ignoreFailures = true,
			},
			{
				text = "-enable-pretty-printing",
				description = "enable pretty printing",
				ignoreFailures = false,
			},
			{
				text = "handle SIGSTOP noprint nostop pass",
				description = "ignore SIGSTOP",
				ignoreFailures = true,
			},
		},
		logging = {
			engineLogging = false,
		},
		externalConsole = false,
		MIMode = "gdb",
		miDebuggerPath = _G.NIX.gdb,
	},
}

dap.configurations.c = dap.configurations.cpp
dap.configurations.rust = {
	vim.tbl_extend("force", dap.configurations.cpp[1], {
		name = "Launch Rust (target/debug)",
		program = function()
			return pick_binary(vim.fn.getcwd() .. "/target/debug/")
		end,
	}),
}

-- DAP Keymaps
vim.keymap.set("n", "<F5>", function()
	dap.continue()
end, { desc = "Debug: Start" })
vim.keymap.set("n", "<F10>", function()
	dap.step_over()
end, { desc = "Debug: Step Over" })
vim.keymap.set("n", "<F11>", function()
	dap.step_into()
end, { desc = "Debug: Step Into" })
vim.keymap.set("n", "<F12>", function()
	dap.step_out()
end, { desc = "Debug: Step Out" })
vim.keymap.set("n", "<leader>b", function()
	dap.toggle_breakpoint()
end, { desc = "Debug: Breakpoint" })
