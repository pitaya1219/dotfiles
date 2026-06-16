local ok, noice = pcall(require, "noice")
if not ok then return end

noice.setup({
  -- CoC は自前で LSP を管理しているので LSP 系は無効化
  lsp = {
    override = {
      ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
      ["vim.lsp.util.stylize_markdown"] = true,
    },
    hover = { enabled = false },
    signature = { enabled = false },
    progress = { enabled = false },
    message = { enabled = false },
  },
  presets = {
    bottom_search = true,
    command_palette = false,
    long_message_to_split = true,
    lsp_doc_border = true,
  },
  -- : コマンドのみシンプルなアイコン表示 (search は bottom_search preset に任せる)
  cmdline = {
    view = "cmdline",
    format = {
      cmdline = { icon = vim.g.have_nerd_font and "󰞷 " or ">" },
    },
  },
  messages = {
    enabled = true,
    view = "notify",
    view_error = "notify",
    view_warn = "notify",
  },
  notify = {
    enabled = true,
    view = "notify",
  },
})
