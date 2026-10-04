local luasnip = require("luasnip")
require("luasnip.loaders.from_vscode").lazy_load()

local cmp = require("cmp")

function _G.check_back_space()
	local col = vim.fn.col(".") - 1
	return col == 0 or vim.fn.getline("."):sub(col, col):match("%s") ~= nil
end

cmp.setup({
	snippet = {
		expand = function(args)
			luasnip.lsp_expand(args.body)
		end,
	},
	mapping = cmp.mapping.preset.insert({
		["<C-b>"] = cmp.mapping.scroll_docs(-4),
		["<C-f>"] = cmp.mapping.scroll_docs(4),
		["<C-Space>"] = cmp.mapping.complete(),
		["<C-e>"] = cmp.mapping.abort(),
		["<S-CR>"] = cmp.mapping.confirm({ select = true }),
		["<CR>"] = cmp.mapping.confirm({ select = false }),
		["<Tab>"] = cmp.mapping(function(fallback)
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
		["<S-Tab>"] = cmp.mapping(function(fallback)
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
		{ name = "path" },
	}),
})

-- Ensure system Rust toolchain bin directory is prioritized in Neovim's PATH
if _G.NIX and _G.NIX.rust_toolchain then
	vim.env.PATH = _G.NIX.rust_toolchain .. "/bin:" .. (vim.env.PATH or "")
	if _G.NIX.rust_lib_src and not vim.env.RUST_SRC_PATH then
		vim.env.RUST_SRC_PATH = _G.NIX.rust_lib_src
	end
end

-- === CONFORM FORMATTING SETUP ===
local conform = require("conform")
conform.setup({
	formatters_by_ft = {
		lua = { "stylua" },
		python = { "ruff_format" },
		rust = { "rustfmt" },
		nix = { "nixfmt" },
		go = { "gofmt", "goimports" },
	},
	formatters = {
		rustfmt = {
			command = (_G.NIX and _G.NIX.rust_toolchain and vim.fn.executable(_G.NIX.rust_toolchain .. "/bin/rustfmt") == 1)
					and (_G.NIX.rust_toolchain .. "/bin/rustfmt")
				or "rustfmt",
		},
	},
	default_format_opts = {
		lsp_format = "fallback",
	},
	format_on_save = {
		lsp_format = "fallback",
		timeout_ms = _G.OPTS.editor.format_timeout_ms,
	},
})

vim.api.nvim_create_user_command("Format", function()
	conform.format({ async = false, lsp_format = "fallback" })
end, {})

-- Async Auto-Format on Auto-Save
local is_formatting = false
vim.api.nvim_create_autocmd("User", {
	pattern = "AutoSaveWritePost",
	group = vim.api.nvim_create_augroup("AutoSaveAsyncFormat", { clear = true }),
	callback = function(args)
		if is_formatting then
			return
		end
		local target_buf = (args.data and args.data.saved_buffer) or vim.api.nvim_get_current_buf()
		if not vim.api.nvim_buf_is_valid(target_buf) or not vim.bo[target_buf].modifiable then
			return
		end

		is_formatting = true
		conform.format({
			bufnr = target_buf,
			async = true,
			lsp_format = "fallback",
			callback = function()
				is_formatting = false
				if vim.api.nvim_buf_is_valid(target_buf) and vim.bo[target_buf].modified then
					vim.api.nvim_buf_call(target_buf, function()
						vim.cmd("silent! noautocmd write")
					end)
				end
			end,
		})
	end,
})

-- Diagnostics Configuration
vim.diagnostic.config({
	virtual_text = true,
	float = {
		focusable = false,
		style = "minimal",
		border = "rounded",
		source = true,
		header = "",
		prefix = "",
	},
})

local diag_float_win = nil

local function close_all_floating_previews()
	if diag_float_win and vim.api.nvim_win_is_valid(diag_float_win) then
		pcall(vim.api.nvim_win_close, diag_float_win, true)
	end
	diag_float_win = nil

	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_is_valid(win) then
			local ok_lsp, _ = pcall(vim.api.nvim_win_get_var, win, "lsp_floating_bufnr")
			local cfg = vim.api.nvim_win_get_config(win)
			if ok_lsp or (cfg and cfg.relative and cfg.relative ~= "" and not cfg.focusable) then
				pcall(vim.api.nvim_win_close, win, true)
			end
		end
	end
end
_G.CloseAllFloatingPreviews = close_all_floating_previews

vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, {
	border = "rounded",
	close_events = {
		"CursorMoved",
		"CursorMovedI",
		"BufLeave",
		"BufHidden",
		"WinLeave",
		"CmdlineEnter",
		"InsertEnter",
	},
})

vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
	group = vim.api.nvim_create_augroup("DiagnosticFloatHover", { clear = true }),
	callback = function()
		local mode = vim.api.nvim_get_mode().mode
		if mode:match("^[ic]") or vim.bo.buftype ~= "" then
			close_all_floating_previews()
			return
		end

		local line = vim.fn.line(".") - 1
		local diags = vim.diagnostic.get(0, { lnum = line })
		if #diags == 0 then
			close_all_floating_previews()
			return
		end

		close_all_floating_previews()
		local _, winid = vim.diagnostic.open_float(nil, {
			focusable = false,
			scope = "cursor",
			close_events = {
				"CursorMoved",
				"CursorMovedI",
				"BufLeave",
				"BufHidden",
				"WinLeave",
				"CmdlineEnter",
				"InsertEnter",
			},
		})
		diag_float_win = winid
	end,
})

