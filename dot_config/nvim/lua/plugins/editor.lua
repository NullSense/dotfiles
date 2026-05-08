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
		-- master branch is archived upstream; main is the canonical branch.
		-- Main has a modular API: parsers via require('nvim-treesitter').install,
		-- highlight via vim.treesitter.start() in a FileType autocmd.
		branch = "main",
		lazy = false,
		build = ":TSUpdate",
		config = function()
			local parsers = {
				"python", "javascript", "typescript", "tsx", "vim", "vimdoc",
				"comment", "awk", "bash", "cmake", "css", "diff", "dockerfile",
				"dot", "gitconfig", "gitignore", "gitcommit", "gitattributes",
				"html", "json", "json5", "htmldjango", "http", "jq", "jsdoc",
				"lua", "luadoc", "markdown", "markdown_inline", "regex", "rust",
				"sql", "todotxt", "yaml", "toml", "query", "c",
			}

			require("nvim-treesitter").install(parsers)

			-- Map filetypes to parsers Treesitter would not otherwise pick up
			-- automatically (vim's filetype != parser name in some cases).
			local ft_to_parser = {
				htmldjango = "htmldjango",
				gitcommit = "gitcommit",
				["markdown.mdx"] = "markdown",
			}

			vim.api.nvim_create_autocmd("FileType", {
				callback = function(args)
					local ft = vim.bo[args.buf].filetype
					local lang = ft_to_parser[ft] or vim.treesitter.language.get_lang(ft) or ft
					if not lang or lang == "" then return end
					-- Start syntax highlighting if a parser is available.
					local ok = pcall(vim.treesitter.start, args.buf, lang)
					if ok then
						-- Treesitter-driven folding (built-in).
						vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
						vim.wo.foldmethod = "expr"
						-- Treesitter-driven indent (experimental, provided by main branch).
						vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
					end
				end,
			})
		end,
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
