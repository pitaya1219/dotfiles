-- CoC.nvim Configuration

-- Merge existing global extensions with additional ones
local existing_extensions = vim.g.coc_global_extensions or {}
local addtional_extensions = {
  'coc-go',
  'coc-elixir',
}
vim.g.coc_global_extensions = vim.list_extend(existing_extensions, addtional_extensions)
