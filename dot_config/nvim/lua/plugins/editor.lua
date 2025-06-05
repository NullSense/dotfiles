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
			indent = { enabled = true },
			signature = { enabled = true },
			tree = { enabled = true },
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
		opts = {
			workspaces = {
				{
					name = "Meditation",
					path = "/mnt/c/Users/matas/OneDrive/Documents/MEDITATION",
				},
			},
		},
		keys = {
			{
				mode = "v",
				"<leader>on",
				"<cmd>Obsidian extract_note<cr>",
			},
		},
	},
	{
		"yetone/avante.nvim",
		event = "VeryLazy",
		version = false,
		opts = {
			provider = "openai",
			openai = {
				endpoint = "https://api.openai.com/v1",
				model = "gpt-4o", -- your desired model (or use gpt-4o, etc.)
				timeout = 30000, -- Timeout in milliseconds, increase this for reasoning models
				temperature = 0,
				max_completion_tokens = 8192, -- Increase this to include reasoning tokens (for reasoning models)
				--reasoning_effort = "medium", -- low|medium|high, only used for reasoning models
			},
		},
		build = "make",
		dependencies = {
			"nvim-treesitter/nvim-treesitter",
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
						lsp_progress = {
							enabled = true,
							throttle = 100, -- Update frequency in ms
							view = "mini", -- or "notify" for larger notifications
						},
					},
					quickfile = { enabled = true },
					scope = { enabled = true },
					scroll = {
						enabled = true,
						animate = {
							duration = { total = 75 },
							easing = "linear",
						},
					},
					statuscolumn = { enabled = true },
					words = { enabled = true },
				},
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
			"nvim-lua/plenary.nvim",
			"MunifTanjim/nui.nvim",
			"echasnovski/mini.pick", -- for file_selector provider mini.pick
			"ibhagwan/fzf-lua", -- for file_selector provider fzf
			"echasnovski/mini.icons",
			"zbirenbaum/copilot.lua",
			{
				"HakonHarnes/img-clip.nvim",
				event = "VeryLazy",
				opts = {
					default = {
						embed_image_as_base64 = false,
						prompt_for_file_name = false,
						drag_and_drop = {
							insert_mode = true,
						},
						use_absolute_path = true,
					},
				},
			},
		},
	},
}
