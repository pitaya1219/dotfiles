-- Neovim Autocommands Configuration

-- Delete autocmd that belong to vimrc
local vimrc_group = vim.api.nvim_create_augroup("vimrc", { clear = true })

-- File type specific settings
vim.api.nvim_create_autocmd("FileType", {
  group = vimrc_group,
  pattern = { "typescript", "javascript", "vue", "markdown" },
  callback = function()
    vim.bo.tabstop = 2
    vim.bo.shiftwidth = 2
  end
})

vim.api.nvim_create_autocmd("BufNewFile", {
  group = vimrc_group,
  pattern = "*.py",
  callback = function()
    vim.api.nvim_buf_set_lines(0, 0, 0, false, {"# -*- coding: utf-8 -*-"})
  end
})

-- When entering cmdline, turn off hjkl_move as default
vim.api.nvim_create_autocmd("CmdlineEnter", {
  group = vimrc_group,
  callback = function()
    vim.g.cmode_hjkl_move = false
  end
})