vim.api.nvim_create_autocmd(
	{ "CursorMoved", "CursorMovedI", "BufLeave", "BufHidden", "WinLeave", "CmdlineEnter", "InsertEnter" },
	{
		group = vim.api.nvim_create_augroup("DiagnosticFloatDismiss", { clear = true }),
		callback = close_all_floating_previews,
	}
)

-- Modern 0.11/0.12 vim.diagnostic.jump() replacing deprecated goto_prev/goto_next
vim.keymap.set("n", "[g", function()
	vim.diagnostic.jump({ count = -1, float = true })
end, { desc = "Previous Diagnostic" })
vim.keymap.set("n", "]g", function()
	vim.diagnostic.jump({ count = 1, float = true })
end, { desc = "Next Diagnostic" })
vim.keymap.set("n", "<space>a", vim.diagnostic.setqflist, { desc = "Workspace Diagnostics" })

vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("UserLspConfig", {}),
	callback = function(ev)
		local opts_lsp = { buffer = ev.buf, silent = true }
		local bind = vim.keymap.set

		bind("n", "gd", vim.lsp.buf.definition, opts_lsp)
		bind("n", "gy", vim.lsp.buf.type_definition, opts_lsp)
		bind("n", "gi", vim.lsp.buf.implementation, opts_lsp)
		bind("n", "gr", vim.lsp.buf.references, opts_lsp)
		bind("n", "K", vim.lsp.buf.hover, opts_lsp)
		bind("n", "<leader>rn", vim.lsp.buf.rename, opts_lsp)
		bind({ "n", "x" }, "<leader>f", function()
			conform.format({ async = false, lsp_format = "fallback" })
		end, opts_lsp)
		bind({ "n", "x" }, "<leader>a", vim.lsp.buf.code_action, opts_lsp)
		bind("n", "<leader>ac", vim.lsp.buf.code_action, opts_lsp)
		bind("n", "<leader>cl", vim.lsp.codelens.run, opts_lsp)
	end,
})

-- Modern 0.10+ inlay hint toggle signature
vim.keymap.set("n", "<C-h>", function()
	if vim.lsp.inlay_hint then
		local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = 0 })
		vim.lsp.inlay_hint.enable(not enabled, { bufnr = 0 })
	end
end, { desc = "Toggle Inlay Hints", silent = true })

local capabilities = require("cmp_nvim_lsp").default_capabilities()

