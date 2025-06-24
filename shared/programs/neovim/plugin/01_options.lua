-- Neovim Options Configuration

-- Configure about file
vim.opt.fileencodings = "utf-8,sjis"
vim.opt.encoding = "utf-8"

-- Configure about appearance
vim.opt.wrap = false
vim.opt.ambiwidth = "double"
vim.opt.foldmethod = "syntax"
vim.opt.background = "dark"
vim.opt.termguicolors = true
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.wildmenu = true
vim.opt.re = 0 -- fix problems: it disable syntax highlight when reload buffer
vim.opt.cursorline = true
vim.opt.cursorcolumn = true
vim.opt.expandtab = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.incsearch = true
vim.opt.clipboard:append({"unnamedplus"})
vim.g.python3_host_prog = vim.env.HOME.."/.nix-profile/bin/nvim-python3"

-- Neovim cursor configuration
vim.opt.guicursor = "n-v-c:block,i-ci-ve:ver25,r-cr:hor20,o:hor50,a:blinkwait700-blinkoff400-blinkon250-Cursor/lCursor,sm:block-blinkwait175-blinkoff150-blinkon175"

-- Enable filetype plugin
vim.cmd("filetype plugin indent on")

vim.cmd("syntax enable")

-- Set default colorscheme
vim.cmd("colorscheme aquarium")

if vim.env.TERM_PROGRAM == "tmux" then
  vim.env.TERM = "tmux-256color"
end
