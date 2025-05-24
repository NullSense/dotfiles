-- make preview window disappear after selection
vim.cmd("autocmd CursorMovedI * if pumvisible() == 0|pclose|endif")
vim.cmd("autocmd InsertLeave * if pumvisible() == 0|pclose|endif")

-- Indentation
vim.opt.autoindent = true
vim.opt.smartindent = true
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smarttab = true
vim.cmd('filetype plugin indent on')

-- Vim general
vim.opt.tags = 'tags'
vim.opt.cmdheight = 1
vim.opt.updatetime = 250
vim.opt.shortmess:append({ c = true })
vim.opt.signcolumn = 'yes'
vim.opt.autoread = true
vim.cmd('au CursorHold * checktime')
vim.opt.mouse = 'a'
vim.opt.encoding = 'UTF-8'
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.scrolloff = 8
vim.opt.hlsearch = true
vim.opt.incsearch = true
vim.opt.inccommand = "nosplit"
vim.opt.wrapscan = false
vim.opt.history = 100
vim.opt.autowrite = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.listchars = { tab = '>·', trail = '$', extends = '>', precedes = '<', nbsp = '␣' }
vim.opt.list = true
vim.opt.hidden = true
vim.opt.termguicolors = true
vim.opt.completeopt = 'menuone,noselect'
vim.opt.shada = "!,'300,<50,s10,%"
vim.opt.undodir = os.getenv("HOME") .. "/.config/nvim/undodir"
vim.opt.undofile = true
vim.cmd('syntax on') -- Syntax highlighting

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

if not (vim.uv or vim.loop).fs_stat(lazypath) then
    local lazyrepo = "https://github.com/folke/lazy.nvim.git"
    local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
    if vim.v.shell_error ~= 0 then
        vim.api.nvim_echo({
            { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
            { out, "WarningMsg" },

            { "\nPress any key to exit..." },
        }, true, {})
        vim.fn.getchar()
        os.exit(1)
    end
end

vim.opt.rtp:prepend(lazypath)

-- Make sure to setup `mapleader` and `maplocalleader` before
-- loading lazy.nvim so that mappings are correct.
-- This is also a good place to setup other settings (vim.opt)

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Move through wrapped text easier
vim.api.nvim_set_keymap('n', 'j', 'gj', {})
vim.api.nvim_set_keymap('n', 'k', 'gk', {})

vim.opt.clipboard = 'unnamedplus'
-- Clipboard remaps
vim.keymap.set('n', '<leader>y', '"+y', { noremap = true })
vim.keymap.set('v', '<leader>y', '"+y', { noremap = true })

-- Yank whole file
vim.keymap.set('n', '<leader>Y', 'gg"+yG', {})

-- Paste without replacing yank register
vim.keymap.set('v', '<leader>p', '"_dP', {})

-- Double esc to disable hlsearch
vim.keymap.set('n', '<Esc><Esc>', '<cmd>nohlsearch<CR><Esc>', { noremap = true })

-- Splits and Buffers
-- For easy split navigation (Ctrl + hjkl)
vim.keymap.set('n', '<C-j>', '<C-W><C-J>', { noremap = true })
vim.keymap.set('n', '<C-k>', '<C-W><C-K>', { noremap = true })
vim.keymap.set('n', '<C-l>', '<C-W><C-L>', { noremap = true })
vim.keymap.set('n', '<C-h>', '<C-W><C-H>', { noremap = true })

-- Resize splits
vim.keymap.set('n', '<S-Up>', ':resize +2<CR>', { silent = true })
vim.keymap.set('n', '<S-Down>', ':resize -2<CR>', { silent = true })
vim.keymap.set('n', '<S-Left>', ':vertical resize -2<CR>', { silent = true })
vim.keymap.set('n', '<S-Right>', ':vertical resize +2<CR>', { silent = true })

-- Moving between buffers
vim.keymap.set('n', '<M-l>', ':bn<CR>', {})
vim.keymap.set('n', '<M-h>', ':bprev<CR>', {})

-- Close buffer
vim.keymap.set('n', '<M-d>', ':bp<Bar>bd #<CR>', { noremap = true, silent = true })

-- Move line up/down and align them
vim.keymap.set('n', '<leader>j', ':m .+1<CR>==', { noremap = true, silent = true })
vim.keymap.set('n', '<leader>k', ':m .-2<CR>==', { noremap = true, silent = true })
-- Same but for visual
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")

-- Keeps search words centered
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")

-- replace the word under cursor
vim.keymap.set("n", "<leader>s", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]])