-- LSP Server Configurations via vim.lsp.config & vim.lsp.enable
vim.lsp.config("rust_analyzer", {
	capabilities = capabilities,
	cmd = { _G.NIX.rust_analyzer },
	cmd_env = {
		PATH = _G.NIX.rust_toolchain .. "/bin:" .. (os.getenv("PATH") or ""),
		RUST_SRC_PATH = _G.NIX.rust_lib_src,
	},
	root_dir = function(bufnr_or_fname, cb)
		local fname = type(bufnr_or_fname) == "number" and vim.api.nvim_buf_get_name(bufnr_or_fname) or bufnr_or_fname
		if not fname or fname == "" then
			if cb then
				cb(nil)
			end
			return nil
		end

		local cargo_root = vim.fs.root(fname, { "Cargo.toml", "rust-project.json" })
		if cargo_root then
			if cb then
				cb(cargo_root)
			end
			return cargo_root
		end

		local hash = vim.fn.sha256(fname):sub(1, 8)
		local standalone_dir = "/tmp/ra_standalone_" .. hash
		vim.fn.mkdir(standalone_dir, "p")

		local clippy_bin = _G.NIX and _G.NIX.rust_toolchain and (_G.NIX.rust_toolchain .. "/bin/clippy-driver")
		local runnables = {}
		if clippy_bin and vim.fn.executable(clippy_bin) == 1 then
			runnables = {
				{
					program = clippy_bin,
					args = {
						"--edition",
						"2024",
						"--error-format=json",
						"--emit=metadata",
						"--out-dir",
						standalone_dir,
						"-W",
						"clippy::all",
						"-W",
						"clippy::pedantic",
						"{saved_file}",
					},
					cwd = standalone_dir,
					kind = "flycheck",
				},
			}
		end

		local project_json = standalone_dir .. "/rust-project.json"
		local f = io.open(project_json, "w")
		if f then
			local content = vim.json.encode({
				sysroot = _G.NIX.rust_toolchain,
				sysroot_src = _G.NIX.rust_lib_src,
				crates = {
					{
						root_module = fname,
						edition = "2024",
						deps = {},
						cfg = { "unix", "debug_assertions" },
						is_workspace_member = true,
						source = {
							include_dirs = { fname },
							exclude_dirs = {},
						},
						build = {
							label = "standalone",
							build_file = standalone_dir .. "/build.rs",
							target_kind = "bin",
						},
					},
				},
				runnables = runnables,
			})
			f:write(content)
			f:close()
		end

		if cb then
			cb(standalone_dir)
		end
		return standalone_dir
	end,
	settings = {
		["rust-analyzer"] = {
			cargo = {
				sysroot = _G.NIX.rust_toolchain,
				sysrootSrc = _G.NIX.rust_lib_src,
			},
			check = {
				command = "clippy",
				extraArgs = { "--", "-W", "clippy::all", "-W", "clippy::pedantic" },
			},
			procMacro = {
				enable = true,
			},
		},
	},
})
vim.lsp.enable("rust_analyzer")

vim.lsp.config("basedpyright", {
	capabilities = capabilities,
	settings = {
		basedpyright = {
			analysis = {
				typeCheckingMode = "standard",
				autoImportCompletions = true,
			},
		},
	},
})
vim.lsp.enable("basedpyright")

vim.lsp.config("ruff", {
	capabilities = capabilities,
	init_options = {
		settings = { logLevel = "debug" },
	},
})
vim.lsp.enable("ruff")

vim.lsp.config("asm_lsp", {
	capabilities = capabilities,
	filetypes = { "asm", "s", "S" },
})
vim.lsp.enable("asm_lsp")

vim.lsp.config("qmlls", {
	capabilities = capabilities,
	cmd = { "qmlls", "-E" },
})
vim.lsp.enable("qmlls")

vim.lsp.config("cmake", {
	capabilities = capabilities,
	init_options = { buildDirectory = "build" },
})
vim.lsp.enable("cmake")

vim.lsp.config("clangd", { capabilities = capabilities })
vim.lsp.enable("clangd")

vim.lsp.config("nixd", {
	capabilities = capabilities,
	settings = {
		nixd = {
			nixpkgs = {
				expr = 'import (builtins.getFlake "'
					.. _G.NIX.nixpkgs_flake
					.. '") { system = "'
					.. _G.NIX.system
					.. '"; config.allowUnfree = true; }',
			},
			formatting = {
				command = { "nixfmt" },
			},
			options = {
				nixos = {
					expr = '(builtins.getFlake "/etc/nixos").nixosConfigurations.nixos.options',
				},
				home_manager = {
					expr = '(builtins.getFlake "/etc/nixos").nixosConfigurations.nixos.options.home-manager.users.type.getSubOptions []',
				},
			},
		},
	},
})
vim.lsp.enable("nixd")

vim.lsp.config("lua_ls", {
	capabilities = capabilities,
	settings = {
		Lua = {
			diagnostics = {
				globals = { "vim" },
			},
		},
	},
})
vim.lsp.enable("lua_ls")

vim.lsp.config("gopls", {
	capabilities = capabilities,
	settings = {
		gopls = {
			analyses = {
				unusedparams = true,
			},
			staticcheck = true,
			gofumpt = true,
		},
	},
})
vim.lsp.enable("gopls")

local standard_lsps = { "bashls", "html", "cssls", "jsonls", "jdtls", "taplo", "yamlls" }
for _, lsp in ipairs(standard_lsps) do
	vim.lsp.config(lsp, { capabilities = capabilities })
	vim.lsp.enable(lsp)
end
