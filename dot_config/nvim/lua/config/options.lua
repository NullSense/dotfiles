-- Indentation
vim.opt.autoindent = true
vim.opt.smartindent = true
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smarttab = true
vim.cmd("filetype plugin indent on")

-- Vim general
vim.opt.tags = "tags"
vim.opt.cmdheight = 2
vim.opt.updatetime = 150
--vim.opt.shortmess:append({ c = true })
vim.opt.signcolumn = "yes"
vim.opt.autoread = true
vim.opt.mouse = "a"
vim.opt.encoding = "UTF-8"
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
vim.opt.listchars = {
	tab = ">·",
	trail = "$",
	extends = ">",
	precedes = "<",
	nbsp = "␣",
}
vim.opt.list = true
vim.opt.hidden = true
vim.opt.termguicolors = true
vim.opt.completeopt = "menuone,noselect"
vim.opt.shada = "!,'300,<50,s10,%"
vim.opt.undodir = os.getenv("HOME") .. "/.config/nvim/undodir"
vim.opt.undofile = true
vim.cmd("syntax on") -- Syntax highlighting

-- Folding
vim.o.foldcolumn = "1" -- '0' is not bad
vim.o.foldlevel = 99 -- Using ufo provider need a large value, feel free to decrease the value
vim.o.foldlevelstart = 99
vim.o.foldenable = true

-- Clipboard
vim.opt.clipboard = "unnamedplus"

-- Python host
vim.g.python3_host_prog = "/usr/bin/python3"

-- Background
vim.o.background = "dark" -- or "light" for light mode
