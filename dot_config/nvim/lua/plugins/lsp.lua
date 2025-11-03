return {
	{ "neovim/nvim-lspconfig" },
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"biome",
				"marksman",
				"markdownlint-cli2",
				"selene",
				"lua-language-server",
				"stylua",
				"clippy",
				"ruff",
			},
		},
	},
	{
		"williamboman/mason-lspconfig.nvim",
		opts = {
			ensure_installed = {
				"lua_ls",
				"marksman",
				"rust_analyzer",
				"basedpyright",
				"html",
				"cssls",
			},
		},
		config = function(_, opts)
			require("mason-lspconfig").setup(opts)

			-- Enable all installed LSP servers using modern Neovim 0.11+ API
			local servers = opts.ensure_installed
			for _, server in ipairs(servers) do
				vim.lsp.enable(server)
			end
		end,
		dependencies = {
			"williamboman/mason.nvim",
			"neovim/nvim-lspconfig",
		},
	},
	{
		"stevearc/conform.nvim",
		config = function()
			require("conform").setup({
				formatters_by_ft = {
					lua = { "stylua" },
					python = { "ruff" },
					rust = { "rustfmt", lsp_format = "fallback" },
					javascript = { "biome", "prettierd", "prettier", stop_after_first = true },
					typescript = { "biome", "prettierd", "prettier", stop_after_first = true },
					javascriptreact = { "biome", "prettierd", "prettier", stop_after_first = true },
					typescriptreact = { "biome", "prettierd", "prettier", stop_after_first = true },
					json = { "biome", "prettierd", "prettier", stop_after_first = true },
					html = { "prettierd" },
					css = { "prettierd" },
					markdown = { "prettierd" },
				},
				formatters = {
					biome = {
						require_cwd = true, -- Only use biome if biome.json exists
					},
				},
				format_on_save = {
					timeout_ms = 500,
					lsp_format = "fallback",
				},
			})
		end,
	},

	{
		"mfussenegger/nvim-lint",
		event = { "BufWritePost", "InsertLeave", "BufEnter" },
		config = function()
			require("lint").linters_by_ft = {
				python = { "ruff" },
				rust = { "clippy" },
				lua = { "selene" },
				javascript = { "biomejs", "eslint_d" },
				typescript = { "biomejs", "eslint_d" },
				javascriptreact = { "biomejs", "eslint_d" },
				typescriptreact = { "biomejs", "eslint_d" },
				html = { "htmlhint" },
				css = { "stylelint" },
				markdown = { "markdownlint-cli2" },
			}
			-- Note: AutoLint autocmd is configured in config/autocmds.lua to avoid duplication
		end,
	},

	{
		"saghen/blink.cmp",
		dependencies = { "rafamadriz/friendly-snippets" },
		-- use a release tag to download pre-built binaries
		version = "1.*",
		opts = {
			keymap = {
				preset = "super-tab",
			},
			appearance = {
				nerd_font_variant = "mono",
			},
			completion = {
				documentation = {
					auto_show = true,
					window = {
						border = "rounded",
					},
				},
			},
			signature = {
				enabled = true,
				trigger = {
					blocked_trigger_characters = {},
					blocked_retrigger_characters = {},
					show_on_insert_on_trigger_character = true,
				},
				window = {
					max_width = 100,
					max_height = 10,
					border = "rounded",
					scrollbar = true,
				},
			},
			sources = {
				default = { "lsp", "path", "snippets", "buffer" },
			},
			fuzzy = { implementation = "prefer_rust_with_warning" },
		},
		opts_extend = { "sources.default" },
	},
	{
		"folke/trouble.nvim",
		opts = {}, -- for default options, refer to the configuration section for custom setup.
		cmd = "Trouble",
		keys = {
			{
				"<leader>xx",
				"<cmd>Trouble diagnostics toggle<cr>",
				desc = "Diagnostics (Trouble)",
			},
			{
				"<leader>xX",
				"<cmd>Trouble diagnostics toggle filter.buf=0<cr>",
				desc = "Buffer Diagnostics (Trouble)",
			},
			{
				"<leader>cs",
				"<cmd>Trouble symbols toggle focus=false<cr>",
				desc = "Symbols (Trouble)",
			},
			{
				"<leader>cl",
				"<cmd>Trouble lsp toggle focus=false win.position=right<cr>",
				desc = "LSP Definitions / references / ... (Trouble)",
			},
			{
				"<leader>xL",
				"<cmd>Trouble loclist toggle<cr>",
				desc = "Location List (Trouble)",
			},
			{
				"<leader>xQ",
				"<cmd>Trouble qflist toggle<cr>",
				desc = "Quickfix List (Trouble)",
			},
		},
	},
	"onsails/lspkind-nvim",
}
