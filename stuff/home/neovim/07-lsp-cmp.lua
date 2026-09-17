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

-- === CONFORM FORMATTING SETUP ===
local conform = require("conform")
conform.setup({
	formatters_by_ft = {
		lua = { "stylua" },
		python = { "ruff_format" },
		rust = { "rustfmt" },
		nix = { "nixfmt" },
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
	callback = function()
		if is_formatting then
			return
		end
		if not vim.bo.modifiable then
			return
		end

		is_formatting = true
		conform.format({
			async = true,
			lsp_format = "fallback",
			callback = function()
				is_formatting = false
				if vim.bo.modified then
					vim.cmd("silent! noautocmd write")
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

vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
	callback = function()
		vim.diagnostic.open_float(nil, { focusable = false, scope = "cursor" })
	end,
})

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

		local project_json = standalone_dir .. "/rust-project.json"
		local f = io.open(project_json, "w")
		if f then
			local content = vim.json.encode({
				sysroot = _G.NIX.rust_toolchain,
				sysroot_src = _G.NIX.rust_lib_src,
				crates = {
					{
						root_module = fname,
						edition = "2021",
						deps = {},
						cfg = { "unix", "debug_assertions" },
						is_workspace_member = true,
						source = {
							include_dirs = { standalone_dir },
							exclude_dirs = {},
						},
					},
				},
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

local standard_lsps = { "bashls", "html", "cssls", "jsonls", "jdtls", "taplo", "yamlls" }
for _, lsp in ipairs(standard_lsps) do
	vim.lsp.config(lsp, { capabilities = capabilities })
	vim.lsp.enable(lsp)
end
