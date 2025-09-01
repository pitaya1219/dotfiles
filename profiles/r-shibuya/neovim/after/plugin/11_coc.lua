-- CoC.nvim Configuration
-- Merge existing global extensions with additional ones
local existing_extensions = vim.g.coc_global_extensions or {}
local addtional_extensions = {
  'coc-eslint',
  'coc-prettier',
  'coc-tslint-plugin',
  'coc-tsserver',
  '@yaegassy/coc-volar',
  '@yaegassy/coc-ruff',
  '@yaegassy/coc-mypy',
  'coc-pyright',
  'coc-elixir',
}
vim.g.coc_global_extensions = vim.list_extend(existing_extensions, addtional_extensions)
