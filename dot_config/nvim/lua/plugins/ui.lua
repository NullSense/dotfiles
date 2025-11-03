return {
	{
		"ellisonleao/gruvbox.nvim",
		priority = 1000,
		config = function()
			require("gruvbox").setup({
				transparent_mode = true,
			})
			vim.o.background = "dark" -- or "light" for light mode
			vim.cmd([[colorscheme gruvbox]])
		end,
	},
	{
		"echasnovski/mini.icons",
		lazy = false,
		config = function()
			require("mini.icons").setup()
			MiniIcons.mock_nvim_web_devicons()
		end,
	},
	{
		"nvim-lualine/lualine.nvim",
		dependencies = { "echasnovski/mini.icons" },
		config = function()
			require("lualine").setup({
				options = {
					theme = "gruvbox",
					icons_enabled = true,
				},
				sections = {
					lualine_a = {
						{
							"mode",
							fmt = function(str)
								return str:sub(1, 1)
							end,
						},
					},
					lualine_b = {
						{
							"branch",
							fmt = function(str)
								return str:sub(1, 7)
							end,
						},
						"diff",
						"diagnostics",
					},
					lualine_c = { "filename" },
					lualine_x = { "filetype" },
					lualine_y = { "progress" },
					lualine_z = { "location" },
				},
				inactive_sections = {
					lualine_c = { "filename" },
					lualine_x = { "location" },
				},
				tabline = {
					lualine_a = {
						{
							"buffers",
							show_filename_only = true, -- Shows shortened relative path when set to false.
							show_modified_status = true, -- Shows indicator when the buffer is modified.
						},
					},
				},
			})
		end,
	},
	{
		"folke/snacks.nvim",
		priority = 1000,
		lazy = false,
		opts = {
			image = { enabled = false },
			bigfile = { enabled = true },
			dashboard = { enabled = true },
			explorer = { enabled = true },
			indent = { enabled = false },
			input = { enabled = true },
			picker = { enabled = true },
			notifier = {
				enabled = true,
				style = "minimal",
				timeout = 4500,
				lsp_progress = {
					enabled = true,
					throttle = 100, -- Update frequency in ms
					view = "mini", -- or "notify" for larger notifications
				},
			},
			quickfile = { enabled = true },
			scope = { enabled = true },
			statuscolumn = { enabled = true },
			words = { enabled = true },
			styles = {
				notification = {
					wo = { wrap = true }, -- Wrap notifications
				},
			},
		},
	},
	{
		"folke/noice.nvim",
		event = "VeryLazy",
		config = function()
			require("noice").setup({
				lsp = {
					override = {
						["vim.lsp.util.convert_input_to_markdown_lines"] = true,
						["vim.lsp.util.stylize_markdown"] = true,
					},
				},
				presets = {
					command_palette = true, -- position the cmdline and popupmenu together
					long_message_to_split = true, -- long messages will be sent to a split
					lsp_doc_border = true, -- add a border to hover docs and signature help
				},
			})
		end,

		dependencies = {
			"MunifTanjim/nui.nvim",
			"folke/snacks.nvim",
		},
	},
	{
		"rachartier/tiny-inline-diagnostic.nvim",

		event = "VeryLazy", -- Or `LspAttach`
		priority = 1000, -- needs to be loaded in first
		config = function()
			require("tiny-inline-diagnostic").setup()
			vim.diagnostic.config({ virtual_text = false }) -- Only if needed in your configuration, if you already have native LSP diagnostics
		end,
	},
}
