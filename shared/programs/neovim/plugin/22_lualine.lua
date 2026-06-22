local ok, lualine = pcall(require, "lualine")
if not ok then return end

-- aquarium colorscheme defines s:colors.bold = "bold," (trailing comma).
-- This causes E418: Illegal value: bold,,nocombine when lualine tries to set
-- highlight groups. Patch before setup to strip trailing commas from gui.
local hl_module = require("lualine.highlight")
local orig_highlight = hl_module.highlight
hl_module.highlight = function(name, fg, bg, gui, link)
  if type(gui) == "string" then
    gui = gui:gsub(",+", ","):gsub("^,", ""):gsub(",$", "")
    if gui == "" then gui = nil end
  end
  return orig_highlight(name, fg, bg, gui, link)
end

lualine.setup({
  options = {
    icons_enabled = false,
    theme = "auto",
    component_separators = { left = "|", right = "|" },
    section_separators = { left = "", right = "" },
    disabled_filetypes = {
      statusline = {},
      winbar = {},
    },
    ignore_focus = {},
    always_divide_middle = true,
    globalstatus = false,
    refresh = {
      statusline = 1000,
      tabline = 1000,
      winbar = 1000,
    },
  },
  sections = {
    lualine_a = { "mode" },
    lualine_b = { "branch", "diff", "diagnostics" },
    lualine_c = { "filename" },
    lualine_x = { "encoding", "fileformat", "filetype" },
    lualine_y = { "progress" },
    lualine_z = { "location" },
  },
  inactive_sections = {
    lualine_a = {},
    lualine_b = {},
    lualine_c = { "filename" },
    lualine_x = { "location" },
    lualine_y = {},
    lualine_z = {},
  },
  tabline = {},
  winbar = {},
  inactive_winbar = {},
  extensions = {},
})
