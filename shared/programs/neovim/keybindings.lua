-- Neovim Keybindings Configuration

-- Leader key
vim.g.mapleader = " "

-- Basic key bindings
vim.keymap.set("n", "<enter>", "i<enter><Esc>k$")
vim.keymap.set("n", "<space><space>", ":let b:yank = @@<cr>\"zyiw:let @/ = '\\<' . @z . '\\>'<cr>:set hlsearch<cr>:let @@ = b:yank<cr>", { silent = true })
vim.keymap.set("n", "<c-\\>", "<c-w>")
vim.keymap.set("t", "<c-\\>", "<C-\\><C-o><C-w>")
vim.keymap.set("t", "<c-\\>N", "<C-\\><C-n>")
vim.keymap.set("i", "jj", "<C-[>")

-- Leader key mappings
vim.keymap.set("n", "<leader>so", ":so $MYVIMRC<cr>")
vim.keymap.set("n", "<leader>vr", "<C-v>")
vim.keymap.set("n", "<leader>va", "ggVG")
vim.keymap.set("n", "<leader>wr", ":w<cr>")
vim.keymap.set("n", "<leader>w", "<C-w>")
vim.keymap.set("n", "<leader>t", ":tabedit<cr>")
vim.keymap.set("n", "<leader>tn", "gt")
vim.keymap.set("n", "<leader>tp", "gT")
vim.keymap.set("n", "<leader>cc", ":")

-- Command mode hjkl navigation
vim.keymap.set("c", "::", function()
  vim.g.cmode_hjkl_move = not vim.g.cmode_hjkl_move
  return ""
end, { expr = true })

vim.keymap.set("c", "h", function()
  return vim.g.cmode_hjkl_move and "<left>" or "h"
end, { expr = true })

vim.keymap.set("c", "j", function()
  return vim.g.cmode_hjkl_move and "<down>" or "j"
end, { expr = true })

vim.keymap.set("c", "k", function()
  return vim.g.cmode_hjkl_move and "<up>" or "k"
end, { expr = true })

vim.keymap.set("c", "l", function()
  return vim.g.cmode_hjkl_move and "<right>" or "l"
end, { expr = true })

vim.keymap.set("c", "b", function()
  return vim.g.cmode_hjkl_move and "<bs>" or "b"
end, { expr = true })

-- Toggle fold method
vim.keymap.set("n", "<leader>fmm", ":set foldmethod=manual<cr>")
vim.keymap.set("n", "<leader>fms", ":set foldmethod=syntax<cr>")
vim.keymap.set("n", "<leader>fmi", ":set foldmethod=indent<cr>")

-- For vimgrep
vim.keymap.set("n", "<leader>cn", ":cnext<cr>")
vim.keymap.set("n", "<leader>cp", ":cprevious<cr>")
vim.keymap.set("n", "<leader>cg", ":cfirst<cr>")
vim.keymap.set("n", "<leader>cG", ":clast<cr>")
vim.keymap.set("n", "<leader>cl", ":clist<cr>")
