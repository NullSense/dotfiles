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
		},
		lazy = false,
		opts = {
			chartoggle = { enabled = true },
			signature = { enabled = true },
			-- tree submodule removed — blink.tree is upstream-alpha (stale ~7mo,
			-- README states a rewrite is planned, no follow-current-file API).
			-- Replaced by neo-tree.nvim spec below for a maintained sidebar.
		},
	},
	-- neo-tree.nvim — maintained sidebar file explorer with native
	-- follow-current-file. Spec is straight from upstream v3.x README;
	-- `lazy = false` is recommended by neo-tree itself ("neo-tree will lazily
	-- load itself") because the plugin manages its own lazy bootstrap.
	{
		"nvim-neo-tree/neo-tree.nvim",
		branch = "v3.x",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"MunifTanjim/nui.nvim",
			-- nvim-web-devicons is optional; we use mini.icons in mock mode
			-- (see plugins/ui.lua) which provides the web-devicons API neo-tree
			-- looks for, so no extra icon dep is needed.
		},
		lazy = false,
		opts = {
			-- Auto-locates the active buffer in the tree on every BufEnter
			-- while the tree is open. Equivalent to nvim-tree's
			-- `update_focused_file.enable = true`.
			follow_current_file = { enabled = true },
			filesystem = {
				filtered_items = {
					-- Mirrors the show_hidden = true behavior of yazi.toml.
					hide_dotfiles = false,
				},
			},
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
	-- numToStr/Comment.nvim removed: Neovim 0.10+ provides native `gc` / `gcc`
	-- / `gcap` commentary out of the box with identical bindings.
	-- editorconfig/editorconfig-vim removed: Neovim 0.9+ supports .editorconfig
	-- natively via its built-in editorconfig integration (`:help editorconfig`).
	{
		-- maintained Lua replacement for szw/vim-maximizer (vimscript). Spec
		-- copied from the project README.
		"declancm/maximize.nvim",
		config = true,
		keys = {
			{ "<leader>z", "<cmd>Maximize<cr>", desc = "Maximize window" },
		},
	},
	{
		-- active fork of the original norcalli/nvim-colorizer.lua (which has
		-- been stale ~2 years). Config copied from the README's `options`
		-- structured-config block: enables hex/rgb/hsl/oklch/css-var via the
		-- `css` preset, and adds Tailwind color-name parsing.
		"catgoose/nvim-colorizer.lua",
		event = "BufReadPre",
		opts = {
			options = {
				parsers = {
					css = true,
					tailwind = { enable = true },
				},
			},
		},
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
		-- replaces iamcco/markdown-preview.nvim (browser-based preview, slow
		-- to update, requires yarn build). render-markdown.nvim renders
		-- headings / code-fence backgrounds / tables / checkboxes / link icons
		-- directly in the buffer using treesitter. Spec straight from the
		-- README; depends on the markdown + markdown_inline parsers which are
		-- already in plugins/editor.lua's nvim-treesitter `parsers` list.
		-- mini.icons is provided by plugins/ui.lua.
		"MeanderingProgrammer/render-markdown.nvim",
		ft = { "markdown" },
		dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.icons" },
		opts = {},
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
