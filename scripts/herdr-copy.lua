-- Init for the scratch buffer scripts/herdr-copy.sh opens over a pane's
-- scrollback. Visual-mode y writes the selection to HERDR_PASTE_REGISTER and
-- quits; scripts/herdr-paste.py reads that file back on prefix+]. Register z
-- is only a staging area, and 'clipboard' is cleared so that neither it nor
-- the write touch the system clipboard.

vim.opt.clipboard = ""
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.number = true
vim.opt.wrap = false
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.statusline = "  y/<CR> copy   q quit "

local register = assert(vim.env.HERDR_PASTE_REGISTER, "HERDR_PASTE_REGISTER is unset")

local function yank_to_register()
  vim.cmd('normal! "zy')
  local handle = assert(io.open(register, "w"))
  handle:write(vim.fn.getreg("z"))
  handle:close()
  vim.cmd("qa!")
end

vim.keymap.set("x", "y", yank_to_register, { desc = "copy to the herdr paste register" })
vim.keymap.set("x", "<CR>", yank_to_register, { desc = "copy to the herdr paste register" })
vim.keymap.set("n", "q", "<Cmd>qa!<CR>", { desc = "leave without copying" })
vim.keymap.set("n", "<Esc>", "<Cmd>qa!<CR>", { desc = "leave without copying" })

vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    vim.bo.modifiable = false
    vim.cmd("normal! G")
  end,
})
