local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

-- ================================
-- UFO FOLD PREVIEW AUTOCMDS
-- ================================

local ufo_preview_group = augroup("UFOPreview", { clear = true })

-- Auto-preview folds on cursor hold
autocmd("CursorHold", {
	group = ufo_preview_group,
	pattern = "*",
	callback = function()
		local line = vim.fn.line(".")
		local foldclosed = vim.fn.foldclosed(line)

		if foldclosed ~= -1 then
			vim.defer_fn(function()
				pcall(function()
					require("ufo").peekFoldedLinesUnderCursor()
				end)
			end, 200)
		end
	end,
	desc = "Show fold preview on cursor hold",
})

-- ================================
-- COMPLETION & PREVIEW MANAGEMENT
-- ================================

-- Close preview window after completion selection
augroup("CompletionPreview", { clear = true })
autocmd({ "CursorMovedI" }, {
	group = "CompletionPreview",
	pattern = "*",
	command = "if pumvisible() == 0|pclose|endif",
	desc = "Close preview window when completion popup is not visible",
})

autocmd({ "InsertLeave" }, {
	group = "CompletionPreview",
	pattern = "*",
	command = "if pumvisible() == 0|pclose|endif",
	desc = "Close preview window when leaving insert mode",
})

-- ================================
-- LINE NUMBER MANAGEMENT
-- ================================

-- Toggle relative line numbers based on focus and mode
augroup("NumberToggle", { clear = true })
autocmd({ "BufEnter", "FocusGained", "InsertLeave", "WinEnter" }, {
	group = "NumberToggle",
	pattern = "*",
	callback = function()
		if vim.opt.number:get() and vim.fn.mode() ~= "i" then
			vim.opt.relativenumber = true
		end
	end,
	desc = "Enable relative line numbers when focused and not in insert mode",
})

autocmd({ "BufLeave", "FocusLost", "InsertEnter", "WinLeave" }, {
	group = "NumberToggle",
	pattern = "*",
	callback = function()
		if vim.opt.number:get() then
			vim.opt.relativenumber = false
		end
	end,
	desc = "Disable relative line numbers when unfocused or in insert mode",
})

-- ================================
-- FILE MANAGEMENT
-- ================================

-- Restore cursor position when reopening files
augroup("CursorRestore", { clear = true })
autocmd({ "BufReadPost" }, {
	group = "CursorRestore",
	pattern = "*",
	callback = function()
		local mark = vim.api.nvim_buf_get_mark(0, '"')
		local lcount = vim.api.nvim_buf_line_count(0)
		if mark[1] > 0 and mark[1] <= lcount then
			pcall(vim.api.nvim_win_set_cursor, 0, mark)
		end
	end,
	desc = "Restore cursor position when reopening files",
})

-- Auto-reload files when changed externally
augroup("AutoReload", { clear = true })
autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
	group = "AutoReload",
	pattern = "*",
	command = 'if mode() !~ "\\v(c|r.?|!|t)" && getcmdwintype() == "" | checktime | endif',
	desc = "Check if file has been changed externally",
})

autocmd({ "FileChangedShellPost" }, {
	group = "AutoReload",
	pattern = "*",
	command = 'echohl WarningMsg | echo "File changed on disk. Buffer reloaded." | echohl None',
	desc = "Notify when file is reloaded due to external changes",
})

-- ================================
-- LINTING AUTOMATION
-- ================================

-- Auto-lint on save, insert leave, or buffer enter
augroup("AutoLint", { clear = true })
autocmd({ "BufWritePost", "InsertLeave", "BufEnter" }, {
	group = "AutoLint",
	pattern = "*",
	callback = function()
		-- Only run if nvim-lint is available
		local ok, lint = pcall(require, "lint")
		if ok then
			lint.try_lint()
		end
	end,
	desc = "Auto-lint on save, insert leave, or buffer enter",
})

-- ================================
-- TERMINAL MANAGEMENT
-- ================================

-- Terminal-specific settings
augroup("TerminalSettings", { clear = true })
autocmd({ "TermOpen" }, {
	group = "TerminalSettings",
	pattern = "*",
	callback = function()
		vim.opt_local.number = false
		vim.opt_local.relativenumber = false
		vim.opt_local.signcolumn = "no"
		vim.cmd("startinsert")
	end,
	desc = "Configure terminal windows",
})

-- ================================
-- HIGHLIGHTING MANAGEMENT
-- ================================

-- Highlight yanked text briefly
augroup("YankHighlight", { clear = true })
autocmd({ "TextYankPost" }, {
	group = "YankHighlight",
	pattern = "*",
	callback = function()
		vim.highlight.on_yank({
			higroup = "IncSearch",
			timeout = 300,
		})
	end,
	desc = "Highlight yanked text briefly",
})

-- ================================
-- QUICKFIX AND LOCATION LIST
-- ================================

-- Auto-open quickfix window
augroup("QuickfixSettings", { clear = true })
autocmd({ "QuickFixCmdPost" }, {
	group = "QuickfixSettings",
	pattern = { "[^l]*" },
	command = "cwindow",
	desc = "Auto-open quickfix window after quickfix commands",
})

autocmd({ "QuickFixCmdPost" }, {
	group = "QuickfixSettings",
	pattern = { "l*" },
	command = "lwindow",
	desc = "Auto-open location list window after location list commands",
})

-- ================================
-- WINDOW MANAGEMENT
-- ================================

-- Equalize splits when vim is resized
augroup("WindowResize", { clear = true })
autocmd({ "VimResized" }, {
	group = "WindowResize",
	pattern = "*",
	command = "wincmd =",
	desc = "Equalize window splits when Vim is resized",
})

-- ================================
-- CLEANUP ON EXIT
-- ================================

-- Clean up temporary files on exit
augroup("CleanupOnExit", { clear = true })
autocmd({ "VimLeavePre" }, {
	group = "CleanupOnExit",
	pattern = "*",
	callback = function()
		-- Clean up any temporary files or perform cleanup tasks
		vim.cmd("mksession! ~/.config/nvim/session.vim")
	end,
	desc = "Save session on exit",
})
