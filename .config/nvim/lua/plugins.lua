-- Requires Neovim 0.11+. On 0.12+ the newest rustaceanvim and the rewritten
-- nvim-treesitter `main` branch are used; on 0.11 the last compatible versions.
if vim.fn.has("nvim-0.11") == 0 then
	vim.api.nvim_echo({
		{ "plugins.lua: Neovim 0.11+ is required (0.12+ recommended). Plugins were not loaded.", "WarningMsg" },
	}, true, {})
	return
end
local nvim_012 = vim.fn.has("nvim-0.12") == 1

-- When launched from Nemo or the menu, Neovim gets the desktop session's PATH,
-- which may lack the dirs your shell adds. Add them so tree-sitter, cargo and
-- rust-analyzer are found however nvim is started.
for _, dir in ipairs({ "~/.cargo/bin", "~/.local/bin" }) do
	dir = vim.fn.expand(dir)
	local path = ":" .. vim.env.PATH .. ":"
	if vim.fn.isdirectory(dir) == 1 and not path:find(":" .. dir .. ":", 1, true) then
		vim.env.PATH = dir .. ":" .. vim.env.PATH
	end
end

-- Bootstrap lazy.nvim ---------------------------------------------------------
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
	local out = vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"--branch=stable",
		"https://github.com/folke/lazy.nvim.git",
		lazypath,
	})
	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({
			{ "Failed to clone lazy.nvim:\n", "ErrorMsg" },
			{ out, "WarningMsg" },
		}, true, {})
		return
	end
end
vim.opt.rtp:prepend(lazypath)

-- General settings (not tied to a single plugin) ------------------------------

-- menuone: popup even when there's only one match
-- noinsert: Do not insert text until a selection is made
-- noselect: Do not select, force to select one from the menu
vim.opt.completeopt = { "menuone", "noselect", "noinsert" }
vim.opt.shortmess:append({ c = true })
vim.opt.updatetime = 300

-- Fixed column for diagnostics; show diagnostic popup on CursorHold
vim.opt.signcolumn = "yes"
local S = vim.diagnostic.severity
vim.diagnostic.config({
	virtual_text = false,
	signs = {
		text = { [S.ERROR] = "", [S.WARN] = "", [S.HINT] = "", [S.INFO] = "" },
	},
	update_in_insert = true,
	underline = true,
	severity_sort = false,
	float = {
		border = "rounded",
		source = true,
		header = "",
		prefix = "",
	},
})

vim.api.nvim_create_autocmd("CursorHold", {
	group = vim.api.nvim_create_augroup("DiagnosticFloat", { clear = true }),
	callback = function()
		vim.diagnostic.open_float(nil, { focusable = false })
	end,
})

-- Treesitter folding (built into Neovim; works with either nvim-treesitter branch)
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"

-- Vimspector options (globals must be set before the plugin loads)
vim.g.vimspector_sidebar_width = 85
vim.g.vimspector_bottombar_height = 15
vim.g.vimspector_terminal_maxwidth = 70

