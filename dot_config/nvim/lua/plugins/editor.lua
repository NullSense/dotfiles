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
		-- IN-BUFFER rendering (always on while editing markdown). Renders
		-- headings, code-fence backgrounds, tables, checkboxes, callouts,
		-- bullets, LaTeX and link icons directly in the buffer via treesitter.
		-- Pairs with live-preview.nvim below, which gives an on-demand,
		-- full-fidelity browser preview (Mermaid, KaTeX, exact GitHub CSS).
		-- Depends on the markdown + markdown_inline parsers (already in the
		-- nvim-treesitter `parsers` list above). mini.icons from plugins/ui.lua.
		"MeanderingProgrammer/render-markdown.nvim",
		ft = { "markdown" },
		dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.icons" },
		opts = {
			heading = {
				sign = true,
				icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
			},
			code = {
				sign = false,
				width = "block",
				right_pad = 1,
				border = "thin",
				language_icon = true,
				language_name = true,
			},
			bullet = {
				icons = { "●", "○", "◆", "◇" },
			},
			checkbox = {
				enabled = true,
				unchecked = { icon = "󰄱 " },
				checked = { icon = "󰱒 " },
			},
			pipe_table = {
				preset = "round",
			},
			link = {
				image = "󰥶 ",
				email = "󰀓 ",
				hyperlink = "󰌹 ",
			},
		},
		keys = {
			{ "<leader>mt", "<cmd>RenderMarkdown buf_toggle<cr>", desc = "Markdown: toggle in-buffer render" },
		},
	},
	{
		-- ON-DEMAND browser preview. Pure-Lua backend (no Node/Deno/yarn
		-- build to break, which is why iamcco/markdown-preview.nvim was
		-- dropped). Live updates as you type, scroll sync, KaTeX math,
		-- Mermaid diagrams, working internal/relative links, GitHub CSS.
		-- Also previews HTML/CSS/JS, AsciiDoc and SVG. fzf-lua (already in
		-- this file) powers `:LivePreview pick`.
		"brianhuster/live-preview.nvim",
		dependencies = { "ibhagwan/fzf-lua" },
		cmd = "LivePreview",
		ft = { "markdown", "html", "asciidoc", "svg" },
		opts = {
			port = 5500,
			browser = "default",
			-- true: webroot = the open file's own directory, URL = its basename.
			-- Means `:LivePreview start` always previews the current buffer no
			-- matter what :pwd is (and sibling images/links resolve). Tradeoff:
			-- parent-dir links (`../other.md`) won't resolve; if you need
			-- repo-wide relative links, set this false and `:cd` to the repo root.
			dynamic_root = true,
			sync_scroll = true,
		},
		config = function(_, opts)
			require("livepreview.config").set(opts)
		end,
		keys = {
			{ "<leader>mp", "<cmd>LivePreview start<cr>", desc = "Markdown: browser preview (start)" },
			{ "<leader>ms", "<cmd>LivePreview close<cr>", desc = "Markdown: browser preview (stop)" },
			{ "<leader>mf", "<cmd>LivePreview pick<cr>", desc = "Markdown: pick file to preview" },
		},
	},
}
