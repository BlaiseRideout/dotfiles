vim.cmd([[packadd packer.nvim]])

return require("packer").startup(function(use)
	--   -- Packer can manage itself
	use("wbthomason/packer.nvim")

	use({
		"alexghergh/nvim-tmux-navigation",
		config = function()
			require("nvim-tmux-navigation").setup({
				disable_when_zoomed = true, -- defaults to false
				keybindings = {
					left = "<C-h>",
					down = "<C-t>",
					up = "<C-n>",
					right = "<C-s>",
					last_active = "<C-\\>",
					-- next = "<C-Space>",
				},
			})
		end,
	})

	-- Simple plugins can be specified as strings
	use("rstacruz/vim-closer")

	-- Load on an autocommand event
	use({ "andymass/vim-matchup", event = "VimEnter" })

	require("packer").use({ "mhartington/formatter.nvim" })

	-- Utilities for creating configurations
	local util = require("formatter.util")

	-- Provides the Format, FormatWrite, FormatLock, and FormatWriteLock commands
	require("formatter").setup({
		-- Enable or disable logging
		logging = true,
		-- Set the log level
		log_level = vim.log.levels.WARN,
		-- All formatter configurations are opt-in
		filetype = {
			-- Formatter configurations for filetype "lua" go here
			-- and will be executed in order
			lua = {
				-- "formatter.filetypes.lua" defines default configurations for the
				-- "lua" filetype
				require("formatter.filetypes.lua").stylua,
			},

			rust = {
				-- "formatter.filetypes.lua" defines default configurations for the
				-- "lua" filetype
				require("formatter.filetypes.rust").rustfmt,
			},

			-- Use the special "*" filetype for defining formatter configurations on
			-- any filetype
			["*"] = {
				-- "formatter.filetypes.any" defines default configurations for any
				-- filetype
				require("formatter.filetypes.any").remove_trailing_whitespace,
			},
		},
	})
	vim.cmd([[
  augroup FormatAutogroup
  autocmd!
  autocmd BufWritePost * FormatWrite
  augroup END
  ]])

	use({
		"williamboman/mason.nvim",
		"williamboman/mason-lspconfig.nvim",
	})
	use({
		"neovim/nvim-lspconfig",
		config = function()
			require("mason").setup()
			require("mason-lspconfig").setup({
				ensure_installed = { "sumneko_lua", "rust_analyzer" },
				automatic_installation = true,
			})
			require("mason-lspconfig").setup_handlers({
				["rust_analyzer"] = function()
					require("rust-tools").setup({})
				end,
			})
		end,
	})
	use({
		"simrat39/rust-tools.nvim",
		config = function()
			local rt = require("rust-tools")

			rt.setup({
				server = {
					on_attach = function(_, bufnr)
						-- Hover actions
						-- vim.keymap.set("n", "<C-space>", rt.hover_actions.hover_actions, { buffer = bufnr })
						-- Code action groups
						vim.keymap.set("n", "<Leader>a", rt.code_action_group.code_action_group, { buffer = bufnr })
					end,
				},
			})
		end,
	})

	use("mfussenegger/nvim-dap")

	-- Completion framework:
	use("hrsh7th/nvim-cmp")

	-- LSP completion source:
	use("hrsh7th/cmp-nvim-lsp")

	-- Useful completion sources:
	use("hrsh7th/cmp-nvim-lua")
	use("hrsh7th/cmp-nvim-lsp-signature-help")
	use("hrsh7th/cmp-vsnip")
	use("hrsh7th/cmp-path")
	use("hrsh7th/cmp-buffer")
	use("hrsh7th/vim-vsnip")

	use({
		"nvim-treesitter/nvim-treesitter",
		config = function()
			-- Treesitter Plugin Setup
			require("nvim-treesitter.configs").setup({
				ensure_installed = { "c", "cpp", "lua", "rust", "toml" },
				auto_install = true,
				highlight = {
					enable = true,
					additional_vim_regex_highlighting = false,
				},
				ident = { enable = true },
				rainbow = {
					enable = true,
					extended_mode = true,
					max_file_lines = nil,
				},
			})
		end,
	})

	--Set completeopt to have a better completion experience
	-- :help completeopt
	-- menuone: popup even when there's only one match
	-- noinsert: Do not insert text until a selection is made
	-- noselect: Do not select, force to select one from the menu
	-- shortness: avoid showing extra messages when using completion
	-- updatetime: set updatetime for CursorHold
	vim.opt.completeopt = { "menuone", "noselect", "noinsert" }
	vim.opt.shortmess = vim.opt.shortmess + { c = true }
	vim.api.nvim_set_option("updatetime", 300)

	-- Fixed column for diagnostics to appear
	-- Show autodiagnostic popup on cursor hover_range
	-- Goto previous / next diagnostic warning / error
	-- Show inlay_hints more frequently
	vim.cmd([[
  set signcolumn=yes
  autocmd CursorHold * lua vim.diagnostic.open_float(nil, { focusable = false })
  ]])

	-- Completion Plugin Setup
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
		-- Installed sources:
		sources = {
			{ name = "path" }, -- file paths
			{ name = "nvim_lsp", keyword_length = 3 }, -- from language server
			{ name = "nvim_lsp_signature_help" }, -- display function signatures with current parameter emphasized
			{ name = "nvim_lua", keyword_length = 2 }, -- complete neovim's Lua runtime API such vim.lsp.*
			{ name = "buffer", keyword_length = 2 }, -- source current buffer
			{ name = "vsnip", keyword_length = 2 }, -- nvim-cmp source for vim-vsnip
			{ name = "calc" }, -- source for math calculation
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

	-- Treesitter folding
	vim.wo.foldmethod = "expr"
	vim.wo.foldexpr = "nvim_treesitter#foldexpr()"
end)