-- Plugins ---------------------------------------------------------------------
require("lazy").setup({
	spec = {
		"vim-airline/vim-airline",
		"vim-airline/vim-airline-themes",

		-- Colorscheme from your X resources (replaces the unmaintained
		-- cshjsc/xresources-nvim). ~/.vimrc runs `colorscheme xresources` when $DISPLAY is set.
		{
			"martineausimon/nvim-xresources",
			lazy = false,
			priority = 1000,
			config = function()
				require("nvim-xresources").setup({})
			end,
		},

		-- tmux/nvim split navigation (replaces alexghergh/nvim-tmux-navigation).
		-- Compatible with the same tmux-side config.
		{
			"christoomey/vim-tmux-navigator",
			init = function()
				vim.g.tmux_navigator_no_mappings = 1
				vim.g.tmux_navigator_disable_when_zoomed = 1
			end,
			cmd = {
				"TmuxNavigateLeft",
				"TmuxNavigateDown",
				"TmuxNavigateUp",
				"TmuxNavigateRight",
				"TmuxNavigatePrevious",
			},
			keys = {
				{ "<C-h>", "<cmd>TmuxNavigateLeft<cr>", silent = true },
				{ "<C-t>", "<cmd>TmuxNavigateDown<cr>", silent = true },
				{ "<C-n>", "<cmd>TmuxNavigateUp<cr>", silent = true },
				{ "<C-s>", "<cmd>TmuxNavigateRight<cr>", silent = true },
				{ "<C-\\>", "<cmd>TmuxNavigatePrevious<cr>", silent = true },
			},
		},

		"rstacruz/vim-closer",

		-- Load on an autocommand event
		{ "andymass/vim-matchup", event = "VimEnter" },

		-- Formatting (replaces mhartington/formatter.nvim)
		{
			"stevearc/conform.nvim",
			event = "BufWritePre",
			cmd = "ConformInfo",
			opts = {
				formatters_by_ft = {
					lua = { "stylua" },
					rust = { "rustfmt" },
				},
				-- Trailing whitespace is already stripped by the BufWritePre autocmd in ~/.vimrc
				format_on_save = { timeout_ms = 500 },
			},
		},

		-- LSP --------------------------------------------------------------------
		{
			"mason-org/mason-lspconfig.nvim",
			dependencies = {
				{ "mason-org/mason.nvim", opts = {} },
				"neovim/nvim-lspconfig", -- provides the default server configs
				"hrsh7th/cmp-nvim-lsp",
			},
			config = function()
				vim.lsp.config("*", {
					capabilities = require("cmp_nvim_lsp").default_capabilities(),
				})
				vim.lsp.config("lua_ls", {
					settings = { Lua = { diagnostics = { globals = { "vim" } } } },
				})
				require("mason-lspconfig").setup({
					ensure_installed = { "lua_ls", "rust_analyzer" },
					-- rustaceanvim starts rust-analyzer itself; enabling it here too would conflict
					automatic_enable = { exclude = { "rust_analyzer" } },
				})
			end,
		},

		-- Rust (replaces the archived simrat39/rust-tools.nvim)
		{
			"mrcjkb/rustaceanvim",
			version = nvim_012 and "^9" or "^8", -- v9 dropped Neovim 0.11
			lazy = false, -- it is already a lazy filetype plugin
			dependencies = { "hrsh7th/cmp-nvim-lsp", "mfussenegger/nvim-dap" },
			init = function()
				vim.g.rustaceanvim = function()
					return {
						server = {
							capabilities = require("cmp_nvim_lsp").default_capabilities(),
							-- on_attach = function(_, bufnr)
							-- 	-- Hover actions
							-- 	vim.keymap.set("n", "<C-space>", function()
							-- 		vim.cmd.RustLsp({ "hover", "actions" })
							-- 	end, { buffer = bufnr })
							-- 	-- Code action groups
							-- 	vim.keymap.set("n", "<Leader>a", function()
							-- 		vim.cmd.RustLsp("codeAction")
							-- 	end, { buffer = bufnr })
							-- end,
						},
					}
				end
			end,
		},

		"mfussenegger/nvim-dap",

		-- Completion ---------------------------------------------------------------
		{
			"hrsh7th/nvim-cmp",
			dependencies = {
				"hrsh7th/cmp-nvim-lsp", -- LSP completion source
				"hrsh7th/cmp-nvim-lua",
				"hrsh7th/cmp-nvim-lsp-signature-help",
				"hrsh7th/cmp-vsnip",
				"hrsh7th/cmp-path",
				"hrsh7th/cmp-buffer",
				"hrsh7th/cmp-calc",
				"hrsh7th/vim-vsnip",
			},
			config = function()
				local cmp = require("cmp")
				cmp.setup({
					-- Enable LSP snippets
					snippet = {
						expand = function(args)
							vim.fn["vsnip#anonymous"](args.body)
						end,
					},
					mapping = {
						["<C-p>"] = cmp.mapping.select_prev_item(),
						["<C-n>"] = cmp.mapping.select_next_item(),
						-- Add tab support
						["<S-Tab>"] = cmp.mapping.select_prev_item(),
						["<Tab>"] = cmp.mapping.select_next_item(),
						["<C-S-f>"] = cmp.mapping.scroll_docs(-4),
						["<C-f>"] = cmp.mapping.scroll_docs(4),
						["<C-Space>"] = cmp.mapping.complete(),
						["<C-e>"] = cmp.mapping.close(),
						["<CR>"] = cmp.mapping.confirm({
							behavior = cmp.ConfirmBehavior.Insert,
							select = true,
						}),
					},
					sources = {
						{ name = "path" }, -- file paths
						{ name = "nvim_lsp", keyword_length = 3 }, -- from language server
						{ name = "nvim_lsp_signature_help" }, -- function signatures, current parameter emphasized
						{ name = "nvim_lua", keyword_length = 2 }, -- neovim's Lua runtime API such vim.lsp.*
						{ name = "buffer", keyword_length = 2 }, -- current buffer
						{ name = "vsnip", keyword_length = 2 }, -- vim-vsnip
						{ name = "calc" }, -- math calculation
					},
					window = {
						completion = cmp.config.window.bordered(),
						documentation = cmp.config.window.bordered(),
					},
					formatting = {
						fields = { "menu", "abbr", "kind" },
						format = function(entry, item)
							local menu_icon = {
								nvim_lsp = "λ",
								vsnip = "⋗",
								buffer = "Ω",
								path = "🖫",
							}
							item.menu = menu_icon[entry.source.name]
							return item
						end,
					},
				})
			end,
		},

		-- Treesitter ---------------------------------------------------------------
		{
			"nvim-treesitter/nvim-treesitter",
			-- `main` is the rewrite (needs Neovim 0.12 + the tree-sitter CLI);
			-- `master` is frozen but still works on 0.11.
			branch = nvim_012 and "main" or "master",
			lazy = false,
			build = ":TSUpdate",
			config = function()
				local parsers = { "c", "cpp", "lua", "rust", "toml" }
				if nvim_012 then
					-- Parsers are compiled with the tree-sitter CLI (0.26.1+). Without it,
					-- skip installing (one warning instead of an error per parser);
					-- already-installed parsers still highlight.
					if vim.fn.executable("tree-sitter") == 1 then
						require("nvim-treesitter").install(parsers)
					else
						vim.notify(
							"nvim-treesitter: `tree-sitter` CLI not found on PATH; skipping parser install",
							vim.log.levels.WARN
						)
					end
					vim.api.nvim_create_autocmd("FileType", {
						group = vim.api.nvim_create_augroup("TreesitterHighlight", { clear = true }),
						callback = function(args)
							pcall(vim.treesitter.start, args.buf)
						end,
					})
				else
					require("nvim-treesitter.configs").setup({
						ensure_installed = parsers,
						auto_install = true,
						highlight = {
							enable = true,
							additional_vim_regex_highlighting = false,
						},
					})
				end
			end,
		},

		{
			"puremourning/vimspector",
			config = function()
				local map = function(key, fn)
					vim.keymap.set("n", key, "<cmd>call vimspector#" .. fn .. "()<cr>")
				end
				map("<F5>", "Continue") -- starts a session if none is running
				map("<F10>", "StepOver")
				map("<F11>", "StepInto")
				map("<F12>", "StepOut")
				map("<F9>", "ToggleBreakpoint")
				map("<F3>", "Reset")
				map("<F4>", "Restart")
				map("<F6>", "Pause")
			end,
		},
	},
	-- None of these plugins need LuaRocks packages. Leaving this on makes lazy.nvim
	-- try to build luarocks via hererocks, which fails with
	-- "{.../lazy-rocks/hererocks/bin/luarocks} not installed".
	rocks = { enabled = false },
	performance = {
		rtp = {
			-- init.vim adds ~/.vim and ~/.vim/after to the runtimepath; keep them.
			reset = false,
		},
	},
	-- Don't nag about updates on every startup
	change_detection = { notify = false },
})
