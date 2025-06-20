-- CoC.nvim Configuration

-- Global extensions
vim.g.coc_global_extensions = {
  'coc-git',
  'coc-highlight',
  'coc-json',
  'coc-markdownlint',
  'coc-snippets',
  'coc-spell-checker',
  'coc-yaml',
  'coc-explorer',
  'coc-vimlsp',
  'coc-lua',
}

-- Coc configuration
vim.g.coc_snippet_next = '<tab>'

if vim.fn.executable('command') == 1 then
  vim.g.coc_node_path = vim.fn.substitute(vim.fn.system('command -v node'), "\n", "", "")
end

-- Helper function for coc
function CheckBackspace()
  local col = vim.fn.col('.') - 1
  return col == 0 or vim.fn.getline('.'):sub(col, col):match('%s') ~= nil
end

-- Keybindings for CoC
vim.keymap.set("i", "<c-f>", function()
  return vim.fn["coc#float#has_scroll"]() == 1 and vim.fn["coc#float#scroll"](1) or "<Right>"
end, { silent = true, nowait = true, expr = true })

vim.keymap.set("i", "<c-b>", function()
  return vim.fn["coc#float#has_scroll"]() == 1 and vim.fn["coc#float#scroll"](0) or "<Left>"
end, { silent = true, nowait = true, expr = true })

vim.keymap.set("n", "<leader>cocact", ":CocAction<cr>")
vim.keymap.set("n", "<leader>cocdia", ":CocDiagnostics<cr>")
vim.keymap.set("n", "<leader>coch", ":call CocActionAsync('doHover')<cr>")
vim.keymap.set("n", "<leader>cocdef", ":call CocActionAsync('jumpDefinition')<cr>")
vim.keymap.set("n", "<leader>cocform", ":call CocActionAsync('format')<cr>")
vim.keymap.set("n", "<leader>cocfix", "<Plug>(coc-fix-current)")
vim.keymap.set("n", "<leader>coclens", "<Plug>(coc-codelens-action)")
vim.keymap.set("n", "<leader>cocuse", ":call CocActionAsync('jumpUsed')<cr>")
vim.keymap.set("n", "<leader>cocren", ":call CocActionAsync('rename')<cr>")
vim.keymap.set("n", "<leader>cocref", ":call CocActionAsync('jumpReference')<cr>")
vim.keymap.set("n", "<leader>coce", "<Cmd>CocCommand explorer<CR>")
vim.keymap.set("x", "<leader>cocform", "<Plug>(coc-format-selected)")
vim.keymap.set("x", "<leader>cocact", "<Plug>(coc-codeaction-selected)")

-- Tab completion for coc
vim.keymap.set("i", "<TAB>", function()
  if vim.fn["coc#pum#visible"]() == 1 then
    return vim.fn["coc#_select_confirm"]()
  elseif vim.fn["coc#expandableOrJumpable"]() == 1 then
    return vim.fn["coc#rpc#request"]('doKeymap', {'snippets-expand-jump',''})
  elseif CheckBackspace() then
    return "<TAB>"
  else
    return vim.fn["coc#refresh"]()
  end
end, { silent = true, expr = true })

vim.keymap.set("i", "<leader>cc", function()
  return vim.fn["coc#pum#visible"]() == 1 and vim.fn["coc#pum#confirm"]() or "  cc"
end, { silent = true, expr = true })

vim.keymap.set("i", "<leader>cn", function()
  return vim.fn["coc#pum#visible"]() == 1 and vim.fn["coc#pum#next"](1) or "  cn"
end, { silent = true, expr = true })

vim.keymap.set("i", "<leader>cp", function()
  return vim.fn["coc#pum#visible"]() == 1 and vim.fn["coc#pum#prev"](1) or "  cp"
end, { silent = true, expr = true })