-- make file +x
vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true })

-- On insert and window unfocus, make line numbers non relative
vim.cmd([[
augroup numbertoggle
autocmd!
autocmd BufEnter,FocusGained,InsertLeave,WinEnter * if &nu && mode() != 'i' | set rnu | endif
autocmd BufLeave,FocusLost,InsertEnter,WinLeave   * if &nu                  | set nornu | endif
augroup END
]])

-- restore last cursor position
vim.cmd([[
augroup cursor
autocmd!
autocmd BufReadPost *
\ if line("'\"") >= 1 && line("'\"") <= line("$") && &ft !~# 'commit'
\ |   exe "normal! g`\""
\ | endif
augroup END
]])
vim.o.foldcolumn = '1' -- '0' is not bad
vim.o.foldlevel = 99   -- Using ufo provider need a large value, feel free to decrease the value
vim.o.foldlevelstart = 99
vim.o.foldenable = true
-------------
-- Plugins --
-------------
require("lazy").setup({
    { "ellisonleao/gruvbox.nvim", priority = 1000 , config = true},
    {"neovim/nvim-lspconfig",},
    {
        "williamboman/mason.nvim",
        opts = {}
    },
    {
        "williamboman/mason-lspconfig.nvim",
        opts = {},
        dependencies = {
            "williamboman/mason.nvim",
            "neovim/nvim-lspconfig",

        },

    },
    {
        'stevearc/conform.nvim',
        opts = {},
    },
    {
        'saghen/blink.nvim',
        build = 'cargo build --release', -- for delimiters
        keys = {
            -- chartoggle
            {
                '<C-;>',
                function()
                    require('blink.chartoggle').toggle_char_eol(';')
                end,
                mode = { 'n', 'v' },
                desc = 'Toggle ; at eol',
            },
            {
                ',',
                function()
                    require('blink.chartoggle').toggle_char_eol(',')
                end,
                mode = { 'n', 'v' },
                desc = 'Toggle , at eol',
            },

            -- tree
            { '<leader>n', '<cmd>BlinkTree toggle<cr>', desc = 'Reveal current file in tree' },
        },
        -- all modules handle lazy loading internally
        lazy = false,
        opts = {
            chartoggle = { enabled = true },
            indent = { enabled = true },
            signature = { enabled = true },
            tree = { enabled = true }
        }
    },
    {
        'saghen/blink.cmp',
        -- optional: provides snippets for the snippet source
        dependencies = { 'rafamadriz/friendly-snippets' },

        -- use a release tag to download pre-built binaries
        version = '1.*',
        opts = {
            keymap = { preset = 'super-tab' },

            appearance = {
                nerd_font_variant = 'mono'
            },
            -- (Default) Only show the documentation popup when manually triggered
            completion = { documentation = { auto_show = true } },

            sources = {
                default = { 'lsp', 'path', 'snippets', 'buffer' },
            },
            fuzzy = { implementation = "prefer_rust_with_warning" }
        },
        opts_extend = { "sources.default" }
    },
    {
        "mfussenegger/nvim-lint",
        event = { "BufWritePost", "InsertLeave", "BufEnter" }, -- lazy-load on relevant events

        config = function()
            require("lint").linters_by_ft = {
                python = { "ruff" },
                javascript = { "eslint_d" },
                typescript = { "eslint_d" },
                html = { "htmlhint" },
                css = { "stylelint" },
            }
            -- Auto-lint on save, insert leave, or buffer enter,
            local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })
            vim.api.nvim_create_autocmd({ "BufWritePost", "InsertLeave", "BufEnter" }, {
                group = lint_augroup,
                callback = function()
                    require("lint").try_lint()

                end,
            })

            -- Optional: manual trigger
            vim.keymap.set("n", "<leader>ln", function()

                require("lint").try_lint()
            end, { desc = "Trigger linting for current file" })
        end,
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
    {
        'echasnovski/mini.icons',
        lazy = false,
        config = function()
            require('mini.icons').setup()
            -- This is the crucial part:
            MiniIcons.mock_nvim_web_devicons()
            print("mini.icons setup and nvim-web-devicons mocked.") -- For debugging
        end,
    },
    {
        'nvim-lualine/lualine.nvim',
        dependencies = { 'echasnovski/mini.icons' }, -- 'nvim-tree/nvim-web-devicons' can often be omitted here
        options = { theme = 'gruvbox' },
        config = function()
            require('lualine').setup {
                options = {
                    theme = 'gruvbox',
                    icons_enabled = true,
                },
                sections = {
                    lualine_a = { { 'mode', fmt = function(str) return str:sub(1, 1) end } },
                    lualine_b = { { 'branch', fmt = function(str) return str:sub(1, 7) end }, 'diff', 'diagnostics' },
                    lualine_c = { 'filename' },
                    lualine_x = { 'filetype' },
                    lualine_y = { 'progress' },
                    lualine_z = { 'location' }
                },
                inactive_sections = {
                    lualine_c = { 'filename' },
                    lualine_x = { 'location' },
                },
                tabline = {
                    lualine_a = {
                        {
                            'buffers',
                            show_filename_only = true,   -- Shows shortened relative path when set to false.
                            show_modified_status = true, -- Shows indicator when the buffer is modified.
                        }
                    }
                },
            }
            print("lualine setup complete.") -- For debugging
        end,
    },
    {
        "ibhagwan/fzf-lua",
        -- optional for icon support
        dependencies = { "echasnovski/mini.icons" },
        opts = {}
    },
    { 'kevinhwang91/nvim-ufo', dependencies = 'kevinhwang91/promise-async' },
    { "lewis6991/gitsigns.nvim", opts = {} },
    "andymass/vim-matchup",
    {
        "folke/noice.nvim",
        event = "VeryLazy",
        opts = {
            -- add any options here
        },
        dependencies = {
            -- if you lazy-load any plugin below, make sure to add proper `module="..."` entries
            "MunifTanjim/nui.nvim",
            -- OPTIONAL:
            --   `nvim-notify` is only needed, if you want to use the notification view.
            --   If not available, we use `mini` as the fallback
            "rcarriga/nvim-notify",
        }
    },
    {
        "folke/flash.nvim",

        event = "VeryLazy",
        ---@type Flash.Config
        opts = {},
        -- stylua: ignore
        keys = {
            { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
            { "S", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
            { "r", mode = "o", function() require("flash").remote() end, desc = "Remote Flash" },

            { "R", mode = { "o", "x" }, function() require("flash").treesitter_search() end, desc = "Treesitter Search" },
            { "<c-s>", mode = { "c" }, function() require("flash").toggle() end, desc = "Toggle Flash Search" },
        },
    },
    "onsails/lspkind-nvim",
    { "kevinhwang91/nvim-hlslens",   config = function() require("hlslens").setup {} end },
    "editorconfig/editorconfig-vim",
    "numToStr/Comment.nvim",
    {
        "nvim-treesitter/nvim-treesitter",
        opts = {
            ensure_installed = { "python", "javascript", "vim", "comment", "awk", "bash", "cmake", "css", "diff",
            "dockerfile", "dot", "gitconfig", "gitignore", "gitcommit", "gitattributes", "html", "json",
            "htmldjango", "http", "jq", "jsdoc", "json5", "lua", "luadoc", "markdown_inline", "regex", "rust", "sql",
            "todotxt", "typescript", "yaml" },
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
        build = ':TSUpdate'
    },
    "romgrk/nvim-treesitter-context",
    "machakann/vim-sandwich",
    { "norcalli/nvim-colorizer.lua", config = function() require("colorizer").setup {} end },
    { "windwp/nvim-autopairs",       config = function() require("nvim-autopairs").setup {} end },
    {
        "MeanderingProgrammer/render-markdown.nvim",
        dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.nvim" }, -- mini.icons
        config = function()
            require("render-markdown").setup({})
        end,
        ft = "markdown",
    },
    {
        "szw/vim-maximizer",
        keys = {
            { "<leader>z", "<cmd>MaximizerToggle<cr>", desc = "Maximizer" },
        },
    },
    {
        "yetone/avante.nvim",
        event = "VeryLazy",
        version = false, -- Never set this value to "*"! Never!
        opts = {
            -- add any opts here
            -- for example
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
        -- if you want to build from source then do `make BUILD_FROM_SOURCE=true`
        build = "make",
        -- build = "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false" -- for windows
        dependencies = {
            "nvim-treesitter/nvim-treesitter",
            "stevearc/dressing.nvim",
            {
                "hedyhli/outline.nvim",
                lazy = true,
                cmd = { "Outline", "OutlineOpen" },
                keys = { -- Example mapping to toggle outline
                    { "<leader>o", "<cmd>Outline<CR>", desc = "Toggle outline" },

                },

                opts = {
                    -- Your setup opts here
                },
            },
            "nvim-lua/plenary.nvim",
            "MunifTanjim/nui.nvim",
            --- The below dependencies are optional,
            "echasnovski/mini.pick", -- for file_selector provider mini.pick

            "ibhagwan/fzf-lua", -- for file_selector provider fzf
            "echasnovski/mini.icons",
            "zbirenbaum/copilot.lua",
            {

                -- support for image pasting
                "HakonHarnes/img-clip.nvim",
                event = "VeryLazy",
                opts = {

                    -- recommended settings
                    default = {
                        embed_image_as_base64 = false,
                        prompt_for_file_name = false,
                        drag_and_drop = {
                            insert_mode = true,

                        },

                        -- required for Windows users
                        use_absolute_path = true,
                    },
                },
            },
        },
    },
})

vim.o.background = "dark" -- or "light" for light mode
vim.cmd([[colorscheme gruvbox]])

require("outline").setup({})
require("Comment").setup()
require("conform").setup({
    formatters_by_ft = {
        lua = { "stylua" },
        python = { "ruff" },
        rust = { "rustfmt", lsp_format = "fallback" },
        javascript = { "prettierd", "prettier", stop_after_first = true },
        html = { "prettier" },
        css = { "prettier" },
    },
})
require("noice").setup({
    lsp = {
        override = {
            ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
            ["vim.lsp.util.stylize_markdown"] = true,
        },
    },
    -- you can enable a preset for easier configuration
    presets = {
        bottom_search = true, -- use a classic bottom cmdline for search
        command_palette = true, -- position the cmdline and popupmenu together
        long_message_to_split = true, -- long messages will be sent to a split
        inc_rename = false, -- enables an input dialog for inc-rename.nvim
        lsp_doc_border = false, -- add a border to hover docs and signature help
    },
})

-- Using ufo provider need remap `zR` and `zM`. If Neovim is 0.6.1, remap yourself
vim.keymap.set('n', 'zR', require("ufo").openAllFolds)
vim.keymap.set('n', 'zM', require("ufo").closeAllFolds)
require("ufo").setup()

-- fzf-lua
vim.keymap.set("n", "<C-\\>", function() require("fzf-lua").buffers() end, { desc = "FZF: Buffers" })
vim.keymap.set("n", "<C-p>", function() require("fzf-lua").files() end, { desc = "FZF: Files" })
vim.keymap.set("n", "<leader>l", function() require("fzf-lua").live_grep_glob() end, { desc = "FZF: Live Grep" })
vim.keymap.set("n", "<C-g>", function() require("fzf-lua").grep_project() end, { desc = "FZF: Grep Project" })
vim.keymap.set("n", "<F1>", function() require("fzf-lua").help_tags() end, { desc = "FZF: Help Tags" })

require'fzf-lua'.setup {
    winopts = { height = 0.85, width = 0.80 },
    keymap = {
        builtin = { ["<M-j>"] = "preview-page-down", ["<M-k>"] = "preview-page-up" },
    },
}

vim.g.python3_host_prog = '/usr/bin/python3'

vim.notify("Neovim config loaded!", vim.log.levels.INFO, {title = "Neovim Startup"})
