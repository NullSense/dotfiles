local keymap = vim.keymap.set
local opts = { noremap = true, silent = true }

-- ================================
-- MOVEMENT & NAVIGATION
-- ================================

-- Move through wrapped text easier
keymap("n", "j", "gj", opts)
keymap("n", "k", "gk", opts)

-- Keeps search words centered
keymap("n", "n", "nzzzv", opts)
keymap("n", "N", "Nzzzv", opts)

-- ================================
-- CLIPBOARD OPERATIONS
-- ================================

-- Copy to system clipboard
keymap("n", "<leader>y", '"+y', { desc = "Copy to system clipboard" })
keymap("v", "<leader>y", '"+y', { desc = "Copy selection to system clipboard" })

-- Yank whole file
keymap("n", "<leader>Y", 'gg"+yG', { desc = "Copy entire file to system clipboard" })

-- Paste without replacing yank register
keymap("v", "<leader>p", '"_dP', { desc = "Paste without losing register" })

-- ================================
-- BLACK HOLE REGISTER OPERATIONS
-- ================================

-- Delete to black hole register (doesn't affect clipboard)
keymap("n", "<leader>d", '"_d', { desc = "Delete to black hole register" })
keymap("x", "<leader>d", '"_d', { desc = "Delete selection to black hole register" })

-- Paste without losing register content
keymap("x", "<leader>p", '"_dP', { desc = "Paste without losing register" })

-- ================================
-- SEARCH & REPLACE
-- ================================

-- Double esc to disable hlsearch
keymap("n", "<Esc><Esc>", "<cmd>nohlsearch<CR><Esc>", { desc = "Clear search highlights" })

-- Replace all instances of word under cursor with s//
keymap("n", "<leader>s", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]], { desc = "Replace word under cursor" })

-- ================================
-- WINDOW & SPLIT MANAGEMENT
-- ================================

-- Split navigation (Ctrl + hjkl)
keymap("n", "<C-j>", "<C-W><C-J>", { desc = "Move to split below" })
keymap("n", "<C-k>", "<C-W><C-K>", { desc = "Move to split above" })
keymap("n", "<C-l>", "<C-W><C-L>", { desc = "Move to split right" })
keymap("n", "<C-h>", "<C-W><C-H>", { desc = "Move to split left" })

-- Resize splits
keymap("n", "<S-Up>", ":resize +2<CR>", { desc = "Increase split height" })
keymap("n", "<S-Down>", ":resize -2<CR>", { desc = "Decrease split height" })
keymap("n", "<S-Left>", ":vertical resize -2<CR>", { desc = "Decrease split width" })
keymap("n", "<S-Right>", ":vertical resize +2<CR>", { desc = "Increase split width" })

-- ================================
-- BUFFER MANAGEMENT
-- ================================

-- Navigate between buffers
keymap("n", "<M-l>", ":bn<CR>", { desc = "Next buffer" })
keymap("n", "<M-h>", ":bprev<CR>", { desc = "Previous buffer" })

-- Close buffer
keymap("n", "<M-d>", ":bp<Bar>bd #<CR>", { desc = "Close current buffer" })

-- ================================
-- LINE MANIPULATION
-- ================================

