return {
	{
		"saghen/blink.nvim",
		build = "cargo build --release", -- for delimiters
		keys = {
			{
				"<C-;>",
				function()
					require("blink.chartoggle").toggle_char_eol(";")
				end,
				mode = { "n", "v" },
				desc = "Toggle ; at eol",
			},
			{
				",",
				function()
					require("blink.chartoggle").toggle_char_eol(",")
				end,
				mode = { "n", "v" },
				desc = "Toggle , at eol",
			},
			{
				"<leader>n",
				"<cmd>BlinkTree toggle<cr>",
				desc = "Reveal current file in tree",
			},
		},
		lazy = false,
		opts = {
			chartoggle = { enabled = true },
			signature = { enabled = true },
			tree = { enabled = true },
		},
	},
	{
		"saghen/blink.indent",
		opts = {
			-- Default configuration is sufficient, plugin auto-initializes
			enabled = true,
		},
	},
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"python",
				"javascript",
				"vim",
				"comment",
				"awk",
				"bash",
				"cmake",
				"css",
				"diff",
				"dockerfile",
				"dot",
				"gitconfig",
				"gitignore",
				"gitcommit",
				"gitattributes",
				"html",
				"json",
				"htmldjango",
				"http",
				"jq",
				"jsdoc",
				"json5",
				"lua",
				"luadoc",
				"markdown_inline",
				"regex",
				"rust",
				"sql",
				"todotxt",
				"typescript",
				"yaml",
			},
			auto_install = true,
			incremental_selection = { enable = true },
			highlight = { enable = true },
			rainbow = { enable = true },
			autotag = { enable = true },
			context_commentstring = { enable = true, enable_autocmd = false },
			refactor = {
				highlight_definitions = { enable = true },
				highlight_current_scope = { enable = true },
				smart_rename = { enable = false },
			},
		},
		build = ":TSUpdate",
	},
	{
		"hedyhli/outline.nvim",
		lazy = true,
		cmd = { "Outline", "OutlineOpen" },
		keys = {
			{ "<leader>o", "<cmd>Outline<CR>", desc = "Toggle outline" },
		},
		config = function()
			require("outline").setup({})
		end,
	},
	"romgrk/nvim-treesitter-context",
	"andymass/vim-matchup",
	"bullets-vim/bullets.vim",
	{
		"folke/flash.nvim",
		event = "VeryLazy",
		---@type Flash.Config
		opts = {},
		keys = {
			{
				"s",
				mode = { "n", "x", "o" },
				function()
					require("flash").jump()
				end,
				desc = "Flash",
			},
		},
	},
	{
		"kylechui/nvim-surround",
		version = "^3.0.0",
		event = "VeryLazy",
		config = function()
			require("nvim-surround").setup({
				keymaps = {
					visual = "S",
				},
			})
		end,
	},
	{
		"windwp/nvim-autopairs",
		config = function()
			require("nvim-autopairs").setup({})
		end,
	},
	{
		"numToStr/Comment.nvim",
		config = function()
			require("Comment").setup()
		end,
	},
	"editorconfig/editorconfig-vim",
	{
		"szw/vim-maximizer",
		keys = {
			{ "<leader>z", "<cmd>MaximizerToggle<cr>", desc = "Maximizer" },
		},
	},
	{
		"norcalli/nvim-colorizer.lua",
		config = function()
			require("colorizer").setup({})
		end,
	},
	{
		"ibhagwan/fzf-lua",
		dependencies = { "echasnovski/mini.icons" },
		config = function()
			require("fzf-lua").setup({
				winopts = { height = 0.85, width = 0.80 },
				keymap = {
					builtin = {
						["<M-j>"] = "preview-page-down",
						["<M-k>"] = "preview-page-up",
					},
				},
			})
		end,
	},
	{
		"iamcco/markdown-preview.nvim",
		cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
		build = "cd app && yarn install",
		init = function()
			vim.g.mkdp_filetypes = { "markdown" }
		end,
		ft = { "markdown" },
	},
	{
		"epwalsh/obsidian.nvim",
		version = "*", -- recommended, use latest release instead of latest commit
		lazy = true,
		ft = "markdown",
		dependencies = {
			"nvim-lua/plenary.nvim",
		},
		opts = function()
			-- Check if WSL path exists, fallback to home directory
			local meditation_path = "/mnt/c/Users/matas/OneDrive/Documents/MEDITATION"
			local fallback_path = vim.fn.expand("~/Documents/MEDITATION")

			local path_to_use = vim.fn.isdirectory(meditation_path) == 1 and meditation_path or fallback_path

			return {
				workspaces = {
					{
						name = "Meditation",
						path = path_to_use,
					},
				},
			}
		end,
		keys = {
			{
				mode = "v",
				"<leader>on",
				"<cmd>Obsidian extract_note<cr>",
			},
		},
	},
}
