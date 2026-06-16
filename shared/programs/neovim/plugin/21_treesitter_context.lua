local ok, ctx = pcall(require, "treesitter-context")
if not ok then return end

ctx.setup({
  enable = true,
  max_lines = 4,
  min_window_height = 0,
  line_numbers = true,
  multiline_threshold = 20,
  trim_scope = "outer",
  mode = "cursor",
  separator = nil,
  zindex = 20,
  on_attach = nil,
})

vim.keymap.set("n", "[c", function()
  ctx.go_to_context(vim.v.count1)
end, { desc = "Jump to context" })