-- Move lines up/down in normal mode
-- Unified line movement with J/K in both normal and visual modes
keymap("n", "J", ":m .+1<CR>==", { noremap = true, silent = true, desc = "Move line down" })
keymap("n", "<leader>K", ":m .-2<CR>==", { noremap = true, silent = true, desc = "Move line up" })
keymap("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
keymap("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })

-- Restore original J functionality (join lines) to a different key
keymap("n", "<leader>j", "j", { noremap = true, silent = true, desc = "Join lines" })

-- Restore original K functionality (keyword lookup) to a different key
keymap("n", "<leader>k", "k", { noremap = true, silent = true, desc = "Keyword lookup" })

-- ================================
-- FILE OPERATIONS
-- ================================

-- Make file executable
keymap("n", "<leader>fx", "<cmd>!chmod +x %<CR>", { desc = "Make file executable" })

-- ================================
-- UFO FOLDING KEYMAPS
-- ================================

-- Open all folds
keymap("n", "zO", function()
	pcall(function()
		require("ufo").openAllFolds()
	end)
end, { desc = "Open all folds" })

-- Close current fold (using native Vim command)
keymap("n", "zc", function()
	pcall(function()
		vim.cmd("normal! zc")
	end)
end, { desc = "Close current fold" })

-- Close all folds
keymap("n", "zC", function()
	pcall(function()
		require("ufo").closeAllFolds()
	end)
end, { desc = "Close all folds" })

-- Toggle fold recursively
keymap("n", "zo", "zA", { desc = "Toggle fold recursively" })

-- ================================
-- FZF-LUA KEYMAPS
-- ================================

keymap("n", "<C-\\>", function()
	require("fzf-lua").buffers()
end, { desc = "FZF: Buffers" })
keymap("n", "<C-p>", function()
	require("fzf-lua").files()
end, { desc = "FZF: Files" })
keymap("n", "<leader>l", function()
	require("fzf-lua").live_grep_glob()
end, { desc = "FZF: Live Grep" })
keymap("n", "<C-g>", function()
	require("fzf-lua").grep_project()
end, { desc = "FZF: Grep Project" })
keymap("n", "<F1>", function()
	require("fzf-lua").help_tags()
end, { desc = "FZF: Help Tags" })

keymap("n", "<leader>ca", function()
	require("fzf-lua").lsp_code_actions()
end, vim.tbl_extend("force", opts, { desc = "Code Actions (FZF)" }))

-- ================================
-- PLUGIN-SPECIFIC KEYMAPS
-- ================================

-- Flash (navigation)
keymap({ "n", "x", "o" }, "s", function()
	require("flash").jump()
end, { desc = "Flash" })
keymap({ "n", "x", "o" }, "S", function()
	require("flash").treesitter()
end, { desc = "Flash Treesitter" })
keymap("o", "r", function()
	require("flash").remote()
end, { desc = "Remote Flash" })
keymap({ "o", "x" }, "R", function()
	require("flash").treesitter_search()
end, { desc = "Treesitter Search" })
keymap("c", "<c-s>", function()
	require("flash").toggle()
end, { desc = "Toggle Flash Search" })

-- Blink (character toggle)
keymap({ "n", "v" }, "<C-;>", function()
	require("blink.chartoggle").toggle_char_eol(";")
end, { desc = "Toggle ; at eol" })
keymap({ "n", "v" }, ",", function()
	require("blink.chartoggle").toggle_char_eol(",")
end, { desc = "Toggle , at eol" })

-- Blink Tree
keymap("n", "<C-n>", "<cmd>BlinkTree toggle<cr>", { desc = "Toggle file tree" })

-- Outline
keymap("n", "<leader>o", "<cmd>Outline<CR>", { desc = "Toggle outline" })

-- Maximizer
keymap("n", "<leader>z", "<cmd>MaximizerToggle<cr>", { desc = "Toggle window maximizer" })

---- ================================
---- LSP KEYMAPS (to be set in LSP on_attach)
---- ================================
----- Add to lsp.lua after mason-lspconfig setup
--vim.api.nvim_create_autocmd("LspAttach", {
--group = vim.api.nvim_create_augroup("UserLspConfig", {}),
--callback = function(ev)
--local opts = { buffer = ev.buf, silent = true }

--keymap("n", "gd", vim.lsp.buf.definition, vim.tbl_extend("force", opts, { desc = "Go to definition" }))
--keymap("n", "gr", vim.lsp.buf.references, vim.tbl_extend("force", opts, { desc = "Go to references" }))
--keymap("n", "gi", vim.lsp.buf.implementation, vim.tbl_extend("force", opts, { desc = "Go to implementation" }))
--keymap("n", "K", vim.lsp.buf.hover, vim.tbl_extend("force", opts, { desc = "Hover documentation" }))
--keymap("n", "<leader>rn", vim.lsp.buf.rename, vim.tbl_extend("force", opts, { desc = "Rename symbol" }))

--keymap("n", "<leader>ca", vim.lsp.buf.code_action, vim.tbl_extend("force", opts, { desc = "Code actions" }))
--end,
--})

-- Replace the commented LSP keymaps section with this
vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("UserLspConfig", {}),
	callback = function(ev)
		local opts = { buffer = ev.buf, silent = true }

		-- FZF-lua LSP navigation
		keymap("n", "gr", function()
			require("fzf-lua").lsp_references({
				jump_to_single_result = true,
				ignore_current_line = true,
			})
		end, vim.tbl_extend("force", opts, { desc = "References (FZF)" }))

		keymap("n", "gd", function()
			require("fzf-lua").lsp_definitions({

				jump_to_single_result = true,
			})
		end, vim.tbl_extend("force", opts, { desc = "Definitions (FZF)" }))

		-- Keep your superior search/replace for renames
		-- No need for LSP rename when you have <leader>s

		keymap("n", "K", vim.lsp.buf.hover, vim.tbl_extend("force", opts, { desc = "Hover" }))
	end,
})
