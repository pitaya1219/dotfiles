local ok, telescope = pcall(require, "telescope")
if not ok then return end

local actions = require("telescope.actions")

telescope.setup({
  defaults = {
    layout_strategy = "horizontal",
    layout_config = { preview_width = 0.55 },
    mappings = {
      n = {
        ["q"] = actions.close,
        ["<esc>"] = actions.close,
      },
    },
  },
  pickers = {
    quickfix = { initial_mode = "normal" },
  },
})

-- Load coc extension (telescope-coc-nvim)
pcall(telescope.load_extension, "coc")
